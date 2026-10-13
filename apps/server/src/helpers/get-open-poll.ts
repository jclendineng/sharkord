import { eq } from 'drizzle-orm';
import { db } from '../db';
import { polls } from '../db/schema';
import { invariant } from '../utils/invariant';

// a poll that still takes votes: not ended early and not past its time
const getOpenPoll = async (messageId: number) => {
  const poll = await db
    .select({
      allowMultiple: polls.allowMultiple,
      expiresAt: polls.expiresAt,
      endedAt: polls.endedAt
    })
    .from(polls)
    .where(eq(polls.messageId, messageId))
    .limit(1)
    .get();

  invariant(poll, {
    code: 'NOT_FOUND',
    message: 'This message has no poll.'
  });

  invariant(poll.endedAt === null && poll.expiresAt > Date.now(), {
    code: 'BAD_REQUEST',
    message: 'This poll has ended.'
  });

  return poll;
};

export { getOpenPoll };
