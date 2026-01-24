# One-Time Backfill: Player Titles

Run this SQL once to populate missing player titles from `tours.players` into `games.players`.

**No triggers, no ongoing performance impact.**

```sql
UPDATE games g
SET players = (
  SELECT jsonb_agg(
    CASE
      WHEN gp->>'title' IS NULL OR gp->>'title' = '' THEN
        gp || jsonb_build_object(
          'title',
          COALESCE(
            (
              SELECT tp->>'title'
              FROM tours t,
                   jsonb_array_elements(t.players) AS tp
              WHERE t.id = g.tour_id
                AND tp->>'title' IS NOT NULL
                AND tp->>'title' != ''
                AND (
                  (
                    (gp->>'fideId')::int > 0
                    AND (tp->>'fideId')::int = (gp->>'fideId')::int
                  )
                  OR
                  (tp->>'name' = gp->>'name')
                )
              LIMIT 1
            ),
            ''
          )
        )
      ELSE gp
    END
  )
  FROM jsonb_array_elements(g.players) AS gp
)
WHERE EXISTS (
  SELECT 1
  FROM jsonb_array_elements(g.players) AS gp
  WHERE gp->>'title' IS NULL OR gp->>'title' = ''
);
```

## Verify after running

```sql
-- Should return 0 rows if successful
SELECT g.id, gp->>'name', gp->>'title'
FROM games g, jsonb_array_elements(g.players) AS gp
WHERE gp->>'title' IS NULL OR gp->>'title' = ''
LIMIT 10;
```
