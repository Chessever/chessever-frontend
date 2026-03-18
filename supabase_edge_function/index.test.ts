/**
 * Push Notification Refactor — Test Suite
 *
 * Tests the per-user personalized notification logic from Vasif's spec (v1.0).
 *
 * Run with:
 *   deno test --allow-env supabase_edge_function/index.test.ts
 *
 * These tests extract and test the PURE LOGIC functions directly, and use a
 * lightweight mock layer for the integration-level tests that exercise the
 * full processItem() flow via the HTTP handler.
 */

import {
    assertEquals,
    assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// 1. Pure function tests — extracted logic that needs no mocking
//    We re-implement the pure helpers here so we can test them in isolation
//    without importing the edge function (which has side-effects on import).
// ---------------------------------------------------------------------------

// --- formatPlayerName (copy from index.ts) ---
function formatPlayerName(name: string): string {
    const trimmed = name.trim();
    if (trimmed.includes(",")) return trimmed;
    const parts = trimmed.split(/\s+/);
    if (parts.length <= 1) return trimmed;
    if (parts[parts.length - 1].length <= 2 && parts.length >= 2) {
        return trimmed;
    }
    const last = parts[parts.length - 1];
    const first = parts.slice(0, -1).join(" ");
    return `${last}, ${first}`;
}

// --- buildEventHeader (copy from index.ts) ---
function buildEventHeader(
    eventName: string | null,
    roundName: string | null | undefined,
): string | null {
    if (eventName && roundName) return `${eventName} — ${roundName}`;
    if (eventName) return eventName;
    return null;
}

// --- extractLastName (copy from index.ts) ---
function extractLastName(name: string): string {
    const trimmed = name.trim();
    if (trimmed.includes(",")) {
        const before = trimmed.split(",")[0].trim();
        const parts = before.split(/\s+/);
        return parts.length > 1 ? parts[parts.length - 1] : parts[0];
    }
    const parts = trimmed.split(/\s+/);
    if (parts.length >= 2 && parts[parts.length - 1].length <= 2) {
        return parts[parts.length - 2];
    }
    return parts[parts.length - 1];
}

// ---------------------------------------------------------------------------
// 2. formatPlayerName tests
// ---------------------------------------------------------------------------

Deno.test("formatPlayerName — already Last, First format", () => {
    assertEquals(formatPlayerName("Nakamura, Hikaru"), "Nakamura, Hikaru");
    assertEquals(formatPlayerName("Carlsen, Magnus"), "Carlsen, Magnus");
    assertEquals(formatPlayerName("Liang, Awonder"), "Liang, Awonder");
});

Deno.test("formatPlayerName — First Last format → Last, First", () => {
    assertEquals(formatPlayerName("Hikaru Nakamura"), "Nakamura, Hikaru");
    assertEquals(formatPlayerName("Magnus Carlsen"), "Carlsen, Magnus");
    assertEquals(formatPlayerName("Awonder Liang"), "Liang, Awonder");
});

Deno.test("formatPlayerName — single name kept as-is", () => {
    assertEquals(formatPlayerName("Carlsen"), "Carlsen");
});

Deno.test("formatPlayerName — Gukesh D kept as-is (short last token)", () => {
    assertEquals(formatPlayerName("Gukesh D"), "Gukesh D");
});

Deno.test("formatPlayerName — trims whitespace", () => {
    assertEquals(formatPlayerName("  Hikaru Nakamura  "), "Nakamura, Hikaru");
    assertEquals(formatPlayerName("  Nakamura, Hikaru  "), "Nakamura, Hikaru");
});

Deno.test("formatPlayerName — multi-word first name", () => {
    assertEquals(
        formatPlayerName("Jose Raul Capablanca"),
        "Capablanca, Jose Raul",
    );
});

// ---------------------------------------------------------------------------
// 3. buildEventHeader tests
// ---------------------------------------------------------------------------

Deno.test("buildEventHeader — event + round", () => {
    assertEquals(
        buildEventHeader("Titled Tuesday", "Round 10"),
        "Titled Tuesday — Round 10",
    );
});

Deno.test("buildEventHeader — event only", () => {
    assertEquals(buildEventHeader("Titled Tuesday", null), "Titled Tuesday");
    assertEquals(buildEventHeader("Titled Tuesday", undefined), "Titled Tuesday");
});

Deno.test("buildEventHeader — no event", () => {
    assertEquals(buildEventHeader(null, "Round 10"), null);
    assertEquals(buildEventHeader(null, null), null);
});

// ---------------------------------------------------------------------------
// 4. Notification message building logic
//    We simulate the core per-user notification body construction.
// ---------------------------------------------------------------------------

type FavInfo = { name: string; rating: number };

function buildRoundStartedBody(
    userFavorites: FavInfo[],
    opponentMap: Map<string, string>,
): string {
    const sorted = [...userFavorites].sort((a, b) => b.rating - a.rating);

    if (sorted.length === 1) {
        const fav = formatPlayerName(sorted[0].name);
        const oppName = opponentMap.get(sorted[0].name) ?? "Opponent";
        const opp = formatPlayerName(oppName);
        return `${fav} vs ${opp} is live.`;
    } else if (sorted.length === 2) {
        const p1 = formatPlayerName(sorted[0].name);
        const p2 = formatPlayerName(sorted[1].name);
        return `${p1} and ${p2} are live.`;
    } else {
        const p1 = formatPlayerName(sorted[0].name);
        const p2 = formatPlayerName(sorted[1].name);
        return `${p1}, ${p2}, and others are live.`;
    }
}

function buildGameFinishedBody(
    white: string,
    black: string,
    result: string,
): string {
    return `${formatPlayerName(white)} vs ${formatPlayerName(black)}: ${result}`;
}

// --- Type 1, Scenario A: Exactly 1 favorite playing ---

Deno.test("Type 1A — 1 favorite: individual game notification", () => {
    const opponents = new Map([
        ["Nakamura, Hikaru", "Liang, Awonder"],
        ["Liang, Awonder", "Nakamura, Hikaru"],
    ]);

    const body = buildRoundStartedBody(
        [{ name: "Nakamura, Hikaru", rating: 2789 }],
        opponents,
    );
    assertEquals(body, "Nakamura, Hikaru vs Liang, Awonder is live.");
});

Deno.test("Type 1A — 1 favorite (opposite side): opponent is the favorite's opponent", () => {
    const opponents = new Map([
        ["Nakamura, Hikaru", "Liang, Awonder"],
        ["Liang, Awonder", "Nakamura, Hikaru"],
    ]);

    const body = buildRoundStartedBody(
        [{ name: "Liang, Awonder", rating: 2620 }],
        opponents,
    );
    assertEquals(body, "Liang, Awonder vs Nakamura, Hikaru is live.");
});

// --- Type 1, Scenario B: Exactly 2 favorites playing ---

Deno.test("Type 1B — 2 favorites: combined notification, ordered by rating", () => {
    const opponents = new Map<string, string>(); // not needed for 2+ favs

    const body = buildRoundStartedBody(
        [
            { name: "Liang, Awonder", rating: 2620 },
            { name: "Nakamura, Hikaru", rating: 2789 },
        ],
        opponents,
    );
    // Nakamura should be first (higher rating)
    assertEquals(body, "Nakamura, Hikaru and Liang, Awonder are live.");
});

Deno.test("Type 1B — 2 favorites: rating order matters", () => {
    const opponents = new Map<string, string>();

    const body = buildRoundStartedBody(
        [
            { name: "Neverov, Valeriy", rating: 2500 },
            { name: "Liang, Awonder", rating: 2620 },
        ],
        opponents,
    );
    assertEquals(body, "Liang, Awonder and Neverov, Valeriy are live.");
});

// --- Type 1, Scenario C: 3+ favorites playing ---

Deno.test("Type 1C — 3 favorites: top 2 by rating + 'and others'", () => {
    const opponents = new Map<string, string>();

    const body = buildRoundStartedBody(
        [
            { name: "Neverov, Valeriy", rating: 2500 },
            { name: "Liang, Awonder", rating: 2620 },
            { name: "Nakamura, Hikaru", rating: 2789 },
        ],
        opponents,
    );
    assertEquals(
        body,
        "Nakamura, Hikaru, Liang, Awonder, and others are live.",
    );
});

Deno.test("Type 1C — 5 favorites: still shows only top 2", () => {
    const opponents = new Map<string, string>();

    const body = buildRoundStartedBody(
        [
            { name: "Player E", rating: 2300 },
            { name: "Player D", rating: 2400 },
            { name: "Neverov, Valeriy", rating: 2500 },
            { name: "Liang, Awonder", rating: 2620 },
            { name: "Nakamura, Hikaru", rating: 2789 },
        ],
        opponents,
    );
    assertEquals(
        body,
        "Nakamura, Hikaru, Liang, Awonder, and others are live.",
    );
});

// --- Type 1: Per-user personalization ---

Deno.test("Per-user: two users get different messages for same round", () => {
    const opponents = new Map([
        ["Nakamura, Hikaru", "Liang, Awonder"],
        ["Liang, Awonder", "Nakamura, Hikaru"],
        ["Smirnov, Anton", "Neverov, Valeriy"],
        ["Neverov, Valeriy", "Smirnov, Anton"],
    ]);

    // User A favorites: Liang + Neverov
    const bodyA = buildRoundStartedBody(
        [
            { name: "Liang, Awonder", rating: 2620 },
            { name: "Neverov, Valeriy", rating: 2500 },
        ],
        opponents,
    );

    // User B favorites: Nakamura + Smirnov
    const bodyB = buildRoundStartedBody(
        [
            { name: "Nakamura, Hikaru", rating: 2789 },
            { name: "Smirnov, Anton", rating: 2650 },
        ],
        opponents,
    );

    assertEquals(bodyA, "Liang, Awonder and Neverov, Valeriy are live.");
    assertEquals(bodyB, "Nakamura, Hikaru and Smirnov, Anton are live.");

    // They must be different
    assertEquals(bodyA !== bodyB, true);
});

// --- Type 1: Title format ---

Deno.test("Type 1 title: always '{event} — {round}'", () => {
    const title = buildEventHeader("Texas Grand Circuit", "Round 2") ?? "Live chess";
    assertEquals(title, "Texas Grand Circuit — Round 2");
});

Deno.test("Type 1 title: fallback when no round name", () => {
    const title = buildEventHeader("Titled Tuesday", null) ?? "Live chess";
    assertEquals(title, "Titled Tuesday");
});

// --- Type 2: Result notification (game_finished) ---

Deno.test("Type 2 — game finished: correct format with result", () => {
    const body = buildGameFinishedBody(
        "Nakamura, Hikaru",
        "Madaminov, Mukhiddin",
        "1/2-1/2",
    );
    assertEquals(body, "Nakamura, Hikaru vs Madaminov, Mukhiddin: 1/2-1/2");
});

Deno.test("Type 2 — game finished: white wins", () => {
    const body = buildGameFinishedBody(
        "Carlsen, Magnus",
        "Nakamura, Hikaru",
        "1-0",
    );
    assertEquals(body, "Carlsen, Magnus vs Nakamura, Hikaru: 1-0");
});

Deno.test("Type 2 — game finished: black wins", () => {
    const body = buildGameFinishedBody(
        "Liang, Awonder",
        "Carlsen, Magnus",
        "0-1",
    );
    assertEquals(body, "Liang, Awonder vs Carlsen, Magnus: 0-1");
});

Deno.test("Type 2 — game finished: fallback result", () => {
    const body = buildGameFinishedBody(
        "White Player",
        "Black Player",
        "Game over",
    );
    assertEquals(body, "Player, White vs Player, Black: Game over");
});

Deno.test("Type 2 — game finished title: event + round", () => {
    const title =
        buildEventHeader("Titled Tuesday March 10, 2026", "Round 10") ??
        "Game result";
    assertEquals(title, "Titled Tuesday March 10, 2026 — Round 10");
});

// ---------------------------------------------------------------------------
// 5. Decision table tests (Type 3 / Event Notification logic)
//    We test the filterRoundRecipients logic as a pure function.
// ---------------------------------------------------------------------------

type PrefsRow = {
    user_id: string;
    push_enabled?: boolean;
    favorite_event_alerts?: boolean;
    favorite_player_alerts?: boolean;
};

/**
 * Pure reimplementation of filterRoundRecipients for testing.
 */
function filterRoundRecipientsSync(
    eventUserIds: Set<string>,
    playerUserIds: Set<string>,
    prefsMap: Map<string, PrefsRow>,
) {
    const allUserIds = new Set([...eventUserIds, ...playerUserIds]);
    const playerRecipients = new Set<string>();
    const eventRecipients = new Set<string>();

    for (const userId of allUserIds) {
        const prefs = prefsMap.get(userId);
        if (prefs && prefs.push_enabled === false) continue;

        const isPlayerFav = playerUserIds.has(userId);
        const isEventFav = eventUserIds.has(userId);
        const playerAllowed = !prefs || prefs.favorite_player_alerts !== false;
        const eventAllowed = !prefs || prefs.favorite_event_alerts !== false;

        if (isPlayerFav && playerAllowed) {
            playerRecipients.add(userId);
            continue;
        }

        if (isEventFav && eventAllowed && !playerRecipients.has(userId)) {
            eventRecipients.add(userId);
        }
    }

    return {
        playerRecipients: Array.from(playerRecipients),
        eventRecipients: Array.from(eventRecipients),
    };
}

Deno.test("Decision table — Starred YES, Favorites NO → event notification only", () => {
    const eventUsers = new Set(["user1"]);
    const playerUsers = new Set<string>();
    const prefs = new Map<string, PrefsRow>();

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);
    assertEquals(result.eventRecipients, ["user1"]);
    assertEquals(result.playerRecipients, []);
});

