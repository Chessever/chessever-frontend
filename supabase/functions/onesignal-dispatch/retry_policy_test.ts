/**
 * Retry policy regression tests for the normal notification dispatcher.
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/retry_policy_test.ts
 */
import {
  assertEquals,
  assertGreaterOrEqual,
  assertLessOrEqual,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  classifyDispatchFailure,
  planDispatchFailure,
  retryScopeFromLastError,
  TransientFailureCircuit,
} from "./retry_policy.ts";

Deno.test("HTTP/2 PostgREST stream failures are transient backend failures", () => {
  assertEquals(
    classifyDispatchFailure(
      "Favorite map name lookup failed: client error: http2 error: stream error detected: unspecific protocol error",
    ),
    { retryable: true, scope: "backend" },
  );
});

Deno.test("rate limits and upstream errors are retryable", () => {
  assertEquals(classifyDispatchFailure("OneSignal HTTP 429"), {
    retryable: true,
    scope: "provider",
  });
  assertEquals(classifyDispatchFailure("OneSignal HTTP 503"), {
    retryable: true,
    scope: "provider",
  });
  assertEquals(
    classifyDispatchFailure("OneSignal API error: 503 upstream response"),
    {
      retryable: true,
      scope: "provider",
    },
  );
  assertEquals(classifyDispatchFailure("TypeError: connection reset by peer"), {
    retryable: true,
    scope: "backend",
  });
});

Deno.test("authentication and invalid requests fail without retry", () => {
  assertEquals(classifyDispatchFailure("OneSignal HTTP 401"), {
    retryable: false,
    scope: "provider",
  });
  assertEquals(classifyDispatchFailure("PostgREST HTTP 400"), {
    retryable: false,
    scope: "backend",
  });
  assertEquals(classifyDispatchFailure("unexpected application invariant"), {
    retryable: false,
    scope: "unknown",
  });
});

Deno.test("fresh transient failures remain retryable after four attempts", () => {
  const createdAtMs = Date.parse("2026-09-01T15:00:00Z");
  const plan = planDispatchFailure({
    error: "Favorite map name lookup failed: http2 stream error",
    attempts: 4,
    createdAtMs,
    nowMs: createdAtMs + 5 * 60_000,
    randomUnit: 0.5,
  });

  if (plan.action !== "retry") {
    throw new Error(`expected retry, got ${plan.action}`);
  }
  assertEquals(plan.delayMs, 10 * 60_000);
  assertEquals(plan.scope, "backend");
});

Deno.test("transient retries use bounded jitter and never cross freshness deadline", () => {
  const createdAtMs = Date.parse("2026-09-01T15:00:00Z");
  const early = planDispatchFailure({
    error: "HTTP 503",
    attempts: 1,
    createdAtMs,
    nowMs: createdAtMs,
    randomUnit: 0,
  });
  if (early.action !== "retry") {
    throw new Error(`expected retry, got ${early.action}`);
  }
  assertGreaterOrEqual(early.delayMs, 12_000);
  assertLessOrEqual(early.delayMs, 18_000);

  const nearDeadline = planDispatchFailure({
    error: "HTTP 503",
    attempts: 20,
    createdAtMs,
    nowMs: createdAtMs + 60 * 60_000 - 5_000,
    randomUnit: 1,
  });
  if (nearDeadline.action !== "retry") {
    throw new Error(`expected retry, got ${nearDeadline.action}`);
  }
  assertEquals(nearDeadline.delayMs, 5_000);
});

Deno.test("expired transient failures become stale skips, not terminal failures", () => {
  const createdAtMs = Date.parse("2026-09-01T15:00:00Z");
  const plan = planDispatchFailure({
    error: "network timeout",
    attempts: 12,
    createdAtMs,
    nowMs: createdAtMs + 60 * 60_000,
    randomUnit: 0.5,
  });

  assertEquals(plan, {
    action: "skip",
    reason: "transient_retry_expired",
    scope: "backend",
  });
});

Deno.test("transient failure circuit delays the rest of a dependency burst", () => {
  const circuit = new TransientFailureCircuit();
  circuit.trip("backend", 30_000);

  assertEquals(circuit.blocked("backend", 10_000), {
    scope: "backend",
    delayMs: 20_000,
  });
  assertEquals(circuit.blocked("provider", 10_000), null);
  assertEquals(circuit.blocked("backend", 30_000), null);
});

Deno.test("only rows already marked transient are eligible for circuit deferral", () => {
  assertEquals(retryScopeFromLastError(null), null);
  assertEquals(retryScopeFromLastError("non_retryable_error"), null);
  assertEquals(
    retryScopeFromLastError("transient_retry:backend: stream error"),
    "backend",
  );
  assertEquals(
    retryScopeFromLastError("transient_circuit_open:provider"),
    "provider",
  );
});

Deno.test("permanent failures remain terminal", () => {
  const createdAtMs = Date.parse("2026-09-01T15:00:00Z");
  assertEquals(
    planDispatchFailure({
      error: "OneSignal HTTP 403",
      attempts: 1,
      createdAtMs,
      nowMs: createdAtMs,
      randomUnit: 0.5,
    }),
    {
      action: "fail",
      reason: "non_retryable_error",
      scope: "provider",
    },
  );
});
