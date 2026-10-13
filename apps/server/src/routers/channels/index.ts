import { t } from '../../utils/trpc';
import { addChannelRoute } from './add-channel';
import { deleteChannelRoute } from './delete-channel';
import { deletePermissionsRoute } from './delete-permissions';
import {
  onChannelCreateRoute,
  onChannelDeleteRoute,
  onChannelPermissionsUpdateRoute,
  onChannelReadStatesDeltaRoute,
  onChannelReadStatesUpdateRoute,
  onChannelUpdateRoute
} from './events';
import { getActivityRoute } from './get-activity';
import { getChannelRoute } from './get-channel';
import { getMembersRoute } from './get-members';
import { getPermissionsRoute } from './get-permissions';
import { markAsReadRoute } from './mark-as-read';
import { markAsUnreadRoute } from './mark-as-unread';
import { reorderChannelsRoute } from './reorder-channels';
import { updateChannelRoute } from './update-channel';
import { updatePermissionsRoute } from './update-permission';

export const channelsRouter = t.router({
  add: addChannelRoute,
  update: updateChannelRoute,
  delete: deleteChannelRoute,
  get: getChannelRoute,
  getActivity: getActivityRoute,
  getMembers: getMembersRoute,
  updatePermissions: updatePermissionsRoute,
  getPermissions: getPermissionsRoute,
  deletePermissions: deletePermissionsRoute,
  reorder: reorderChannelsRoute,
  markAsRead: markAsReadRoute,
  markAsUnread: markAsUnreadRoute,
  onCreate: onChannelCreateRoute,
  onDelete: onChannelDeleteRoute,
  onUpdate: onChannelUpdateRoute,
  onPermissionsUpdate: onChannelPermissionsUpdateRoute,
  onReadStateUpdate: onChannelReadStatesUpdateRoute,
  onReadStateDelta: onChannelReadStatesDeltaRoute
});
