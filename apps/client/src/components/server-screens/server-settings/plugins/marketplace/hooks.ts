import {
  MARKETPLACE_REGISTRY_URL,
  parseMarketplaceRegistry,
  type TMarketplaceEntry
} from '@sharkord/shared';
import type { TFunction } from 'i18next';
import { useCallback, useEffect, useMemo, useState } from 'react';

const getLatestTimestamp = (entry: TMarketplaceEntry) => {
  return entry.versions[0]?.timestamp ?? 0;
};

// the registry with each plugin's versions newest first, and the plugins by their newest
const loadMarketplace = async (): Promise<TMarketplaceEntry[]> => {
  const response = await fetch(MARKETPLACE_REGISTRY_URL);

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  const data = parseMarketplaceRegistry(await response.json());

  return data
    .map((entry) => ({
      ...entry,
      versions: [...entry.versions].sort(
        (left, right) => right.timestamp - left.timestamp
      )
    }))
    .sort(
      (left, right) => getLatestTimestamp(right) - getLatestTimestamp(left)
    );
};

const useMarketplaceData = (t: TFunction<'settings'>) => {
  const [entries, setEntries] = useState<TMarketplaceEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [isRefreshing, setIsRefreshing] = useState(false);

  // the error starts empty, so only a refresh has one to clear. state is only set in the
  // promise's callbacks, never before the request goes out
  const fetchMarketplace = useCallback(
    () =>
      loadMarketplace()
        .then(setEntries)
        .catch(() => setError(t('marketplaceFetchError')))
        .finally(() => {
          setLoading(false);
          setIsRefreshing(false);
        }),
    [t]
  );

  useEffect(() => {
    fetchMarketplace();
  }, [fetchMarketplace]);

  const refresh = useCallback(async () => {
    setError(null);
    setIsRefreshing(true);
    await fetchMarketplace();
  }, [fetchMarketplace]);

  const filtered = useMemo(() => {
    if (!search.trim()) return entries;

    const query = search.toLowerCase().trim();

    return entries.filter((entry) => {
      const { plugin } = entry;

      return (
        plugin.name.toLowerCase().includes(query) ||
        plugin.description.toLowerCase().includes(query) ||
        plugin.author.toLowerCase().includes(query) ||
        plugin.tags?.some((tag) => tag.toLowerCase().includes(query)) ||
        plugin.categories?.some((cat) => cat.toLowerCase().includes(query))
      );
    });
  }, [entries, search]);

  return {
    entries,
    filtered,
    loading,
    error,
    search,
    setSearch,
    isRefreshing,
    refresh
  };
};

export { useMarketplaceData };
