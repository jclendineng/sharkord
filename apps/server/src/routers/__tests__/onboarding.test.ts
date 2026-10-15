import { Permission } from '@sharkord/shared';
import { describe, expect, test } from 'bun:test';
import { and, eq } from 'drizzle-orm';
import { initTest } from '../../__tests__/helpers';
import { tdb } from '../../__tests__/setup';
import { getPublicSettings, getSettings } from '../../db/queries/server';
import {
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
