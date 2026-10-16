import { Permission } from '@sharkord/shared';
import { z } from 'zod';
import { config } from '../../config';
import { addFreesoundSound } from '../../helpers/freesound-sounds';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

const addFreesoundSoundRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.addEmoji.maxRequests,
  windowMs: config.rateLimiters.addEmoji.windowMs,
  logLabel: 'addFreesoundSound'
})
  .input(z.object({ freesoundId: z.number().int().positive() }))
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_SOUNDBOARD);

    return addFreesoundSound(input.freesoundId, ctx.userId);
  });

export { addFreesoundSoundRoute };