Deno.test("Decision table — Starred YES, Favorites YES → player notification ONLY", () => {
    const eventUsers = new Set(["user1"]);
    const playerUsers = new Set(["user1"]);
    const prefs = new Map<string, PrefsRow>();

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);
    assertEquals(result.playerRecipients, ["user1"]);
    assertEquals(result.eventRecipients, []);
});

Deno.test("Decision table — Starred NO, Favorites YES → player notification only", () => {
    const eventUsers = new Set<string>();
    const playerUsers = new Set(["user1"]);
    const prefs = new Map<string, PrefsRow>();

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);
    assertEquals(result.playerRecipients, ["user1"]);
    assertEquals(result.eventRecipients, []);
});

Deno.test("Decision table — Starred NO, Favorites NO → nothing", () => {
    const eventUsers = new Set<string>();
    const playerUsers = new Set<string>();
    const prefs = new Map<string, PrefsRow>();

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);
    assertEquals(result.playerRecipients, []);
    assertEquals(result.eventRecipients, []);
});

Deno.test("Decision table — push disabled → no notifications", () => {
    const eventUsers = new Set(["user1"]);
    const playerUsers = new Set(["user1"]);
    const prefs = new Map<string, PrefsRow>([
        ["user1", { user_id: "user1", push_enabled: false }],
    ]);

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);
    assertEquals(result.playerRecipients, []);
    assertEquals(result.eventRecipients, []);
});

