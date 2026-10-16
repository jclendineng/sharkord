import { ServerEvents } from '@sharkord/shared';
import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  spyOn,
  test
} from 'bun:test';
import fs from 'fs/promises';
import { parse, stringify } from 'ini';
import path from 'path';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { getSettings } from '../../db/queries/server';
import { settings } from '../../db/schema';
import { pubsub } from '../../utils/pubsub';
import { applyConfigFileEdits, syncConfigFile } from '../config-file-sync';
import { CONFIG_INI_PATH, DATA_PATH } from '../paths';

// the settings mirrored between config.ini and the settings screens. the test data folder's
// config.ini is the real one for the test process, so it is put back once the file is done
const LAST_SYNC_PATH = path.join(DATA_PATH, 'config-sync.json');

let originalConfig = '';

const readIni = async () =>
  parse(await fs.readFile(CONFIG_INI_PATH, { encoding: 'utf-8' }));

const writeIni = async (sections: Record<string, unknown>) => {
  await fs.writeFile(CONFIG_INI_PATH, stringify(sections));
};

// a file as an older server left it: no mirrored keys and no record of a sync
const resetToUnsynced = async () => {
  const parsed = await readIni();

  delete parsed.registration;
  delete parsed.storage;
  delete parsed.gifs;
  delete parsed.links;

  await writeIni(parsed);
  await fs.rm(LAST_SYNC_PATH, { force: true });
};

beforeAll(async () => {
  originalConfig = await fs.readFile(CONFIG_INI_PATH, { encoding: 'utf-8' });
});

afterAll(async () => {
  await fs.writeFile(CONFIG_INI_PATH, originalConfig);
  await fs.rm(LAST_SYNC_PATH, { force: true });
});

beforeEach(async () => {
  await resetToUnsynced();
});

describe('syncConfigFile', () => {
  test('should write the settings into the file the first time', async () => {
    await syncConfigFile();

    const parsed = await readIni();

    expect(parsed.registration).toEqual({ allowNewUsers: true });
    // file links are always signed, there is no switch to write
    expect(parsed.storage).toBeUndefined();
    expect(parsed.gifs).toEqual({ klipyApiKey: '' });
    expect(parsed.sounds).toEqual({ freesoundApiKey: '' });
    expect(parsed.links).toEqual({ previewPrivateNetwork: false });
  });

  test('should keep the rest of the file as it was', async () => {
    const before = await readIni();

    await syncConfigFile();

    const after = await readIni();

    expect(after.server).toEqual(before.server);
    expect(after.rateLimiters).toEqual(before.rateLimiters);
  });

  test('should apply an edit made while the server was down', async () => {
    await syncConfigFile();

    const parsed = await readIni();

    parsed.registration = { allowNewUsers: false };
    parsed.gifs = { klipyApiKey: 'from-the-file' };
    parsed.links = { previewPrivateNetwork: true };
    await writeIni(parsed);

    await syncConfigFile();

    const { allowNewUsers, klipyApiKey, linkPreviewsPrivateNetwork } =
      await getSettings();

    expect(allowNewUsers).toBe(false);
    expect(klipyApiKey).toBe('from-the-file');
    expect(linkPreviewsPrivateNetwork).toBe(true);
  });

  test('should apply a freesound key added to the file', async () => {
    await syncConfigFile();

    const parsed = await readIni();

    parsed.sounds = { freesoundApiKey: 'sounds-from-the-file' };
    await writeIni(parsed);

    await syncConfigFile();

    const { freesoundApiKey } = await getSettings();

    expect(freesoundApiKey).toBe('sounds-from-the-file');
  });

  test('should write a freesound key saved in the settings into the file', async () => {
    await tdb.update(settings).set({ freesoundApiKey: 'saved-sounds-key' });

    await syncConfigFile();

    expect((await readIni()).sounds).toEqual({
      freesoundApiKey: 'saved-sounds-key'
    });
  });

  test('should leave the settings alone when the file was not edited', async () => {
    await syncConfigFile();
    await tdb.update(settings).set({ allowNewUsers: false });

    await syncConfigFile();

    const { allowNewUsers } = await getSettings();

    expect(allowNewUsers).toBe(false);
    expect((await readIni()).registration).toEqual({ allowNewUsers: false });
  });

  test('should carry over the old inviteOnly key and drop the old signing switches', async () => {
    const parsed = await readIni();

    parsed.registration = { inviteOnly: true };
    parsed.storage = { forceSignedUrls: true, signedUrls: false };
    await writeIni(parsed);

    await syncConfigFile();

    const { allowNewUsers } = await getSettings();
    const after = await readIni();

    expect(allowNewUsers).toBe(false);
    expect(after.registration).toEqual({ allowNewUsers: false });
    expect(after.storage).toBeUndefined();
  });

  test('should not let the old empty klipy key wipe one saved in the settings', async () => {
    await tdb.update(settings).set({ klipyApiKey: 'saved-key' });

    const parsed = await readIni();

    parsed.gifs = { klipyApiKey: '' };
    await writeIni(parsed);

    await syncConfigFile();

    const { klipyApiKey } = await getSettings();

    expect(klipyApiKey).toBe('saved-key');
    expect((await readIni()).gifs).toEqual({ klipyApiKey: 'saved-key' });
  });

  test('should clear the klipy key when it is emptied in the file', async () => {
    await tdb.update(settings).set({ klipyApiKey: 'saved-key' });
    await syncConfigFile();

    const parsed = await readIni();

    parsed.gifs = { klipyApiKey: '' };
    await writeIni(parsed);

    await syncConfigFile();

    const { klipyApiKey } = await getSettings();

    expect(klipyApiKey).toBeNull();
  });
});

describe('applyConfigFileEdits', () => {
  test('should apply an edit made while running and tell everyone', async () => {
    await syncConfigFile();

    const publish = spyOn(pubsub, 'publish');
    const parsed = await readIni();

    parsed.links = { previewPrivateNetwork: true };
    await writeIni(parsed);

    await applyConfigFileEdits();

    const { linkPreviewsPrivateNetwork } = await getSettings();

    expect(linkPreviewsPrivateNetwork).toBe(true);
    expect(publish).toHaveBeenCalledWith(
      ServerEvents.SERVER_SETTINGS_UPDATE,
      expect.anything()
    );
  });

  test('should do nothing when the file did not change', async () => {
    await syncConfigFile();

    const publish = spyOn(pubsub, 'publish');

    await applyConfigFileEdits();

    expect(publish).not.toHaveBeenCalled();
  });
});

describe('others.updateSettings', () => {
  test('should write a change to a mirrored setting into the file', async () => {
    await syncConfigFile();

    const { caller } = await initTest(1);

    await caller.others.updateSettings({
      allowNewUsers: false,
      klipyApiKey: 'typed-key',
      linkPreviewsPrivateNetwork: true
    });

    const parsed = await readIni();

    expect(parsed.registration).toEqual({ allowNewUsers: false });
    expect(parsed.storage).toBeUndefined();
    expect(parsed.gifs).toEqual({ klipyApiKey: 'typed-key' });
    expect(parsed.links).toEqual({ previewPrivateNetwork: true });
  });

  test('should leave the file alone for other settings', async () => {
    await syncConfigFile();

    const before = await fs.readFile(CONFIG_INI_PATH, { encoding: 'utf-8' });
    const { caller } = await initTest(1);

    await caller.others.updateSettings({ name: 'Renamed' });

    expect(await fs.readFile(CONFIG_INI_PATH, { encoding: 'utf-8' })).toBe(
      before
    );
  });
});
