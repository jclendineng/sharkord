import {
  ChannelPermission,
  Permission,
  ServerEvents,
  StreamKind,
  type TVoiceUserState
} from '@sharkord/shared';
import { publishVoiceEvent } from '../db/publishers';
import { channelUserCan } from '../db/queries/channels';
import { userCan } from '../db/queries/roles';
import { VoiceRuntime } from '../runtimes/voice';
import { pubsub } from '../utils/pubsub';

// the same pairs produce checks before a stream starts
const GATED_STREAMS: {
  permission: ChannelPermission;
  serverPermission: Permission;
  kinds: StreamKind[];
  stateKey: keyof Pick<TVoiceUserState, 'webcamEnabled' | 'sharingScreen'>;
}[] = [
  {
    permission: ChannelPermission.WEBCAM,
    serverPermission: Permission.ENABLE_WEBCAM,
    kinds: [StreamKind.VIDEO],
    stateKey: 'webcamEnabled'
  },
  {
    permission: ChannelPermission.SHARE_SCREEN,
    serverPermission: Permission.SHARE_SCREEN,
    kinds: [StreamKind.SCREEN, StreamKind.SCREEN_AUDIO],
    stateKey: 'sharingScreen'
  }
];

const enforceUserVoicePermissions = async (userId: number) => {
  const runtime = VoiceRuntime.findRuntimeByUserId(userId);

  if (!runtime) return;

  const channelId = runtime.id;
  const allowed = await Promise.all(
    GATED_STREAMS.map(async ({ permission, serverPermission }) => {
      const [channelAllowed, serverAllowed] = await Promise.all([
        // the same rule produce applies, or a moved user would lose a stream they may run
        channelUserCan(channelId, userId, permission, { ignoreView: true }),
        userCan(userId, serverPermission)
      ]);

      return channelAllowed && serverAllowed;
    })
  );

  let stateChanged = false;

  GATED_STREAMS.forEach(({ kinds, stateKey }, index) => {
    if (allowed[index]) return;

    kinds.forEach((kind) => {
      const producer = runtime.getProducer(kind, userId);

      if (!producer) return;

      runtime.removeProducer(userId, kind);

      pubsub.publishForChannel(channelId, ServerEvents.VOICE_PRODUCER_CLOSED, {
        channelId,
        remoteId: userId,
        kind,
        producerId: producer.id
      });
    });

    if (runtime.getUserState(userId)[stateKey]) {
      runtime.updateUserState(userId, { [stateKey]: false });
      stateChanged = true;
    }
  });

  if (!stateChanged) return;

  await publishVoiceEvent(ServerEvents.USER_VOICE_STATE_UPDATE, {
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

// a role change can reach anyone holding the role, and checking everyone in a call is cheaper
// than working out who holds it
const enforceVoicePermissionsForEveryone = async () => {
  const userIds = VoiceRuntime.getAll().flatMap((runtime) => {
    const { users } = runtime.getState();

    return users.map(({ userId }) => userId);
  });

  await enforceVoicePermissions(userIds);
};

export { enforceVoicePermissions, enforceVoicePermissionsForEveryone };
