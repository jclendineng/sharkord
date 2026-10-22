import { describe, expect, test } from 'bun:test';
import fs from 'fs/promises';
import path from 'path';
import { TMP_PATH, UPLOADS_PATH } from '../../helpers/paths';
import { STALE_AFTER_MS, sweepStaleUploads } from '../sweep-stale-uploads';

const writeFileAged = async (filePath: string, ageMs: number) => {
  await fs.writeFile(filePath, 'left behind');

  const time = new Date(Date.now() - ageMs);

  await fs.utimes(filePath, time, time);
};

describe('sweepStaleUploads', () => {
  test('should remove stale files and keep fresh files and directories', async () => {
    const staleUpload = path.join(UPLOADS_PATH, 'stale-upload.txt');
    const staleTemp = path.join(TMP_PATH, 'stale-temp.txt');
    const freshUpload = path.join(UPLOADS_PATH, 'fresh-upload.txt');
    const workingDir = path.join(TMP_PATH, 'sweep-working-dir');

    await Promise.all([
      writeFileAged(staleUpload, STALE_AFTER_MS + 1000),
      writeFileAged(staleTemp, STALE_AFTER_MS + 1000),
      writeFileAged(freshUpload, 0),
      fs.mkdir(workingDir, { recursive: true })
    ]);

    try {
      await sweepStaleUploads();

      expect(await fs.exists(staleUpload)).toBe(false);
      expect(await fs.exists(staleTemp)).toBe(false);
      expect(await fs.exists(freshUpload)).toBe(true);
      expect(await fs.exists(workingDir)).toBe(true);
    } finally {
      await Promise.all([
        fs.rm(freshUpload, { force: true }),
        fs.rm(workingDir, { recursive: true, force: true })
      ]);
    }
  });
});
