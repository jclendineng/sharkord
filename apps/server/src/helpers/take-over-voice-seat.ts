import { ServerEvents } from '@sharkord/shared';
import { publishVoiceEvent } from '../db/publishers';
import { VoiceRuntime } from '../runtimes/voice';
import type { Context } from '../utils/trpc';
import { findVoiceSocket } from '../utils/wss';

// joining voice from another device, or from the same one after its connection dropped,
// takes the seat over as discord does. the old seat's leave tells the device that held it to
// end its call; the one joining ignores its own leave while the join is under way. before,
// the join was refused, and a phone back from the background whose old socket the server had
// not yet noticed was dead could neither join nor leave
const takeOverVoiceSeat = async (ctx: Context) => {
  const ownSocket = ctx.getOwnWs();

  // a caller with no socket of its own, a plugin's, takes nobody's seat
  if (!ownSocket) return;

  const voiceSocket = findVoiceSocket(ctx.user.id);

  if (voiceSocket === ownSocket) return;

  // the old socket closing later must not take the new seat with it
  if (voiceSocket) voiceSocket.inVoice = false;

  const runtime = VoiceRuntime.findRuntimeByUserId(ctx.user.id);

  if (!runtime) return;

  runtime.removeUser(ctx.user.id);

  await publishVoiceEvent(ServerEvents.USER_LEAVE_VOICE, {
    channelId: runtime.id,
    userId: ctx.user.id,
    takenOver: true
  });
};

export { takeOverVoiceSeat };
