-- Per-event notification muting.
-- A row in this table means the user has muted notifications for the event
-- identified by group_broadcast_id. Absence of a row = not muted.

CREATE TABLE IF NOT EXISTS public.user_muted_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_broadcast_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, group_broadcast_id)
);

ALTER TABLE public.user_muted_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "select_own" ON public.user_muted_events
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "insert_own" ON public.user_muted_events
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "delete_own" ON public.user_muted_events
  FOR DELETE USING (auth.uid() = user_id);

-- For edge function lookups: "which users muted this event?"
CREATE INDEX idx_muted_events_gbi ON public.user_muted_events(group_broadcast_id);
