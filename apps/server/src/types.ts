export type TTokenPayload = {
  userId: number;
  exp: number;
  tokenVersion?: number;
  // absent on tokens from before sessions existed, which are still accepted until they expire
  sessionId?: string;
};

export type TConnectionInfo = {
  ip?: string;
  os?: string;
  device?: string;
  userAgent?: string;
};
