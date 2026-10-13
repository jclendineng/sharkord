import jwt from 'jsonwebtoken';
import type { TTokenPayload } from '../types';

// the token was already verified by whoever holds it, this only reads the claim back
const getTokenSessionId = (token: string | undefined) => {
  if (!token) return undefined;

  const payload = jwt.decode(token) as TTokenPayload | null;

  return payload?.sessionId;
};

export { getTokenSessionId };
