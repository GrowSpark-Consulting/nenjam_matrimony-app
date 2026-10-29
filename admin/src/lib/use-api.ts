'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useSession } from './session';
import type { ApiClient } from './api';

/**
 * Loads data with the session's API client: { data, error, loading, reload }.
 * [deps] re-run it; a newer load always wins over an older one.
 */
export function useApi<T>(
  load: (api: ApiClient) => Promise<T>,
  deps: readonly unknown[],
) {
  const { api } = useSession();
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const generation = useRef(0);

  const run = useCallback(async () => {
    const mine = ++generation.current;
    setLoading(true);
    setError(null);
    try {
      const result = await load(api);
      if (mine === generation.current) setData(result);
    } catch (e) {
      if (mine === generation.current) {
        setError(e instanceof Error ? e.message : 'Something went wrong.');
      }
    } finally {
      if (mine === generation.current) setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [api, ...deps]);

  useEffect(() => {
    void run();
  }, [run]);

  return { data, error, loading, reload: run, setData };
}
