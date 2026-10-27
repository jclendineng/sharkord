type TRateLimit = {
  maxRequests: number;
  windowMs: number;
};

// limits whose default went up, at the default they had before. a config.ini written earlier
// holds every value, and the file wins over the defaults in the merge, so the old number would
// stay for good. one still exactly at its old default was never chosen by the operator and is
// dropped from the file's values to take the new one; one they changed is left as it is
const RAISED_RATE_LIMITS: Record<string, TRateLimit> = {
  sendAndEditMessage: { maxRequests: 15, windowMs: 60_000 },
  messageAction: { maxRequests: 60, windowMs: 60_000 },
  upload: { maxRequests: 30, windowMs: 60_000 },
  search: { maxRequests: 15, windowMs: 60_000 }
};

// ini reads every value as a string, so the numbers are compared as numbers
const isAt = (limit: unknown, old: TRateLimit) => {
  if (!limit || typeof limit !== 'object') {
    return false;
  }

  const { maxRequests, windowMs } = limit as Record<string, unknown>;

  return (
    Number(maxRequests) === old.maxRequests && Number(windowMs) === old.windowMs
  );
};

const raiseRateLimitDefaults = (
  fileConfig: Record<string, unknown>
): Record<string, unknown> => {
  const { rateLimiters } = fileConfig;

  if (!rateLimiters || typeof rateLimiters !== 'object') {
    return fileConfig;
  }

  const kept = { ...(rateLimiters as Record<string, unknown>) };

  for (const [name, old] of Object.entries(RAISED_RATE_LIMITS)) {
    if (isAt(kept[name], old)) {
      delete kept[name];
    }
  }

  return { ...fileConfig, rateLimiters: kept };
};

export { raiseRateLimitDefaults };
