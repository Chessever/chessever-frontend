-- Partner news stores only the opening half of each article. ChessEver
-- shows it under the partner's name and sends the reader to the partner's
-- site for the rest, so it never stands in for the partner's own page
-- (product decision, 2026-10-26).
--
-- partner-news-sync cuts the article (EXCERPT_SHARE in feed.ts) before it
-- reaches this table; articles stored whole before the change are cut on
-- the next sync, since their stored text no longer matches.
--
-- Additive: a comment only.

comment on column public.partner_news.content is
  'Markdown: the opening half of the article, never all of it. The rest is read on the partner''s site (url).';
