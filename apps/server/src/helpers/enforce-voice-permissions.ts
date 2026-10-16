import {
  ChannelPermission,
  ServerEvents,
  StreamKind,
  type TVoiceUserState
} from '@sharkord/shared';
import { channelUserCan } from '../db/queries/channels';
import { VoiceRuntime } from '../runtimes/voice';
import { pubsub } from '../utils/pubsub';

const GATED_STREAMS: {
  permission: ChannelPermission;
  kinds: StreamKind[];
  stateKey: keyof Pick<TVoiceUserState, 'webcamEnabled' | 'sharingScreen'>;
}[] = [
  {
    permission: ChannelPermission.WEBCAM,
    kinds: [StreamKind.VIDEO],
    stateKey: 'webcamEnabled'
  },
  {
    permission: ChannelPermission.SHARE_SCREEN,
    kinds: [StreamKind.SCREEN, StreamKind.SCREEN_AUDIO],
    stateKey: 'sharingScreen'
  }
];

const enforceUserVoicePermissions = async (userId: number) => {
  const runtime = VoiceRuntime.findRuntimeByUserId(userId);

  if (!runtime) return;

  const channelId = runtime.id;
  const allowed = await Promise.all(
    GATED_STREAMS.map(({ permission }) =>
      channelUserCan(channelId, userId, permission)
    )
  );

  let stateChanged = false;

  GATED_STREAMS.forEach(({ kinds, stateKey }, index) => {
    if (allowed[index]) return;

    kinds.forEach((kind) => {
      if (!runtime.getProducer(kind, userId)) return;

      runtime.removeProducer(userId, kind);

      pubsub.publishForChannel(channelId, ServerEvents.VOICE_PRODUCER_CLOSED, {
        channelId,
        remoteId: userId,
        kind
      });
    });

    if (runtime.getUserState(userId)[stateKey]) {
      runtime.updateUserState(userId, { [stateKey]: false });
      stateChanged = true;
    }
  });

  if (!stateChanged) return;

  pubsub.publish(ServerEvents.USER_VOICE_STATE_UPDATE, {
    channelId,
    userId,
    state: runtime.getUserState(userId)
  });
};

// a user who loses webcam or screen share in the voice channel they are in has that stream
// closed at once. otherwise it keeps running until they turn it off, since the permission is
// only checked when a stream starts
const enforceVoicePermissions = async (userIds: number[]) => {
  await Promise.all(userIds.map(enforceUserVoicePermissions));
};

export { enforceVoicePermissions };
