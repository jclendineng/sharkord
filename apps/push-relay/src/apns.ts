import { encoder, fromBase64Url, toBase64Url } from './encoding';
import type { TApnsResult, TEnv, TTicket } from './types';

const PRODUCTION_ORIGIN = 'https://api.push.apple.com';
const SANDBOX_ORIGIN = 'https://api.sandbox.push.apple.com';

// apple rejects a provider token older than an hour and throttles one refreshed more often
// than every twenty minutes. the cache lives as long as the isolate does
const PROVIDER_TOKEN_TTL_MS = 50 * 60 * 1000;

const providerTokens = new Map<string, { value: string; expiresAt: number }>();

const importP8 = (pem: string) => {
  const base64 = pem
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');

  return crypto.subtle.importKey(
    'pkcs8',
    fromBase64Url(base64),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );
};

const getProviderToken = async (env: TEnv, sandbox: boolean) => {
  const keyId = sandbox ? env.APNS_SANDBOX_KEY_ID : env.APNS_KEY_ID;
  const cached = providerTokens.get(keyId);

  if (cached && Date.now() < cached.expiresAt) return cached.value;

  const header = toBase64Url(
    encoder.encode(JSON.stringify({ alg: 'ES256', kid: keyId }))
  );
  const claims = toBase64Url(
    encoder.encode(
      JSON.stringify({
        iss: env.APNS_TEAM_ID,
        iat: Math.floor(Date.now() / 1000)
      })
    )
  );

  const key = await importP8(sandbox ? env.APNS_SANDBOX_KEY : env.APNS_KEY);
  // webcrypto signs ecdsa as raw r and s, which is the form a jwt wants
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    encoder.encode(`${header}.${claims}`)
  );

  const value = `${header}.${claims}.${toBase64Url(new Uint8Array(signature))}`;

  providerTokens.set(keyId, {
    value,
    expiresAt: Date.now() + PROVIDER_TOKEN_TTL_MS
  });

  return value;
};

// the alert is what shows when the app cannot decrypt the payload. the app's notification
// service extension replaces it with the real title and body
const sendToApns = async (
  env: TEnv,
  { deviceToken, sandbox }: TTicket,
  encrypted: string
): Promise<TApnsResult> => {
  const origin = sandbox ? SANDBOX_ORIGIN : PRODUCTION_ORIGIN;

  const response = await fetch(`${origin}/3/device/${deviceToken}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${await getProviderToken(env, sandbox)}`,
      'apns-topic': env.APNS_TOPIC,
      'apns-push-type': 'alert',
      'content-type': 'application/json'
    },
    body: JSON.stringify({
      aps: {
        alert: { body: 'New notification' },
        sound: 'default',
        'mutable-content': 1
      },
      encrypted
    })
  });

  if (response.status === 200) return { status: 200 };

  const text = await response.text();
  let reason: string | undefined;

  try {
    ({ reason } = JSON.parse(text) as { reason?: string });
  } catch {
    reason = undefined;
  }

  return { status: response.status, reason };
};

export { sendToApns };
