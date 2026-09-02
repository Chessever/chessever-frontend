/**
 * Per-round favorite lookup cache regressions.
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/round_favorite_cache_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { RoundFavoriteCache } from "./round_favorite_cache.ts";

Deno.test("round favorite cache loads only users not already resolved", async () => {
  const calls: string[][] = [];
  const cache = new RoundFavoriteCache((_roundId, userIds) => {
    calls.push([...userIds]);
    return Promise.resolve(
      new Map([...userIds].map((userId) => [userId, [`favorite:${userId}`]])),
    );
  });

  assertEquals(
    await cache.resolve("round-1", new Set(["user-1", "user-2"])),
    new Map([
      ["user-1", ["favorite:user-1"]],
      ["user-2", ["favorite:user-2"]],
    ]),
  );
  assertEquals(
    await cache.resolve("round-1", new Set(["user-2", "user-3"])),
    new Map([
      ["user-2", ["favorite:user-2"]],
      ["user-3", ["favorite:user-3"]],
    ]),
  );
  assertEquals(calls, [["user-1", "user-2"], ["user-3"]]);
});

Deno.test("round favorite cache remembers empty results", async () => {
  let calls = 0;
  const cache = new RoundFavoriteCache(() => {
    calls += 1;
    return Promise.resolve(new Map());
  });

  assertEquals(await cache.resolve("round-1", new Set(["user-1"])), new Map());
  assertEquals(await cache.resolve("round-1", new Set(["user-1"])), new Map());
  assertEquals(calls, 1);
});

Deno.test("round favorite cache retries a failed loader", async () => {
  let calls = 0;
  const cache = new RoundFavoriteCache((_roundId, userIds) => {
    calls += 1;
    if (calls === 1) {
      return Promise.reject(new Error("temporary lookup failure"));
    }
    return Promise.resolve(
      new Map([...userIds].map((userId) => [userId, ["ok"]])),
    );
  });

  try {
    await cache.resolve("round-1", new Set(["user-1"]));
    throw new Error("expected loader failure");
  } catch (error) {
    assertEquals((error as Error).message, "temporary lookup failure");
  }
  assertEquals(
    await cache.resolve("round-1", new Set(["user-1"])),
    new Map([["user-1", ["ok"]]]),
  );
  assertEquals(calls, 2);
});

Deno.test("round favorite cache isolates rounds", async () => {
  const calls: string[] = [];
  const cache = new RoundFavoriteCache((roundId, userIds) => {
    calls.push(roundId);
    return Promise.resolve(
      new Map([...userIds].map((userId) => [userId, [roundId]])),
    );
  });

  assertEquals(
    await cache.resolve("round-1", new Set(["user-1"])),
    new Map([["user-1", ["round-1"]]]),
  );
  assertEquals(
    await cache.resolve("round-2", new Set(["user-1"])),
    new Map([["user-1", ["round-2"]]]),
  );
  assertEquals(calls, ["round-1", "round-2"]);
});
