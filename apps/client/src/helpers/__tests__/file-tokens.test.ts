import type { TFile } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { getFileToken, setFileSigner } from '../file-tokens';

const getFile = (id: number, expiresAt: number): TFile =>
  ({
    id,
    name: `file-${id}.png`,
    _accessToken: `own-${id}`,
    _accessTokenExpiresAt: expiresAt
  }) as TFile;

describe('getFileToken', () => {
  test('should leave an unsigned file alone', () => {
    expect(getFileToken({ id: 1, name: 'a.png' } as TFile)).toBeUndefined();
  });

  test('should keep a link that still works, so nothing on screen loads again', () => {
    const expiresAt = Date.now() + 60 * 60 * 1000;

    expect(getFileToken(getFile(2, expiresAt))).toEqual({
      accessToken: 'own-2',
      expiresAt
    });
  });

  test('should hand out a fresh link once the file own has run out', async () => {
    const asked: number[][] = [];
    const freshExpiresAt = Date.now() + 60 * 60 * 1000;

    setFileSigner(async (fileIds) => {
      asked.push(fileIds);

      // file 4 is gone or hidden, the server leaves it out
      return fileIds
        .filter((fileId) => fileId !== 4)
        .map((fileId) => ({
          fileId,
          accessToken: `fresh-${fileId}`,
          expiresAt: freshExpiresAt
        }));
    });

    const expired = getFile(3, Date.now() - 1000);
    const hidden = getFile(4, Date.now() - 1000);

    getFileToken(expired);
    getFileToken(hidden);

    await Bun.sleep(20);

    expect(asked.flat()).toContain(3);
    expect(getFileToken(expired)).toEqual({
      accessToken: 'fresh-3',
      expiresAt: freshExpiresAt
    });

    // still its own expired link, nothing fresher came back for it
    expect(getFileToken(hidden)).toEqual({
      accessToken: 'own-4',
      expiresAt: hidden._accessTokenExpiresAt!
    });
  });
});
