// ended early or past its time. the apps have this rule once more, in Message.swift
export const isPollClosed = (
  poll: { endedAt: number | null; expiresAt: number },
  now: number = Date.now()
) => poll.endedAt !== null || poll.expiresAt <= now;
