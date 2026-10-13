import fs from 'fs/promises';
import http2 from 'http2';
import jwt from 'jsonwebtoken';
import { config } from '../config';

const PRODUCTION_ORIGIN = 'https://api.push.apple.com';
const SANDBOX_ORIGIN = 'https://api.sandbox.push.apple.com';
const REQUEST_TIMEOUT_MS = 10_000;

// apple rejects a provider token older than an hour and throttles one refreshed more often
// than every twenty minutes, so it is reused in between
const PROVIDER_TOKEN_TTL_MS = 50 * 60 * 1000;

type TApnsResult = {
  status: number;
  reason?: string;
};

type TApnsNotification = {
  deviceToken: string;
  sandbox: boolean;
  payload: Record<string, unknown>;
};

let providerToken: { value: string; expiresAt: number } | null = null;

const sessions = new Map<string, http2.ClientHttp2Session>();

const getProviderToken = async () => {
  if (providerToken && Date.now() < providerToken.expiresAt) {
    return providerToken.value;
  }

  const key = await fs.readFile(config.push.apnsKeyPath, 'utf8');
  const value = jwt.sign({}, key, {
    algorithm: 'ES256',
    issuer: config.push.apnsTeamId,
    keyid: config.push.apnsKeyId
  });

  providerToken = { value, expiresAt: Date.now() + PROVIDER_TOKEN_TTL_MS };

  return value;
};

// apple asks providers to keep one connection open rather than reconnect per notification
const getSession = (origin: string) => {
  const existing = sessions.get(origin);

  if (existing && !existing.closed && !existing.destroyed) return existing;

  const session = http2.connect(origin);

  // without a listener an error on an idle connection would take the process down
  session.on('error', () => sessions.delete(origin));
  session.on('close', () => sessions.delete(origin));

  sessions.set(origin, session);

  return session;
};

const sendApnsNotification = async ({
  deviceToken,
  sandbox,
  payload
}: TApnsNotification): Promise<TApnsResult> => {
  const authorization = `bearer ${await getProviderToken()}`;
  const session = getSession(sandbox ? SANDBOX_ORIGIN : PRODUCTION_ORIGIN);

  const result = await new Promise<TApnsResult>((resolve, reject) => {
    const request = session.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization,
      'apns-topic': config.push.apnsBundleId,
      'apns-push-type': 'alert',
      'content-type': 'application/json'
    });

    let status = 0;
    let body = '';

    request.setEncoding('utf8');
    request.setTimeout(REQUEST_TIMEOUT_MS, () => {
      request.close(http2.constants.NGHTTP2_CANCEL);
      reject(new Error('APNs did not answer in time'));
    });

    request.on('response', (headers) => {
      status = Number(headers[':status']);
    });
    request.on('data', (chunk: string) => {
      body += chunk;
    });
    request.on('end', () => {
      let reason: string | undefined;

      // a success has an empty body, a failure carries { reason }
      try {
        reason = (JSON.parse(body) as { reason?: string }).reason;
      } catch {
        reason = undefined;
      }

      resolve({ status, reason });
    });
    request.on('error', reject);

    request.end(JSON.stringify(payload));
  });

  if (result.reason === 'ExpiredProviderToken') {
    providerToken = null;
  }

  return result;
};

export { sendApnsNotification };
export type { TApnsNotification, TApnsResult };
