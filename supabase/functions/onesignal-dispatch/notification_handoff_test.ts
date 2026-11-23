import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { compactPushData, handoffNotification } from "./notification_handoff.ts";

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

Deno.test("handoff drops null and undefined data values", async () => {
  const payloads: Array<Record<string, unknown>> = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (_input, init) => {
    payloads.push(JSON.parse((init as { body: string }).body));
    return Promise.resolve(new Response(null, { status: 202 }));
  };
  try {
    await handoffNotification(
      "https://notifications.invalid",
      "test-secret",
      "outbox-2",
      ["user-1"],
      {
        title: "Round 3 starts in 15 minutes",
        body: "Zürich Open",
        url: null,
        // round_heads_up with neither id known: the FCM worker stringified
        // these into "null", which the app then looked up as a tour.
        data: {
          type: "round_heads_up",
          round_id: "round-3",
          tour_id: null,
          group_broadcast_id: undefined,
        },
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
  assertEquals(payloads[0].data, { type: "round_heads_up", round_id: "round-3" });
});

Deno.test("handoff carries the push picture and collapse key only when set", async () => {
  const payloads: Array<Record<string, unknown>> = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (_input, init) => {
    payloads.push(JSON.parse((init as { body: string }).body));
    return Promise.resolve(new Response(null, { status: 202 }));
  };
  try {
    await handoffNotification(
      "https://notifications.invalid",
      "test-secret",
      "outbox-3",
      ["user-1"],
      {
        title: "New games in Najdorf Mastery",
        body: "3 games added",
        url: null,
        data: { type: "collection_games_added", collection_slug: "najdorf" },
        imageUrl: "https://cdn.chessever.com/covers/najdorf.webp",
      },
      "collection:najdorf",
    );
    await handoffNotification(
      "https://notifications.invalid",
      "test-secret",
      "outbox-4",
      ["user-1"],
      {
        title: "Round 3 started",
        body: "Zürich Open",
        url: null,
        data: { type: "round_started", round_id: "round-3" },
        imageUrl: null,
      },
      null,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
  assertEquals(payloads[0].image, "https://cdn.chessever.com/covers/najdorf.webp");
  assertEquals(payloads[0].collapseKey, "collection:najdorf");
  // Old shape exactly when neither is known: no image or collapseKey keys.
  assertEquals("image" in payloads[1], false);
  assertEquals("collapseKey" in payloads[1], false);
});

Deno.test("compactPushData keeps falsy values that are not null", () => {
  assertEquals(
    compactPushData({ a: 0, b: "", c: false, d: null, e: undefined, f: "x" }),
    { a: 0, b: "", c: false, f: "x" },
  );
});
