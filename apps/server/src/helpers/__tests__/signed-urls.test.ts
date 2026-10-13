import { afterEach, describe, expect, test } from 'bun:test';
import { initTest } from '../../__tests__/helpers';
import { config } from '../../config';
import { getSettings } from '../../db/queries/server';
import { applyForcedSignedUrls } from '../signed-urls';

// config.ini's storage.forceSignedUrls, which holds the signed file links switch on
afterEach(() => {
  config.storage.forceSignedUrls = false;
});

describe('applyForcedSignedUrls', () => {
  test('should turn signed file links on when config.ini forces them', async () => {
    config.storage.forceSignedUrls = true;

    await applyForcedSignedUrls();

    const { storageSignedUrlsEnabled } = await getSettings();

    expect(storageSignedUrlsEnabled).toBe(true);
  });

  test('should leave the switch alone without the lock', async () => {
    await applyForcedSignedUrls();

    const { storageSignedUrlsEnabled } = await getSettings();

    expect(storageSignedUrlsEnabled).toBe(false);
  });
});

describe('others.updateSettings', () => {
  test('should refuse to turn signed file links off while config.ini forces them', async () => {
    config.storage.forceSignedUrls = true;

    const { caller } = await initTest(1);

    await caller.others.updateSettings({ storageSignedUrlsEnabled: true });

    await expect(
      caller.others.updateSettings({ storageSignedUrlsEnabled: false })
    ).rejects.toThrow('Signed file links are locked on by config.ini');

    const { storageSignedUrlsEnabled } = await getSettings();

    expect(storageSignedUrlsEnabled).toBe(true);
  });

  test('should still turn them off without the lock', async () => {
    const { caller } = await initTest(1);

    await caller.others.updateSettings({ storageSignedUrlsEnabled: true });
    await caller.others.updateSettings({ storageSignedUrlsEnabled: false });

    const { storageSignedUrlsEnabled } = await getSettings();

    expect(storageSignedUrlsEnabled).toBe(false);
  });
});

describe('others.getStorageSettings', () => {
  test('should tell admins when config.ini locks signed file links', async () => {
    const { caller } = await initTest(1);

    expect((await caller.others.getStorageSettings()).signedUrlsLocked).toBe(
      false
    );

    config.storage.forceSignedUrls = true;

    expect((await caller.others.getStorageSettings()).signedUrlsLocked).toBe(
      true
    );
  });
});
