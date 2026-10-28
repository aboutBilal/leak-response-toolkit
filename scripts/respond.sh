#!/usr/bin/env bash
# Run the first hour of a leak response in order, and keep the record. It creates an
# incident folder, then snapshots the repository as evidence, scans its full history,
# plans the rotations, hunts for surviving copies and builds the incident report. Every
# step is written to timeline.md with its UTC time, and its full output to logs/.
# Rotating the secrets, the takedown and telling people stay yours: it says what to do
# and records the time when you mark each one done. Run it again with the same folder to
# continue; a finished step is not repeated unless you ask (--redo).
#
# Usage: leak respond <owner>/<repo> [--id ID] [--dir DIR] [--repo-path CLONE] [--tlp LABEL] [--since YYYY-MM-DD]
#        leak respond --dir DIR [--redo STEP] [--done STEP] [--status]
#   <owner>/<repo>     the exposed GitHub repository
#   --id ID            incident reference (default: INC-<UTC date>-<time>)
#   --dir DIR          the incident folder (default: ./<ID>); give it again to continue
#   --repo-path CLONE  scan this clone instead of the mirror (when the repository is already gone)
#   --tlp LABEL        handling label for the plan and report: clear, green, amber, amber+strict (default), red
#   --since DATE       for the hunt: same-name copies created on or after this date (default: 60 days ago)
#   --redo STEP        run snapshot, scan, plan, hunt or report again, and every step after it
#                      (repeat the hunt after 7 days: --redo hunt)
#   --done STEP        record that you finished rotate, takedown or notify, with the time
#   --status           show where the incident stands; change nothing
# Env:   GITHUB_TOKEN (optional) - higher rate limits; the owner's token also saves traffic data.
# Exit:  0 nothing found, 1 secrets or copies found, 2 bad arguments,
#        4 a step failed or is incomplete (see timeline.md and logs/)
# Read-only, like the steps it runs: it never changes the repository or any credential.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo=""; id=""; dir=""; repo_path=""; tlp=""; since=""; redo=""; done_step=""; status_only=0
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --id) need_value "$1" "${2:-}"; id="$2"; shift 2 ;;
    --dir) need_value "$1" "${2:-}"; dir="$2"; shift 2 ;;
    --repo-path) need_value "$1" "${2:-}"; repo_path="$2"; shift 2 ;;
    --tlp) need_value "$1" "${2:-}"; tlp="${2,,}"; shift 2 ;;
    --since) need_value "$1" "${2:-}"; since="$2"; shift 2 ;;
    --redo) need_value "$1" "${2:-}"; redo="$2"; shift 2 ;;
    --done) need_value "$1" "${2:-}"; done_step="$2"; shift 2 ;;
    --status) status_only=1; shift ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) if [[ -z "$repo" ]]; then repo="$1"; else echo "unexpected argument: $1" >&2; exit "$EXIT_USAGE"; fi; shift ;;
  esac
done
usage_fail() { echo "$1" >&2; echo "usage: leak respond <owner>/<repo> [--id ID] [--dir DIR]   or   leak respond --dir DIR [--status]" >&2; exit "$EXIT_USAGE"; }

