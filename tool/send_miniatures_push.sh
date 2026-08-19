#!/usr/bin/env bash
#
# One-off marketing push: "we have miniature games".
#
# Routing contract (verified against lib/services/deep_link_service.dart):
#   main() registers OneSignal.Notifications.addClickListener and forwards
#   ONLY event.notification.additionalData -> DeepLinkService.ingestNotificationData.
#   handleNotificationData switches on data["type"]; "game_finished" + "game_id"
#   has routed to the board since 47c2c24f (2026-02-10), so every build in the
#   wild honours it. A launch `url` is deliberately NOT set: production never
#   sets one, and OneSignal opening the URL itself would race the in-app route.
#
# Usage:
#   ONESIGNAL_REST_API_KEY=... ./tool/send_miniatures_push.sh verify
#   ONESIGNAL_REST_API_KEY=... ./tool/send_miniatures_push.sh test <external_id>
#   ONESIGNAL_REST_API_KEY=... ./tool/send_miniatures_push.sh broadcast
set -euo pipefail

APP_ID="1fee79ce-4e15-4de1-90a5-61a7e124a021"
GAME_ID="PAnJ8CJp"
TITLE="Gentle reminder ❤️ Even strong players get miniatured"
BODY="A top-40 player just got caught in one 👀. See it in the miniatures library."

: "${ONESIGNAL_REST_API_KEY:?Set ONESIGNAL_REST_API_KEY (OneSignal > Settings > Keys & IDs > App API Key)}"

API="https://api.onesignal.com"
AUTH="Authorization: Key ${ONESIGNAL_REST_API_KEY}"

# Shared payload. `priority: 10` matches the production dispatcher so Android
# does not hold the message until the next Doze maintenance window.
base_payload() {
  python3 - "$APP_ID" "$TITLE" "$BODY" "$GAME_ID" <<'PY'
import json, sys
app_id, title, body, game_id = sys.argv[1:5]
print(json.dumps({
    "app_id": app_id,
    "target_channel": "push",
    "headings": {"en": title},
    "contents": {"en": body},
    "data": {"type": "game_finished", "game_id": game_id},
    "priority": 10,
}))
PY
}

with_target() {
  python3 -c 'import json,sys; p=json.loads(sys.argv[1]); p.update(json.loads(sys.argv[2])); print(json.dumps(p))' "$(base_payload)" "$1"
}

post() {
  curl -sS -w '\nHTTP:%{http_code}\n' -X POST "$API/notifications" \
    -H 'Content-Type: application/json' -H "$AUTH" -d "$1"
}

case "${1:-}" in
  verify)
    echo "Payload that will be sent:"
    base_payload | python3 -m json.tool
    echo
    echo "Auth check (GET /notifications):"
    curl -sS -o /dev/null -w 'HTTP:%{http_code}\n' -G "$API/notifications" \
      --data-urlencode "app_id=$APP_ID" --data-urlencode 'limit=1' -H "$AUTH"
    echo "200 = key is valid. 401/403 = wrong key."
    ;;
  test)
    external_id="${2:?Usage: $0 test <external_id (Supabase auth user id)>}"
    post "$(with_target "{\"include_aliases\":{\"external_id\":[\"$external_id\"]}}")"
    ;;
  broadcast)
    # "Total Subscriptions" is this app's default all-hands segment (confirmed
    # against GET /apps/<id>/segments — the legacy "Subscribed Users" name does
    # not exist here). Deliberately a single attempt with no fallback: a retry
    # after a partially-accepted send would double-push the whole user base.
    post "$(with_target '{"included_segments":["Total Subscriptions"]}')"
    ;;
  *)
    echo "Usage: $0 {verify|test <external_id>|broadcast}" >&2
    exit 2
    ;;
esac
