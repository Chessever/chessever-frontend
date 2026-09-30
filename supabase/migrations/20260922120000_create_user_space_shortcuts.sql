-- My Space: user-owned shortcuts into any deep-linkable surface of the app
-- (a player, a player's games tab or opening tree, an event, a round, a game,
-- an explorer position, an opening, a folder or database, a smart event,
-- countrymen, miniatures, likes, a streak, or any chessever.com link).
--
-- Additive only: a new table, its RLS policies, an index, and a Realtime
-- publication entry so every signed-in device sees adds/removes live.

CREATE TABLE IF NOT EXISTS public.user_space_shortcuts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  kind text NOT NULL,
  target_id text NOT NULL,
  title text NOT NULL,
  subtitle text,
  params jsonb NOT NULL DEFAULT '{}'::jsonb,
  sort_index double precision NOT NULL DEFAULT 0,
  open_count integer NOT NULL DEFAULT 0,
  last_opened_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_space_shortcuts_kind_len CHECK (char_length(kind) BETWEEN 1 AND 40),
  CONSTRAINT user_space_shortcuts_target_len CHECK (char_length(target_id) BETWEEN 1 AND 2048),
  CONSTRAINT user_space_shortcuts_unique UNIQUE (user_id, kind, target_id)
);

CREATE INDEX IF NOT EXISTS user_space_shortcuts_user_sort_idx
  ON public.user_space_shortcuts (user_id, sort_index);

ALTER TABLE public.user_space_shortcuts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_space_shortcuts' AND policyname = 'space_shortcuts_select_own') THEN
    CREATE POLICY space_shortcuts_select_own ON public.user_space_shortcuts
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_space_shortcuts' AND policyname = 'space_shortcuts_insert_own') THEN
    CREATE POLICY space_shortcuts_insert_own ON public.user_space_shortcuts
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_space_shortcuts' AND policyname = 'space_shortcuts_update_own') THEN
    CREATE POLICY space_shortcuts_update_own ON public.user_space_shortcuts
      FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_space_shortcuts' AND policyname = 'space_shortcuts_delete_own') THEN
    CREATE POLICY space_shortcuts_delete_own ON public.user_space_shortcuts
      FOR DELETE USING (auth.uid() = user_id);
  END IF;
END
$$;

-- Deletes must reach other devices with the user_id filter intact.
ALTER TABLE public.user_space_shortcuts REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'user_space_shortcuts'
  ) THEN
    PERFORM set_config('lock_timeout', '3s', true);
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_space_shortcuts;
  END IF;
END
$$;

-- Rollback (only if this migration created it):
-- ALTER PUBLICATION supabase_realtime DROP TABLE public.user_space_shortcuts;
-- DROP TABLE public.user_space_shortcuts;
