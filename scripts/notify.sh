#!/usr/bin/env bash
# Send a short alert to Slack, Microsoft Teams (Workflows webhook) or Discord.
# The webhook URL is read from the environment, so it never appears in process
# lists, shell history or CI logs. Messages must never contain secret values.
#
# Usage: LEAK_WEBHOOK_URL=<url> ./scripts/notify.sh [--format slack|teams|discord] "message"
#   --format   payload style (default: slack, which also suits Mattermost and Rocket.Chat)
# Exit:  0 sent, 1 the webhook refused it, 2 bad arguments or no LEAK_WEBHOOK_URL
set -euo pipefail

help() { sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0"; }
format=slack; message=""
while (($#)); do
  case "$1" in
    -h|--help) help; exit 0 ;;
    --format) format="${2:-}"; shift 2 ;;
    *) message="$1"; shift ;;
  esac
done
[[ -n "$message" ]] || { help >&2; exit 2; }
[[ -n "${LEAK_WEBHOOK_URL:-}" ]] || { echo "set LEAK_WEBHOOK_URL (keep it in a secret store, not in code)" >&2; exit 2; }
[[ "$LEAK_WEBHOOK_URL" == https://* || "$LEAK_WEBHOOK_URL" == http://127.0.0.1:* || "$LEAK_WEBHOOK_URL" == http://localhost:* ]] \
  || { echo "LEAK_WEBHOOK_URL must be an https:// URL" >&2; exit 2; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit 2; }

case "$format" in
  slack) payload="$(jq -n --arg t "$message" '{text: $t}')" ;;
  discord) payload="$(jq -n --arg t "$message" '{content: $t}')" ;;
  teams) payload="$(jq -n --arg t "$message" '{
      type: "message",
      attachments: [{
        contentType: "application/vnd.microsoft.card.adaptive",
        content: { "$schema": "http://adaptivecards.io/schemas/adaptive-card.json", type: "AdaptiveCard", version: "1.4",
                   body: [{ type: "TextBlock", text: $t, wrap: true }] }
      }]
    }')" ;;
  *) echo "unknown format: $format (slack, teams or discord)" >&2; exit 2 ;;
esac

if curl -fsS --max-time 20 -X POST -H 'Content-Type: application/json' --data-binary @- "$LEAK_WEBHOOK_URL" <<<"$payload" >/dev/null; then
  echo "notification sent ($format)"
else
  echo "the webhook did not accept the notification ($format)" >&2
  exit 1
fi
