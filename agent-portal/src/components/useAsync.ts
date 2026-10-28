import { useCallback, useEffect, useMemo, useState } from 'react';

export interface AsyncState<T> {
  data: T | null;
  error: unknown;
  loading: boolean;
  reload: () => void;
}

/**
 * Runs `load` on mount and whenever its identity changes. State is only set
 * when a request settles, keyed by the request it answers, so "loading" is
 * derived (the latest request hasn't answered yet) rather than set inside
 * the effect, and a stale answer is ignored.
 */
export function useAsync<T>(load: () => Promise<T>): AsyncState<T> {
  const [tick, setTick] = useState(0);
  // A fresh key per (load, reload) pair.
  const key = useMemo(() => ({ load, tick }), [load, tick]);
  const [result, setResult] = useState<{ key: object; data: T | null; error: unknown } | null>(
    null,
  );

  useEffect(() => {
    let alive = true;
    load().then(
      (data) => alive && setResult({ key, data, error: null }),
      (error: unknown) => alive && setResult({ key, data: null, error }),
    );
    return () => {
      alive = false;
    };
  }, [key, load]);

  const reload = useCallback(() => setTick((t) => t + 1), []);
  const current = result?.key === key ? result : null;
  return {
    data: current?.data ?? null,
    error: current?.error ?? null,
    loading: current === null,
    reload,
  };
}
