import {
  ActivityLogType,
  Permission,
  REACTION_EMOJI_MAX_LENGTH,
  SOUND_MAX_VOLUME,
  SOUND_MIN_VOLUME,
  SOUND_NAME_MAX_LENGTH,
  SOUND_NAME_MIN_LENGTH
} from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../../db';
import { publishSound } from '../../db/publishers';
import { soundboardSounds } from '../../db/schema';
import { enqueueActivityLog } from '../../queues/activity-log';
import { invariant } from '../../utils/invariant';
import { protectedProcedure } from '../../utils/trpc';

const updateSoundRoute = protectedProcedure
  .input(
    z.object({
      soundId: z.number(),
      name: z
        .string()
        .trim()
        .min(SOUND_NAME_MIN_LENGTH)
        .max(SOUND_NAME_MAX_LENGTH),
      emoji: z.string().trim().max(REACTION_EMOJI_MAX_LENGTH).optional(),
      volume: z.number().int().min(SOUND_MIN_VOLUME).max(SOUND_MAX_VOLUME)
    })
  )
  .mutation(async ({ input, ctx }) => {
    await ctx.needsPermission(Permission.MANAGE_SOUNDBOARD);

    const existing = await db
      .select({ id: soundboardSounds.id, name: soundboardSounds.name })
      .from(soundboardSounds)
      .where(eq(soundboardSounds.id, input.soundId))
      .limit(1)
      .get();

    invariant(existing, {
      code: 'NOT_FOUND',
      message: 'Sound not found.'
    });

    await db
      .update(soundboardSounds)
      .set({
        name: input.name,
        emoji: input.emoji || null,
        volume: input.volume,
        updatedAt: Date.now()
      })
      .where(eq(soundboardSounds.id, existing.id));

    publishSound(existing.id, 'update');
    enqueueActivityLog({
      type: ActivityLogType.UPDATED_SOUND,
      userId: ctx.user.id,
      details: { fromName: existing.name, toName: input.name }
    });
  });

export { updateSoundRoute };
