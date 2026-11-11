import {
  type TJoinedPublicUser,
  type TJoinedUser,
  type TStorageData
} from '@sharkord/shared';
import { and, count, eq, ne, sql, sum, type SQL } from 'drizzle-orm';
import { alias } from 'drizzle-orm/sqlite-core';
import jwt from 'jsonwebtoken';
import { db } from '..';
import { signFile } from '../../helpers/files-crypto';
import type { TTokenPayload } from '../../types';
import { prepared } from '../prepared';
import { files, userRoles, users } from '../schema';
import { getServerToken, getSettings } from './server';
import { getSession } from './sessions';

const getPublicUserById = async (
  userId: number
): Promise<TJoinedPublicUser | undefined> => {
  const avatarFiles = alias(files, 'avatarFiles');
  const bannerFiles = alias(files, 'bannerFiles');

  const results = await db
    .select({
      id: users.id,
      name: users.name,
      profileColor: users.profileColor,
      bio: users.bio,
      banned: users.banned,
      avatarId: users.avatarId,
      bannerId: users.bannerId,
      avatar: avatarFiles,
      banner: bannerFiles,
      createdAt: users.createdAt,
      customStatus: users.customStatus
    })
    .from(users)
    .leftJoin(avatarFiles, eq(users.avatarId, avatarFiles.id))
    .leftJoin(bannerFiles, eq(users.bannerId, bannerFiles.id))
    .where(eq(users.id, userId))
    .get();

  if (!results) return undefined;

  const roles = getRoleIdsForUser(userId);
  const { storageSignedUrlsTtlSeconds } = await getSettings();

  return {
    id: results.id,
    name: results.name,
    profileColor: results.profileColor,
    bio: results.bio,
    avatarId: results.avatarId,
    bannerId: results.bannerId,
    avatar: signFile(results.avatar, storageSignedUrlsTtlSeconds),
    banner: signFile(results.banner, storageSignedUrlsTtlSeconds),
    createdAt: results.createdAt,
    customStatus: results.customStatus,
    banned: results.banned,
    roleIds: roles.map((r) => r.roleId)
  };
};

const getPublicUsers = async (
  returnIdentity: boolean = false
): Promise<TJoinedPublicUser[]> => {
  const avatarFiles = alias(files, 'avatarFiles');
  const bannerFiles = alias(files, 'bannerFiles');

  const { storageSignedUrlsTtlSeconds } = await getSettings();

  if (returnIdentity) {
    const results = await db
      .select({
        id: users.id,
        name: users.name,
        profileColor: users.profileColor,
        bio: users.bio,
        banned: users.banned,
        avatarId: users.avatarId,
        bannerId: users.bannerId,
        avatar: avatarFiles,
        banner: bannerFiles,
        createdAt: users.createdAt,
        customStatus: users.customStatus,
        _identity: users.identity
      })
      .from(users)
      .leftJoin(avatarFiles, eq(users.avatarId, avatarFiles.id))
      .leftJoin(bannerFiles, eq(users.bannerId, bannerFiles.id))
      .all();

    const rolesByUser = await db
      .select({
        userId: userRoles.userId,
        roleId: userRoles.roleId
      })
      .from(userRoles)
      .all();

    const rolesMap = rolesByUser.reduce(
      (acc, { userId, roleId }) => {
        if (!acc[userId]) acc[userId] = [];
        acc[userId].push(roleId);
        return acc;
      },
      {} as Record<number, number[]>
    );

    return results.map((result) => ({
      id: result.id,
      name: result.name,
      profileColor: result.profileColor,
      bio: result.bio,
      banned: result.banned,
      avatarId: result.avatarId,
      bannerId: result.bannerId,
      avatar: signFile(result.avatar, storageSignedUrlsTtlSeconds),
      banner: signFile(result.banner, storageSignedUrlsTtlSeconds),
      createdAt: result.createdAt,
      customStatus: result.customStatus,
      _identity: result._identity,
      roleIds: rolesMap[result.id] || []
    }));
  } else {
    const results = await db
      .select({
        id: users.id,
        name: users.name,
        banned: users.banned,
        profileColor: users.profileColor,
        bio: users.bio,
        avatarId: users.avatarId,
        bannerId: users.bannerId,
        avatar: avatarFiles,
        banner: bannerFiles,
        createdAt: users.createdAt,
        customStatus: users.customStatus
      })
      .from(users)
      .leftJoin(avatarFiles, eq(users.avatarId, avatarFiles.id))
      .leftJoin(bannerFiles, eq(users.bannerId, bannerFiles.id))
      .all();

    // Get role IDs for all users
    const rolesByUser = await db
      .select({
        userId: userRoles.userId,
        roleId: userRoles.roleId
      })
      .from(userRoles)
      .all();

    const rolesMap = rolesByUser.reduce(
      (acc, { userId, roleId }) => {
        if (!acc[userId]) acc[userId] = [];
        acc[userId].push(roleId);
        return acc;
      },
      {} as Record<number, number[]>
    );

    return results.map((result) => ({
      id: result.id,
      name: result.name,
      banned: result.banned,
      profileColor: result.profileColor,
      bio: result.bio,
      avatarId: result.avatarId,
      bannerId: result.bannerId,
      avatar: signFile(result.avatar, storageSignedUrlsTtlSeconds),
      banner: signFile(result.banner, storageSignedUrlsTtlSeconds),
      createdAt: result.createdAt,
      customStatus: result.customStatus,
      roleIds: rolesMap[result.id] || []
    }));
  }
};

