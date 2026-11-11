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
    earlierToday: 0,
    otherPlayers: 0,
    profileKind: null,
    ...overrides,
  };
}

Deno.test("leads with the player and the count", () => {
  assertEquals(prepGamesAddedCopy(push({})), {
    title: "GM Vasif Durarbayli played 7 games today!",
    body: "Fresh from durarbayli on Lichess. Tap to see all 7.",
  });
});

Deno.test("a later push the same day says more, and the day's total", () => {
  assertEquals(
    prepGamesAddedCopy(push({
      profileName: "Magnus Carlsen",
      games: 12,
      earlierToday: 9,
      accounts: [{ source: "lichess", username: "DrNykterstein" }],
    })),
    {
      title: "GM Magnus Carlsen played 12 more games today!",
      body:
        "Fresh from DrNykterstein on Lichess. That's 21 today. Tap to see all 12.",
    },
  );
});

Deno.test("a different player's earlier push is not 'more'", () => {
  // earlierToday counts this player only: another player's push leaves it 0.
  assertEquals(
    prepGamesAddedCopy(push({ earlierToday: 0 })).title,
    "GM Vasif Durarbayli played 7 games today!",
  );
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
    "Fresh from Hikaru on Chess.com and DrNykterstein on Lichess. 2 more of your players are playing too. Tap to see all 7.",
  );
});

Deno.test("says how many games, one or many", () => {
  assertEquals(
    prepGamesAddedCopy(push({ games: 1 })),
    {
      title: "GM Vasif Durarbayli played 1 game today!",
      body: "Fresh from durarbayli on Lichess. Tap to see it.",
    },
  );
  assertEquals(
    prepGamesAddedCopy(push({ games: 1, earlierToday: 4 })).title,
    "GM Vasif Durarbayli played 1 more game today!",
  );
  assertEquals(
    prepGamesAddedCopy(push({ otherPlayers: 1 })).body,
    "Fresh from durarbayli on Lichess. Another of your players is playing too. Tap to see all 7.",
  );
});

Deno.test("no title, or a name that already carries it, is not doubled", () => {
  assertEquals(
    prepGamesAddedCopy(push({ profileTitle: null })).title,
    "Vasif Durarbayli played 7 games today!",
  );
  assertEquals(
    prepGamesAddedCopy(push({ profileName: "GM Vasif Durarbayli" })).title,
    "GM Vasif Durarbayli played 7 games today!",
  );
});

Deno.test("no named account still reads", () => {
  assertEquals(
    prepGamesAddedCopy(push({ accounts: [] })).body,
    "Fresh games are in. Tap to see all 7.",
  );
});

Deno.test("the payload is read defensively", () => {
  const read = prepGamesPushFromPayload({
    profile_name: "Vasif Durarbayli",
    profile_title: "GM",
    accounts: [{ source: "lichess", username: "durarbayli" }, { bad: 1 }, null],
    earlier_today: "5",
    added: "12",
  });
  assertEquals(read.accounts, [{ source: "lichess", username: "durarbayli" }]);
  assertEquals(read.earlierToday, 5);
  assertEquals(read.games, 12);
  assertEquals(read.otherPlayers, 0);
  // Rows queued before earlier_today existed read as a first push.
  assertEquals(prepGamesPushFromPayload({ slot: 2 }).earlierToday, 0);
});

Deno.test("the reader's own profile speaks to them, never about them", () => {
  const own = push({
    profileKind: "mine",
    profileName: "Berkay",
    profileTitle: null,
    games: 7,
    accounts: [
      { source: "lichess", username: "berkay" },
      { source: "chesscom", username: "berkay" },
    ],
  });
  assertEquals(prepGamesAddedCopy(own), {
    title: "7 new games of yours. Spot the leak?",
    body:
      "They're all in Prep on Lichess and Chess.com. Tap to see the opening you keep reaching, and how it's really going.",
  });
});

Deno.test("the reader's one new game", () => {
  assertEquals(
    prepGamesAddedCopy(push({ profileKind: "mine", games: 1 })),
    {
      title: "Your new game is in. Where did it turn?",
      body:
        "It's waiting in Prep, next to every game you've played on Lichess. Tap to find the move that decided it.",
    },
  );
});

Deno.test("the reader's later push gives the day's total", () => {
  assertEquals(
    prepGamesAddedCopy(
      push({ profileKind: "mine", games: 4, earlierToday: 6, otherPlayers: 2 }),
    ),
    {
      title: "10 games today. Still the same opening?",
      body:
        "4 more on Lichess just landed in Prep. 2 of your players are at it too. Tap to see which lines held up and which keep costing you.",
    },
  );
});

Deno.test("profile_kind is read from the payload", () => {
  assertEquals(
    prepGamesPushFromPayload({ profile_kind: "mine" }).profileKind,
    "mine",
  );
  assertEquals(prepGamesPushFromPayload({}).profileKind, null);
});
