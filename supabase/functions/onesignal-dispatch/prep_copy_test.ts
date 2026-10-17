/**
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/prep_copy_test.ts
 */
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { prepGamesAddedCopy } from "./prep_copy.ts";

Deno.test("the push never says how many games", () => {
  for (const added of [1, 2, 3, 4, 5, 7, 12, 19, 20, 21, 64, 150]) {
    const { title, body } = prepGamesAddedCopy("Hikaru", added);
    assert(!`${title} ${body}`.includes(String(added)), `${added}: ${title}`);
    assert(title.startsWith("Hikaru "));
  }
});

Deno.test("more games, stronger words", () => {
  assertEquals(prepGamesAddedCopy("Hikaru", 2).title, "Hikaru played today");
  assertEquals(prepGamesAddedCopy("Hikaru", 8).title, "Hikaru had a busy day");
  assertEquals(
    prepGamesAddedCopy("Hikaru", 40).title,
    "Hikaru could not stop playing",
  );
});

Deno.test("a blank name still reads", () => {
  assertEquals(prepGamesAddedCopy("  ", 1).title, "Your player played today");
});