auto_steps="snapshot scan plan hunt report"
own_steps="rotate takedown notify"
[[ -z "$redo" || " $auto_steps " == *" $redo "* ]] || usage_fail "--redo takes one of: $auto_steps"
[[ -z "$done_step" || " $own_steps " == *" $done_step "* ]] || usage_fail "--done takes one of: $own_steps"
[[ -z "$repo" || "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage_fail "not an owner/repo: $repo"
[[ -z "$id" || "$id" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || usage_fail "--id may use letters, digits, dot, dash and underscore: $id"
[[ -z "$since" || "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage_fail "--since needs a date, YYYY-MM-DD: $since"
[[ -z "$tlp" ]] || tlp_info "$tlp" >/dev/null || usage_fail "--tlp must be clear, green, amber, amber+strict or red"
[[ -z "$repo_path" || -d "$repo_path" ]] || usage_fail "--repo-path is not a folder: $repo_path"
[[ -n "$repo_path" ]] && repo_path="$(cd "$repo_path" && pwd)"

# ---------- The incident folder and its state ----------
# .respond holds one "key<TAB>value" per line; the last line for a key wins, so it is also a history.
if [[ -z "$dir" ]]; then
  [[ -n "$repo" ]] || usage_fail "name the repository, or give --dir to continue an incident"
  id="${id:-INC-$(date -u +%Y%m%d-%H%M)}"; dir="$id"
fi
state="$dir/.respond"
get() { [[ -f "$state" ]] && awk -F'\t' -v k="$1" '$1 == k { v = $2 } END { printf "%s", v }' "$state"; }
put() { printf '%s\t%s\n' "$1" "$2" >> "$state"; }

if [[ -f "$state" ]]; then
  [[ -z "$repo" || "$repo" == "$(get repo)" ]] || usage_fail "$dir is the incident for $(get repo), not $repo"
  repo="$(get repo)"; id="${id:-$(get id)}"
  tlp="${tlp:-$(get tlp)}"; since="${since:-$(get since)}"; repo_path="${repo_path:-$(get repo_path)}"
elif [[ -n "$repo" ]] && ((status_only == 0)) && [[ -z "$done_step" ]]; then
  [[ ! -e "$dir" || -z "$(ls -A "$dir")" ]] || usage_fail "$dir exists and is not an incident folder from leak respond"
  mkdir -p "$dir/logs"
  id="${id:-$(basename "$dir")}"
  [[ "$id" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || usage_fail "give --id: the folder name is not a usable incident ID"
  # The evidence includes a mirror of the leaked code and its secrets: keep it out of every repository.
  printf '# Incident evidence: it holds the leaked code and secrets. Never commit this folder.\n*\n' > "$dir/.gitignore"
  put repo "$repo"; put id "$id"
else
  usage_fail "no incident in $dir (start one with: leak respond <owner>/<repo>)"
fi
dir="$(cd "$dir" && pwd)"; state="$dir/.respond"
tlp="${tlp:-amber+strict}"
put tlp "$tlp"; [[ -n "$since" ]] && put since "$since"; [[ -n "$repo_path" ]] && put repo_path "$repo_path"
leak="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leak"
timeline="$dir/timeline.md"

bold=""; dim=""; off=""
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then bold=$'\e[1m'; dim=$'\e[2m'; off=$'\e[0m'; fi
now() { date -u '+%Y-%m-%d %H:%M'; }
note() {   # <step> <result> <detail>: one timeline row
  if [[ ! -f "$timeline" ]]; then
    printf '# Incident %s: timeline\n\nRepository: %s. All times UTC. Rows are added by `leak respond`; add your own as things happen\n(decisions, revocations, messages sent), so the report and the review have one record.\n\n| Time (UTC) | Step | Result | Detail |\n|---|---|---|---|\n' "$id" "$repo" > "$timeline"
  fi
  printf '| %s | %s | %s | %s |\n' "$(now)" "$1" "$2" "${3//|/\\|}" >> "$timeline"
}
finish() {   # <step> <result> <detail>: record a step's outcome in the state and the timeline
  put "$1" "$2"; put "$1_at" "$(now)"; put "$1_detail" "$3"; note "$1" "$2" "$3"
}
run_step() {   # <step> <title> <command...>: show the output, keep it in logs/<step>.log, return its exit code
  local step="$1" title="$2"; shift 2
  printf '\n%s==> %s%s\n' "$bold" "$title" "$off"
  mkdir -p "$dir/logs"
  local rc=0
  "$@" 2>&1 | tee "$dir/logs/$step.log" || rc=${PIPESTATUS[0]}
  return "$rc"
}
is_done() { case "$(get "$1")" in ok|found|incomplete) return 0 ;; *) return 1 ;; esac; }

# ---------- The steps ----------
step_snapshot() {
  local rc=0 snap forks mirror
  run_step snapshot "Snapshot the evidence before the repository disappears" "$leak" snapshot "$repo" "$dir/evidence" || rc=$?
  snap="$(sed -n 's/^Saved: //p' "$dir/logs/snapshot.log" | tail -n 1)"
  if [[ -n "$snap" && -d "$snap" ]]; then
    put snapshot_path "${snap#"$dir"/}"
    forks="$(jq 'length' "$snap/forks.json" 2>/dev/null || echo "?")"
    mirror="no mirror"; [[ -d "$snap/repo.git" ]] && mirror="full mirror"
    case "$rc" in
      0) finish snapshot ok "${snap#"$dir"/}: $mirror, $forks fork(s)" ;;
      *) finish snapshot incomplete "${snap#"$dir"/}: $mirror, $forks fork(s); see logs/snapshot.log" ;;
    esac
  else
    finish snapshot failed "nothing saved (exit $rc); see logs/snapshot.log"
  fi
}
step_scan() {
  local rc=0 src="$repo_path" snap n where
  snap="$(get snapshot_path)"
  [[ -n "$src" || -z "$snap" || ! -d "$dir/$snap/repo.git" ]] || src="$dir/$snap/repo.git"
  if [[ -z "$src" ]]; then
    finish scan failed "no copy to scan: the mirror could not be taken; run again with --repo-path <a clone>"; return
  fi
  run_step scan "Find every secret in the full history" "$leak" scan "$src" "$dir/secrets-report.json" || rc=$?
  where="$src"; [[ "$src" == "$dir/$snap/repo.git" ]] && where="the evidence mirror"
  case "$rc" in
    0) finish scan ok "no secrets in any commit of $where" ;;
    1) n="$(jq 'length' "$dir/secrets-report.json")"
       finish scan found "$n finding(s) of $(jq '[.[].RuleID] | unique | length' "$dir/secrets-report.json") type(s) in $where; values redacted" ;;
    *) finish scan failed "the scanner failed (exit $rc); see logs/scan.log" ;;
  esac
}
step_plan() {
  local rc=0
  if [[ "$(get scan)" != ok && "$(get scan)" != found ]]; then finish plan failed "needs a finished scan"; return; fi
  run_step plan "Plan the rotations, most dangerous first" "$leak" plan "$dir/secrets-report.json" --out "$dir" --id "$id" --tlp "$tlp" || rc=$?
  case "$rc" in
    0) finish plan ok "nothing to rotate" ;;
    1) finish plan found "$(jq -r '"\(.count) to rotate, starting with the \(.items[0].type)"' "$dir/rotation-plan.json") (rotation-plan.md)" ;;
    *) finish plan failed "exit $rc; see logs/plan.log" ;;
  esac
}
step_hunt() {
  local rc=0 hunt found unchecked what
  run_step hunt "Hunt for copies that survive deletion" "$leak" hunt ${since:+--since "$since"} --out "$dir/hunts" "$repo" || rc=$?
  hunt="$(ls -dt "$dir"/hunts/hunt_*/ 2>/dev/null | head -n 1)"; hunt="${hunt%/}"
  if [[ -z "$hunt" || ! -f "$hunt/REPORT.md" ]]; then finish hunt failed "no hunt report (exit $rc); see logs/hunt.log"; return; fi
  put hunt_path "${hunt#"$dir"/}"
  found="$(grep -c '^| .*| \*\*found\*\* |' "$hunt/REPORT.md" || true)"
  unchecked="$(grep -c '^| .*| not checked |' "$hunt/REPORT.md" || true)"
  what="$(grep '^| .*| \*\*found\*\* |' "$hunt/REPORT.md" | cut -d '|' -f 2 | sed 's/^ *//; s/ *$//' | head -n 3 | paste -sd ";" - | sed 's/;/; /g' || true)"
  # leak hunt exits 1 when it finds something even if some sources were not checked, so count both.
  case "$rc" in
    0|1|4)
      if ((unchecked > 0)); then
        finish hunt incomplete "$found item(s) need follow-up, $unchecked source(s) not checked (rate limits or outages: set GITHUB_TOKEN, then --redo hunt): ${hunt#"$dir"/}/REPORT.md"
      elif ((found > 0)); then finish hunt found "$found item(s) need follow-up (${what}): ${hunt#"$dir"/}/REPORT.md"
      else finish hunt ok "no copies found: ${hunt#"$dir"/}/REPORT.md"; fi ;;
    *) finish hunt failed "exit $rc; see logs/hunt.log" ;;
  esac
}
step_report() {
  local rc=0 hunt args=()
  hunt="$(get hunt_path)"
  if [[ -z "$hunt" || ! -d "$dir/$hunt" ]]; then finish report failed "needs a hunt"; return; fi
  [[ -f "$dir/secrets-report.json" ]] && args=(--scan "$dir/secrets-report.json")
  run_step report "Build the incident report for leadership" \
    "$leak" report "$dir/$hunt" "${args[@]}" --id "$id" --tlp "$tlp" --out "$dir/incident-report.html" || rc=$?
  if ((rc == 0)); then finish report ok "incident-report.html: fill in the highlighted fields"
  else finish report failed "exit $rc; see logs/report.log"; fi
}