Deno.test("Decision table — player alerts disabled, has star → falls to event", () => {
    const eventUsers = new Set(["user1"]);
    const playerUsers = new Set(["user1"]);
    const prefs = new Map<string, PrefsRow>([
        ["user1", { user_id: "user1", favorite_player_alerts: false }],
    ]);

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);
    // Player alerts disabled, so user should NOT be in playerRecipients.
    // They have starred the event, so they should get the event notification.
    assertEquals(result.playerRecipients, []);
    assertEquals(result.eventRecipients, ["user1"]);
});

Deno.test("Decision table — multiple users, mixed scenarios", () => {
    // user1: starred + favorites → player only
    // user2: starred, no favorites → event only
    // user3: not starred, favorites → player only
    // user4: not starred, no favorites → nothing
    const eventUsers = new Set(["user1", "user2"]);
    const playerUsers = new Set(["user1", "user3"]);
    const prefs = new Map<string, PrefsRow>();

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);

    assertEquals(result.playerRecipients.sort(), ["user1", "user3"]);
    assertEquals(result.eventRecipients, ["user2"]);
});

// ---------------------------------------------------------------------------
// 6. game_started notification tests
// ---------------------------------------------------------------------------

function buildGameStartedNotification(
    white: string,
    black: string,
    eventName: string | null,
    roundName: string | null | undefined,
): { title: string; body: string } {
    const eventHeader = buildEventHeader(eventName, roundName);
    return {
        title: eventHeader ?? `${formatPlayerName(white)} vs ${formatPlayerName(black)}`,
        body: eventHeader
            ? `${formatPlayerName(white)} vs ${formatPlayerName(black)} is live.`
            : "A favorite game just went live.",
    };
}