const getStorageUsageByUserId = async (
  userId: number
): Promise<TStorageData> => {
  const result = await db
    .select({
      fileCount: count(files.id),
      usedStorage: sum(files.size)
    })
    .from(files)
    .where(eq(files.userId, userId))
    .get();

  return {
    userId,
    fileCount: result?.fileCount ?? 0,
    usedStorage: Number(result?.usedStorage ?? 0)
  };
};

// the user and their files, the where left to the caller
const joinedUserQuery = () => {
  const avatarFiles = alias(files, 'avatarFiles');
  const bannerFiles = alias(files, 'bannerFiles');

  return db
    .select({
      id: users.id,
      identity: users.identity,
      name: users.name,
      avatarId: users.avatarId,
      bannerId: users.bannerId,
      bio: users.bio,
      password: users.password,
      profileColor: users.profileColor,
      createdAt: users.createdAt,
      customStatus: users.customStatus,
      updatedAt: users.updatedAt,
      lastLoginAt: users.lastLoginAt,
      banned: users.banned,
      banReason: users.banReason,
      bannedAt: users.bannedAt,
      tokenVersion: users.tokenVersion,
      allowDirectMessages: users.allowDirectMessages,
      presence: users.presence,
      oidcSub: users.oidcSub,
      oidcIssuer: users.oidcIssuer,
      passwordSet: users.passwordSet,
      avatar: avatarFiles,
      banner: bannerFiles
    })
    .from(users)
    .leftJoin(avatarFiles, eq(users.avatarId, avatarFiles.id))
    .leftJoin(bannerFiles, eq(users.bannerId, bannerFiles.id));
};

type TJoinedUserRow = Awaited<
  ReturnType<ReturnType<typeof joinedUserQuery>['get']>
>;

// a user's role ids, read for every permission check
const getRoleIdsForUser = (userId: number) => {
  const statement = prepared('roleIdsForUser', () =>
    db
      .select({ roleId: userRoles.roleId })
      .from(userRoles)
      .where(eq(userRoles.userId, sql.placeholder('userId')))
      .prepare()
  );

  return statement.all({ userId });
};

const withRolesAndSignedFiles = async (
  user: NonNullable<TJoinedUserRow>
): Promise<TJoinedUser> => {
  const roles = getRoleIdsForUser(user.id);
  const { storageSignedUrlsTtlSeconds } = await getSettings();

  return {
    ...user,
    avatar: signFile(user.avatar, storageSignedUrlsTtlSeconds),
    banner: signFile(user.banner, storageSignedUrlsTtlSeconds),
    roleIds: roles.map((r) => r.roleId)
  };
};

const getJoinedUser = async (
  where: SQL | undefined
): Promise<TJoinedUser | undefined> => {
  const user = await joinedUserQuery().where(where).get();

  if (!user) return undefined;

  return withRolesAndSignedFiles(user);
};

// the caller of nearly every request, prepared once
const getUserById = async (
  userId: number
): Promise<TJoinedUser | undefined> => {
  const statement = prepared('userById', () =>
    joinedUserQuery()
      .where(eq(users.id, sql.placeholder('userId')))
      .prepare()
  );
  const user = statement.get({ userId });

  if (!user) return undefined;

  return withRolesAndSignedFiles(user);
};

const getUserByIdentity = async (
  identity: string
): Promise<TJoinedUser | undefined> =>
  getJoinedUser(eq(users.identity, identity));

const getUserByOidcSub = async (
  oidcSub: string
): Promise<TJoinedUser | undefined> =>
  getJoinedUser(eq(users.oidcSub, oidcSub));

