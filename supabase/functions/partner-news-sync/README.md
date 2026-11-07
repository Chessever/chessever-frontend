# partner-news-sync moved

Canonical source and deployment owner:
`Chessever/chessever-web-frontend/supabase/functions/partner-news-sync/`.
The runtime files and their parser/extraction tests now live beside `create-news`.
Do not restore a mobile deployment copy or deploy this slug from this repository.

The existing production function, URL, authentication, ten-minute cron schedule,
secrets and notification behavior are unchanged. Historical SQL migrations and
their database tests remain here; run `npm run test:partner-news` in `supabase/tests`.
Run runtime/parser tests in the web repository with `npm run test:partner-news`.
Deploy future function changes explicitly from the web repository with
`--project-ref oelbsuggrzyqwzmvidju --no-verify-jwt`.

Destination source handoff: web commit `22d37b41` (`codex/colocate-news-functions`).
All six moved files retain their source SHA-256 values; the three runtime files
also match live function version 12 byte-for-byte. Mobile validation passed:
14 partner database tests, 8 native-news tests and 13 rewarded-backend tests.
Production was neither redeployed nor reconfigured for this move.
