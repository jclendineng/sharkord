import { POLL_MAX_ANSWERS } from '@sharkord/shared';
import { and, eq, inArray } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { publishMessage } from '../../db/publishers';
import { pollAnswers, pollVotes } from '../../db/schema';
import { getOpenPoll } from '../../helpers/get-open-poll';
import { loadMessageForWrite } from '../../helpers/load-message-for-write';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// replaces the caller's vote with the answers given, none takes the vote back. like discord,
// anyone who can see the channel can vote, so there is no global permission beyond the channel
// access loadMessageForWrite proves
const votePollRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.toggleMessageReaction.maxRequests,
  windowMs: config.rateLimiters.toggleMessageReaction.windowMs,
  logLabel: 'votePoll'
})
  .input(
    z.object({
      messageId: z.number(),
      answerIds: z.array(z.number()).max(POLL_MAX_ANSWERS)
    })
  )
  .mutation(async ({ input, ctx }) => {
    const message = await loadMessageForWrite(ctx, input.messageId);
    const poll = await getOpenPoll(input.messageId);
    const answerIds = Array.from(new Set(input.answerIds));

    invariant(poll.allowMultiple || answerIds.length <= 1, {
      code: 'BAD_REQUEST',
      message: 'This poll takes a single answer.'
    });

    if (answerIds.length > 0) {
      const known = await db
        .select({ id: pollAnswers.id })
        .from(pollAnswers)
        .where(
          and(
            eq(pollAnswers.messageId, input.messageId),
            inArray(pollAnswers.id, answerIds)
          )
        );

      invariant(known.length === answerIds.length, {
        code: 'BAD_REQUEST',
        message: 'That answer is not part of this poll.'
      });
    }

    const now = Date.now();

    db.transaction((tx) => {
      tx.delete(pollVotes)
        .where(
          and(
            eq(pollVotes.messageId, input.messageId),
            eq(pollVotes.userId, ctx.userId)
          )
        )
        .run();

      if (answerIds.length > 0) {
        tx.insert(pollVotes)
          .values(
            answerIds.map((answerId) => ({
              answerId,
              messageId: input.messageId,
              userId: ctx.userId,
              createdAt: now
            }))
          )
          .run();
      }
    });

    publishMessage(input.messageId, message.channelId, 'update');
  });

export { votePollRoute };
