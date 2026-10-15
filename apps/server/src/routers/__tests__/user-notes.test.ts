import { USER_NOTE_MAX_LENGTH } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { userNotes, users } from '../../db/schema';

describe('users.setNote and users.getNote', () => {
  test('should save a note and read it back', async () => {
    const { caller } = await initTest(1);

    await caller.users.setNote({ userId: 3, note: '  plays support  ' });

    expect(await caller.users.getNote({ userId: 3 })).toBe('plays support');
  });

  test('should keep a note to the one who wrote it', async () => {
    const { caller } = await initTest(1);
    const { caller: otherCaller } = await initTest(2);

    await caller.users.setNote({ userId: 3, note: 'mine' });

    expect(await otherCaller.users.getNote({ userId: 3 })).toBe('');
  });

  test('should replace a note', async () => {
    const { caller } = await initTest(1);

    await caller.users.setNote({ userId: 3, note: 'first' });
    await caller.users.setNote({ userId: 3, note: 'second' });

    const rows = await tdb.select().from(userNotes);

    expect(rows).toHaveLength(1);
    expect(await caller.users.getNote({ userId: 3 })).toBe('second');
  });

  test('should remove a note set to nothing', async () => {
    const { caller } = await initTest(1);

    await caller.users.setNote({ userId: 3, note: 'gone soon' });
    await caller.users.setNote({ userId: 3, note: '   ' });

    expect(await tdb.select().from(userNotes)).toHaveLength(0);
    expect(await caller.users.getNote({ userId: 3 })).toBe('');
  });

  test('should refuse a note on someone who does not exist', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.users.setNote({ userId: 999, note: 'nobody' })
    ).rejects.toThrow('User not found');
  });

  test('should refuse a note that is too long', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.users.setNote({
        userId: 3,
        note: 'a'.repeat(USER_NOTE_MAX_LENGTH + 1)
      })
    ).rejects.toThrow();
  });

  test('should go with the person it was about', async () => {
    const { caller } = await initTest(1);

    await caller.users.setNote({ userId: 4, note: 'about user b' });
    await tdb.delete(users).where(eq(users.id, 4));

    expect(await tdb.select().from(userNotes)).toHaveLength(0);
  });
});
