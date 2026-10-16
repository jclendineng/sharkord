import { Permission } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { searchFreesoundSounds } from '../../helpers/freesound-sounds';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// only for managers, it is where sounds are picked from to add
const searchFreesoundRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.search.maxRequests,
  windowMs: config.rateLimiters.search.windowMs,
  logLabel: 'searchFreesound'
})
  .input(
    z.object({
      query: z.string().trim().min(1).max(100),
      page: z.number().int().min(1).max(50).default(1)
    })
  )
  .query(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_SOUNDBOARD);

    return searchFreesoundSounds(input.query, input.page);
  });

export { searchFreesoundRoute };
