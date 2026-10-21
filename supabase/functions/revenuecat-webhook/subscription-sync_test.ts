import {
  affectedAccounts,
  syncSubscriptionEvent,
} from "./subscription-sync.ts";

const before = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const after = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("transfer reconciles both accounts without app_user_id or product_id", () => {
  equal(
    affectedAccounts({
      type: "TRANSFER",
      transferred_from: [before, "$RCAnonymousID:old"],
      transferred_to: [after],
    }),
    [before, after],
  );
});

Deno.test("renewal reconciles valid account aliases once and ignores anonymous IDs", () => {
  equal(
    affectedAccounts({
      app_user_id: "$RCAnonymousID:old",
      original_app_user_id: before,
      aliases: [before, after, null, "not-an-account"],
    }),
    [before, after],
  );
});

Deno.test("lifecycle events request current state without trusting their status", async () => {
  let received: unknown;
  const fetcher: typeof fetch = (_input, options) => {
    received = JSON.parse((options as { body: string }).body);
    return Promise.resolve(Response.json({ summary: { error: 0 } }));
  };
  await syncSubscriptionEvent(
    { type: "EXPIRATION", app_user_id: before },
    "https://example.supabase.co",
    "test-only",
    fetcher,
  );
  equal(received, { userIds: [before], concurrency: 4 });
});

for (const failure of ["http", "partial"]) {
  Deno.test(`${failure} sync failure must be retried rather than acknowledged`, async () => {
    const fetcher: typeof fetch = () =>
      Promise.resolve(
        failure === "http"
          ? new Response(null, { status: 503 })
          : Response.json({ summary: { error: 1 } }),
      );
    let failed = false;
    try {
      await syncSubscriptionEvent(
        { app_user_id: before },
        "https://example.supabase.co",
        "test-only",
        fetcher,
      );
    } catch {
      failed = true;
    }
    equal(failed, true);
  });
}
