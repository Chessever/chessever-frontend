-- Enforce authenticated-only access for app tables that are queried from clients.

-- Read-only tables: allow SELECT only when authenticated.
DO $$
DECLARE
  tbl text;
  policy_name text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'games',
    'rounds',
    'tours',
    'chess_players',
    'calendar_events',
    'settings',
    'group_broadcasts',
    'group_broadcasts_current',
    'group_broadcasts_upcoming',
    'group_broadcasts_past'
  ]
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = tbl
        AND c.relkind IN ('r', 'p')
    ) THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
      policy_name := format('auth_read_%s', tbl);
      IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = tbl
          AND policyname = policy_name
      ) THEN
        EXECUTE format(
          'CREATE POLICY %I ON public.%I FOR SELECT USING (auth.uid() IS NOT NULL)',
          policy_name,
          tbl
        );
      END IF;
    END IF;
  END LOOP;
END $$;

-- Read/write cache tables: allow all operations only when authenticated.
DO $$
DECLARE
  tbl text;
  policy_name text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'positions',
    'evals',
    'pvs'
  ]
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = tbl
        AND c.relkind IN ('r', 'p')
    ) THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
      policy_name := format('auth_rw_%s', tbl);
      IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = tbl
          AND policyname = policy_name
      ) THEN
        EXECUTE format(
          'CREATE POLICY %I ON public.%I FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL)',
          policy_name,
          tbl
        );
      END IF;
    END IF;
  END LOOP;
END $$;

-- User-scoped settings table: only allow access to the owning user.
DO $$
DECLARE
  policy_name text;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'user_engine_settings'
      AND c.relkind IN ('r', 'p')
  ) THEN
    EXECUTE 'ALTER TABLE public.user_engine_settings ENABLE ROW LEVEL SECURITY';
    policy_name := 'user_engine_settings_own';
    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'user_engine_settings'
        AND policyname = policy_name
    ) THEN
      EXECUTE
        'CREATE POLICY "user_engine_settings_own" ON public.user_engine_settings FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)';
    END IF;
  END IF;
END $$;
