export type PaymentAnalyticsEvent = {
  event_key: string;
  channel: "web" | "mobile";
  provider: "stripe" | "revenuecat";
  user_id: string;
  appsflyer_id?: string | null;
  app_id?: string | null;
  event_name: string;
  transaction_id: string;
  amount: number;
  currency: string;
  occurred_at: string;
  is_sandbox: boolean;
};
/** Persist first, then dispatch separately. A failed enqueue asks the provider to
 * retry; the event_key prevents duplicate ledger/reporting entries on redelivery. */
export async function recordPaymentAnalytics(event: PaymentAnalyticsEvent) {
  const response = await fetch(
    `${Deno.env.get("SUPABASE_URL")}/functions/v1/payment-analytics`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-payment-analytics-token": Deno.env.get("PAYMENT_ANALYTICS_TOKEN") ??
          "",
      },
      body: JSON.stringify({ event }),
      signal: AbortSignal.timeout(8_000),
    },
  );
  if (!response.ok) {
    throw new Error(`Payment analytics enqueue failed (${response.status})`);
  }
}
