import { sha256 } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { tdb } from '../../__tests__/setup';
import { rotateDevSecretToken } from '../rotate-dev-secret-token';
import { settings } from '../schema';

const getSecretToken = async () => {
  const row = await tdb
    .select({ secretToken: settings.secretToken })
    .from(settings)
    .limit(1)
    .get();

  return row?.secretToken;
};

describe('rotateDevSecretToken', () => {
  test('should replace the development token with a random one', async () => {
    const devTokenHash = await sha256('dev');

    await tdb.update(settings).set({ secretToken: devTokenHash });
    await rotateDevSecretToken();

    const secretToken = await getSecretToken();

    expect(secretToken).toBeTruthy();
    expect(secretToken).not.toBe(devTokenHash);
  });

  test('should leave any other token alone', async () => {
    const before = await getSecretToken();

    await rotateDevSecretToken();

    expect(await getSecretToken()).toBe(before);
  });
});
