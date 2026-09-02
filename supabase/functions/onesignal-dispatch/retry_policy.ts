export type DispatchFailureScope = "backend" | "provider" | "unknown";

export type DispatchFailureClassification = {
  retryable: boolean;
  scope: DispatchFailureScope;
};

export type DispatchFailurePlan =
  | {
    action: "retry";
    delayMs: number;
    scope: DispatchFailureScope;
  }
  | {
    action: "skip" | "fail";
    reason: "transient_retry_expired" | "non_retryable_error";
    scope: DispatchFailureScope;
  };

const FRESHNESS_WINDOW_MS = 60 * 60 * 1000;
const RETRY_DELAYS_MS = [15_000, 60_000, 3 * 60_000, 10 * 60_000];
const JITTER_MIN = 0.8;
const JITTER_RANGE = 0.4;

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function httpStatus(message: string): number | null {
  const match = message.match(
    /\b(?:http(?:\/\d(?:\.\d)?)?\s*(?:error|status)?|api error)\s*[:=]?\s*(\d{3})\b/i,
  );
  return match ? Number(match[1]) : null;
}

function failureScope(message: string): DispatchFailureScope {
  if (/onesignal/i.test(message)) return "provider";
  if (
    /postgrest|supabase|lookup failed|http2|stream error|network|fetch|connection|timed?\s*out|timeout|socket|dns|broken pipe|reset by peer/i
      .test(message)
  ) {
    return "backend";
  }
  return "unknown";
}

export function classifyDispatchFailure(
  error: unknown,
): DispatchFailureClassification {
  const message = errorMessage(error);
  const scope = failureScope(message);
  const status = httpStatus(message);

  if (status !== null) {
    if (status === 408 || status === 429 || status >= 500) {
      return { retryable: true, scope };
    }
    if (status >= 400) return { retryable: false, scope };
  }

  const retryable =
    /http2|stream error|network|fetch failed|connection|timed?\s*out|timeout|socket|dns|broken pipe|reset by peer|temporar(?:y|ily)|unavailable|rate limit/i
      .test(message);
  return { retryable, scope };
}

export function planDispatchFailure(args: {
  error: unknown;
  attempts: number;
  createdAtMs: number;
  nowMs: number;
  randomUnit?: number;
}): DispatchFailurePlan {
  const classification = classifyDispatchFailure(args.error);
  if (!classification.retryable) {
    return {
      action: "fail",
      reason: "non_retryable_error",
      scope: classification.scope,
    };
  }

  const deadlineMs = args.createdAtMs + FRESHNESS_WINDOW_MS;
  const remainingMs = deadlineMs - args.nowMs;
  if (remainingMs <= 0) {
    return {
      action: "skip",
      reason: "transient_retry_expired",
      scope: classification.scope,
    };
  }

  const index = Math.max(
    0,
    Math.min(args.attempts - 1, RETRY_DELAYS_MS.length - 1),
  );
  const baseDelayMs = RETRY_DELAYS_MS[index];
  const randomUnit = Math.max(0, Math.min(args.randomUnit ?? Math.random(), 1));
  const jitteredDelayMs = Math.round(
    baseDelayMs * (JITTER_MIN + JITTER_RANGE * randomUnit),
  );

  return {
    action: "retry",
    delayMs: Math.min(jitteredDelayMs, remainingMs),
    scope: classification.scope,
  };
}

export function retryScopeFromLastError(
  lastError: string | null,
): DispatchFailureScope | null {
  const match = lastError?.match(
    /^transient_(?:retry|circuit_open):(backend|provider)(?::|$)/,
  );
  return (match?.[1] as DispatchFailureScope | undefined) ?? null;
}

export class TransientFailureCircuit {
  private readonly openUntilByScope = new Map<DispatchFailureScope, number>();

  trip(scope: DispatchFailureScope, openUntilMs: number): void {
    if (scope === "unknown") return;
    const existing = this.openUntilByScope.get(scope) ?? 0;
    this.openUntilByScope.set(scope, Math.max(existing, openUntilMs));
  }

  blocked(
    scope: DispatchFailureScope,
    nowMs: number,
  ): { scope: DispatchFailureScope; delayMs: number } | null {
    const delayMs = (this.openUntilByScope.get(scope) ?? 0) - nowMs;
    return delayMs > 0 ? { scope, delayMs } : null;
  }
}
