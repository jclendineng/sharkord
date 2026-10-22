import { describe, expect, spyOn, test } from 'bun:test';
import { config } from '../../config';
import { printDebug } from '../print-debug';

describe('printDebug', () => {
  test('should leave secrets out of the config it prints', () => {
    const { debug } = config.server;
    const { clientSecret } = config.oidc;
    const log = spyOn(console, 'log').mockImplementation(() => {});

    config.server.debug = true;
    config.oidc.clientSecret = 'very-secret-value';

    try {
      printDebug();

      const output = log.mock.calls.flat().join('\n');

      expect(output).not.toContain('very-secret-value');
      expect(output).toContain('[redacted]');
    } finally {
      config.server.debug = debug;
      config.oidc.clientSecret = clientSecret;
    }
  });
});
