import { createPrivateKey, createPublicKey, generateKeyPairSync } from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import { DATA_PATH } from '../helpers/paths';

const KEY_PATH = path.join(DATA_PATH, 'push-relay-key.pem');

type TPushRelayKey = {
  privateKey: ReturnType<typeof createPrivateKey>;
  // the ed25519 public key as unpadded base64url, the form /info publishes and the relay seals
  // into every ticket it issues for this server
  publicKey: string;
};

let cached: Promise<TPushRelayKey> | undefined;

const loadOrCreateKey = async (): Promise<TPushRelayKey> => {
  let privateKey: TPushRelayKey['privateKey'];

  try {
    privateKey = createPrivateKey(await fs.readFile(KEY_PATH, 'utf8'));
  } catch {
    ({ privateKey } = generateKeyPairSync('ed25519'));

    // a new key voids every ticket naming the old one, so it is written once and kept
    await fs.writeFile(
      KEY_PATH,
      privateKey.export({ format: 'pem', type: 'pkcs8' }),
      { mode: 0o600 }
    );
  }

  const { x } = createPublicKey(privateKey).export({ format: 'jwk' });

  return { privateKey, publicKey: x! };
};

const getPushRelayKey = () => {
  cached ??= loadOrCreateKey();

  return cached;
};

export { getPushRelayKey };
