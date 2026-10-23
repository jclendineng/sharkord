import { getTRPCClient } from '@/lib/trpc';
import { getTrpcError } from '@sharkord/shared';
import { useEffect, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from 'sonner';
import type { TSearchResults, TUnifiedSearchResult } from './types';

const EMPTY_RESULTS: TSearchResults = {
  messages: [],
  files: [],
  truncated: false
};
const MIN_QUERY_LENGTH = 2;
const DEBOUNCE_MS = 300;

export const useSearch = (isOpen: boolean) => {
  const { t } = useTranslation('common');

  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState<TSearchResults>(EMPTY_RESULTS);

  useEffect(() => {
    const trimmed = query.trim();

    // a query too short to search shows nothing without touching state, see canSearch below
    if (!isOpen || trimmed.length < MIN_QUERY_LENGTH) {
      return;
    }

    let cancelled = false;

    const load = async () => {
      const trpc = getTRPCClient();

      setLoading(true);

      try {
        const next = await trpc.messages.search.query({ query: trimmed });

        if (!cancelled) {
          setResults(next);
        }
      } catch (error) {
        toast.error(getTrpcError(error, t('common:failedLoadSearchResults')));

        setResults(EMPTY_RESULTS);
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    };

    const timer = setTimeout(load, DEBOUNCE_MS);

    return () => {
      clearTimeout(timer);
      cancelled = true;
    };
  }, [query, isOpen, t]);

  // the dialog unmounts once closed, so it opens fresh each time. a query too short to
  // search hides the last results rather than clearing them
  const canSearch = query.trim().length >= MIN_QUERY_LENGTH;
  const shownResults = canSearch ? results : EMPTY_RESULTS;
  const totalResults = shownResults.messages.length + shownResults.files.length;
  const truncated = shownResults.truncated;

  // combine messages and files into a single list
  const unifiedResults: TUnifiedSearchResult[] = useMemo(
    () =>
      [
        ...shownResults.messages.map((message) => ({
          type: 'message' as const,
          createdAt: message.createdAt,
          key: `message-${message.id}`,
          item: message
        })),
        ...shownResults.files.map((fileResult) => ({
          type: 'file' as const,
          createdAt: fileResult.messageCreatedAt,
          key: `file-${fileResult.file.id}-${fileResult.messageId}`,
          item: fileResult
        }))
      ].sort((a, b) => b.createdAt - a.createdAt),
    [shownResults]
  );

  return {
    query,
    setQuery,
    loading: canSearch && loading,
    canSearch,
    totalResults,
    truncated,
    unifiedResults
  };
};
