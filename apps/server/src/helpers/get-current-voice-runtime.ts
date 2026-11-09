import { Permission } from '@sharkord/shared';
import { VoiceRuntime } from '../runtimes/voice';
import { invariant } from '../utils/invariant';
import type { Context } from '../utils/trpc';
import { getHeldVoiceChannelId } from './voice-seat';

const getCurrentVoiceRuntime = async (ctx: Context) => {
  await ctx.needsPermission(Permission.JOIN_VOICE_CHANNELS);

  const channelId = getHeldVoiceChannelId(ctx);

  invariant(channelId, {
    code: 'BAD_REQUEST',
    message: 'User is not in a voice channel'
  });

  const runtime = VoiceRuntime.findById(channelId);

  invariant(runtime, {
    code: 'INTERNAL_SERVER_ERROR',
    message: 'Voice runtime not found for this channel'
  });

  return { runtime, channelId };
};

export { getCurrentVoiceRuntime };
