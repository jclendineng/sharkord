import { getTRPCClient, type TRouterOutputs } from '@/lib/trpc';
import {
  DELETED_USER_IDENTITY_AND_NAME,
  parseTrpcErrors,
  type TCategory,
  type TChannel,
  type TChannelRolePermission,
  type TChannelUserPermission,
  type TDiskMetrics,
  type TFile,
  type TJoinedEmoji,
  type TJoinedInvite,
  type TJoinedRole,
  type TLogin,
  type TMessage,
  type TPluginInfo,
  type TPluginStorageUsage,
  type TStorageData,
  type TStorageSettings,
  type TTrpcErrors
} from '@sharkord/shared';
import { useCallback, useEffect, useState } from 'react';

export type TAdminUser = TRouterOutputs['users']['getAll'][number];
export type TAdminUserInfo = TRouterOutputs['users']['getInfo']['user'];

// loads on mount and whenever load changes. loading starts true, so a load sets no state
// before its request and an effect never sets state synchronously; only refetch shows
// loading again
const useAdminLoad = (load: () => Promise<void>) => {
  const [loading, setLoading] = useState(true);

  const refetch = useCallback(async () => {
    setLoading(true);
    await load();
    setLoading(false);
  }, [load]);

  useEffect(() => {
    load().then(() => setLoading(false));
  }, [load]);

  return { loading, refetch };
};

export const useAdminGeneral = () => {
  const [settings, setSettings] = useState<
    TRouterOutputs['others']['getSettings'] | undefined
  >(undefined);

  const fetchSettings = useCallback(async () => {
    const trpc = getTRPCClient();

    setSettings(await trpc.others.getSettings.query());
  }, []);

  const { loading, refetch } = useAdminLoad(fetchSettings);

  return { settings, refetch, loading };
};

export const useAdminPlugins = (canManagePlugins: boolean) => {
  const [errors, setErrors] = useState<TTrpcErrors>({});
  const [plugins, setPlugins] = useState<TPluginInfo[]>([]);

  const fetchPlugins = useCallback(async () => {
    if (!canManagePlugins) {
      return;
    }

    const trpc = getTRPCClient();

    try {
      const { plugins } = await trpc.plugins.get.query();

      // TODO: check this
      // @ts-expect-error - ver esta merda wtf
      setPlugins(plugins);
    } catch (error) {
      console.error('Error fetching plugins:', error);
      setErrors(parseTrpcErrors(error));
    }
  }, [canManagePlugins]);

  const { loading, refetch } = useAdminLoad(fetchPlugins);

  return {
    refetch,
    plugins,
    loading,
    errors
  };
};

export const useAdminChannelGeneral = (channelId: number) => {
  const [channel, setChannel] = useState<TChannel | undefined>(undefined);

  const fetchChannel = useCallback(async () => {
    const trpc = getTRPCClient();

    setChannel(await trpc.channels.get.query({ channelId }));
  }, [channelId]);

  const { loading, refetch } = useAdminLoad(fetchChannel);

  return { channel, refetch, loading };
};

export const useAdminCategoryGeneral = (categoryId: number) => {
  const [category, setCategory] = useState<TCategory | undefined>(undefined);

  const fetchCategory = useCallback(async () => {
    const trpc = getTRPCClient();

    setCategory(await trpc.categories.get.query({ categoryId }));
  }, [categoryId]);

  const { loading, refetch } = useAdminLoad(fetchCategory);

  return { category, refetch, loading };
};

export const useAdminEmojis = () => {
  const [emojis, setEmojis] = useState<TJoinedEmoji[]>([]);

  const fetchEmojis = useCallback(async () => {
    const trpc = getTRPCClient();

    setEmojis(await trpc.emojis.getAll.query());
  }, []);

  const { loading, refetch } = useAdminLoad(fetchEmojis);

  return { emojis, refetch, loading };
};