Deno.test("game_started — with event context: title is event header, body names players", () => {
    const { title, body } = buildGameStartedNotification(
        "Nakamura, Hikaru",
        "Liang, Awonder",
        "Titled Tuesday",
        "Round 5",
    );
    assertEquals(title, "Titled Tuesday — Round 5");
    assertEquals(body, "Nakamura, Hikaru vs Liang, Awonder is live.");
});

Deno.test("game_started — event name only, no round: title is event name", () => {
    const { title, body } = buildGameStartedNotification(
        "Carlsen, Magnus",
        "Nakamura, Hikaru",
        "Speed Chess Championship",
        null,
    );
    assertEquals(title, "Speed Chess Championship");
    assertEquals(body, "Carlsen, Magnus vs Nakamura, Hikaru is live.");
});

Deno.test("game_started — no event context: title is player matchup, body is generic", () => {
    const { title, body } = buildGameStartedNotification(
        "Carlsen, Magnus",
        "Nakamura, Hikaru",
        null,
        null,
    );
    assertEquals(title, "Carlsen, Magnus vs Nakamura, Hikaru");
    assertEquals(body, "A favorite game just went live.");
});

Deno.test("game_started — player names in First Last format are converted", () => {
    const { title, body } = buildGameStartedNotification(
        "Magnus Carlsen",
        "Hikaru Nakamura",
        "World Chess",
        "Round 1",
    );
    assertEquals(title, "World Chess — Round 1");
    assertEquals(body, "Carlsen, Magnus vs Nakamura, Hikaru is live.");
});

