import type { TInvite, TInviteJoin, TJoinedInvite } from '@sharkord/shared';
import { asc, eq, inArray } from 'drizzle-orm';
import { alias } from 'drizzle-orm/sqlite-core';
import { db } from '..';
import { signFile } from '../../helpers/files-crypto';
import { files, invites, inviteUses, roles, userRoles, users } from '../schema';
import { getSettings } from './server';

const isInviteValid = async (
  code: string | undefined
): Promise<{ error?: string; invite?: TInvite }> => {
  if (!code) {
    return { error: 'Invalid invite code' };
  }

  const invite = await db
    .select()
    .from(invites)
    .where(eq(invites.code, code))
    .get();

  // a deleted invite reads as one that never existed
  if (!invite || invite.deletedAt) {
    return { error: 'Invite code not found' };
  }

  if (invite.expiresAt && invite.expiresAt < Date.now()) {
    return { error: 'Invite code has expired' };
  }

  if (invite.maxUses && invite.uses >= invite.maxUses) {
    return { error: 'Invite code has reached maximum uses' };
  }

  return { invite };
};

const getInvites = async (): Promise<TJoinedInvite[]> => {
  const avatarFiles = alias(files, 'avatarFiles');
  const bannerFiles = alias(files, 'bannerFiles');

  const rows = await db
    .select({
      invite: invites,
      creator: {
        id: users.id,
        name: users.name,
        profileColor: users.profileColor,
        bio: users.bio,
        banned: users.banned,
        createdAt: users.createdAt,
        avatarId: users.avatarId,
        bannerId: users.bannerId
      },
      avatar: avatarFiles,
      banner: bannerFiles,
      role: {
        id: roles.id,
        name: roles.name,
        color: roles.color
      }
    })
    .from(invites)
    .innerJoin(users, eq(invites.creatorId, users.id))
    .leftJoin(avatarFiles, eq(users.avatarId, avatarFiles.id))
    .leftJoin(bannerFiles, eq(users.bannerId, bannerFiles.id))
    .leftJoin(roles, eq(invites.roleId, roles.id));

  const inviteIds = rows.map((row) => row.invite.id);

  const [rolesByUser, { storageSignedUrlsTtlSeconds }, uses] =
    await Promise.all([
      db
        .select({
          userId: userRoles.userId,
          roleId: userRoles.roleId
        })
        .from(userRoles)
        .all(),
      getSettings(),
      db
        .select({
          inviteId: inviteUses.inviteId,
          userId: inviteUses.userId,
          createdAt: inviteUses.createdAt
        })
        .from(inviteUses)
        .where(inArray(inviteUses.inviteId, inviteIds))
        .orderBy(asc(inviteUses.createdAt))
        .all()
    ]);

  const joinsByInvite = uses.reduce(
    (acc, { inviteId, userId, createdAt }) => {
      if (!acc[inviteId]) acc[inviteId] = [];
      acc[inviteId].push({ userId, createdAt });
      return acc;
    },
    {} as Record<number, TInviteJoin[]>
  );

  const rolesMap = rolesByUser.reduce(
    (acc, { userId, roleId }) => {
      if (!acc[userId]) acc[userId] = [];
      acc[userId].push(roleId);
      return acc;
    },
    {} as Record<number, number[]>
  );

  return rows.map((row) => ({
    ...row.invite,
    creator: {
      ...row.creator,
      avatar: signFile(row.avatar, storageSignedUrlsTtlSeconds),
      banner: signFile(row.banner, storageSignedUrlsTtlSeconds),
      roleIds: rolesMap[row.creator.id] || []
    },
    role: row.role?.id ? row.role : null,
    joins: joinsByInvite[row.invite.id] || []
  }));
};

// the role the invite a member signed up with carries, if it carries one
const getSignupInviteRoleId = async (
  userId: number
): Promise<number | undefined> => {
  const row = await db
    .select({ roleId: invites.roleId })
    .from(inviteUses)
    .innerJoin(invites, eq(invites.id, inviteUses.inviteId))
    .where(eq(inviteUses.userId, userId))
    .limit(1)
    .get();

  return row?.roleId ?? undefined;
};

export { getInvites, getSignupInviteRoleId, isInviteValid };
