import { Permission } from '@sharkord/shared';
import { config } from '../../config';
import { getGifCategories } from '../../helpers/gifs';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const getGifCategoriesRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.search.maxRequests,
  windowMs: config.rateLimiters.search.windowMs,
  logLabel: 'gifCategories'
}).query(async ({ ctx }) => {
  await ctx.needsPermission(Permission.SEND_MESSAGES);

  return getGifCategories(ctx.userId);
});

export { getGifCategoriesRoute };