# ---------- What the person does ----------
own_hint() {
  case "$1" in
    rotate) if [[ "$(get plan)" == found ]]; then
              jq -r '.items[:3][] | "             \(.n). \(.type) in \(.file): \(if .recipe then "leak rotate \(.recipe)" else "by hand, guide linked in the plan" end)"' "$dir/rotation-plan.json"
              echo "             The whole list: rotation-plan.md. Revoke each old value; a new one alone is not enough."
            else echo "             Nothing found to rotate. Still check by hand: .env, *.pem, *.pfx, *.tfvars, kubeconfigs."; fi ;;
    takedown) echo "             Ask the owner to delete it, or file a DMCA takedown listing every fork"
              echo "             (forks.json in the evidence; templates/takedown-request.md)." ;;
    notify) echo "             Manager, security and legal, and the owner of the code or data if it is not yours"
            echo "             (templates/notification-messages.md; the report: incident-report.html)." ;;
  esac
}
show_status() {
  local s mark when detail
  printf '\n%sIncident %s%s · %s · %s\n' "$bold" "$id" "$off" "$repo" "$dir"
  for s in snapshot scan plan rotate hunt takedown report notify; do
    when="$(get "${s}_at")"; detail="$(get "${s}_detail")"
    case "$(get "$s")" in
      ok|done) mark="✔" ;; found) mark="!" ;; incomplete) mark="~" ;; failed) mark="✘" ;; *) mark="·" ;;
    esac
    if [[ " $own_steps " == *" $s "* && -z "$(get "$s")" ]]; then
      printf '  %s %-9s %syours to do%s\n' "$mark" "$s" "$dim" "$off"; own_hint "$s"
    else
      printf '  %s %-9s %s  %s\n' "$mark" "$s" "${when:-not run}" "$detail"
    fi
  done
  echo
  echo "Timeline: $timeline   ✔ done  ! found something  ~ incomplete  ✘ failed  · to do"
}

