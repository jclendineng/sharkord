// the slice of cloudflare's rate limiting binding the relay uses, declared here rather than
// pulling in all of @cloudflare/workers-types for one method
type TRateLimiter = {
  limit: (options: { key: string }) => Promise<{ success: boolean }>;
};

type TEnv = {
  TICKET_SECRET: string;
  APNS_TOPIC: string;
  APNS_TEAM_ID: string;
  APNS_KEY_ID: string;
  APNS_KEY: string;
  APNS_SANDBOX_KEY_ID: string;
  APNS_SANDBOX_KEY: string;
  TICKETS_LIMITER: TRateLimiter;
  SERVER_LIMITER: TRateLimiter;
  DEVICE_LIMITER: TRateLimiter;
};

type TTicket = {
  deviceToken: string;
  sandbox: boolean;
  serverKey: string;
  expiresAt: number;
};

type TApnsResult = {
  status: number;
  reason?: string;
};

export type { TApnsResult, TEnv, TRateLimiter, TTicket };