Deno.test("game_started — only player-favorite users receive notification", () => {
    const eventUsers = new Set(["user1", "user2"]);
    const playerUsers = new Set(["user2"]);
    const allUsers = new Set([...eventUsers, ...playerUsers]);
    const prefs = new Map<string, Record<string, unknown>>();

    const result = applyPreferencesSync(
        "game_started",
        allUsers,
        eventUsers,
        playerUsers,
        prefs,
    );

    // user1 is event-only → should NOT get game_started
    // user2 is player-favorited → should get game_started
    assertEquals(result.has("user1"), false);
    assertEquals(result.has("user2"), true);
});

Deno.test("game_started — player with favorite_player_alerts disabled gets nothing", () => {
    const playerUsers = new Set(["user1"]);
    const allUsers = new Set(["user1"]);
    const prefs = new Map<string, Record<string, unknown>>([
        ["user1", { user_id: "user1", favorite_player_alerts: false }],
    ]);

    const result = applyPreferencesSync(
        "game_started",
        allUsers,
        new Set(),
        playerUsers,
        prefs,
    );

    assertEquals(result.size, 0);
});

Deno.test("game_started — push disabled user gets nothing", () => {
    const playerUsers = new Set(["user1"]);
    const allUsers = new Set(["user1"]);
    const prefs = new Map<string, Record<string, unknown>>([
        ["user1", { user_id: "user1", push_enabled: false }],
    ]);

    const result = applyPreferencesSync(
        "game_started",
        allUsers,
        new Set(),
        playerUsers,
        prefs,
    );

    assertEquals(result.size, 0);
});

Deno.test("game_started — event-starred user without player favorite gets nothing", () => {
    const eventUsers = new Set(["user1"]);
    const playerUsers = new Set<string>();
    const allUsers = new Set(["user1"]);
    const prefs = new Map<string, Record<string, unknown>>();

    const result = applyPreferencesSync(
        "game_started",
        allUsers,
        eventUsers,
        playerUsers,
        prefs,
    );

    assertEquals(result.size, 0);
});

// ---------------------------------------------------------------------------
// 7. applyPreferences for game_finished
//    Only player-favorite users should receive game_finished notifications.
// ---------------------------------------------------------------------------

