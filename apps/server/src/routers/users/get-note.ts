import { z } from 'zod';
import { getUserNote } from '../../db/queries/user-notes';
import { protectedProcedure } from '../../utils/trpc';

// the caller's own note on someone, which only they ever see
const getNoteRoute = protectedProcedure
  .input(z.object({ userId: z.number().int().positive() }))
  .query(async ({ ctx, input }) => getUserNote(ctx.userId, input.userId));

export { getNoteRoute };
