# Supabase Migration Handoff

Deploy these SQL files in order:

1. `001_add_show_coordinates_to_user_engine_settings.sql`
2. `002_grouped_round_start_exact_time_dedupe.sql`

Notes:
- These are copied from the repo-local migrations created during the PR cleanup.
- `002_grouped_round_start_exact_time_dedupe.sql` is paired with the local Edge Function changes in `supabase/functions/onesignal-dispatch/index.ts`; deploy that function too for the full duplicate-notification fix.
- Supabase MCP was unauthorized in this session, so these were not applied remotely here.
