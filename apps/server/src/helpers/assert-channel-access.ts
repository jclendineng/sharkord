import { ChannelPermission } from '@sharkord/shared';
import { assertDmChannel } from '../db/queries/dms';
import type { Context } from '../utils/trpc';

const assertChannelAccess = async (
  ctx: Context,
  channelId: number
): Promise<void> => {
  await assertDmChannel(channelId, ctx.userId);
  await ctx.needsChannelPermission(channelId, ChannelPermission.VIEW_CHANNEL);
};

// the same check for code that filters rather than rejects, such as a list of files where only
// the ones the caller can see are answered
const canAccessChannel = async (
  ctx: Context,
  channelId: number
): Promise<boolean> => {
  try {
    await assertChannelAccess(ctx, channelId);

    return true;
  } catch {
    return false;
  }
};

export { assertChannelAccess, canAccessChannel };
