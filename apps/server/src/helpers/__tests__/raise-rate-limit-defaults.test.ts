import { describe, expect, test } from 'bun:test';
import { parse } from 'ini';
import { defaultConfig } from '../../config';
import { deepMerge } from '../../utils/deep-merge';
import { raiseRateLimitDefaults } from '../raise-rate-limit-defaults';

// a config.ini as an older server wrote it, every value a string the way ini reads it back
const OLD_FILE = `
[rateLimiters.sendAndEditMessage]
maxRequests=15
windowMs=60000

[rateLimiters.search]
maxRequests=40
windowMs=60000

[rateLimiters.login]
maxRequests=5
windowMs=60000
`;

describe('raiseRateLimitDefaults', () => {
  test('should give a limit still at its old default the new one', () => {
    const merged = deepMerge(
      structuredClone(defaultConfig),
      raiseRateLimitDefaults(parse(OLD_FILE))
    );

    expect(merged.rateLimiters.sendAndEditMessage).toEqual(
      defaultConfig.rateLimiters.sendAndEditMessage
    );
    expect(merged.rateLimiters.sendAndEditMessage.maxRequests).toBe(60);
  });

  test('should keep a limit the operator changed', () => {
    const fileConfig = raiseRateLimitDefaults(parse(OLD_FILE));

    expect(fileConfig.rateLimiters).toMatchObject({
      search: { maxRequests: '40', windowMs: '60000' }
    });
  });

  test('should leave limits whose default did not change', () => {
    const fileConfig = raiseRateLimitDefaults(parse(OLD_FILE));

    expect(fileConfig.rateLimiters).toMatchObject({
      login: { maxRequests: '5', windowMs: '60000' }
    });
  });

  test('should leave a file without rate limits as it is', () => {
    const fileConfig = { server: { port: '4991' } };

    expect(raiseRateLimitDefaults(fileConfig)).toBe(fileConfig);
  });
});
