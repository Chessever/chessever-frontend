/**
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/prep_copy_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  prepGamesAddedCopy,
  type PrepGamesPush,
  prepGamesPushFromPayload,
} from "./prep_copy.ts";

function push(overrides: Partial<PrepGamesPush>): PrepGamesPush {
  return {
    profileName: "Vasif Durarbayli",
    profileTitle: "GM",
    games: 7,
    accounts: [{ source: "lichess", username: "durarbayli" }],
    slot: 1,
    localHour: 15,
    otherPlayers: 0,
    ...overrides,
  };
}

Deno.test("names the player, the account and when", () => {
  assertEquals(prepGamesAddedCopy(push({})), {
    title: "GM Vasif Durarbayli played 7 games this afternoon",
    body: "New games from durarbayli on Lichess. Tap to see.",
  });
  assertEquals(
    prepGamesAddedCopy(push({ localHour: 10 })).title,
    "GM Vasif Durarbayli played 7 games this morning",
  );
  assertEquals(
    prepGamesAddedCopy(push({ localHour: 21 })).title,
    "GM Vasif Durarbayli played 7 games this evening",
  );
});

Deno.test("the day's second push says they kept playing", () => {
  assertEquals(prepGamesAddedCopy(push({ slot: 2 })), {
    title: "GM Vasif Durarbayli is still playing: 7 more games",
    body: "More new games from durarbayli on Lichess. Tap to see.",
  });
});

Deno.test("two accounts, and the other players who played", () => {
  const copy = prepGamesAddedCopy(push({
    accounts: [
      { source: "chesscom", username: "Hikaru" },
      { source: "lichess", username: "DrNykterstein" },
    ],
    profileName: "Hikaru Nakamura",
    otherPlayers: 2,
  }));
  assertEquals(
    copy.body,
    "New games from Hikaru on Chess.com and DrNykterstein on Lichess. 2 more of your players played too. Tap to see.",
  );
});

Deno.test("says how many games, one or many", () => {
  assertEquals(
    prepGamesAddedCopy(push({ games: 1 })).title,
    "GM Vasif Durarbayli played 1 game this afternoon",
  );
  assertEquals(
    prepGamesAddedCopy(push({ games: 1, slot: 2 })).title,
    "GM Vasif Durarbayli is still playing: 1 more game",
  );
  const copy = prepGamesAddedCopy(push({ otherPlayers: 1 }));
  assertEquals(
    copy.body,
    "New games from durarbayli on Lichess. Another of your players played too. Tap to see.",
  );
});

Deno.test("no title, or a name that already carries it, is not doubled", () => {
  assertEquals(
    prepGamesAddedCopy(push({ profileTitle: null })).title,
    "Vasif Durarbayli played 7 games this afternoon",
  );
  assertEquals(
    prepGamesAddedCopy(push({ profileName: "GM Vasif Durarbayli" })).title,
    "GM Vasif Durarbayli played 7 games this afternoon",
  );
});

Deno.test("the payload is read defensively", () => {
  const read = prepGamesPushFromPayload({
    profile_name: "Vasif Durarbayli",
    profile_title: "GM",
    accounts: [{ source: "lichess", username: "durarbayli" }, { bad: 1 }, null],
    slot: "2",
    local_hour: 30,
    added: "12",
  });
  assertEquals(read.accounts, [{ source: "lichess", username: "durarbayli" }]);
  assertEquals(read.slot, 2);
  assertEquals(read.games, 12);
  assertEquals(read.localHour, 23);
  assertEquals(read.otherPlayers, 0);
});
