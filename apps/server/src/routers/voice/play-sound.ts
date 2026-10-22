import { Permission, ServerEvents } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import { publishVoiceEvent } from '../../db/publishers';
import { soundboardSounds } from '../../db/schema';
import { getCurrentVoiceRuntime } from '../../helpers/get-current-voice-runtime';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// everyone's app plays the sound itself at their own soundboard volume, so it is never mixed
// into anyone's mic and a deafened member does not hear it
const playSoundRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.soundboardPlay.maxRequests,
  windowMs: config.rateLimiters.soundboardPlay.windowMs,
  logLabel: 'playSound'
})
  .input(z.object({ soundId: z.number() }))
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.USE_SOUNDBOARD);

    const sound = await db
      .select({ id: soundboardSounds.id })
      .from(soundboardSounds)
      .where(eq(soundboardSounds.id, input.soundId))
      .limit(1)
      .get();

    invariant(sound, {
      code: 'NOT_FOUND',
      message: 'Sound not found.'
    });

    const { channelId } = await getCurrentVoiceRuntime(ctx);

    await publishVoiceEvent(ServerEvents.USER_VOICE_SOUND, {
      channelId,
      userId: ctx.user.id,
      soundId: sound.id
    });
  });

export { playSoundRoute };
