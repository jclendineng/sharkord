import { OWNER_ROLE_ID, Permission } from '@sharkord/shared';
import { describe, expect, spyOn, test } from 'bun:test';
import { initTest } from '../../__tests__/helpers';
import * as publishers from '../../db/publishers';

describe('roles router', () => {
  test('should throw when user lacks permissions (getAll)', async () => {
    const { caller } = await initTest(2);

    await expect(caller.roles.getAll()).rejects.toThrow(
      'Insufficient permissions'
    );
  });

  test('should throw when user lacks permissions (add)', async () => {
    const { caller } = await initTest(2);

    await expect(caller.roles.add()).rejects.toThrow(
      'Insufficient permissions'
    );
  });

  test('should throw when user lacks permissions (update)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.roles.update({
        roleId: 2,
        name: 'Updated Role',
        color: '#ff0000',
        permissions: [Permission.SEND_MESSAGES],
        storageQuotaOverrideEnabled: false,
        storageSpaceQuota: 0
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should throw when user lacks permissions (delete)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.roles.delete({
        roleId: 2
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should throw when user lacks permissions (setDefault)', async () => {
    const { caller } = await initTest(2);

    await expect(
      caller.roles.setDefault({
        roleId: 1
      })
    ).rejects.toThrow('Insufficient permissions');
  });

  test('should get all roles', async () => {
    const { caller } = await initTest();

    const roles = await caller.roles.getAll();

    expect(roles).toBeDefined();
    expect(Array.isArray(roles)).toBe(true);
    expect(roles.length).toBeGreaterThanOrEqual(2);
  });

  test('should create new role', async () => {
    const { caller } = await initTest();

    const roleId = await caller.roles.add();

    expect(roleId).toBeDefined();
    expect(typeof roleId).toBe('number');
    expect(roleId).toBeGreaterThan(0);

    const roles = await caller.roles.getAll();
    const newRole = roles.find((r) => r.id === roleId);

    expect(newRole).toBeDefined();
    expect(newRole!.name).toBe('New Role');
    expect(newRole!.color).toBe('#ffffff');
    expect(newRole!.isDefault).toBe(false);
    expect(newRole!.isPersistent).toBe(false);
    expect(newRole!.storageQuotaOverrideEnabled).toBe(false);
    expect(newRole!.storageSpaceQuota).toBe(0);
  });

  test('should update existing role', async () => {
    const { caller } = await initTest();

    const roleId = await caller.roles.add();

    await caller.roles.update({
      roleId,
      name: 'Updated Role Name',
      color: '#ff5500',
      permissions: [Permission.SEND_MESSAGES, Permission.UPLOAD_FILES],
      storageQuotaOverrideEnabled: false,
      storageSpaceQuota: 0
    });

    const roles = await caller.roles.getAll();
    const updatedRole = roles.find((r) => r.id === roleId);

    expect(updatedRole).toBeDefined();
    expect(updatedRole!.name).toBe('Updated Role Name');
    expect(updatedRole!.color).toBe('#ff5500');
    expect(updatedRole!.permissions).toContain(Permission.SEND_MESSAGES);
    expect(updatedRole!.permissions).toContain(Permission.UPLOAD_FILES);
    expect(updatedRole!.permissions.length).toBe(2);
    expect(updatedRole!.storageQuotaOverrideEnabled).toBe(false);
    expect(updatedRole!.storageSpaceQuota).toBe(0);
  });

  test('should update role storage override settings', async () => {
    const { caller } = await initTest();

    const roleId = await caller.roles.add();

    await caller.roles.update({
      roleId,
      name: 'Storage Role',
      color: '#336699',
      permissions: [Permission.UPLOAD_FILES],
      storageQuotaOverrideEnabled: true,
      storageSpaceQuota: 1024 * 1024 * 1024
    });

    const roles = await caller.roles.getAll();
    const updatedRole = roles.find((r) => r.id === roleId);

    expect(updatedRole).toBeDefined();
    expect(updatedRole!.storageQuotaOverrideEnabled).toBe(true);
    expect(updatedRole!.storageSpaceQuota).toBe(1024 * 1024 * 1024);
  });

  test('should reject invalid role storage quota', async () => {
    const { caller } = await initTest();

    const roleId = await caller.roles.add();

    await expect(
      caller.roles.update({
        roleId,
        name: 'Invalid Storage Role',
        color: '#336699',
        permissions: [Permission.UPLOAD_FILES],
        storageQuotaOverrideEnabled: true,
        storageSpaceQuota: -1
      })
    ).rejects.toThrow();
  });

  test('should not allow updating Owner role permissions', async () => {
    const { caller } = await initTest();

    await caller.roles.update({
      roleId: 1,
      name: 'Owner',
      color: '#ff0000',
      permissions: [Permission.SEND_MESSAGES],
      storageQuotaOverrideEnabled: false,
      storageSpaceQuota: 0
    });

    const roles = await caller.roles.getAll();
    const ownerRole = roles.find((r) => r.id === 1);

    expect(ownerRole).toBeDefined();
    expect(ownerRole!.permissions.length).toBeGreaterThan(1);
  });

  test('should delete non-persistent role', async () => {
    const { caller } = await initTest();

    const roleId = await caller.roles.add();

    const rolesBefore = await caller.roles.getAll();
    expect(rolesBefore.find((r) => r.id === roleId)).toBeDefined();

    await caller.roles.delete({ roleId });

    const rolesAfter = await caller.roles.getAll();
    expect(rolesAfter.find((r) => r.id === roleId)).toBeUndefined();
  });

  test('should throw when deleting persistent role', async () => {
    const { caller } = await initTest();

    await expect(
      caller.roles.delete({
        roleId: 1
      })
    ).rejects.toThrow('Cannot delete a persistent role');
  });

  test('should throw when deleting default role', async () => {
    const { caller } = await initTest();

    const newRoleId = await caller.roles.add();
    await caller.roles.setDefault({ roleId: newRoleId });

    await expect(
      caller.roles.delete({
        roleId: newRoleId
      })
    ).rejects.toThrow('Cannot delete the default role');
  });

  test('should throw when deleting non-existing role', async () => {
    const { caller } = await initTest();

    await expect(
      caller.roles.delete({
        roleId: 999999
      })
    ).rejects.toThrow('Role not found');
  });

  test('should set new default role', async () => {
    const { caller } = await initTest();

    const newRoleId = await caller.roles.add();

    await caller.roles.setDefault({ roleId: newRoleId });

    const roles = await caller.roles.getAll();
    const newDefaultRole = roles.find((r) => r.id === newRoleId);
    const oldDefaultRole = roles.find((r) => r.id === 2);

    expect(newDefaultRole!.isDefault).toBe(true);
    expect(oldDefaultRole!.isDefault).toBe(false);
  });

  test('should throw when setting non-existing role as default', async () => {
    const { caller } = await initTest();

    await expect(
      caller.roles.setDefault({
        roleId: 999999
      })
    ).rejects.toThrow('Role not found');
  });

  test('should refuse the owner role as the default role', async () => {
    const { caller } = await initTest();

    await expect(
      caller.roles.setDefault({
        roleId: OWNER_ROLE_ID
      })
    ).rejects.toThrow('The owner role cannot be the default role');

    const roles = await caller.roles.getAll();
    const ownerRole = roles.find((r) => r.id === OWNER_ROLE_ID);

    expect(ownerRole!.isDefault).toBe(false);
  });

  test('should create multiple roles', async () => {
    const { caller } = await initTest();

    const initialRoles = await caller.roles.getAll();
    const initialCount = initialRoles.length;

    await caller.roles.add();
    await caller.roles.add();
    await caller.roles.add();

    const finalRoles = await caller.roles.getAll();

    expect(finalRoles.length).toBe(initialCount + 3);
  });

  test('should update role with empty permissions array', async () => {
    const { caller } = await initTest();

    const roleId = await caller.roles.add();

    await caller.roles.update({
      roleId,
      name: 'No Permissions Role',
      color: '#000000',
      permissions: [],
      storageQuotaOverrideEnabled: false,
      storageSpaceQuota: 0
    });

    const roles = await caller.roles.getAll();
    const role = roles.find((r) => r.id === roleId);

    expect(role).toBeDefined();
    expect(role!.permissions.length).toBe(0);
  });

  test('should update role with multiple permissions', async () => {
    const { caller } = await initTest();

    const roleId = await caller.roles.add();

    const permissions = [
      Permission.SEND_MESSAGES,
      Permission.UPLOAD_FILES,
      Permission.MANAGE_CHANNELS,
      Permission.MANAGE_ROLES
    ];

    await caller.roles.update({
      roleId,
      name: 'Multi Permission Role',
      color: '#00ff00',
      permissions,
      storageQuotaOverrideEnabled: false,
      storageSpaceQuota: 0
    });

    const roles = await caller.roles.getAll();
    const role = roles.find((r) => r.id === roleId);

    expect(role).toBeDefined();
    expect(role!.permissions.length).toBe(permissions.length);
    permissions.forEach((perm) => {
      expect(role!.permissions).toContain(perm);
    });
  });

  test('should not let a role manager grant a permission they lack', async () => {
    const { caller: owner } = await initTest();
    const roleId = await owner.roles.add();

    const { caller } = await initTest(5);

    await expect(
      caller.roles.update({
        roleId,
        name: 'Escalated',
        color: '#00ff00',
        permissions: [Permission.MANAGE_SETTINGS],
        storageQuotaOverrideEnabled: false,
        storageSpaceQuota: 0
      })
    ).rejects.toThrow('You cannot grant permissions that you do not have');

    const roles = await owner.roles.getAll();

    expect(roles.find((r) => r.id === roleId)!.permissions.length).toBe(0);
  });

  test('should let a role manager edit a role holding a permission they lack', async () => {
    const { caller: owner } = await initTest();
    const roleId = await owner.roles.add();

    await owner.roles.update({
      roleId,
      name: 'Higher Role',
      color: '#00ff00',
      permissions: [Permission.MANAGE_SETTINGS],
      storageQuotaOverrideEnabled: false,
      storageSpaceQuota: 0
    });

    const { caller } = await initTest(5);

    await caller.roles.update({
      roleId,
      name: 'Renamed Higher Role',
      color: '#00ff00',
      permissions: [Permission.MANAGE_SETTINGS],
      storageQuotaOverrideEnabled: false,
      storageSpaceQuota: 0
    });

    const roles = await owner.roles.getAll();
    const role = roles.find((r) => r.id === roleId);

    expect(role!.name).toBe('Renamed Higher Role');
    expect(role!.permissions).toContain(Permission.MANAGE_SETTINGS);
  });

  test('should throw when updating a non-existing role', async () => {
    const { caller } = await initTest();

    await expect(
      caller.roles.update({
        roleId: 9999,
        name: 'Ghost',
        color: '#00ff00',
        permissions: [],
        storageQuotaOverrideEnabled: false,
        storageSpaceQuota: 0
      })
    ).rejects.toThrow('Role not found');
  });
});

// seeded order: Owner (1), Member (2, the default), Guest (3), Moderator (4)
describe('roles.reorder', () => {
  const roleOrder = async (
    caller: Awaited<ReturnType<typeof initTest>>['caller']
  ) => (await caller.roles.getAll()).map(({ id }) => id);

  test('should move the roles between the owner and the default one', async () => {
    const { caller } = await initTest(1);

    await caller.roles.reorder({ roleIds: [4, 3] });

    const order = await roleOrder(caller);

    expect(order.indexOf(4)).toBeLessThan(order.indexOf(3));
    expect(order[0]).toBe(1);
  });

  test('should ignore the owner and the default role', async () => {
    const { caller } = await initTest(1);

    await caller.roles.reorder({ roleIds: [2, 1, 4, 3] });

    const roles = await caller.roles.getAll();
    const position = (id: number) =>
      roles.find((role) => role.id === id)!.position;

    expect(position(1)).toBe(1);
    expect(position(2)).toBe(2);
    expect(position(4)).toBeLessThan(position(3));
  });

  test('should tell everyone about each moved role', async () => {
    const { caller } = await initTest(1);
    const publishRole = spyOn(publishers, 'publishRole');

    await caller.roles.reorder({ roleIds: [4, 3] });

    expect(publishRole).toHaveBeenCalledWith(4, 'update');
    expect(publishRole).toHaveBeenCalledWith(3, 'update');
  });

  test('should put a new role at the bottom', async () => {
    const { caller } = await initTest(1);

    await caller.roles.add();

    const roles = await caller.roles.getAll();
    const newest = roles.reduce((a, b) => (a.id > b.id ? a : b));

    expect(newest.position).toBeGreaterThan(
      Math.max(
        ...roles
          .filter(({ id }) => id !== newest.id)
          .map(({ position }) => position)
      )
    );
  });

  test('should refuse without the manage roles permission', async () => {
    const { caller } = await initTest(2);

    await expect(caller.roles.reorder({ roleIds: [4, 3] })).rejects.toThrow(
      'Insufficient permissions'
    );
  });

  test('should refuse an id that is not positive', async () => {
    const { caller } = await initTest(1);

    await expect(caller.roles.reorder({ roleIds: [0] })).rejects.toThrow();
  });
});
