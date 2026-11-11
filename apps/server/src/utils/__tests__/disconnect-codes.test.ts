import { DisconnectCode } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';

// the router tests close fake sockets, so a code outside the range the websocket spec leaves to
// applications only shows up on a deployed server: bun's ws from 1.4.4 throws on it, which stops
// a kick or ban before anything is written. unexpected is what the browser reports for a lost
// connection, never one we send
describe('disconnect codes', () => {
  const sentCodes = Object.entries(DisconnectCode).filter(
    ([, code]) => typeof code === 'number' && code !== DisconnectCode.UNEXPECTED
  );

  test.each(sentCodes)('%s is a close code the server can send', (_, code) => {
    expect(code).toBeGreaterThanOrEqual(3000);
    expect(code).toBeLessThanOrEqual(4999);
  });
});
