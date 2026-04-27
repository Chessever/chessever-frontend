-- User-applied NAG codes per move pointer for a saved analysis.
-- Shape: jsonb object keyed by encoded ChessMovePointer (e.g. "0,1,3"),
-- each value a json array of NAG ints.
--   { "0,1,3": [1, 16], "0,2,5,1": [3] }
-- Why jsonb (not a side table): NAGs are written together with
-- variation_comments on the same auto-save tick, queried as one blob with
-- the rest of the analysis state, and never queried by NAG value. Keeping
-- them on the same row avoids a join and matches the existing convention
-- already used for variation_comments.

ALTER TABLE public.user_saved_analyses
  ADD COLUMN IF NOT EXISTS move_nags jsonb NOT NULL DEFAULT '{}'::jsonb;

-- Top-level shape guard only: must be a jsonb object. Postgres CHECK
-- constraints can't contain subqueries, so per-value array validation lives
-- in the client model (saved_analysis.dart) which is the source of writes.
ALTER TABLE public.user_saved_analyses
  DROP CONSTRAINT IF EXISTS user_saved_analyses_move_nags_shape_check;

ALTER TABLE public.user_saved_analyses
  ADD CONSTRAINT user_saved_analyses_move_nags_shape_check
  CHECK (jsonb_typeof(move_nags) = 'object');

COMMENT ON COLUMN public.user_saved_analyses.move_nags IS
  'User-applied NAG codes per move. Map<encodedPointer, List<int>>. '
  'See lib/repository/library/models/saved_analysis.dart for the client model.';
