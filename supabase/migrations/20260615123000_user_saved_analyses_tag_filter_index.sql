-- Forward, additive infrastructure for filtering (and later sorting) liked
-- games by tag.
--
-- Purely ADDITIVE. The `tags TEXT[]` column already exists
-- (004_create_library_tables_v2.sql) and the client has always written it;
-- this migration only adds indexes. No column is added, no table is rewritten,
-- no data changes, and existing behaviour is untouched — rows keep their
-- (often empty) tags array and the client reads/writes `tags` exactly as before.
--
-- Follows Supabase / Postgres best practices, and mirrors the table's existing
-- index conventions (partial indexes, user-scoped composites):
--   * GIN is the correct index type for a text[] membership filter.
--   * A partial EXPRESSION index serves the single "primary" tag, deliberately
--     instead of a STORED generated column — the latter would force an
--     ACCESS EXCLUSIVE full-table rewrite on add (see lock best practices).
--   * lock_timeout makes the build fail fast rather than queue behind a long
--     lock on a busy table.

set local lock_timeout = '5s';

-- Filter by one or more tags.
--   PostgREST: tags=cs.{Sacrifice}
--   SQL:       WHERE tags @> ARRAY['Sacrifice']::text[]   /   't' = ANY(tags)
-- Kept FULL (not partial): PostgREST containment queries won't carry a
-- `tags <> '{}'` predicate, so a partial GIN couldn't be chosen — and empty
-- arrays contribute no searchable GIN keys, so untagged rows cost ~nothing.
create index if not exists idx_user_saved_analyses_tags
  on public.user_saved_analyses using gin (tags);

-- Equality / ORDER BY on the single (primary) tag, without adding a column or
-- rewriting the table. Partial over the untagged majority (first element null);
-- the equality-implies-not-null proof still lets the planner use it for
-- `(tags)[1] = '...'`. If PostgREST column-level `order=primary_tag` is ever
-- needed, expose `(tags)[1] AS primary_tag` through a `security_invoker` view
-- backed by this index — still no table rewrite.
create index if not exists idx_user_saved_analyses_primary_tag
  on public.user_saved_analyses (((tags)[1]))
  where (tags)[1] is not null;
