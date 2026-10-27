#!/usr/bin/env bash
# Send a short alert to Slack, Microsoft Teams (Workflows webhook) or Discord.
# The webhook URL is read from the environment and handed to curl on stdin, so it
# never appears in arguments, process lists, shell history or CI logs.
# Messages must never contain secret values.
#
# Usage: LEAK_WEBHOOK_URL=<url> leak notify [--format slack|teams|discord] <message ...>
#   --format   payload style (default: slack, which also suits Mattermost and Rocket.Chat)
# Exit:  0 sent, 2 bad arguments or no LEAK_WEBHOOK_URL, 4 the webhook did not accept it
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

format=slack; words=()
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --format) need_value "$1" "${2:-}"; format="$2"; shift 2 ;;
    --) shift; words+=("$@"); break ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) words+=("$1"); shift ;;
  esac
done
message="${words[*]:-}"
[[ -n "$message" ]] || { print_help "$0" >&2; exit "$EXIT_USAGE"; }
[[ -n "${LEAK_WEBHOOK_URL:-}" ]] || { echo "set LEAK_WEBHOOK_URL (keep it in a secret store, not in code)" >&2; exit "$EXIT_USAGE"; }
[[ "$LEAK_WEBHOOK_URL" == https://* || "$LEAK_WEBHOOK_URL" == http://127.0.0.1:* || "$LEAK_WEBHOOK_URL" == http://localhost:* ]] \
  || { echo "LEAK_WEBHOOK_URL must be an https:// URL" >&2; exit "$EXIT_USAGE"; }
[[ "$LEAK_WEBHOOK_URL" != *[[:space:]\"\\]* ]] || { echo "LEAK_WEBHOOK_URL contains characters that are not allowed" >&2; exit "$EXIT_USAGE"; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit "$EXIT_USAGE"; }

case "$format" in
  slack) filter='{text: $t}' ;;
  discord) filter='{content: $t}' ;;
  teams) filter='{
      type: "message",
      attachments: [{
        contentType: "application/vnd.microsoft.card.adaptive",
        content: { "$schema": "http://adaptivecards.io/schemas/adaptive-card.json", type: "AdaptiveCard", version: "1.4",
                   body: [{ type: "TextBlock", text: $t, wrap: true }] }
      }]
    }' ;;
  *) echo "unknown format: $format (slack, teams or discord)" >&2; exit "$EXIT_USAGE" ;;
esac

payload="$(mktemp)"; trap 'rm -f "$payload"' EXIT
jq -n --arg t "$message" "$filter" > "$payload"

# URL comes from curl's config on stdin (-K -), so it is not visible in argv.
if printf 'url = "%s"\n' "$LEAK_WEBHOOK_URL" \
  | curl -fsS --max-time 20 -K - -X POST -H 'Content-Type: application/json' --data-binary "@$payload" -o /dev/null; then
  echo "notification sent ($format)"
else
  echo "the webhook did not accept the notification ($format)" >&2
  exit "$EXIT_FAILED"
fi
