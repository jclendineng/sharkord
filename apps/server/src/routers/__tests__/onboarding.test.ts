import { ChannelPermission, Permission } from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { and, eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import * as publishers from '../../db/publishers';
import { getChannelsForUser } from '../../db/queries/channels';
import { getPublicSettings, getSettings } from '../../db/queries/server';
import {
  channelRolePermissions,
  channels,
  messageReactions,
  messages,
  rolePermissions,
  userRoles,
  users
} from '../../db/schema';

// seeded: message 1 sits in General, user 3 is a plain member, role 3 (Guest) stands in for the role the rules give,
// role 2 (Member) is the default role and role 1 the owner's
const RULES_MESSAGE_ID = 1;
const ONBOARDING_ROLE_ID = 3;
const DEFAULT_ROLE_ID = 2;

const hasRole = async (userId: number, roleId: number) => {
  const row = await tdb
    .select({ userId: userRoles.userId })
    .from(userRoles)
    .where(and(eq(userRoles.userId, userId), eq(userRoles.roleId, roleId)))
    .get();

  return !!row;
};

const setUpRules = async () => {
  const { caller } = await initTest(1);

  await caller.others.setOnboarding({
    messageId: RULES_MESSAGE_ID,
    roleId: ONBOARDING_ROLE_ID
  });
};

describe('others.setOnboarding', () => {
  test('should set the rules message and its role, with a reaction to tap', async () => {
    await setUpRules();

    const settings = await getSettings();
    const publicSettings = await getPublicSettings();
    const reaction = await tdb
      .select()
      .from(messageReactions)
      .where(eq(messageReactions.messageId, RULES_MESSAGE_ID))
      .get();

    expect(settings.onboardingMessageId).toBe(RULES_MESSAGE_ID);
    expect(settings.onboardingRoleId).toBe(ONBOARDING_ROLE_ID);
    expect(publicSettings.onboardingMessageId).toBe(RULES_MESSAGE_ID);
    expect(reaction?.emoji).toBe('white_check_mark');
    expect(reaction?.userId).toBe(1);
  });

  test('should give the role to members already here when asked', async () => {
    const { caller } = await initTest(1);

    await caller.others.setOnboarding({
      messageId: RULES_MESSAGE_ID,
      roleId: ONBOARDING_ROLE_ID,
      giveExistingMembers: true
    });

    const allUsers = await tdb.select({ id: users.id }).from(users);

    for (const { id } of allUsers) {
      expect(await hasRole(id, ONBOARDING_ROLE_ID)).toBe(true);
    }
  });

  test('should leave members without the role unless asked', async () => {
    await setUpRules();

    expect(await hasRole(2, ONBOARDING_ROLE_ID)).toBe(false);
  });

  test('should clear both', async () => {
    await setUpRules();

    const { caller } = await initTest(1);

    await caller.others.setOnboarding({ messageId: null, roleId: null });

    const settings = await getSettings();

    expect(settings.onboardingMessageId).toBeNull();
    expect(settings.onboardingRoleId).toBeNull();
  });

  test('should clear itself when the rules message is deleted', async () => {
    await setUpRules();

    await tdb.delete(messages).where(eq(messages.id, RULES_MESSAGE_ID));

    const settings = await getSettings();

    expect(settings.onboardingMessageId).toBeNull();
  });

  test('should refuse without the manage settings permission', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.others.setOnboarding({
        messageId: RULES_MESSAGE_ID,
        roleId: ONBOARDING_ROLE_ID
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should close every other public channel to the default role when asked', async () => {
    const { caller } = await initTest(1);
    const accessChange = spyOn(publishers, 'publishChannelAccessChange');

    await caller.others.setOnboarding({
      messageId: RULES_MESSAGE_ID,
      roleId: ONBOARDING_ROLE_ID,
      closeOtherChannels: true
    });

    const privacy = await tdb
      .select({ id: channels.id, private: channels.private })
      .from(channels);
    const isPrivate = Object.fromEntries(
      privacy.map(({ id, private: value }) => [id, value])
    );

    // the rules stay in the open, voice (2) closes, the private ones (4, 5) are left alone
    expect(isPrivate[1]).toBe(false);
    expect(isPrivate[2]).toBe(true);
    expect(isPrivate[4]).toBe(true);
    expect(isPrivate[5]).toBe(true);

    const grants = await tdb
      .select({
        roleId: channelRolePermissions.roleId,
        permission: channelRolePermissions.permission
      })
      .from(channelRolePermissions)
      .where(eq(channelRolePermissions.channelId, 2));

    // every role but the owner's and the default one gets everything a public channel gave
    expect(new Set(grants.map(({ roleId }) => roleId))).toEqual(
      new Set([3, 4])
    );
    expect(
      grants
        .filter(({ roleId }) => roleId === 3)
        .map(({ permission }) => permission)
    ).toEqual(expect.arrayContaining(Object.values(ChannelPermission)));

    // user 3 only has the default role, so only the rules channel is left to them
    const visibleToNewcomer = (await getChannelsForUser(3)).map(({ id }) => id);

    expect(visibleToNewcomer).toContain(1);
    expect(visibleToNewcomer).not.toContain(2);

    expect(accessChange).toHaveBeenCalledWith(2, expect.any(Array));
  });

  test('should leave the channels alone unless asked', async () => {
    await setUpRules();

    const voice = await tdb
      .select({ private: channels.private })
      .from(channels)
      .where(eq(channels.id, 2))
      .get();

    expect(voice!.private).toBe(false);
  });

  test('should refuse to close channels without the channel permissions', async () => {
    const { caller } = await initTest(2);

    await tdb.insert(rolePermissions).values({
      roleId: 2,
      permission: Permission.MANAGE_SETTINGS,
      createdAt: Date.now()
    });

    await expect(
      caller.others.setOnboarding({
        messageId: RULES_MESSAGE_ID,
        roleId: ONBOARDING_ROLE_ID,
        closeOtherChannels: true
      })
    ).rejects.toThrow('Insufficient permissions');

    const [settings, voice] = await Promise.all([
      getSettings(),
      tdb
        .select({ private: channels.private })
        .from(channels)
        .where(eq(channels.id, 2))
        .get()
    ]);

    expect(settings.onboardingMessageId).toBeNull();
    expect(voice!.private).toBe(false);
  });

  test('should keep whether reacting takes the default role, and forget it when cleared', async () => {
    const { caller } = await initTest(1);

    await caller.others.setOnboarding({
      messageId: RULES_MESSAGE_ID,
      roleId: ONBOARDING_ROLE_ID,
      removeDefaultRole: true
    });

    expect((await getSettings()).onboardingRemovesDefaultRole).toBe(true);

    await caller.others.setOnboarding({ messageId: null, roleId: null });

    expect((await getSettings()).onboardingRemovesDefaultRole).toBe(false);
  });

  test('should refuse only one of the two', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.others.setOnboarding({
        messageId: RULES_MESSAGE_ID,
        roleId: null
      })
    ).rejects.toThrow('Pick both the rules message and the role it gives.');
  });

  test('should refuse a message that does not exist', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.others.setOnboarding({
        messageId: 999,
        roleId: ONBOARDING_ROLE_ID
      })
    ).rejects.toThrow('Message not found');
  });

  test('should refuse a role that does not exist', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.others.setOnboarding({
        messageId: RULES_MESSAGE_ID,
        roleId: 999
      })
    ).rejects.toThrow('Role not found');
  });

  test('should refuse the owner role and the default role', async () => {
    const { caller } = await initTest(1);

    await expect(
      caller.others.setOnboarding({ messageId: RULES_MESSAGE_ID, roleId: 1 })
    ).rejects.toThrow('Pick a role new members do not already have.');
    await expect(
      caller.others.setOnboarding({ messageId: RULES_MESSAGE_ID, roleId: 2 })
    ).rejects.toThrow('Pick a role new members do not already have.');
  });

  test('should refuse rules in a direct message', async () => {
    // usera takes part in the seeded dm, channel 3, and is given the right to set this up
    await tdb.insert(rolePermissions).values({
      roleId: 2,
      permission: Permission.MANAGE_SETTINGS,
      createdAt: Date.now()
    });

    const [dmMessage] = await tdb
      .insert(messages)
      .values({
        channelId: 3,
        userId: 3,
        content: 'rules',
        createdAt: Date.now()
      })
      .returning({ id: messages.id });

    const { caller } = await initTest(3);

    await expect(
      caller.others.setOnboarding({
        messageId: dmMessage!.id,
        roleId: ONBOARDING_ROLE_ID
      })
    ).rejects.toThrow('The rules have to be in a server channel.');
  });

  test('should refuse a role with permissions the caller does not have', async () => {
    // the moderator may manage settings, and the role it picks may manage channels
    await tdb.insert(rolePermissions).values([
      {
        roleId: 4,
        permission: Permission.MANAGE_SETTINGS,
        createdAt: Date.now()
      },
      {
        roleId: ONBOARDING_ROLE_ID,
        permission: Permission.MANAGE_CHANNELS,
        createdAt: Date.now()
      }
    ]);

    const { caller } = await initTest(5);

    await expect(
      caller.others.setOnboarding({
        messageId: RULES_MESSAGE_ID,
        roleId: ONBOARDING_ROLE_ID
      })
    ).rejects.toThrow(
      'You cannot assign a role with permissions that you do not have.'
    );
  });
});

