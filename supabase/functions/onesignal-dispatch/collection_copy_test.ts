/**
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/collection_copy_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  collectionGamesAddedCopy,
  collectionGamesPushFromPayload,
} from "./collection_copy.ts";

Deno.test("the count leads", () => {
  assertEquals(
    collectionGamesAddedCopy({ title: "Best of 2026", kind: "book", added: 4 }),
    {
      title: "Best of 2026 added 4 new games",
      body: "Fresh in a book you starred. Tap to see all 4.",
    },
  );
  assertEquals(
    collectionGamesAddedCopy({
      title: "Tata Steel 2026",
      kind: "event",
      added: 1,
    }),
    {
      title: "Tata Steel 2026 added 1 new game",
      body: "Fresh in an event you starred. Tap to see it.",
    },
  );
});

Deno.test("a big import reads as one number", () => {
  assertEquals(
    collectionGamesAddedCopy({ title: "Mega 2026", kind: "book", added: 12480 })
      .title,
    "Mega 2026 added 12,480 new games",
  );
});

Deno.test("a row with no count still reads", () => {
  assertEquals(
    collectionGamesAddedCopy({
      title: "Best of 2026",
      kind: null,
      added: null,
    }),
    {
      title: "Best of 2026 has new games",
      body:
        "Fresh games just landed in a collection you starred. Tap to see them.",
    },
  );
  assertEquals(
    collectionGamesAddedCopy({ title: " ", kind: "book", added: 3 }).title,
    "A collection you starred added 3 new games",
  );
});

Deno.test("the payload is read defensively", () => {
  assertEquals(
    collectionGamesPushFromPayload({ title: "X", kind: "book", added: "7" }),
    { title: "X", kind: "book", added: 7 },
  );
  assertEquals(collectionGamesPushFromPayload({ added: null }).added, null);
  assertEquals(collectionGamesPushFromPayload({ added: 0 }).added, null);
  assertEquals(collectionGamesPushFromPayload({}).added, null);
  assertEquals(collectionGamesPushFromPayload(null).title, "");
});
