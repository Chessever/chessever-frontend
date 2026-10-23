/**
 * The words of a starred collection's "new games" push, sent as soon as games
 * reach its readers (gamebase queues `collection_games_added`).
 *
 * The count leads: "Best of 2026 added 4 new games". gamebase always sends it
 * now; a row queued before it did, with no count, still reads.
 */
export type CollectionGamesCopy = { title: string; body: string };

export type CollectionGamesPush = {
  title: string;
  /** "book" or "event"; anything else reads as a collection. */
  kind: string | null;
  /** Games that reached readers, or null when the producer did not say. */
  added: number | null;
};

/** 1240 → "1,240": a big number reads as one. */
function count(n: number): string {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

export function collectionGamesAddedCopy(
  push: CollectionGamesPush,
): CollectionGamesCopy {
  const name = push.title.trim() || "A collection you starred";
  const what = push.kind === "book"
    ? "a book you starred"
    : push.kind === "event"
    ? "an event you starred"
    : "a collection you starred";
  const n = push.added !== null && push.added > 0 ? push.added : null;

  if (n === null) {
    return {
      title: `${name} has new games`,
      body: `Fresh games just landed in ${what}. Tap to see them.`,
    };
  }
  return {
    title: `${name} added ${count(n)} new ${n === 1 ? "game" : "games"}`,
    body: n === 1
      ? `Fresh in ${what}. Tap to see it.`
      : `Fresh in ${what}. Tap to see all ${count(n)}.`,
  };
}

/** The outbox payload gamebase writes, read safely. */
export function collectionGamesPushFromPayload(
  payload: Record<string, unknown> | null | undefined,
): CollectionGamesPush {
  const p = payload ?? {};
  const raw = typeof p.added === "number" ? p.added : Number(p.added);
  return {
    title: typeof p.title === "string" ? p.title : "",
    kind: typeof p.kind === "string" ? p.kind : null,
    added: p.added !== null && p.added !== undefined && Number.isFinite(raw) &&
        raw > 0
      ? Math.trunc(raw)
      : null,
  };
}