// no seeded role but the owner's may react, and on a real server the default role has to
const letMembersReact = async () => {
  await tdb.insert(rolePermissions).values({
    roleId: 2,
    permission: Permission.REACT_TO_MESSAGES,
    createdAt: Date.now()
  });
};

describe('reacting to the rules message', () => {
  test('should give the onboarding role', async () => {
    await setUpRules();

    await letMembersReact();

    const { caller } = await initTest(3);

    await caller.messages.toggleReaction({
      messageId: RULES_MESSAGE_ID,
      emoji: 'white_check_mark'
    });

    expect(await hasRole(3, ONBOARDING_ROLE_ID)).toBe(true);
    // the default role stays unless the rules were set to take it
    expect(await hasRole(3, DEFAULT_ROLE_ID)).toBe(true);
  });

  test('should take the default role away when the rules say so', async () => {
    const { caller: owner } = await initTest(1);

    await owner.others.setOnboarding({
      messageId: RULES_MESSAGE_ID,
      roleId: ONBOARDING_ROLE_ID,
      removeDefaultRole: true
    });

    await letMembersReact();

    const { caller } = await initTest(3);

    await caller.messages.toggleReaction({
      messageId: RULES_MESSAGE_ID,
      emoji: 'white_check_mark'
    });

    expect(await hasRole(3, ONBOARDING_ROLE_ID)).toBe(true);
    expect(await hasRole(3, DEFAULT_ROLE_ID)).toBe(false);
  });

  test('should keep the role when the reaction is taken back', async () => {
    await setUpRules();

    await letMembersReact();

    const { caller } = await initTest(3);

    await caller.messages.toggleReaction({
      messageId: RULES_MESSAGE_ID,
      emoji: 'white_check_mark'
    });
    await caller.messages.toggleReaction({
      messageId: RULES_MESSAGE_ID,
      emoji: 'white_check_mark'
    });

    expect(await hasRole(3, ONBOARDING_ROLE_ID)).toBe(true);
  });

  test('should give nothing for a reaction to another message', async () => {
    await setUpRules();

    await letMembersReact();

    const { caller } = await initTest(3);

    await caller.messages.toggleReaction({
      messageId: 2,
      emoji: 'white_check_mark'
    });

    expect(await hasRole(3, ONBOARDING_ROLE_ID)).toBe(false);
  });

  test('should give nothing when no rules are set', async () => {
    await letMembersReact();

    const { caller } = await initTest(3);

    await caller.messages.toggleReaction({
      messageId: RULES_MESSAGE_ID,
      emoji: 'white_check_mark'
    });

    expect(await hasRole(3, ONBOARDING_ROLE_ID)).toBe(false);
  });
});
