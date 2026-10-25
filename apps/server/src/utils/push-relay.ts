import { sign } from 'crypto';
import { config } from '../config';
import type { TApnsResult } from './apns';
import { getPushRelayKey } from './push-relay-key';

const REQUEST_TIMEOUT_MS = 10_000;

type TRelayNotification = {
  ticket: string;
  encrypted: string;
};

// the relay answers with apple's status and reason, so the result is handled the same way as a
// direct send
const sendRelayNotification = async ({
  ticket,
  encrypted
}: TRelayNotification): Promise<TApnsResult> => {
  const body = JSON.stringify({ ticket, encrypted });
  const timestamp = `${Date.now()}`;
  const { privateKey } = await getPushRelayKey();
  const signature = sign(
    null,
    Buffer.from(`${timestamp}\n${body}`),
    privateKey
  ).toString('base64url');

  const response = await fetch(new URL('/v1/push', config.push.relayUrl), {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-sharkord-timestamp': timestamp,
      'x-sharkord-signature': signature
    },
    body,
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
  });

  let reason: string | undefined;

  try {
    ({ reason } = (await response.json()) as { reason?: string });
  } catch {
    reason = undefined;
  }

  return { status: response.status, reason };
};

export { sendRelayNotification };
