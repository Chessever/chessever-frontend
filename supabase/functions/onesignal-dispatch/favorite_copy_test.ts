import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { favoriteBoardCopy, groupFavoriteBoardCopy } from "./favorite_copy.ts";

const board = {
  white: "Caruana, Fabiano",
  black: "Jakubowski, Krzysztof",
};
const eventHeader = "Titled Tuesday October 6 2026 - Round 1";
const fallback = {
  title: eventHeader,
  body: "Caruana, Fabiano vs Jakubowski, Krzysztof is live.",
};

Deno.test("favorite start alert uses readable punctuation for the reported pairing", () => {
  assertEquals(
    favoriteBoardCopy({
      board,
      favorites: [board.white],
      eventType: "game_started",
      eventHeader,
      fallback,
    }),
    {
      title: "Fabiano Caruana is live",
      body:
        "Caruana, Fabiano vs Jakubowski, Krzysztof is live. Titled Tuesday October 6 2026 - Round 1",
    },
  );
});

Deno.test("Unicode player names survive notification formatting", () => {
  assertEquals(
    favoriteBoardCopy({
      board: { white: "Šarić, Ivan", black: "Gürel, Ediz" },
      favorites: ["Ivan Šarić"],
      eventType: "game_started",
      eventHeader: "Zürich - Round 2",
      fallback: { title: "Zürich", body: "Ivan Šarić vs Ediz Gürel is live." },
    }),
    {
      title: "Ivan Šarić is live",
      body: "Ivan Šarić vs Ediz Gürel is live. Zürich - Round 2",
    },
  );
});

Deno.test("finished draw alerts recognize both PGN and Unicode draw scores", () => {
  for (const status of ["1/2-1/2", "½-½", "D", "DRAW"]) {
    const copy = favoriteBoardCopy({
      board,
      favorites: [board.white],
      eventType: "game_finished",
      status,
      eventHeader,
      fallback: { title: eventHeader, body: "Caruana vs Jakubowski: ½-½" },
    });
    assertEquals(copy, {
      title: "Fabiano Caruana drew",
      body:
        "Caruana vs Jakubowski: ½-½. Titled Tuesday October 6 2026 - Round 1",
    });
  }
});

Deno.test("absent event context and unmatched favorites preserve the fallback", () => {
  assertEquals(
    favoriteBoardCopy({
      board,
      favorites: [],
      eventType: "game_started",
      eventHeader,
      fallback,
    }),
    fallback,
  );
  assertEquals(
    favoriteBoardCopy({
      board,
      favorites: [board.white],
      eventType: "game_started",
      eventHeader: null,
      fallback,
    }).body,
    fallback.body,
  );
});

Deno.test("copy grouping retains each recipient and the appropriate favorite title", () => {
  const groups = groupFavoriteBoardCopy(
    ["white-1", "black-1", "both-1", "white-2", "event-1"],
    new Map([
      ["white-1", [board.white]],
      ["white-2", [board.white]],
      ["black-1", [board.black]],
      ["both-1", [board.white, board.black]],
    ]),
    { board, eventType: "game_started", eventHeader, fallback },
  );
  assertEquals(groups.map((group) => [group.userIds, group.copy.title]), [
    [["white-1", "white-2"], "Fabiano Caruana is live"],
    [["black-1"], "Krzysztof Jakubowski is live"],
    [["both-1"], "Fabiano Caruana vs Krzysztof Jakubowski is live"],
    [["event-1"], eventHeader],
  ]);
});

Deno.test("dispatcher source must not contain UTF-8 decoded as Windows-1252", async () => {
  const directory = new URL(".", import.meta.url);
  const corruptions = [
    "\u00c2\u00b7",
    "\u00c2\u00bd",
    "\u00e2\u20ac\u201d",
    "\u00e2\u20ac\u201c",
    "\u00e2\u20ac\u00a6",
    "\u00e2\u2020\u2019",
    "\u00c3\u00a1",
    "\u00c3\u00b3",
    "\u00c3\u00bc",
  ];
  for await (const entry of Deno.readDir(directory)) {
    if (!entry.isFile || !entry.name.endsWith(".ts")) continue;
    const source = await Deno.readTextFile(new URL(entry.name, directory));
    assertEquals(
      corruptions.filter((sequence) => source.includes(sequence)),
      [],
      entry.name,
    );
  }
});
