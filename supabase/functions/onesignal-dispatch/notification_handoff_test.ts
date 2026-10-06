import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handoffNotification } from "./notification_handoff.ts";

Deno.test("in-house handoff preserves UTF-8 copy and retry identity", async () => {
  const requests: Array<
    { headers: Headers; payload: Record<string, unknown> }
  > = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (_input, init) => {
    const request = init as { headers: Record<string, string>; body: string };
    requests.push({
      headers: new Headers(request.headers),
      payload: JSON.parse(request.body),
    });
    return Promise.resolve(new Response(null, { status: 202 }));
  };
  const notification = {
    title: "Ivan Šarić is live",
    body: "Ivan Šarić vs Ediz Gürel is live. Zürich - Round 2",
    url: null,
    data: { type: "game_started", game_id: "game-1" },
  };
  try {
    await handoffNotification(
      "https://notifications.invalid",
      "test-secret",
      "outbox-1",
      ["user-2", "user-1"],
      notification,
    );
    await handoffNotification(
      "https://notifications.invalid",
      "test-secret",
      "outbox-1",
      ["user-1", "user-2", "user-1"],
      notification,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
  assertEquals(requests.length, 2);
  for (const request of requests) {
    assertEquals(
      request.headers.get("content-type"),
      "application/json; charset=utf-8",
    );
    assertEquals(request.payload.title, notification.title);
    assertEquals(request.payload.body, notification.body);
    assertEquals(request.payload.userIds, ["user-1", "user-2"]);
    assertEquals(request.payload.ttlSeconds, 900);
  }
  assertEquals(requests[0].payload.eventKey, requests[1].payload.eventKey);
});
