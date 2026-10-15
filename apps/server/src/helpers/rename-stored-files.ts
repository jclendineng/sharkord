import { randomUUID } from 'crypto';
import { eq } from 'drizzle-orm';
import fs from 'fs/promises';
import path from 'path';
import { db } from '../db';
import { files } from '../db/schema';
import { logger } from '../logger';
import { PUBLIC_PATH } from './paths';

const RANDOM_NAME =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/;

// files uploaded before uploads were stored under random names still sit under the name they
// were sent with, which anyone could guess. at startup, before anyone connects, each is moved to a
// random name. a file whose name is already random is left alone, so this only does work once
const renameStoredFiles = async () => {
  const rows = await db.select({ id: files.id, name: files.name }).from(files);

  const pending = rows.filter(({ name }) => !RANDOM_NAME.test(name));

  if (pending.length === 0) {
    return;
  }

  let renamed = 0;

  // one at a time, each rename followed straight away by its row: stopping halfway leaves every
  // file either fully moved or untouched, never on disk under a name the database does not know
  for (const { id, name } of pending) {
    const newName = `${randomUUID()}${path.extname(name)}`;

    try {
      await fs.rename(
        path.join(PUBLIC_PATH, name),
        path.join(PUBLIC_PATH, newName)
      );
    } catch (error) {
      // missing from disk already, there is nothing to move
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        continue;
      }

      throw error;
    }

    await db.update(files).set({ name: newName }).where(eq(files.id, id));

    renamed++;
  }

  logger.info('Moved %d stored files to random names', renamed);
};

export { renameStoredFiles };
