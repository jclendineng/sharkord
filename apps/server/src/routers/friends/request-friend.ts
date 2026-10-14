import { ServerEvents } from '@sharkord/shared';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { config } from '../../config';
import { db } from '../../db';
import {
  acceptFriendRequest,
  addFriendRequest
} from '../../db/mutations/friends';
import { getFriendship } from '../../db/queries/friends';
import { users } from '../../db/schema';
import { invariant } from '../../utils/invariant';
import { protectedProcedure, rateLimitedProcedure } from '../../utils/trpc';

// asks someone to be friends. asking someone who already asked you makes you friends, as
// discord does, and asking twice changes nothing
const requestFriendRoute = rateLimitedProcedure(protectedProcedure, {
  maxRequests: config.rateLimiters.openDirectMessage.maxRequests,
  windowMs: config.rateLimiters.openDirectMessage.windowMs,
  logLabel: 'requestFriend'
})
  .input(z.object({ userId: z.number().int().positive() }))
  .mutation(async ({ ctx, input }) => {
    invariant(input.userId !== ctx.userId, {
      code: 'BAD_REQUEST',
      message: "You can't add yourself as a friend."
    });

    const target = await db
      .select({ id: users.id, banned: users.banned })
      .from(users)
      .where(eq(users.id, input.userId))
      .limit(1)
      .get();

    invariant(target && !target.banned, {
      code: 'NOT_FOUND',
      message: 'User not found'
    });

    const existing = await getFriendship(ctx.userId, input.userId);

    invariant(existing?.status !== 'accepted', {
      code: 'BAD_REQUEST',
      message: "You're already friends."
    });

    if (existing?.requesterId === ctx.userId) {
      return;
    }

    if (existing) {
      await acceptFriendRequest(ctx.userId, input.userId);
    } else {
      await addFriendRequest(ctx.userId, input.userId);
    }

    ctx.pubsub.publishFor(input.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: ctx.userId
    });
    ctx.pubsub.publishFor(ctx.userId, ServerEvents.FRIENDSHIP_UPDATE, {
      userId: input.userId
    });
  });

export { requestFriendRoute };