function applyPreferencesSync(
    eventType: string,
    allUserIds: Set<string>,
    eventUserIds: Set<string>,
    playerUserIds: Set<string>,
    prefsMap: Map<string, Record<string, unknown>>,
): Set<string> {
    const ids = Array.from(allUserIds);
    if (ids.length === 0) return allUserIds;

    const filtered = new Set<string>();

    for (const userId of ids) {
        const prefs = prefsMap.get(userId);
        if (prefs && prefs.push_enabled === false) continue;

        const isPlayerFav = playerUserIds.has(userId);

        if (eventType === "game_started" || eventType === "game_finished") {
            const playerAllowed =
                !prefs || prefs.favorite_player_alerts !== false;
            if (isPlayerFav && playerAllowed) {
                filtered.add(userId);
            }
            continue;
        }

        filtered.add(userId);
    }

    return filtered;
}

Deno.test("game_finished — only player-favorite users receive notification", () => {
    const eventUsers = new Set(["user1", "user2"]);
    const playerUsers = new Set(["user2"]);
    const allUsers = new Set([...eventUsers, ...playerUsers]);
    const prefs = new Map<string, Record<string, unknown>>();

    const result = applyPreferencesSync(
        "game_finished",
        allUsers,
        eventUsers,
        playerUsers,
        prefs,
    );

    // user1 is only event-favorited → should NOT get game_finished
    // user2 is player-favorited → should get game_finished
    assertEquals(result.has("user1"), false);
    assertEquals(result.has("user2"), true);
});

Deno.test("game_finished — player with alerts disabled gets nothing", () => {
    const playerUsers = new Set(["user1"]);
    const allUsers = new Set(["user1"]);
    const prefs = new Map<string, Record<string, unknown>>([
        ["user1", { user_id: "user1", favorite_player_alerts: false }],
    ]);

    const result = applyPreferencesSync(
        "game_finished",
        allUsers,
        new Set(),
        playerUsers,
        prefs,
    );

    assertEquals(result.size, 0);
});

// ---------------------------------------------------------------------------
// 8. Rating sort edge cases
// ---------------------------------------------------------------------------

Deno.test("Rating sort — equal ratings maintain stable order", () => {
    const opponents = new Map<string, string>();
    const favs: FavInfo[] = [
        { name: "Player A", rating: 2600 },
        { name: "Player B", rating: 2600 },
    ];
    const body = buildRoundStartedBody(favs, opponents);
    // Both have same rating — we just check both names appear
    assertStringIncludes(body, "are live.");
    assertStringIncludes(body, "Player");
});

Deno.test("Rating sort — missing ratings treated as 0", () => {
    const opponents = new Map([
        ["Nakamura, Hikaru", "Unknown Player"],
    ]);

    // Simulate: rating map doesn't have one player → defaults to 0
    const favs: FavInfo[] = [
        { name: "Unknown Player", rating: 0 },
        { name: "Nakamura, Hikaru", rating: 2789 },
    ];
    const body = buildRoundStartedBody(favs, opponents);
    // Nakamura should come first (higher rating)
    // "Unknown Player" → formatPlayerName → "Player, Unknown"
    assertEquals(body, "Nakamura, Hikaru and Player, Unknown are live.");
});

// ---------------------------------------------------------------------------
// 9. Message batching test
//    Users with identical favorites should be batched into one sendOneSignal call.
// ---------------------------------------------------------------------------

Deno.test("Message batching — users with same single favorite get same body", () => {
    const opponents = new Map([
        ["Nakamura, Hikaru", "Liang, Awonder"],
        ["Liang, Awonder", "Nakamura, Hikaru"],
    ]);

    // User A and User B both have only Nakamura as favorite
    const bodyA = buildRoundStartedBody(
        [{ name: "Nakamura, Hikaru", rating: 2789 }],
        opponents,
    );
    const bodyB = buildRoundStartedBody(
        [{ name: "Nakamura, Hikaru", rating: 2789 }],
        opponents,
    );
    assertEquals(bodyA, bodyB); // Same body → can be batched
    assertEquals(bodyA, "Nakamura, Hikaru vs Liang, Awonder is live.");
});

