import { encoder, fromBase64Url } from './encoding';

// a server signs `${timestamp}\n${body}` with the ed25519 key it published in /info, the
// same key that was sealed into every ticket issued for it
const verifyServerSignature = async ({
  serverKey,
  timestamp,
  body,
  signature
}: {
  serverKey: string;
  timestamp: string;
  body: string;
  signature: string;
}) => {
  try {
    const key = await crypto.subtle.importKey(
      'jwk',
      { kty: 'OKP', crv: 'Ed25519', x: serverKey },
      { name: 'Ed25519' },
      false,
      ['verify']
    );

    return await crypto.subtle.verify(
      { name: 'Ed25519' },
      key,
      fromBase64Url(signature),
      encoder.encode(`${timestamp}\n${body}`)
    );
  } catch {
    return false;
  }
};

export { verifyServerSignature };