export const useAdminRoles = () => {
  const [roles, setRoles] = useState<TJoinedRole[]>([]);

  const fetchRoles = useCallback(async () => {
    const trpc = getTRPCClient();

    setRoles(await trpc.roles.getAll.query());
  }, []);

  const { loading, refetch } = useAdminLoad(fetchRoles);

  return { roles, refetch, loading };
};

export const useAdminStorage = () => {
  const [storageSettings, setStorageSettings] = useState<
    TStorageSettings | undefined
  >(undefined);
  const [diskMetrics, setDiskMetrics] = useState<TDiskMetrics | undefined>(
    undefined
  );
  const [pluginStorage, setPluginStorage] = useState<TPluginStorageUsage[]>([]);

  const fetchStorageSettings = useCallback(async () => {
    const trpc = getTRPCClient();
    const { storageSettings, diskMetrics, pluginStorage } =
      await trpc.others.getStorageSettings.query();

    setStorageSettings(storageSettings);
    setDiskMetrics(diskMetrics);
    setPluginStorage(pluginStorage);
  }, []);

  const { loading, refetch } = useAdminLoad(fetchStorageSettings);

  return {
    storageSettings,
    diskMetrics,
    pluginStorage,
    refetch,
    loading
  };
};

export const useAdminUsers = () => {
  const [users, setUsers] = useState<TAdminUser[]>([]);

  const fetchUsers = useCallback(async () => {
    const trpc = getTRPCClient();
    const users = await trpc.users.getAll.query();

    const filteredUsers = users.filter(
      (user) => user.name !== DELETED_USER_IDENTITY_AND_NAME
    );

    setUsers(filteredUsers);
  }, []);

  const { loading, refetch } = useAdminLoad(fetchUsers);

  return {
    users,
    refetch,
    loading
  };
};

export const useAdminChannelPermissions = (channelId: number) => {
  const [rolePermissions, setRolePermissions] = useState<
    TChannelRolePermission[]
  >([]);
  const [userPermissions, setUserPermissions] = useState<
    TChannelUserPermission[]
  >([]);

  const fetchPermissions = useCallback(async () => {
    const trpc = getTRPCClient();
    const { rolePermissions, userPermissions } =
      await trpc.channels.getPermissions.query({ channelId });

    setRolePermissions(rolePermissions);
    setUserPermissions(userPermissions);
  }, [channelId]);

  const { loading, refetch } = useAdminLoad(fetchPermissions);

  return {
    rolePermissions,
    userPermissions,
    refetch,
    loading
  };
};

export const useAdminUserInfo = (userId: number) => {
  const [user, setUser] = useState<TAdminUserInfo | null>(null);
  const [logins, setLogins] = useState<TLogin[]>([]);
  const [files, setFiles] = useState<TFile[]>([]);
  const [messages, setMessages] = useState<TMessage[]>([]);
  const [storage, setStorage] = useState<TStorageData & { quota: number }>({
    userId,
    fileCount: 0,
    usedStorage: 0,
    quota: 0
  });

  const fetchUser = useCallback(async () => {
    const trpc = getTRPCClient();
    const { user, logins, files, messages, storage } =
      await trpc.users.getInfo.query({
        userId
      });

    setUser(user);
    setLogins(logins);
    setFiles(files);
    setMessages(messages);
    setStorage(storage);
  }, [userId]);

  const { loading, refetch } = useAdminLoad(fetchUser);

  return {
    user,
    logins,
    files,
    storage,
    refetch,
    loading,
    messages
  };
};

export const useAdminInvites = () => {
  const [invites, setInvites] = useState<TJoinedInvite[]>([]);

  const fetchInvites = useCallback(async () => {
    const trpc = getTRPCClient();
    const invites = await trpc.invites.getAll.query();

    setInvites(invites);
  }, []);

  const { loading, refetch } = useAdminLoad(fetchInvites);

  return {
    invites,
    refetch,
    loading
  };
};
