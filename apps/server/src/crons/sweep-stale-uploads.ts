import chalk from 'chalk';
import fs from 'fs/promises';
import path from 'path';
import { TMP_PATH, UPLOADS_PATH } from '../helpers/paths';
import { logger } from '../logger';

// an upload being written keeps touching its file, and a temporary file lives for a minute,
// so anything untouched this long was left behind by a crash or a dropped connection
const STALE_AFTER_MS = 1000 * 60 * 60;

const sweepDir = async (dir: string, now: number) => {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  let removed = 0;

  await Promise.all(
    entries.map(async (entry) => {
      // the tmp dir also holds working directories, such as plugin downloads, that own
      // their own cleanup
      if (!entry.isFile()) return;

      const filePath = path.join(dir, entry.name);

      // the temporary file timer may delete it between the listing and here
      const stats = await fs.stat(filePath).catch(() => undefined);

      if (!stats || now - stats.mtimeMs < STALE_AFTER_MS) return;

      await fs.rm(filePath, { force: true });

      removed++;
    })
  );

  return removed;
};

const sweepStaleUploads = async () => {
  const now = Date.now();
  const counts = await Promise.all(
    [UPLOADS_PATH, TMP_PATH].map((dir) => sweepDir(dir, now))
  );
  const removed = counts.reduce((total, count) => total + count, 0);

  if (removed === 0) return;

  logger.info(`${chalk.dim('[Cron]')} Removed ${removed} stale upload files.`);
};

export { STALE_AFTER_MS, sweepStaleUploads };
