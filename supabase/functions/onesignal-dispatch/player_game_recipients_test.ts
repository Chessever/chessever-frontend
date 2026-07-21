/**
 * Favorite-player game_started deliverability + prefs.
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/player_game_recipients_test.ts
 */
import {
  assertEquals,
  assert,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  filterGameStartedPlayerRecipients,
  playerAllowedForGameNotification,
  shouldReceiveGameStartedForPlayerFavorite,
} from "./player_game_recipients.ts";

Deno.test("single-favorite user is kept for game_started (Scenario A)", () => {
  assertEquals(
    shouldReceiveGameStartedForPlayerFavorite(1, false),
    true,
  );
});

Deno.test(
  "map-miss (count 0) still keeps user — they matched playerUserIds for this game",
  () => {
    // Regression: old code used favCount !== 1 and deleted these users.
    assertEquals(
      shouldReceiveGameStartedForPlayerFavorite(0, false),
      true,
    );
  },
);

Deno.test("multi-favorite in round is suppressed (Scenarios B/C)", () => {
  assertEquals(
    shouldReceiveGameStartedForPlayerFavorite(2, false),
    false,
  );
  assertEquals(
    shouldReceiveGameStartedForPlayerFavorite(5, false),
    false,
  );
});

Deno.test("active game-start window suppresses even single-favorite", () => {
  assertEquals(
    shouldReceiveGameStartedForPlayerFavorite(1, true),
    false,
  );
  assertEquals(
    shouldReceiveGameStartedForPlayerFavorite(0, true),
    false,
  );
});

Deno.test("filterGameStartedPlayerRecipients keeps allow-set, tags skips", () => {
  const map = new Map<string, string[]>([
    ["u-single", ["Carlsen, Magnus"]],
    ["u-multi", ["Carlsen, Magnus", "Nakamura, Hikaru"]],
    // u-miss intentionally absent from map → count 0
  ]);
  const covered = new Set(["u-window"]);
  const { keep, skippedMultiFavorite, skippedWindow } =
    filterGameStartedPlayerRecipients(
      ["u-single", "u-multi", "u-miss", "u-window"],
      map,
      covered,
    );

  assert(keep.has("u-single"), "single favorite must receive");
  assert(keep.has("u-miss"), "map-miss player-fav must still receive");
  assert(!keep.has("u-multi"), "multi-fav must not get per-game push");
  assert(!keep.has("u-window"), "window-covered must not receive");
  assertEquals(skippedMultiFavorite, ["u-multi"]);
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
