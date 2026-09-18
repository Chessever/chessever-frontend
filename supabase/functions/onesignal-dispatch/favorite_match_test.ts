/**
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/favorite_match_test.ts
 */
import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  collectFavoriteMatches,
  type FavoriteMatchRow,
} from "./favorite_match.ts";

Deno.test("collectFavoriteMatches pages the RPC until a short page", async () => {
  const calls: number[] = [];
  const rows = await collectFavoriteMatches({
    fideIds: ["1"],
    names: [],
    pageSize: 2,
    rpc: ({ p_offset, p_limit }) => {
      calls.push(p_offset);
      const page: FavoriteMatchRow[] = [];
      for (let i = 0; i < p_limit && p_offset + i < 5; i++) {
        page.push({
          user_id: `u${p_offset + i}`,
          fide_id: "1",
          player_name: null,
        });
      }
      return Promise.resolve({ data: page, error: null, status: 200 });
    },
  });
  assertEquals(rows.length, 5);
  assertEquals(calls, [0, 2, 4]);
});

Deno.test("collectFavoriteMatches falls back to packed REST when RPC fails", async () => {
  const restCalls: string[] = [];
  const rows = await collectFavoriteMatches({
    fideIds: ["1", "2"],
    names: [],
    rpc: () => {
      throw new Error("function not found");
    },
    restPage: (column, values, from, _to) => {
      restCalls.push(`${column}:${values.join(",")}:${from}`);
      if (from > 0) return Promise.resolve({ data: [], error: null, status: 200 });
      return Promise.resolve({
        data: values.map((id) => ({
          user_id: `u-${id}`,
          fide_id: id,
          player_name: null,
        })),
        error: null,
        status: 200,
      });
    },
  });
  assertEquals(rows.map((r) => r.user_id), ["u-1", "u-2"]);
  assertEquals(restCalls[0].startsWith("fide_id:"), true);
});

Deno.test("empty fide+name lists short-circuit", async () => {
  const rows = await collectFavoriteMatches({
    fideIds: [],
    names: [],
    rpc: () => {
      throw new Error("should not run");
    },
  });
  assertEquals(rows, []);
});