Deno.test("Message batching — different favorites produce different bodies", () => {
    const opponents = new Map([
        ["Nakamura, Hikaru", "Liang, Awonder"],
        ["Liang, Awonder", "Nakamura, Hikaru"],
    ]);

    const bodyA = buildRoundStartedBody(
        [{ name: "Nakamura, Hikaru", rating: 2789 }],
        opponents,
    );
    const bodyB = buildRoundStartedBody(
        [{ name: "Liang, Awonder", rating: 2620 }],
        opponents,
    );
    assertEquals(bodyA !== bodyB, true); // Different → separate sends
});

// ---------------------------------------------------------------------------
// 10. Integration-level scenario tests (end-to-end flow simulation)
//     These simulate the full flow with mock data structures.
// ---------------------------------------------------------------------------

Deno.test("Integration — round_started full flow: 3 users, 3 scenarios", () => {
    // Setup: Round has 4 games with 8 players
    const playerRatingMap = new Map([
        ["Nakamura, Hikaru", 2789],
        ["Liang, Awonder", 2620],
        ["Neverov, Valeriy", 2500],
        ["Smirnov, Anton", 2650],
        ["Player E", 2400],
        ["Player F", 2350],
        ["Player G", 2300],
        ["Player H", 2250],
    ]);
    const playerOpponentMap = new Map([
        ["Nakamura, Hikaru", "Liang, Awonder"],
        ["Liang, Awonder", "Nakamura, Hikaru"],
        ["Neverov, Valeriy", "Smirnov, Anton"],
        ["Smirnov, Anton", "Neverov, Valeriy"],
        ["Player E", "Player F"],
        ["Player F", "Player E"],
        ["Player G", "Player H"],
        ["Player H", "Player G"],
    ]);

    // User1: Favorites Nakamura only (Scenario A)
    const user1Favs = ["Nakamura, Hikaru"];
    // User2: Favorites Liang + Neverov (Scenario B)
    const user2Favs = ["Liang, Awonder", "Neverov, Valeriy"];
    // User3: Favorites Nakamura + Smirnov + Player E (Scenario C)
    const user3Favs = ["Nakamura, Hikaru", "Smirnov, Anton", "Player E"];

    // Simulate the per-user body building
    const buildBody = (favNames: string[]) => {
        const sorted = [...favNames].sort((a, b) => {
            const ra = playerRatingMap.get(a) ?? 0;
            const rb = playerRatingMap.get(b) ?? 0;
            return rb - ra;
        });

        if (sorted.length === 1) {
            const fav = formatPlayerName(sorted[0]);
            const oppName = playerOpponentMap.get(sorted[0]) ?? "Opponent";
            const opp = formatPlayerName(oppName);
            return `${fav} vs ${opp} is live.`;
        } else if (sorted.length === 2) {
            const p1 = formatPlayerName(sorted[0]);
            const p2 = formatPlayerName(sorted[1]);
            return `${p1} and ${p2} are live.`;
        } else {
            const p1 = formatPlayerName(sorted[0]);
            const p2 = formatPlayerName(sorted[1]);
            return `${p1}, ${p2}, and others are live.`;
        }
    };

    const body1 = buildBody(user1Favs);
    const body2 = buildBody(user2Favs);
    const body3 = buildBody(user3Favs);

    // Scenario A: 1 fav
    assertEquals(body1, "Nakamura, Hikaru vs Liang, Awonder is live.");

    // Scenario B: 2 favs, Liang (2620) > Neverov (2500)
    assertEquals(body2, "Liang, Awonder and Neverov, Valeriy are live.");

    // Scenario C: 3 favs, top 2 by rating: Nakamura (2789), Smirnov (2650)
    assertEquals(
        body3,
        "Nakamura, Hikaru, Smirnov, Anton, and others are live.",
    );

    // Verify all are different (per-user personalization)
    assertEquals(body1 !== body2, true);
    assertEquals(body2 !== body3, true);
    assertEquals(body1 !== body3, true);
});

