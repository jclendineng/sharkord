import { Permission } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { getGifs } from '../../helpers/gifs';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const searchGifsRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.search.maxRequests,
  windowMs: config.rateLimiters.search.windowMs,
  logLabel: 'searchGifs'
})
  .input(
    z.object({
      query: z.string().trim().min(1).max(100),
      page: z.number().int().min(1).max(50).default(1)
    })
  )
  .query(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.SEND_MESSAGES);

    return getGifs(ctx.userId, { query: input.query, page: input.page });
  });

export { searchGifsRoute };
