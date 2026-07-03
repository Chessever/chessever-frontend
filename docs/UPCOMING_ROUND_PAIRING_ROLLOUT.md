# Upcoming-Round Pairing Display — Rollout Checklist

_Status as of 2026-07-03. Owner: Berkay._

## What this feature is

During a round break (e.g. Naroditsky Memorial: round 3 done, round 4 in 20 min), the
Games tab shows the NEXT round's published pairings instead of hiding the round.
Display rules (all three must hold for the top slot):

1. It is the **one-and-only very next round** of that tour.
2. Its **boards/matchups are already published** (resolved names — `?`/TBD never shown).
3. Its known start time is **less than an hour away**.

→ then it renders **top-most** (list is newest-first). Any other future pairing round
renders bottom-most. Lichess publishes pairings ~20–25 min before start (measured).

## What is already shipped

| Piece | Where | State |
|---|---|---|
| Games-tab pairing rules + placeholder filter | chessever-frontend `a8704cc1` (dev) | merged, awaiting store release |
| Client-side lichess fallback (works WITHOUT backend) | chessever-frontend `849e7180` (dev) | merged, awaiting store release |
| Same two pieces for desktop | chessever_frontend_desktop `37ddbb4` + `a976d25` (main) | merged, awaiting release |
| Backend pairing sync (fast detector) | chessever-data-hub `bb0b115` | deployed to both droplets, **GATED OFF** |

The client-side fallback fetches `GET https://lichess.org/api/broadcast/-/-/{roundId}`
directly, so the feature works in these builds even while the backend stays gated.

## ⚠️ Why the backend is gated

Published desktop 19.5.x renders raw `games` rows with **no placeholder filter** — if the
backend started inserting pairing rows today, store desktop builds would show idle
start-position boards. Gate = systemd drop-ins setting `FAST_DETECT_PAIRING_SYNC=false`.

## TODO after BOTH store releases are approved & published

1. ```bash
   # FAST-DETECTOR (hop via DATA-HUB-MAIN; direct ssh rejects local keys)
   ssh -i ~/.ssh/datahub_key root@157.230.224.162 \
     "ssh -i /root/.ssh/id_ed25519 root@10.116.0.3 \
       'rm /etc/systemd/system/chessever-fast-detector.service.d/pairing.conf && \
        systemctl daemon-reload && systemctl restart chessever-fast-detector'"
   ```
2. ```bash
   # DATA-HUB-MAIN
   ssh -i ~/.ssh/datahub_key root@157.230.224.162 \
     "rm /etc/systemd/system/chessever-data-hub.service.d/pairing.conf && \
      systemctl daemon-reload && systemctl restart chessever-data-hub"
   ```
3. Verify within ~5 min of a round break on any live event:
   ```bash
   grep PAIRINGS /opt/fast_detector/logs/job_scheduler.py.log   # on FAST-DETECTOR
   ```
   Expect `📋 PAIRINGS [FEATURED]: synced N/N boards for upcoming round …`.

Backend knobs: `FAST_DETECT_PAIRING_SYNC` (default true), `FAST_DETECT_PAIRING_LOOKAHEAD_SEC`
(3900), `FAST_DETECT_PAIRING_TTL` (120), `FAST_DETECT_PAIRING_LATE_GRACE_SEC` (1800).

Once enabled, DB rows arrive within ~2 min of lichess publishing pairings; the client-side
lichess fallback in the apps deactivates automatically per round (DB rows always win).