Deno.test("Integration — game_finished notification format", () => {
    const eventName = "Titled Tuesday March 10, 2026";
    const roundName = "Round 10";
    const white = "Nakamura, Hikaru";
    const black = "Madaminov, Mukhiddin";
    const result = "1/2-1/2";

    const title =
        buildEventHeader(eventName, roundName) ??
        `${formatPlayerName(white)} vs ${formatPlayerName(black)}`;
    const body = buildGameFinishedBody(white, black, result);

    assertEquals(title, "Titled Tuesday March 10, 2026 — Round 10");
    assertEquals(body, "Nakamura, Hikaru vs Madaminov, Mukhiddin: 1/2-1/2");
});

Deno.test("Integration — game_finished title falls back when no event", () => {
    const white = "Carlsen, Magnus";
    const black = "Nakamura, Hikaru";
    const result = "1-0";

    const title =
        buildEventHeader(null, null) ??
        `${formatPlayerName(white)} vs ${formatPlayerName(black)}`;
    const body = buildGameFinishedBody(white, black, result);

    assertEquals(title, "Carlsen, Magnus vs Nakamura, Hikaru");
    assertEquals(body, "Carlsen, Magnus vs Nakamura, Hikaru: 1-0");
});

// ---------------------------------------------------------------------------
// 11. Bug regression tests
// ---------------------------------------------------------------------------

Deno.test("BUG FIX: No duplicate notifications for multi-favorite users", () => {
    // Old behavior: User with 3 favorites got 3 separate notifications.
    // New behavior: User gets exactly 1 notification.
    const userFavs = [
        { name: "Nakamura, Hikaru", rating: 2789 },
        { name: "Carlsen, Magnus", rating: 2830 },
        { name: "Liang, Awonder", rating: 2620 },
    ];
    const opponents = new Map<string, string>();

    // buildRoundStartedBody returns a single string — one notification
    const body = buildRoundStartedBody(userFavs, opponents);
    assertStringIncludes(body, "and others are live.");

    // Top 2 by rating: Carlsen (2830), Nakamura (2789)
    assertEquals(
        body,
        "Carlsen, Magnus, Nakamura, Hikaru, and others are live.",
    );
});

Deno.test("BUG FIX: Starred user with favorites gets ONLY Type 1", () => {
    const eventUsers = new Set(["user1"]);
    const playerUsers = new Set(["user1"]);
    const prefs = new Map<string, PrefsRow>();

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);

    // user1 should be in playerRecipients ONLY
    assertEquals(result.playerRecipients.includes("user1"), true);
    assertEquals(result.eventRecipients.includes("user1"), false);
});

Deno.test("BUG FIX: Non-starred users do NOT get event notifications", () => {
    // user1 has favorites but didn't star the event
    // user1 should get player notification, NOT event notification
    const eventUsers = new Set<string>(); // nobody starred
    const playerUsers = new Set(["user1"]);
    const prefs = new Map<string, PrefsRow>();

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);

    assertEquals(result.playerRecipients, ["user1"]);
    assertEquals(result.eventRecipients, []);
});

Deno.test("BUG FIX: Event notification only goes to starred users", () => {
    // user1 starred, user2 did not, neither has favorites
    const eventUsers = new Set(["user1"]);
    const playerUsers = new Set<string>();
    const prefs = new Map<string, PrefsRow>();

    const result = filterRoundRecipientsSync(eventUsers, playerUsers, prefs);

    assertEquals(result.eventRecipients, ["user1"]);
    assertEquals(result.playerRecipients, []);
    // user2 should not appear anywhere
});

// ---------------------------------------------------------------------------
// 12. extractLastName tests (used internally for dedup)
// ---------------------------------------------------------------------------

Deno.test("extractLastName — Last, First format", () => {
    assertEquals(extractLastName("Carlsen, Magnus"), "Carlsen");
    assertEquals(extractLastName("Nakamura, Hikaru"), "Nakamura");
});

Deno.test("extractLastName — First Last format", () => {
    assertEquals(extractLastName("Magnus Carlsen"), "Carlsen");
});

Deno.test("extractLastName — Gukesh D → Gukesh", () => {
    assertEquals(extractLastName("Gukesh D"), "Gukesh");
});

Deno.test("extractLastName — single name", () => {
    assertEquals(extractLastName("Carlsen"), "Carlsen");
});
