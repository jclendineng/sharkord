import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { publishMessage } from '../../db/publishers';
import { polls } from '../../db/schema';
import { getOpenPoll } from '../../helpers/get-open-poll';
import {
  assertCanModifyMessage,
  loadMessageForWrite
} from '../../helpers/load-message-for-write';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// closes a poll before its time is up, the results stay as they are
const endPollRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.messageAction.maxRequests,
  windowMs: config.rateLimiters.messageAction.windowMs,
  logLabel: 'endPoll'
})
  .input(z.object({ messageId: z.number() }))
  .mutation(async ({ input, ctx }) => {
    const message = await loadMessageForWrite(ctx, input.messageId);

    await assertCanModifyMessage(ctx, message, 'end this poll');
    await getOpenPoll(input.messageId);

    await db
      .update(polls)
      .set({ endedAt: Date.now() })
      .where(eq(polls.messageId, input.messageId));

    publishMessage(input.messageId, message.channelId, 'update');
  });

export { endPollRoute };
