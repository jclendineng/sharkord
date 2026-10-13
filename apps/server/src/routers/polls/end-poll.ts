import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../../db';
import { publishMessage } from '../../db/publishers';
import { polls } from '../../db/schema';
import { getOpenPoll } from '../../helpers/get-open-poll';
import {
  assertCanModifyMessage,
  loadMessageForWrite
} from '../../helpers/load-message-for-write';
import { protectedProcedure } from '../../utils/trpc';

// closes a poll before its time is up, the results stay as they are
const endPollRoute = protectedProcedure
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
