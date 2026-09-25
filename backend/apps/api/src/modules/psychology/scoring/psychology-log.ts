import type { Logger } from '@nestjs/common';

const WINDOW_MS = 60_000;

interface Window {
  startedAt: number;
  suppressed: number;
}

const windows = new Map<string, Window>();

/**
 * Warns at most once per minute per `key`, noting how many repeats were
 * swallowed in between.
 *
 * Psychology failures are, by design, silent to the member — Discover falls
 * back to non-psychology matching — so the log line is the only signal
 * operators get. But the failure paths run once per Discover request (or once
 * per candidate pair), so an unthrottled warning during an outage would bury
 * every other log line and cost more than the failure it reports.
 */
export function warnThrottled(
  logger: Logger,
  key: string,
  message: string,
  now: number = Date.now(),
): void {
  const window = windows.get(key);
  if (window && now - window.startedAt < WINDOW_MS) {
    window.suppressed += 1;
    return;
  }
  const repeats = window?.suppressed ?? 0;
  windows.set(key, { startedAt: now, suppressed: 0 });
  logger.warn(
    repeats > 0
      ? `${message} (+${repeats} similar in the last minute)`
      : message,
  );
}

/** Test seam: forget throttle state. */
export function resetWarnThrottle(): void {
  windows.clear();
}

const MAX_LOGGED_MESSAGE = 200;

/**
 * A log-safe summary of an error. Never the full message of a database error:
 * Prisma's messages embed the failing query's arguments, and for a quiz write
 * those arguments ARE the member's answers — sensitive personal information
 * that has no business in an application log. Database errors are reduced to
 * their class and code; anything else is truncated to its first line.
 */
export function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    if (/prisma|driveradapter/i.test(error.name)) {
      const code = (error as { code?: unknown }).code;
      return typeof code === 'string' ? `${error.name} (${code})` : error.name;
    }
    return firstLine(error.message);
  }
  return typeof error === 'string' ? firstLine(error) : 'unknown error';
}

function firstLine(text: string): string {
  return text.split(/[\r\n]/)[0].slice(0, MAX_LOGGED_MESSAGE);
}
