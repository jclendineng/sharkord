import { SOUNDBOARD_LIBRARY } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { testsBaseUrl } from '../../__tests__/setup';

describe('/soundboard-library', () => {
  test('should serve a library sound to preview without signing in', async () => {
    const response = await fetch(
      `${testsBaseUrl}/soundboard-library/you-win.m4a`
    );

    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toBe('audio/mp4');
    expect((await response.arrayBuffer()).byteLength).toBeGreaterThan(0);
  });

  test('should have a file for every sound in the library', async () => {
    for (const { key } of SOUNDBOARD_LIBRARY) {
      const response = await fetch(
        `${testsBaseUrl}/soundboard-library/${key}.m4a`
      );

      expect(response.status, key).toBe(200);
    }
  });

  test('should refuse a sound that is not in the library', async () => {
    const response = await fetch(`${testsBaseUrl}/soundboard-library/nope.m4a`);

    expect(response.status).toBe(404);
  });

  test('should not reach outside the library with a path', async () => {
    const response = await fetch(
      `${testsBaseUrl}/soundboard-library/..%2F..%2Fconfig.ini`
    );

    expect(response.status).toBe(404);
  });
});
