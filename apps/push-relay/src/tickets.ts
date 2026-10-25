import {
  decoder,
  encoder,
  fromBase64Url,
  toBase64Url,
  toHex
} from './encoding';
import type { TTicket } from './types';

// the app refreshes its ticket on every launch, so this only decides how long a device that
// stopped opening the app keeps receiving pushes
const TICKET_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000;
const IV_LENGTH = 12;

type TTicketKeys = {
  ticketKey: CryptoKey;
  idKey: CryptoKey;
};

let cachedKeys: { secret: string; keys: Promise<TTicketKeys> } | undefined;

// one secret, two keys: sealing tickets and naming devices never share key material
const deriveKeys = async (secret: string): Promise<TTicketKeys> => {
  const base = await crypto.subtle.importKey(
    'raw',
    fromBase64Url(secret),
    'HKDF',
    false,
    ['deriveKey']
  );

  const derive = (
    info: string,
    algorithm: Parameters<SubtleCrypto['deriveKey']>[2],
    usages: Parameters<SubtleCrypto['deriveKey']>[4]
  ) =>
    crypto.subtle.deriveKey(
      {
        name: 'HKDF',
        hash: 'SHA-256',
        salt: new Uint8Array(),
        info: encoder.encode(info)
      },
      base,
      algorithm,
      false,
      usages
    );

  const [ticketKey, idKey] = await Promise.all([
    derive('sharkord ticket', { name: 'AES-GCM', length: 256 }, [
      'encrypt',
      'decrypt'
    ]),
    derive('sharkord device id', { name: 'HMAC', hash: 'SHA-256' }, ['sign'])
  ]);

  return { ticketKey, idKey };
};

const getKeys = (secret: string) => {
  if (cachedKeys?.secret !== secret) {
    cachedKeys = { secret, keys: deriveKeys(secret) };
  }

  return cachedKeys.keys;
};

// the id is stable for one device on one server, so the server can recognise a refreshed
// ticket as the same device. it is 64 hex characters, the shape the server already stores
const getDeviceId = async (
  idKey: CryptoKey,
  deviceToken: string,
  serverKey: string
) => {
  const signature = await crypto.subtle.sign(
    'HMAC',
    idKey,
    encoder.encode(`${deviceToken}\n${serverKey}`)
  );

  return toHex(new Uint8Array(signature));
};

const issueTicket = async (
  secret: string,
  { deviceToken, sandbox, serverKey }: Omit<TTicket, 'expiresAt'>,
  now = Date.now()
) => {
  const { ticketKey, idKey } = await getKeys(secret);
  const ticket: TTicket = {
    deviceToken,
    sandbox,
    serverKey,
    expiresAt: now + TICKET_LIFETIME_MS
  };

  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv },
      ticketKey,
      encoder.encode(JSON.stringify(ticket))
    )
  );

  const bytes = new Uint8Array(iv.length + sealed.length);

  bytes.set(iv);
  bytes.set(sealed, iv.length);

  return {
    id: await getDeviceId(idKey, deviceToken, serverKey),
    ticket: toBase64Url(bytes),
    expiresAt: ticket.expiresAt
  };
};

// undefined for anything this relay did not seal itself, whatever is wrong with it
const openTicket = async (
  secret: string,
  value: string
): Promise<TTicket | undefined> => {
  const { ticketKey } = await getKeys(secret);

  try {
    const bytes = fromBase64Url(value);
    const opened = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: bytes.slice(0, IV_LENGTH) },
      ticketKey,
      bytes.slice(IV_LENGTH)
    );

    return JSON.parse(decoder.decode(opened)) as TTicket;
  } catch {
    return undefined;
  }
};

export { issueTicket, openTicket, TICKET_LIFETIME_MS };
