import type { WebSocket } from 'ws';
import type { Context } from '../utils/trpc';

// a seat in voice belongs to the one socket that joined. the channel lives on the socket's
// context, and inVoice on the socket itself so another device taking the seat over can clear it

const claimVoiceSeat = (ctx: Context, channelId: number) => {
  const ws = ctx.getOwnWs();

  ctx.currentVoiceChannelId = channelId;

  if (ws) ws.inVoice = true;
};

const releaseVoiceSeat = (ctx: Context) => {
  const ws = ctx.getOwnWs();

  ctx.currentVoiceChannelId = undefined;

  if (ws) ws.inVoice = false;
};

// another device took the seat, the old socket's own context can't be reached from here
const revokeVoiceSeat = (ws: WebSocket) => {
  ws.inVoice = false;
};

// the channel whose seat this socket still holds. one whose seat another device took over
// still remembers its channel, and must not act on what is now the other device's
const getHeldVoiceChannelId = (ctx: Context) => {
  const ws = ctx.getOwnWs();

  return !ws || ws.inVoice ? ctx.currentVoiceChannelId : undefined;
};

export {
  claimVoiceSeat,
  getHeldVoiceChannelId,
  releaseVoiceSeat,
  revokeVoiceSeat
};
