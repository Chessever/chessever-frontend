# Collections (Discovery › Collection)

A collection is a curated set of annotated games: a GM's annotated games from
one tournament (`kind = event`, e.g. "US Championship 2025"), or the games of a
book (`kind = book`, with an About text on the author and the book). The app
lists them under For You › Discovery › Collection, laid out like an event:
About, Games and Players tabs.

## Where they live

Supabase, both projects (test `odmekzlfunfocvedqusl`, production
`oelbsuggrzyqwzmvidju`), migration
`supabase/migrations/20260925120000_create_discovery_collections.sql`:

| table | what |
| --- | --- |
| `discovery_collections` | one row per collection: `slug`, `kind`, `title`, `subtitle`, `author`, `about`, `cover_url`, `sort_order`, `published` |
| `discovery_collection_games` | one row per game: the whole `pgn`, plus header fields copied beside it |

Everyone can read published collections and their games. Nobody can write
with the app's keys; uploads use the service role key.

## Uploading one

1. Put the games in one PGN file, in the order they should appear. Keep the
   annotations in the PGN: comments `{...}`, NAGs (`$1`, `!?`) and variations
   all reach the board as they are. `WhiteTitle`, `WhiteElo`, `WhiteFed`
   (and the Black ones) fill the players' titles, ratings and flags.
2. Write the About text in a plain text file; blank lines separate
   paragraphs.
3. Run, with the target project's URL and service role key in the
   environment (never commit them):

   ```bash
   SUPABASE_URL=https://oelbsuggrzyqwzmvidju.supabase.co \
   SUPABASE_SERVICE_ROLE_KEY=... \
   python3 scripts/collections/upload_collection.py us-champ-2025.pgn \
     --slug us-championship-2025 --kind event \
     --title "US Championship 2025" \
     --subtitle "Saint Louis · October 2025" \
     --author "GM Name" --about-file about.txt
   ```

   The collection is saved **unpublished**. Check it, then publish it by
   running the same command with `--publish` (the slug makes it an update,
   not a second collection), or in SQL:

   ```sql
   update public.discovery_collections set published = true
   where slug = 'us-championship-2025';
   ```

- `--replace` swaps a collection's games for the file's (only that
  collection's games are dropped).
- `--sort-order` orders collections; lower comes first.
- `--cover-url` sets the card and About image; without one the card shows
  its pixel object (a trophy for an event, stacked boards for a book).
- To take a collection down, set `published = false`.
