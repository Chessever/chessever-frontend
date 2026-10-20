/**
 * Favorite-player game_started deliverability + prefs.
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/player_game_recipients_test.ts
 */
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  coveredBoardsByUser,
  filterGameStartedPlayerRecipients,
  GAME_START_WINDOW_PREFIX,
  gameIdFromWindowFamily,
  gameStartWindowFamily,
  playerAllowedForGameNotification,
  shouldReceiveGameStartedForPlayerFavorite,
  usersCoveredForBoard,
} from "./player_game_recipients.ts";

Deno.test("single-favorite user is kept for game_started (Scenario A)", () => {
  assertEquals(
    shouldReceiveGameStartedForPlayerFavorite(false),
    true,
  );
});

Deno.test(
  "map-miss (count 0) still keeps user — they matched playerUserIds for this game",
  () => {
    // Regression: old code used favCount !== 1 and deleted these users.
    assertEquals(
      shouldReceiveGameStartedForPlayerFavorite(false),
      true,
    );
  },
);

Deno.test(
  "uncovered user receives game_started fallback when combined round start was not sent",
  () => {
    assertEquals(
      shouldReceiveGameStartedForPlayerFavorite(false),
      true,
    );
  },
);

Deno.test("confirmed round-start window suppresses multi-favorite fallback", () => {
  assertEquals(
    shouldReceiveGameStartedForPlayerFavorite(true),
    false,
  );
});

Deno.test("active game-start window suppresses even single-favorite", () => {
  assertEquals(
    shouldReceiveGameStartedForPlayerFavorite(true),
    false,
  );
  assertEquals(
    shouldReceiveGameStartedForPlayerFavorite(true),
    false,
  );
});

Deno.test("filterGameStartedPlayerRecipients keeps uncovered users", () => {
  const covered = new Set(["u-window"]);
  const { keep, skippedWindow } = filterGameStartedPlayerRecipients(
    ["u-first-fallback", "u-map-miss", "u-window"],
    covered,
  );

  assert(
    keep.has("u-first-fallback"),
    "uncovered favorite-player user must receive one fallback",
  );
  assert(keep.has("u-map-miss"), "map-miss player-fav must still receive");
  assert(!keep.has("u-window"), "window-covered must not receive");
  assertEquals(skippedWindow, ["u-window"]);
  assertEquals(keep.size, 2);
});

Deno.test("prefs: favorite_player_alerts=false excludes", () => {
  assertEquals(
    playerAllowedForGameNotification(
      { favorite_player_alerts: false },
      true,
      "classical",
    ),
    false,
  );
});

Deno.test("prefs: push_enabled=false excludes", () => {
  assertEquals(
    playerAllowedForGameNotification(
      { push_enabled: false, favorite_player_alerts: true },
      true,
      "classical",
    ),
    false,
  );
});

Deno.test("prefs: fp_blitz=false excludes blitz game", () => {
  assertEquals(
    playerAllowedForGameNotification(
      {
        push_enabled: true,
        favorite_player_alerts: true,
        fp_blitz: false,
        fp_classical: true,
      },
      true,
      "blitz",
    ),
    false,
  );
  assertEquals(
    playerAllowedForGameNotification(
      {
        push_enabled: true,
        favorite_player_alerts: true,
        fp_blitz: false,
        fp_classical: true,
      },
      true,
      "classical",
    ),
    true,
  );
});

Deno.test("prefs: fail-open when no row", () => {
  assertEquals(
    playerAllowedForGameNotification(null, true, "classical"),
    true,
  );
  assertEquals(
    playerAllowedForGameNotification(undefined, true, null),
    true,
  );
});

Deno.test("prefs: non-player-fav never allowed for game_started path", () => {
  assertEquals(
    playerAllowedForGameNotification(
      { favorite_player_alerts: true },
      false,
      "classical",
    ),
    false,
  );
});

// European Club Cup 2026 R3: a reader favoriting Mamedyarov AND Suleymanli
// got Mamedyarov's board, and the round-wide window then swallowed
// Suleymanli's. Windows are per board now.
Deno.test("start windows: one board alert never covers another board", () => {
  const covered = coveredBoardsByUser([
    { user_id: "vasif", family: gameStartWindowFamily("jpCIz8lJ") },
  ]);

  assertEquals(usersCoveredForBoard(covered, "jpCIz8lJ"), new Set(["vasif"]));
  assertEquals(usersCoveredForBoard(covered, "VjCkBH77"), new Set());

  const { keep } = filterGameStartedPlayerRecipients(
    ["vasif", "other"],
    usersCoveredForBoard(covered, "VjCkBH77"),
  );
  assertEquals(keep, new Set(["vasif", "other"]));
});

Deno.test("start windows: the same board is announced once", () => {
  const covered = coveredBoardsByUser([
    { user_id: "a", family: gameStartWindowFamily("g1") },
    { user_id: "a", family: gameStartWindowFamily("g2") },
    { user_id: "b", family: gameStartWindowFamily("g2") },
  ]);

  assertEquals(covered.get("a"), new Set(["g1", "g2"]));
  const { keep, skippedWindow } = filterGameStartedPlayerRecipients(
    ["a", "b", "c"],
    usersCoveredForBoard(covered, "g2"),
  );
  assertEquals(keep, new Set(["c"]));
  assertEquals(skippedWindow, ["a", "b"]);
});

Deno.test("start windows: old round-wide rows cover no board", () => {
  const covered = coveredBoardsByUser([
    { user_id: "a", family: "game_start" },
    { user_id: "b", family: GAME_START_WINDOW_PREFIX },
  ]);

  assertEquals(covered.size, 0);
  assertEquals(gameIdFromWindowFamily("game_start"), null);
  assertEquals(gameIdFromWindowFamily(gameStartWindowFamily("g1")), "g1");
});
