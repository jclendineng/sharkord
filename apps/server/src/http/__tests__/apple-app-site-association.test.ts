import { describe, expect, test } from 'bun:test';
import { testsBaseUrl } from '../../__tests__/setup';

describe('/.well-known/apple-app-site-association', () => {
  test('should let the ios app open invite links and nothing else', async () => {
    const response = await fetch(
      `${testsBaseUrl}/.well-known/apple-app-site-association`
    );

    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toBe('application/json');

    const body = (await response.json()) as {
      applinks: {
        details: { appIDs: string[]; components: unknown[] }[];
      };
    };
    const [detail] = body.applinks.details;

    expect(detail!.appIDs).toEqual(['KNSS87R6RR.com.sharkord.ios']);
    expect(detail!.components).toEqual([
      { '?': { invite: '?*' }, comment: 'invite links' }
    ]);
  });
});
