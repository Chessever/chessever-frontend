/**
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/postgrest_in_test.ts
 */
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  chunk,
  estimatedInFilterUrlBytes,
  packForUrlBudget,
  POSTGREST_IN_URL_BUDGET_BYTES,
} from "./postgrest_in.ts";
import { packedPageCountFor } from "./favorite_match.ts";

function olympiadNames(count: number): string[] {
  return Array.from({ length: count }, (_, i) => `Player, Name ${i + 1}`);
}

Deno.test("empty list chunks to nothing", () => {
  assertEquals(chunk([], 100), []);
});

Deno.test("list shorter than the chunk stays one page", () => {
  assertEquals(chunk(["a", "b"], 100), [["a", "b"]]);
});

Deno.test("packForUrlBudget never drops a leftover", () => {
  const names = olympiadNames(800);
  const pages = packForUrlBudget(names);
  assert(pages.length > 1);
  assertEquals(pages.flat().length, 800);
  for (const page of pages) {
    assert(estimatedInFilterUrlBytes(page) <= POSTGREST_IN_URL_BUDGET_BYTES);
  }
});

Deno.test("one 404-board olympiad .in() exceeds the URL budget", () => {
  const names = olympiadNames(800);
  assert(estimatedInFilterUrlBytes(names) > POSTGREST_IN_URL_BUDGET_BYTES);
  assert(packedPageCountFor(names) > 1);
});

Deno.test("a value over budget still gets its own page", () => {
  const huge = "x".repeat(20_000);
  const pages = packForUrlBudget(["ok", huge, "also"]);
  assertEquals(pages.flat(), ["ok", huge, "also"]);
});