const getUserByToken = async (token: string | undefined) => {
  try {
    if (!token) return undefined;

    // a session's token is checked against its row below, which is what ends it, so the
    // expiry the tokens of the past carried is ignored: devices left unopened for a week come
    // back without signing in again. a token from before sessions has no row to check and
    // still ends when it expires
    const decoded = jwt.verify(token, await getServerToken(), {
      ignoreExpiration: true
    }) as TTokenPayload;

    if (!decoded.sessionId && decoded.exp && decoded.exp * 1000 < Date.now()) {
      return undefined;
    }

    const user = await getUserById(decoded.userId);

    if (user?.banned) return undefined;

    // a deleted user has no row, so deletion already invalidates its tokens. this covers
    // the case where the row survives but its sessions should not, such as a password
    // change. tokens predating this mechanism carry no version and count as 0
    if (user && (decoded.tokenVersion ?? 0) !== user.tokenVersion) {
      return undefined;
    }

    // a signed out device's session row is gone
    if (
      user &&
      decoded.sessionId &&
      !(await getSession(decoded.sessionId, user.id))
    ) {
      return undefined;
    }

    return user;
  } catch {
    return undefined;
  }
};

const getUsers = async (): Promise<TJoinedUser[]> => {
  const avatarFiles = alias(files, 'avatarFiles');
  const bannerFiles = alias(files, 'bannerFiles');

  const [results, { storageSignedUrlsTtlSeconds }] = await Promise.all([
    db
      .select({
        id: users.id,
        name: users.name,
        profileColor: users.profileColor,
        bio: users.bio,
        avatarId: users.avatarId,
        bannerId: users.bannerId,
        updatedAt: users.updatedAt,
        createdAt: users.createdAt,
        customStatus: users.customStatus,
        identity: users.identity,
        password: users.password,
        lastLoginAt: users.lastLoginAt,
        banned: users.banned,
        banReason: users.banReason,
        bannedAt: users.bannedAt,
        tokenVersion: users.tokenVersion,
        allowDirectMessages: users.allowDirectMessages,
        presence: users.presence,
        oidcSub: users.oidcSub,
        oidcIssuer: users.oidcIssuer,
        passwordSet: users.passwordSet,
        avatar: avatarFiles,
        banner: bannerFiles
      })
      .from(users)
      .leftJoin(avatarFiles, eq(users.avatarId, avatarFiles.id))
      .leftJoin(bannerFiles, eq(users.bannerId, bannerFiles.id))
      .all(),
    getSettings()
  ]);

  // Get role IDs for all users
  const rolesByUser = await db
    .select({
      userId: userRoles.userId,
      roleId: userRoles.roleId
    })
    .from(userRoles)
    .all();

  const rolesMap = rolesByUser.reduce(
    (acc, { userId, roleId }) => {
      if (!acc[userId]) acc[userId] = [];
      acc[userId].push(roleId);
      return acc;
    },
    {} as Record<number, number[]>
  );

  return results.map((result) => ({
    id: result.id,
    name: result.name,
    profileColor: result.profileColor,
    bio: result.bio,
    avatarId: result.avatarId,
    bannerId: result.bannerId,
    avatar: signFile(result.avatar, storageSignedUrlsTtlSeconds),
    banner: signFile(result.banner, storageSignedUrlsTtlSeconds),
    createdAt: result.createdAt,
    updatedAt: result.updatedAt,
    identity: result.identity,
    password: result.password,
    lastLoginAt: result.lastLoginAt,
    banned: result.banned,
    banReason: result.banReason,
    bannedAt: result.bannedAt,
    tokenVersion: result.tokenVersion,
    allowDirectMessages: result.allowDirectMessages,
    presence: result.presence,
    customStatus: result.customStatus,
    oidcSub: result.oidcSub,
    oidcIssuer: result.oidcIssuer,
    passwordSet: result.passwordSet,
    roleIds: rolesMap[result.id] || []
  }));
};

// names compare without case, so "Joel" and "joel" count as the same person on screen
const isUserNameTaken = async (
  name: string,
  exceptUserId?: number
): Promise<boolean> => {
  const sameName = sql`${users.name} = ${name} COLLATE NOCASE`;
  const where =
    exceptUserId === undefined
      ? sameName
      : and(sameName, ne(users.id, exceptUserId));

  const taken = await db
    .select({ id: users.id })
    .from(users)
    .where(where)
    .limit(1)
    .get();

  return !!taken;
};

const getAllUserIds = async (): Promise<number[]> => {
  const results = await db.select({ id: users.id }).from(users);
  return results.map((r) => r.id);
};

export {
  getAllUserIds,
  getPublicUserById,
  getPublicUsers,
  getStorageUsageByUserId,
  getUserById,
  getUserByIdentity,
  getUserByOidcSub,
  getUserByToken,
  getUsers,
  isUserNameTaken
};
