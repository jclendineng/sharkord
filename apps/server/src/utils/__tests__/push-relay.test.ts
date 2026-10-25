import { afterAll, describe, expect, spyOn, test } from 'bun:test';
import { config } from '../../config';
import { sendRelayNotification } from '../push-relay';
import { getPushRelayKey } from '../push-relay-key';

const originalRelayUrl = config.push.relayUrl;

afterAll(() => {
  config.push.relayUrl = originalRelayUrl;
});

const spyOnFetch = (status: number, body = '') =>
  spyOn(globalThis, 'fetch').mockResolvedValue(new Response(body, { status }));

describe('sendRelayNotification', () => {
  test('should post the ticket and payload signed with the server key', async () => {
    config.push.relayUrl = 'https://relay.test';

    const spy = spyOnFetch(200);

    const result = await sendRelayNotification({
      ticket: 'the-ticket',
      encrypted: 'the-payload'
    });

    expect(result).toEqual({ status: 200, reason: undefined });

    const [url, init] = spy.mock.calls[0]!;
    const headers = init!.headers as Record<string, string>;
    const body = init!.body as string;

    expect(`${url}`).toBe('https://relay.test/v1/push');
    expect(JSON.parse(body)).toEqual({
      ticket: 'the-ticket',
      encrypted: 'the-payload'
    });

    // verified the way the relay does it, against the key /info publishes
    const { publicKey } = await getPushRelayKey();
    const key = await crypto.subtle.importKey(
      'jwk',
      { kty: 'OKP', crv: 'Ed25519', x: publicKey },
      { name: 'Ed25519' },
      false,
      ['verify']
    );

    const verified = await crypto.subtle.verify(
      { name: 'Ed25519' },
      key,
      Buffer.from(headers['x-sharkord-signature']!, 'base64url'),
      new TextEncoder().encode(`${headers['x-sharkord-timestamp']}\n${body}`)
    );

    expect(verified).toBe(true);
  });

  test("should hand back the relay's status and reason", async () => {
    config.push.relayUrl = 'https://relay.test';

    spyOnFetch(410, JSON.stringify({ reason: 'ExpiredTicket' }));

    const result = await sendRelayNotification({
      ticket: 'the-ticket',
      encrypted: 'the-payload'
    });

    expect(result).toEqual({ status: 410, reason: 'ExpiredTicket' });
  });

  test('should keep the same key across calls', async () => {
    const [first, second] = await Promise.all([
      getPushRelayKey(),
      getPushRelayKey()
    ]);

    expect(first.publicKey).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(second.publicKey).toBe(first.publicKey);
  });
});
