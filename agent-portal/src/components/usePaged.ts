import { useMemo, useState } from 'react';
import type { Page } from '../api/types';
import { useAsync } from './useAsync';

/**
 * A cursor-paged list: the first page loads with `fetchPage(null)`; "Load
 * more" passes `nextCursor` back unchanged. A new `fetchPage` (e.g. a changed
 * filter) starts over from the first page.
 */
export function usePaged<T>(fetchPage: (cursor: string | null) => Promise<Page<T>>) {
  const first = useAsync(useMemo(() => () => fetchPage(null), [fetchPage]));
  const [more, setMore] = useState<{
    owner: unknown;
    items: T[];
    cursor: string | null;
  } | null>(null);
  const [moreError, setMoreError] = useState<unknown>(null);
  const [loadingMore, setLoadingMore] = useState(false);

  const extra = more && more.owner === first.data ? more : null;
  const items = [...(first.data?.items ?? []), ...(extra?.items ?? [])];
  const cursor = extra ? extra.cursor : (first.data?.nextCursor ?? null);

  async function loadMore() {
    if (!cursor || loadingMore) return;
    const owner = first.data;
    setLoadingMore(true);
    setMoreError(null);
    try {
      const page = await fetchPage(cursor);
      setMore((prev) => ({
        owner,
        items: [...(prev && prev.owner === owner ? prev.items : []), ...page.items],
        cursor: page.nextCursor,
      }));
    } catch (e) {
      setMoreError(e);
    } finally {
      setLoadingMore(false);
    }
  }

  return {
    items,
    cursor,
    error: first.error ?? moreError,
    loading: first.loading || loadingMore,
    loadMore: () => void loadMore(),
    /** Retries whatever failed: the first page, or the last "load more". */
    retry: () => (first.error ? first.reload() : void loadMore()),
  };
}
