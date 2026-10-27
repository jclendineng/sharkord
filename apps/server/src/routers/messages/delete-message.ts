import { z } from 'zod';
import { config } from '../../config';
import { deleteMessage } from '../../db/mutations/messages';
import {
  assertCanModifyMessage,
  loadMessageForWrite
} from '../../helpers/load-message-for-write';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const deleteMessageRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.deleteMessage.maxRequests,
  windowMs: config.rateLimiters.deleteMessage.windowMs,
  logLabel: 'deleteMessage'
})
  .input(z.object({ messageId: z.number() }))
  .mutation(async ({ input, ctx }) => {
    const targetMessage = await loadMessageForWrite(ctx, input.messageId);

    await assertCanModifyMessage(ctx, targetMessage, 'delete this message');

    await deleteMessage({
      id: input.messageId,
      channelId: targetMessage.channelId,
      parentMessageId: targetMessage.parentMessageId
    });
  });

export { deleteMessageRoute };
