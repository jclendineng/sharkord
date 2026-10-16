import { t } from '../../utils/trpc';
import { closeProducerRoute } from './close-producer';
import { connectConsumerTransportRoute } from './connect-consumer-transport';
import { connectProducerTransportRoute } from './connect-producer-transport';
import { consumeRoute } from './consume';
import { createConsumerTransportRoute } from './create-consumer-transport';
import { createProducerTransportRoute } from './create-producer-transport';
import {
  onUserJoinVoiceRoute,
  onUserLeaveVoiceRoute,
  onUserUpdateVoiceStateRoute,
  onUserVoiceMovedRoute,
  onUserVoiceReactionRoute,
  onUserVoiceSoundRoute,
  onVoiceAddExternalStreamRoute,
  onVoiceNewProducerRoute,
  onVoiceProducerClosedRoute,
  onVoiceRemoveExternalStreamRoute,
  onVoiceUpdateExternalStreamRoute
} from './events';
import { getProducersRoute } from './get-producers';
import { joinVoiceRoute } from './join';
import { leaveVoiceRoute } from './leave';
import { moveUserRoute } from './move';
import { playSoundRoute } from './play-sound';
import { produceRoute } from './produce';
import { sendVoiceReactionRoute } from './send-reaction';
import { setConsumerQualityRoute } from './set-consumer-quality';
import { updateVoiceStateRoute } from './update-state';

export const voiceRouter = t.router({
  join: joinVoiceRoute,
  leave: leaveVoiceRoute,
  moveUser: moveUserRoute,
  updateState: updateVoiceStateRoute,
  sendReaction: sendVoiceReactionRoute,
  playSound: playSoundRoute,
  createProducerTransport: createProducerTransportRoute,
  connectProducerTransport: connectProducerTransportRoute,
  createConsumerTransport: createConsumerTransportRoute,
  connectConsumerTransport: connectConsumerTransportRoute,
  closeProducer: closeProducerRoute,
  produce: produceRoute,
  consume: consumeRoute,
  setConsumerQuality: setConsumerQualityRoute,
  getProducers: getProducersRoute,
  onJoin: onUserJoinVoiceRoute,
  onLeave: onUserLeaveVoiceRoute,
  onUpdateState: onUserUpdateVoiceStateRoute,
  onMoved: onUserVoiceMovedRoute,
  onReaction: onUserVoiceReactionRoute,
  onSound: onUserVoiceSoundRoute,
  onNewProducer: onVoiceNewProducerRoute,
  onProducerClosed: onVoiceProducerClosedRoute,
  onAddExternalStream: onVoiceAddExternalStreamRoute,
  onUpdateExternalStream: onVoiceUpdateExternalStreamRoute,
  onRemoveExternalStream: onVoiceRemoveExternalStreamRoute
});
