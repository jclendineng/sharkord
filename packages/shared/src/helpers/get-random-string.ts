const CHARACTERS =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

// the largest multiple of the alphabet that fits in a byte, so every character is equally
// likely: bytes above it would favour the first few characters and are drawn again
const UNBIASED_BYTE_LIMIT = 256 - (256 % CHARACTERS.length);

// invite codes come from here, so it draws from the platform's secure random source, which
// both the browser and bun provide, instead of Math.random
const getRandomString = (length: number): string => {
  let result = '';

  while (result.length < length) {
    const bytes = crypto.getRandomValues(new Uint8Array(length));

    for (const byte of bytes) {
      if (byte >= UNBIASED_BYTE_LIMIT) continue;

      result += CHARACTERS.charAt(byte % CHARACTERS.length);

      if (result.length === length) break;
    }
  }

  return result;
};

export { getRandomString };
