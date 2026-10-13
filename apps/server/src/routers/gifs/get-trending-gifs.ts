import { Permission } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { getGifs } from '../../helpers/gifs';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const getTrendingGifsRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.search.maxRequests,
  windowMs: config.rateLimiters.search.windowMs,
  logLabel: 'trendingGifs'
})
  .input(z.object({ page: z.number().int().min(1).max(50).default(1) }))
  .query(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.SEND_MESSAGES);

    return getGifs(ctx.userId, { page: input.page });
  });

export { getTrendingGifsRoute };
