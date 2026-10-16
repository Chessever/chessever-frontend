/**
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/collection_subscribers_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  collectionStarNotifies,
  collectionStarRecipients,
} from "./collection_subscribers.ts";

Deno.test("a collection star notifies unless its owner turned it off", () => {
  assertEquals(collectionStarNotifies(true), true);
  // Never asked: an older build, the desktop app, a star from before the question.
  assertEquals(collectionStarNotifies(null), true);
  assertEquals(collectionStarNotifies(undefined), true);
  assertEquals(collectionStarNotifies(false), false);
  assertEquals(collectionStarNotifies("false"), false);
});

Deno.test("recipients are every starring user once, minus those who said no", () => {
  assertEquals(
    collectionStarRecipients([
      { user_id: "legacy", notifications: null },
      { user_id: "yes", notifications: true },
      { user_id: "no", notifications: false },
      { user_id: "yes", notifications: true },
      { user_id: null, notifications: true },
    ]),
    ["legacy", "yes"],
  );
});
