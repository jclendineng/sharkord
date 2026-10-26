import { sign } from 'crypto';
import { config } from '../config';
import { getPushRelayKey } from './push-relay-key';

const REQUEST_TIMEOUT_MS = 10_000;

// apple's status and reason as the relay passed them on, or the relay's own
type TRelayResult = {
  status: number;
  reason?: string;
};

type TRelayNotification = {
  ticket: string;
  encrypted: string;
};

// signed with this server's key, the one sealed into every ticket issued for it
const sendRelayNotification = async ({
  ticket,
  encrypted
}: TRelayNotification): Promise<TRelayResult> => {
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
export type { TRelayResult };
