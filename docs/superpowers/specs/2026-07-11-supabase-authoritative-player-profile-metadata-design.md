# Supabase-Authoritative Player Profile Metadata Design

**Date:** 2026-07-11

## Goal

Make player profiles display the same current Elo and player metadata as the
Favorites and Countrymen player cards. Treat `public.chess_players` in the main
Supabase project as the authoritative player metadata source.

## Current mismatch

Favorites and Countrymen player cards query `chess_players` directly. The
profile data path instead prefers TWIC/Gamebase classical ratings and uses an
indefinitely cached single-player Supabase lookup as a fallback. A current card
rating can therefore be replaced by stale profile metadata after navigation.

## Data ownership

For a player with a valid FIDE ID, a freshly fetched `chess_players` row owns
all populated metadata represented by the profile:

- name, title, and federation;
- classical, rapid, and blitz ratings and game counts;
- birthday and sex.

TWIC/Gamebase continues to own game history, event history, statistics,
Gamebase identity, and explorer behavior. It may fill a metadata field only
when the authoritative Supabase field is absent. Constructor/card values remain
the final fallback when neither backend supplies a value.

Players without a valid FIDE ID continue using the existing TWIC/name-based
profile behavior because they cannot be joined reliably to `chess_players`.

## Data flow

The keyed profile provider will fetch the complete `chess_players` metadata row
by FIDE ID without accepting the repository's indefinite in-memory snapshot.
It will merge that row over the TWIC player response. Profile header, About-tab
rating cards, explorer fallback, favorite metadata, and share cards already
consume the keyed profile model and will therefore resolve consistently.

Pull-to-refresh will repeat the authoritative read. A failed or missing
Supabase row will not blank a usable profile; the existing TWIC and navigation
fallbacks remain available.

No schema, migration, RLS, or backend synchronization change is required.

## Regression coverage

Add a focused deterministic test around the production metadata-resolution
seam. Given conflicting TWIC and Supabase values, every populated Supabase
field—especially classical Elo—must win. Given missing Supabase fields, TWIC
values must remain available. The test must also prove the profile path requests
a fresh row rather than reusing an earlier cached rating.

Validation is limited to the focused Flutter test and scoped
`flutter analyze --no-pub` for touched files. Runtime verification remains a
user device check under the repository rules.

## Non-goals

- Changing Favorites or Countrymen card queries.
- Changing TWIC game, event, statistics, or explorer behavior.
- Adding realtime subscriptions or periodic refresh work.
- Modifying the `chess_players` schema or its update pipeline.
