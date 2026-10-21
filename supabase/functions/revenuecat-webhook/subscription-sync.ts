const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Transfers omit app_user_id; reconcile both sides and every account alias. */
export function affectedAccounts(event: Record<string, unknown>): string[] {
  const values = [event.app_user_id, event.original_app_user_id];
  for (const field of ["aliases", "transferred_from", "transferred_to"]) {
    if (Array.isArray(event[field])) values.push(...event[field]);
  }
  return [
    ...new Set(
      values.filter((value): value is string =>
        typeof value === "string" && UUID.test(value)
      ).map((value) => value.toLowerCase()),
    ),
  ];
}

/** Re-read current receipts instead of applying possibly out-of-order events. */
export async function syncSubscriptionEvent(
  event: Record<string, unknown>,
  projectUrl: string,
  syncToken: string,
  fetcher: typeof fetch = fetch,
): Promise<void> {
  const userIds = affectedAccounts(event);
  if (!userIds.length) return;
  if (!syncToken) throw new Error("Subscription sync token is not configured");

  const response = await fetcher(`${projectUrl}/functions/v1/revenuecat-sync`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-sync-token": syncToken },
    body: JSON.stringify({ userIds, concurrency: 4 }),
    signal: AbortSignal.timeout(25_000),
  });
  if (!response.ok) {
    throw new Error(`Subscription sync returned ${response.status}`);
  }
  const result = await response.json();
  if (result.summary?.error !== 0) {
    throw new Error("Subscription sync did not complete; retry the webhook");
  }
}
