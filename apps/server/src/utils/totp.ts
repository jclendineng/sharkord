import { createHmac, randomBytes } from 'crypto';

// rfc 6238 as every authenticator app does it: sha1, 30 second steps, six digits
const STEP_SECONDS = 30;
const DIGITS = 6;
const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

const toBase32 = (bytes: Buffer): string => {
  let bits = 0;
  let value = 0;
  let output = '';

  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;

    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }

  if (bits > 0) {
    output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }

  return output;
};

const fromBase32 = (text: string): Buffer => {
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];

  for (const character of text.replace(/=+$/, '').toUpperCase()) {
    const index = BASE32_ALPHABET.indexOf(character);

    if (index === -1) continue;

    value = (value << 5) | index;
    bits += 5;

    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }

  return Buffer.from(bytes);
};

const generateTotpSecret = () => toBase32(randomBytes(20));

const getTotpStep = (now = Date.now()) => Math.floor(now / 1000 / STEP_SECONDS);

const getTotpCode = (secret: string, step: number): string => {
  const counter = Buffer.alloc(8);

  counter.writeBigUInt64BE(BigInt(step));

  const hmac = createHmac('sha1', fromBase32(secret)).update(counter).digest();
  const offset = hmac[hmac.length - 1]! & 15;
  const binary =
    ((hmac[offset]! & 127) << 24) |
    (hmac[offset + 1]! << 16) |
    (hmac[offset + 2]! << 8) |
    hmac[offset + 3]!;

  return String(binary % 10 ** DIGITS).padStart(DIGITS, '0');
};

// the step a code belongs to, one step either side allowed for a clock that drifts, or null.
// a step at or before lastStep was already used and is refused
const matchTotpStep = (
  secret: string,
  code: string,
  lastStep: number
): number | null => {
  const current = getTotpStep();

  for (const step of [current - 1, current, current + 1]) {
    if (step <= lastStep) continue;
    if (getTotpCode(secret, step) === code) return step;
  }

  return null;
};

const getTotpUri = (issuer: string, account: string, secret: string) => {
  const label = encodeURIComponent(`${issuer}:${account}`);
  const params = new URLSearchParams({
    secret,
    issuer,
    algorithm: 'SHA1',
    digits: String(DIGITS),
    period: String(STEP_SECONDS)
  });

  return `otpauth://totp/${label}?${params.toString()}`;
};

export {
  generateTotpSecret,
  getTotpCode,
  getTotpStep,
  getTotpUri,
  matchTotpStep
};
