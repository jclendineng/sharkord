// ecdh p-256 with a fresh key per notification, hkdf-sha256, then aes-256-gcm. the app does the
// same with cryptokit: x963 public keys, the ephemeral key as the hkdf salt
const INFO = new TextEncoder().encode('sharkord push v1');
const NONCE_LENGTH = 12;

// the result is ephemeral public key (65) + nonce (12) + ciphertext and tag, as base64url
const encryptForDevice = async (
  encryptionKey: string,
  payload: Record<string, unknown>
) => {
  const recipient = await crypto.subtle.importKey(
    'raw',
    Buffer.from(encryptionKey, 'base64url'),
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    []
  );

  const ephemeral = (await crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' },
    true,
    ['deriveBits']
  )) as CryptoKeyPair;

  const [sharedSecret, ephemeralPublicKey] = await Promise.all([
    crypto.subtle.deriveBits(
      { name: 'ECDH', public: recipient },
      ephemeral.privateKey,
      256
    ),
    crypto.subtle.exportKey('raw', ephemeral.publicKey)
  ]);

  const hkdfKey = await crypto.subtle.importKey(
    'raw',
    sharedSecret,
    'HKDF',
    false,
    ['deriveKey']
  );

  const aesKey = await crypto.subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt: ephemeralPublicKey, info: INFO },
    hkdfKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt']
  );

  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_LENGTH));
  const sealed = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce },
    aesKey,
    new TextEncoder().encode(JSON.stringify(payload))
  );

  return Buffer.concat([
    Buffer.from(ephemeralPublicKey),
    nonce,
    Buffer.from(sealed)
  ]).toString('base64url');
};

export { encryptForDevice };