if ((status_only)); then show_status; exit "$EXIT_OK"; fi
if [[ -n "$done_step" ]]; then
  finish "$done_step" "done" "marked done by hand"
  echo "Recorded: $done_step done at $(now) UTC."
  show_status; exit "$EXIT_OK"
fi
if [[ -n "$redo" ]]; then   # forget this step and every one after it, so they run again
  after=0
  for s in $auto_steps; do [[ "$s" == "$redo" ]] && after=1; ((after)) && put "$s" ""; done
  note "$redo" "redo" "asked to run it again"
fi

[[ -f "$timeline" ]] || note started ok "leak respond for $repo"
for s in $auto_steps; do
  if is_done "$s"; then printf '%s==> %s: done at %s%s\n' "$dim" "$s" "$(get "${s}_at")" "$off"; continue; fi
  "step_$s"
done
show_status
echo "Mark your steps when they are done:  leak respond --dir $dir --done rotate   (or takedown, notify)"
echo "Repeat the hunt in 7 days:           leak respond --dir $dir --redo hunt"
echo "The full runbook:                    https://aboutbilal.github.io/spillkit/docs/01-runbook.html"

for s in $auto_steps; do case "$(get "$s")" in failed|incomplete) exit "$EXIT_FAILED" ;; esac; done
for s in scan plan hunt; do [[ "$(get "$s")" == found ]] && exit "$EXIT_FOUND"; done
exit "$EXIT_OK"
