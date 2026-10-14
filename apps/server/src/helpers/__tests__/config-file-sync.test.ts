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
    expect(parsed.storage).toEqual({ signedUrls: false });
    expect(parsed.gifs).toEqual({ klipyApiKey: '' });
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
    parsed.storage = { signedUrls: true };
    parsed.gifs = { klipyApiKey: 'from-the-file' };
    await writeIni(parsed);

    await syncConfigFile();

    const { allowNewUsers, storageSignedUrlsEnabled, klipyApiKey } =
      await getSettings();

    expect(allowNewUsers).toBe(false);
    expect(storageSignedUrlsEnabled).toBe(true);
    expect(klipyApiKey).toBe('from-the-file');
  });

  test('should leave the settings alone when the file was not edited', async () => {
    await syncConfigFile();
    await tdb.update(settings).set({ allowNewUsers: false });

    await syncConfigFile();

    const { allowNewUsers } = await getSettings();

    expect(allowNewUsers).toBe(false);
    expect((await readIni()).registration).toEqual({ allowNewUsers: false });
  });

  test('should carry over the old inviteOnly and forceSignedUrls keys', async () => {
    const parsed = await readIni();

    parsed.registration = { inviteOnly: true };
    parsed.storage = { forceSignedUrls: true };
    await writeIni(parsed);

    await syncConfigFile();

    const { allowNewUsers, storageSignedUrlsEnabled } = await getSettings();
    const after = await readIni();

    expect(allowNewUsers).toBe(false);
    expect(storageSignedUrlsEnabled).toBe(true);
    expect(after.registration).toEqual({ allowNewUsers: false });
    expect(after.storage).toEqual({ signedUrls: true });
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

    parsed.storage = { signedUrls: true };
    await writeIni(parsed);

    await applyConfigFileEdits();

    const { storageSignedUrlsEnabled } = await getSettings();

    expect(storageSignedUrlsEnabled).toBe(true);
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
      storageSignedUrlsEnabled: true,
      klipyApiKey: 'typed-key'
    });

    const parsed = await readIni();

    expect(parsed.registration).toEqual({ allowNewUsers: false });
    expect(parsed.storage).toEqual({ signedUrls: true });
    expect(parsed.gifs).toEqual({ klipyApiKey: 'typed-key' });
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
