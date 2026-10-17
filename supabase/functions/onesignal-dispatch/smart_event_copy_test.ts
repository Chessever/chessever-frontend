/**
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/smart_event_copy_test.ts
 */
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type SmartEventDigest,
  smartEventDigestCopy,
  smartEventDigestFromPayload,
  smartEventPlayerName,
} from "./smart_event_copy.ts";

function digest(overrides: Partial<SmartEventDigest>): SmartEventDigest {
  return {
    label: null,
    minElo: 0,
    maxElo: 3200,
    formats: [],
    ecoCode: null,
    games: 6,
    liveGames: 0,
    whiteWins: 0,
    blackWins: 0,
    draws: 0,
    topWhite: "Grischuk, Alexander",
    topBlack: "Artemiev, Vladislav",
    topStatus: "*",
    topAverage: 2689,
    ...overrides,
  };
}

Deno.test("an opening smart event names its opening and the count", () => {
  const copy = smartEventDigestCopy(digest({
    label: "Sicilian: Najdorf",
    ecoCode: "B9",
    games: 8,
    topWhite: "Godart, Francois",
    topBlack: "Yakubboev, Nodirbek",
    topStatus: "0-1",
    topAverage: 2551,
  }));
  assertEquals(copy.kind, "opening:played");
  assertEquals(copy.title, "Sicilian: Najdorf played in 8 games");
  assertEquals(copy.body, "Yakubboev beat Godart (2551 avg). Tap to see.");
});

Deno.test("every mix of filters gets its own line", () => {
  const formats = [[], ["live"], ["completed"]];
  const mixes = [
    {},
    { ecoCode: "E0", label: "Catalan" },
    { minElo: 2500 },
    { formats: ["blitz"] },
    { ecoCode: "E0", label: "Catalan", minElo: 2500 },
    { ecoCode: "E0", label: "Catalan", formats: ["rapid"] },
    { minElo: 2500, formats: ["blitz"] },
    { ecoCode: "E0", label: "Catalan", minElo: 2500, formats: ["blitz"] },
  ];
  const kinds = new Set<string>();
  const titles = new Set<string>();
  for (const state of formats) {
    for (const mix of mixes) {
      const copy = smartEventDigestCopy(digest({
        ...mix,
        formats: [...(mix.formats ?? []), ...state],
        games: 3,
      }));
      kinds.add(copy.kind);
      titles.add(copy.title);
      assert(copy.title.includes("3"), copy.title);
      assert(copy.body.endsWith("Tap to see."), copy.body);
    }
  }
  assertEquals(kinds.size, 24);
  assertEquals(titles.size, 24);
});

Deno.test("level, time control and state read as one line", () => {
  assertEquals(
    smartEventDigestCopy(digest({ minElo: 2500, formats: ["blitz", "live"] }))
      .title,
    "6 Blitz games live now at GM level",
  );
  assertEquals(
    smartEventDigestCopy(digest({ minElo: 2450, formats: ["standard"] })).title,
    "6 Classical games played at 2450+",
  );
  assertEquals(
    smartEventDigestCopy(digest({ minElo: 2200, maxElo: 2400 })).title,
    "6 games played at 2200–2400",
  );
  assertEquals(
    smartEventDigestCopy(
      digest({ ecoCode: "E0", label: "Catalan", formats: ["live"], games: 1 }),
    ).title,
    "Catalan is live in 1 game",
  );
});

Deno.test("a finished batch says how it went", () => {
  const copy = smartEventDigestCopy(digest({
    formats: ["completed", "rapid"],
    games: 180,
    whiteWins: 75,
    blackWins: 67,
    draws: 38,
  }));
  assertEquals(copy.kind, "time:finished");
  assertEquals(copy.title, "180 Rapid results are in");
  assertEquals(copy.body, "White won 75, Black 67, 38 draws. Tap to see.");
});

Deno.test("all three time controls, or none, is every time control", () => {
  for (const formats of [[], ["blitz", "rapid", "standard"]]) {
    assertEquals(
      smartEventDigestCopy(digest({ formats, minElo: 2500 })).kind,
      "level:played",
    );
  }
  assertEquals(
    smartEventDigestCopy(digest({ formats: ["blitz", "rapid"] })).title,
    "6 Rapid & Blitz games just played",
  );
});

Deno.test("the full 0-3200 scale is no level", () => {
  assertEquals(smartEventDigestCopy(digest({})).kind, "all:played");
  assertEquals(
    smartEventDigestCopy(digest({})).title,
    "6 games played in the last 4 hours",
  );
});

Deno.test("an unrated top game leaves the average out", () => {
  assertEquals(
    smartEventDigestCopy(digest({ topAverage: 0 })).body,
    "Top game: Grischuk vs Artemiev. Tap to see.",
  );
});

Deno.test("player names shorten like the round pushes", () => {
  assertEquals(smartEventPlayerName("Carlsen, Magnus"), "Carlsen");
  assertEquals(smartEventPlayerName("GM Carlsen, Magnus"), "Carlsen");
  assertEquals(smartEventPlayerName("Shelke Sankarsha"), "Sankarsha");
  assertEquals(smartEventPlayerName("Gukesh D"), "Gukesh");
  assertEquals(smartEventPlayerName("OsboAM"), "OsboAM");
  assertEquals(smartEventPlayerName(null), "?");
});

Deno.test("the payload is read defensively", () => {
  const read = smartEventDigestFromPayload({
    min_elo: "2500",
    max_elo: null,
    formats: ["live", 3],
    games: 4,
    eco_code: "",
  });
  assertEquals(read.minElo, 2500);
  assertEquals(read.maxElo, 3200);
  assertEquals(read.formats, ["live"]);
  assertEquals(read.ecoCode, null);
  assertEquals(read.games, 4);
});
