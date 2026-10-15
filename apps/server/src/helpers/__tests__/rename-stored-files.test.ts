import { afterEach, describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import fs from 'fs/promises';
import path from 'path';
import { storedNamePattern } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { files } from '../../db/schema';
import { PUBLIC_PATH } from '../paths';
import { renameStoredFiles } from '../rename-stored-files';

const created: string[] = [];

// a file row, written to disk under the given name unless it is meant to be missing
const insertFile = async (name: string, onDisk = true) => {
  if (onDisk) {
    await fs.writeFile(path.join(PUBLIC_PATH, name), `contents of ${name}`);
    created.push(name);
  }

  const [row] = await tdb
    .insert(files)
    .values({
      name,
      originalName: name,
      md5: `md5-${name}-${Date.now()}`,
      userId: 1,
      size: 10,
      mimeType: 'text/plain',
      extension: path.extname(name),
      createdAt: Date.now()
    })
    .returning();

  return row!;
};

const storedName = async (id: number) => {
  const row = await tdb
    .select({ name: files.name })
    .from(files)
    .where(eq(files.id, id))
    .get();

  return row!.name;
};

afterEach(async () => {
  const rows = await tdb.select({ name: files.name }).from(files);

  await Promise.all(
    [...created, ...rows.map(({ name }) => name)].map((name) =>
      fs.rm(path.join(PUBLIC_PATH, name), { force: true })
    )
  );

  created.length = 0;
});

describe('renameStoredFiles', () => {
  test('should move a file stored under its own name to a random one', async () => {
    const file = await insertFile(`report-${Date.now()}.txt`);

    await renameStoredFiles();

    const name = await storedName(file.id);

    expect(name).toMatch(storedNamePattern('.txt'));
    expect(await fs.readFile(path.join(PUBLIC_PATH, name), 'utf-8')).toBe(
      `contents of ${file.name}`
    );
    expect(await fs.exists(path.join(PUBLIC_PATH, file.name))).toBe(false);
  });

  test('should leave a file already under a random name alone', async () => {
    const file = await insertFile(`${crypto.randomUUID()}.png`);

    await renameStoredFiles();

    expect(await storedName(file.id)).toBe(file.name);
  });

  test('should skip a file missing from disk', async () => {
    const file = await insertFile(`gone-${Date.now()}.txt`, false);

    await renameStoredFiles();

    expect(await storedName(file.id)).toBe(file.name);
  });

  test('should change nothing the second time', async () => {
    const file = await insertFile(`twice-${Date.now()}.txt`);

    await renameStoredFiles();

    const first = await storedName(file.id);

    await renameStoredFiles();

    expect(await storedName(file.id)).toBe(first);
  });
});
