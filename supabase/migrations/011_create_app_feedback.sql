-- Store low-rating feedback from in-app review flow

CREATE TABLE IF NOT EXISTS public.app_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  rating SMALLINT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  feedback TEXT,
  source TEXT,
  app_version TEXT,
  build_number TEXT,
  platform TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.app_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "app_feedback_insert"
  ON public.app_feedback
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);
