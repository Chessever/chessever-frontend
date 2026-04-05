-- Normalize legacy eval cache metadata and prune obviously bad duplicates.
-- This keeps the server-side eval cache depth-aware without dropping the
-- deepest usable row for any position / MultiPV combination.

UPDATE public.evals
SET multi_pv = GREATEST(
  jsonb_array_length(COALESCE(pvs, '[]'::jsonb)),
  1
)
WHERE multi_pv IS NULL;

CREATE INDEX IF NOT EXISTS idx_evals_position_depth_multipv
  ON public.evals(position_id, depth DESC, multi_pv DESC);

WITH ranked_exact_duplicates AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY
        position_id,
        COALESCE(depth, 0),
        COALESCE(
          multi_pv,
          GREATEST(jsonb_array_length(COALESCE(pvs, '[]'::jsonb)), 1)
        ),
        md5(COALESCE(pvs::text, ''))
      ORDER BY id DESC
    ) AS row_rank
  FROM public.evals
)
DELETE FROM public.evals evals
USING ranked_exact_duplicates duplicates
WHERE evals.id = duplicates.id
  AND duplicates.row_rank > 1;

WITH ranked_zero_depth_rows AS (
  SELECT
    id,
    COALESCE(depth, 0) AS effective_depth,
    row_number() OVER (
      PARTITION BY
        position_id,
        COALESCE(
          multi_pv,
          GREATEST(jsonb_array_length(COALESCE(pvs, '[]'::jsonb)), 1)
        )
      ORDER BY COALESCE(depth, 0) DESC, id DESC
    ) AS quality_rank
  FROM public.evals
)
DELETE FROM public.evals evals
USING ranked_zero_depth_rows ranked
WHERE evals.id = ranked.id
  AND ranked.quality_rank > 1
  AND ranked.effective_depth = 0;
