-- Partner news stores whole articles again. RookReview is happy for
-- ChessEver to show its articles in full, provided every one always links
-- to the original (product decision, 2026-10-26, replacing the half-article
-- rule of 20261026180000 the same day). The apps and chessever.com show
-- "Read original article" on every partner article.
--
-- partner-news-sync rewrites the articles still in the feed on its next run
-- (their stored text no longer matches); older ones are restored by hand.
--
-- Additive: a comment only.

comment on column public.partner_news.content is
  'Markdown: the whole article, converted from the partner''s feed by partner-news-sync. Every surface links to the original (url).';
