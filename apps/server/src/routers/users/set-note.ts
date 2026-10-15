import { USER_NOTE_MAX_LENGTH } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { setUserNote } from '../../db/mutations/user-notes';
import { users } from '../../db/schema';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// discord's note on a profile: something the caller wants to remember about someone, for
// nobody but them. an empty one clears it
const setNoteRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.sendAndEditMessage.maxRequests,
  windowMs: config.rateLimiters.sendAndEditMessage.windowMs,
  logLabel: 'setNote'
})
  .input(
    z.object({
      userId: z.number().int().positive(),
      note: z.string().trim().max(USER_NOTE_MAX_LENGTH)
    })
  )
  .mutation(async ({ ctx, input }) => {
    const target = await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.id, input.userId))
      .limit(1)
      .get();

    invariant(target, {
      code: 'NOT_FOUND',
      message: 'User not found'
    });

    await setUserNote(ctx.userId, input.userId, input.note);
  });

export { setNoteRoute };
