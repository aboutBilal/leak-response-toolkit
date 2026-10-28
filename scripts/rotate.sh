#!/usr/bin/env bash
# Rotate one leaked credential with its provider's own CLI, one step at a time.
# Without --apply this is a dry run: it prints every step with the exact command and
# changes nothing. With --apply STEP it runs that one step, logs it with the time, and
# says what comes next. A new secret goes from the provider straight into your secret
# store through a pipe: never shown, never written to disk, never in a command line.
#
# Usage: leak rotate <recipe> [options] [--apply STEP [--store TARGET] [--yes]]
# Recipes and their options:
#   aws-key            --user NAME --key-id AKIA...      access key of an IAM user
#   azure-app-secret   --app APP-ID --key-id KEY-ID      client secret of an Entra ID app registration
#   gcp-sa-key         --account SA-EMAIL --key-id ID    key of a Google Cloud service account
#   azure-storage-key  --group RG --account NAME [--key key1|key2]   storage account key (default key1)
#   gitlab-token       --token-id ID [--project PATH | --group PATH] [--expires YYYY-MM-DD]
#                      personal, project or group access token; needs GITLAB_TOKEN (api scope,
#                      not the leaked token) and GITLAB_URL when self-managed
#   azure-devops-pat   --org ORG --authorization-id ID [--expires YYYY-MM-DD]
#                      your own personal access token; needs az login as that user
# Steps, in this order (deploy the new secret before revoking the old one):
#   check     who used the leaked credential, and when (read-only)
#   replace   create the new credential and put it in --store (aws-key, azure-app-secret, gcp-sa-key,
#             azure-devops-pat)
#   disable   switch the leaked one off; can be undone (aws-key, gcp-sa-key)
#   delete    delete the leaked one for good (renew, for azure-storage-key)
#   rotate    gitlab-token: GitLab revokes the leaked token and puts a new one in --store, in one call
#   revoke    gitlab-token, azure-devops-pat: revoke the leaked token (for gitlab-token, when a
#             replacement you made yourself is already deployed)
# Options:
#   --store TARGET   where the new secret goes: aws-sm:<secret-id> (AWS Secrets Manager),
#                    azure-kv:<vault>/<name> (Azure Key Vault) or gcp-sm:<secret> (Secret Manager)
#   --yes            do not ask before disable, delete, renew, rotate or revoke (without it they ask on a terminal)
#   --log FILE       append each applied step to FILE (default: ./rotation-log.tsv); never values
# Exit:  0 done (or dry run printed), 2 bad arguments, missing CLI or not confirmed,
#        4 the provider refused or failed (the step did not complete)
set -euo pipefail
set +x   # never trace: a traced run would print the new secret (bash -x leak rotate ...)
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

recipe=""; user=""; key_id=""; app=""; account=""; group=""; which_key="key1"
token_id=""; gl_project=""; expires=""; ref=""; org=""; auth_id=""
apply=""; store=""; yes=0; log="$PWD/rotation-log.tsv"
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --user) need_value "$1" "${2:-}"; user="$2"; shift 2 ;;
    --key-id) need_value "$1" "${2:-}"; key_id="$2"; shift 2 ;;
    --app) need_value "$1" "${2:-}"; app="$2"; shift 2 ;;
    --account) need_value "$1" "${2:-}"; account="$2"; shift 2 ;;
    --group) need_value "$1" "${2:-}"; group="$2"; shift 2 ;;
    --key) need_value "$1" "${2:-}"; which_key="$2"; shift 2 ;;
    --token-id) need_value "$1" "${2:-}"; token_id="$2"; shift 2 ;;
    --project) need_value "$1" "${2:-}"; gl_project="$2"; shift 2 ;;
    --expires) need_value "$1" "${2:-}"; expires="$2"; shift 2 ;;
    --org) need_value "$1" "${2:-}"; org="$2"; shift 2 ;;
    --authorization-id) need_value "$1" "${2:-}"; auth_id="$2"; shift 2 ;;
    --apply) need_value "$1" "${2:-}"; apply="$2"; shift 2 ;;
    --store) need_value "$1" "${2:-}"; store="$2"; shift 2 ;;
    --log) need_value "$1" "${2:-}"; log="$2"; shift 2 ;;
    --yes) yes=1; shift ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) if [[ -z "$recipe" ]]; then recipe="$1"; else echo "unexpected argument: $1" >&2; exit "$EXIT_USAGE"; fi; shift ;;
  esac
done
usage_fail() { echo "$1" >&2; echo "run 'leak rotate --help' for recipes and steps" >&2; exit "$EXIT_USAGE"; }
[[ -n "$recipe" ]] || usage_fail "usage: leak rotate <recipe> [options] [--apply STEP]"

# Each recipe: its CLI, its steps, a readable name, and the values it needs (validated before use).
case "$recipe" in
  aws-key)
    cli=aws; steps="check replace disable delete"
    what="AWS access key ${key_id:-<key-id>} of IAM user ${user:-<user>}"
    [[ -z "$user" || "$user" =~ ^[A-Za-z0-9+=,.@_-]{1,64}$ ]] || usage_fail "not an IAM user name: $user"
    [[ -z "$key_id" || "$key_id" =~ ^(AKIA|ASIA)[A-Z0-9]{16}$ ]] || usage_fail "not an AWS access key ID: $key_id"
    need=(user key_id) ;;
  azure-app-secret)
    cli=az; steps="check replace delete"
    what="client secret ${key_id:-<key-id>} of app registration ${app:-<app-id>}"
    [[ -z "$app" || "$app" =~ ^[0-9a-fA-F-]{36}$ ]] || usage_fail "--app needs the application (client) ID, a GUID: $app"
    [[ -z "$key_id" || "$key_id" =~ ^[0-9a-fA-F-]{36}$ ]] || usage_fail "--key-id needs the secret's key ID, a GUID: $key_id"
    need=(app key_id) ;;
  gcp-sa-key)
    cli=gcloud; steps="check replace disable delete"
    what="key ${key_id:-<key-id>} of service account ${account:-<sa>@<project>.iam.gserviceaccount.com}"
    [[ -z "$account" || "$account" =~ ^[a-z0-9-]+@[a-z0-9.-]+\.gserviceaccount\.com$ ]] || usage_fail "--account needs a service account email: $account"
    [[ -z "$key_id" || "$key_id" =~ ^[0-9a-f]{40}$ ]] || usage_fail "--key-id needs the 40-character key ID: $key_id"
    need=(account key_id) ;;
  azure-storage-key)
    cli=az; steps="check renew"
    what="$which_key of storage account ${account:-<account>} in resource group ${group:-<group>}"
    [[ -z "$account" || "$account" =~ ^[a-z0-9]{3,24}$ ]] || usage_fail "not a storage account name: $account"
    [[ -z "$group" || "$group" =~ ^[-A-Za-z0-9._()]{1,90}$ ]] || usage_fail "not a resource group name: $group"
    [[ "$which_key" =~ ^key[12]$ ]] || usage_fail "--key must be key1 or key2"
    need=(group account) ;;
  gitlab-token)
    cli=curl; steps="check rotate revoke"
    gl_path='^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$'
    [[ -z "$gl_project" || -z "$group" ]] || usage_fail "use --project or --group, not both (neither: a personal access token)"
    [[ -z "$gl_project" || ( "$gl_project" =~ $gl_path && ${#gl_project} -le 255 ) ]] || usage_fail "--project needs a project path or ID: $gl_project"
    [[ -z "$group" || ( "$group" =~ $gl_path && ${#group} -le 255 ) ]] || usage_fail "--group needs a group path or ID: $group"
    [[ -z "$token_id" || "$token_id" =~ ^[0-9]{1,12}$ ]] || usage_fail "--token-id needs the token's numeric ID (check without it lists them): $token_id"
    [[ -z "$expires" || "$expires" =~ ^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] || usage_fail "--expires needs a date, YYYY-MM-DD: $expires"
    # GitLab gives a rotated token one week unless told otherwise: default to 90 days.
    expires="${expires:-$(jq -nr 'now + 90 * 86400 | strftime("%Y-%m-%d")' 2>/dev/null || echo "<YYYY-MM-DD>")}"
    gl_base="$(gitlab_url)/api/v4"
    if [[ -n "$gl_project" ]]; then
      kind="project access token"; tokens_path="/projects/$(jq -rn --arg s "$gl_project" '$s|@uri')/access_tokens"
    elif [[ -n "$group" ]]; then
      kind="group access token"; tokens_path="/groups/$(jq -rn --arg s "$group" '$s|@uri')/access_tokens"
    else
      kind="personal access token"; tokens_path="/personal_access_tokens"
    fi
    what="GitLab $kind ${token_id:-<token-id>}${gl_project:+ of project $gl_project}${group:+ of group $group}"
    ref="${token_id}@${gl_project:-${group:-personal}}"
    need=(token_id) ;;
  azure-devops-pat)
    cli=az; steps="check replace revoke"
    [[ -z "$org" || "$org" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,49}$ ]] || usage_fail "--org needs the organisation name, as in dev.azure.com/<org>: $org"
    [[ -z "$auth_id" || "$auth_id" =~ ^[0-9a-fA-F-]{36}$ ]] || usage_fail "--authorization-id needs the token's authorization ID, a GUID (check lists them): $auth_id"
    [[ -z "$expires" || "$expires" =~ ^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] || usage_fail "--expires needs a date, YYYY-MM-DD: $expires"
    expires="${expires:-$(jq -nr 'now + 90 * 86400 | strftime("%Y-%m-%d")' 2>/dev/null || echo "<YYYY-MM-DD>")}"
    ado_base="https://vssps.dev.azure.com/${org:-<org>}/_apis/tokens/pats"
    what="Azure DevOps personal access token ${auth_id:-<authorization-id>} in ${org:-<org>}"
    ref="${auth_id}@${org}"
    need=(org auth_id) ;;
  *) usage_fail "unknown recipe: $recipe (aws-key, azure-app-secret, gcp-sa-key, azure-storage-key, gitlab-token, azure-devops-pat)" ;;
esac

store_kind=""; store_ref=""
if [[ -n "$store" ]]; then
  [[ "$store" == *:?* ]] || usage_fail "--store needs a target after the colon, such as aws-sm:<secret-id>"
  store_kind="${store%%:*}"; store_ref="${store#*:}"
  [[ "$store_ref" != -* ]] || usage_fail "--store target cannot start with -: $store_ref"
  case "$store_kind" in
    aws-sm) [[ "$store_ref" =~ ^[A-Za-z0-9/_+=.@:-]+$ && ${#store_ref} -le 2048 ]] || usage_fail "use --store aws-sm:<secret-id or ARN>" ;;
    azure-kv) [[ "$store_ref" =~ ^[A-Za-z0-9-]{3,24}/[A-Za-z0-9-]{1,127}$ ]] || usage_fail "use --store azure-kv:<vault>/<secret-name>" ;;
    gcp-sm) [[ "$store_ref" =~ ^[A-Za-z0-9/_-]+$ && ${#store_ref} -le 255 ]] || usage_fail "use --store gcp-sm:<secret> or gcp-sm:projects/<p>/secrets/<secret>" ;;
    *) usage_fail "--store must start with aws-sm:, azure-kv: or gcp-sm:" ;;
  esac
fi
store_cli() { case "$store_kind" in aws-sm) echo aws ;; azure-kv) echo az ;; gcp-sm) echo gcloud ;; esac; }
store_label() {
  case "$store_kind" in
    aws-sm) echo "AWS Secrets Manager secret $store_ref" ;;
    azure-kv) echo "Key Vault ${store_ref%%/*}, secret ${store_ref#*/}" ;;
    gcp-sm) echo "Secret Manager secret $store_ref" ;;
    *) echo "<your secret store>" ;;
  esac
}
case "$account" in   # the project the service account lives in
  *@appspot.gserviceaccount.com) project="${account%@*}" ;;                 # PROJECT@appspot (App Engine default)
  *-compute@developer.gserviceaccount.com) project="${account%-compute@*}" ;;  # NUMBER-compute@developer (Compute default)
  *) project="${account#*@}"; project="${project%%.*}" ;;                   # sa@PROJECT.iam.gserviceaccount.com
esac
p() { if [[ -n "${!1}" ]]; then printf '%s' "${!1}"; else printf '<%s>' "$2"; fi; }

# ---------- Dry run: every step with its command ----------
dry_run() {
  local u k a s g
  u="$(p user user)"; k="$(p key_id key-id)"; a="$(p app app-id)"; s="$(p account sa-email)"; g="$(p group group)"
  echo "Rotate the $what"
  echo "Dry run: nothing was changed. Run each step with --apply STEP, in order."
  echo
  case "$recipe" in
    aws-key) cat <<EOF
1. check    Who used the key, when, and whether AWS has quarantined it (read-only)
              aws iam get-access-key-last-used --access-key-id $k
              aws iam list-access-keys --user-name $u
              aws iam list-attached-user-policies --user-name $u
2. replace  Create a new key and put it in $(store_label) (needs --store)
              aws iam create-access-key --user-name $u   → piped into the store, never shown
3. (you)    Deploy the new key everywhere the old one is used
4. disable  Switch the leaked key off; undo with --status Active if something breaks
              aws iam update-access-key --user-name $u --access-key-id $k --status Inactive
5. delete   Delete the leaked key for good
              aws iam delete-access-key --user-name $u --access-key-id $k
EOF
    ;;
    azure-app-secret) cat <<EOF
1. check    The app's secrets: key IDs, names and expiry, never values (read-only)
              az ad app credential list --id $a
            Usage: Entra ID → Sign-in logs → Service principal sign-ins, filtered by this app
2. replace  Add a new secret alongside the old one; put it in $(store_label) (needs --store)
              az ad app credential reset --id $a --append --display-name rotated-<date> --years 1   → piped into the store
3. (you)    Deploy the new secret everywhere the old one is used
4. delete   Remove the leaked secret; anything still using it stops working
              az ad app credential delete --id $a --key-id $k
EOF
    ;;
    gcp-sa-key) cat <<EOF
1. check    The account's keys and when this key was last used to authenticate (read-only)
              gcloud iam service-accounts keys list --iam-account $s
              gcloud policy-intelligence query-activity --activity-type=serviceAccountKeyLastAuthentication --project $(p project project)
2. replace  Create a new key and put it in $(store_label) (needs --store)
              gcloud iam service-accounts keys create /dev/stdout --iam-account $s   → piped into the store, never shown
            Better: workload identity federation, so there is no key file to leak next time
3. (you)    Deploy the new key everywhere the old one is used
4. disable  Switch the leaked key off; undo with keys enable if something breaks
              gcloud iam service-accounts keys disable $k --iam-account $s
5. delete   Delete the leaked key for good
              gcloud iam service-accounts keys delete $k --iam-account $s --quiet
EOF
    ;;
    azure-storage-key) cat <<EOF
1. check    Key names and when each was created, never values (read-only)
              az storage account keys list -g $g -n $(p account account) --query "[].{key:keyName, created:creationTime}" -o table
            Usage: the account's Insights or diagnostic logs (StorageRead, StorageWrite)
2. (you)    Point consumers at the other key first, or accept that they fail until updated
3. renew    Regenerate $which_key: the leaked value, and every SAS signed with it, stops working at once
              az storage account keys renew -g $g -n $(p account account) --key $which_key -o none
            With --store, the new connection string goes into $(store_label)
EOF
    ;;
    gitlab-token) cat <<EOF
1. check    The token's name, scopes, last use and expiry, never its value (read-only)
              GET $gl_base$tokens_path/$(p token_id token-id)
            Without --token-id it lists the active tokens with their IDs, to find the leaked one
2. rotate   GitLab revokes the leaked token and issues a new one, expiring $expires, in one call;
            the new one goes into $(store_label) (needs --store, which must already exist)
              POST $gl_base$tokens_path/$(p token_id token-id)/rotate?expires_at=$expires   → piped into the store, never shown
3. (you)    Deploy the new token at once: anything still using the old one fails until then
   revoke   Instead of rotate, for no downtime: make a replacement in GitLab yourself, deploy it, then revoke
              DELETE $gl_base$tokens_path/$(p token_id token-id)
EOF
    ;;
    azure-devops-pat) cat <<EOF
1. check    Your tokens in $(p org org): names, scopes and expiry, never values (read-only)
              GET $ado_base?displayFilterOption=active   (as the user signed in with az login)
            Azure DevOps revokes tokens it finds on public GitHub by itself: look for Token.PatSystemRevokeEvent
            in Organization settings → Auditing. Token use is not logged there; check the owner's activity
2. replace  A new token with the same scope, for this organisation only, expiring $expires;
            straight into $(store_label) (needs --store)
              POST $ado_base   → piped into the store, never shown
3. (you)    Deploy the new token everywhere the old one is used
4. revoke   Revoke the leaked token; anything still using it stops working
              DELETE $ado_base?authorizationId=$(p auth_id authorization-id)
EOF
    ;;
  esac
  echo
  echo "Being abused right now? Revoke first (disable, delete, renew or revoke) and accept the downtime."
  echo "Each applied step is logged with its time in $log, ready for the incident timeline."
}

# ---------- Applying a step ----------
fail() { echo "  failed: $1" >&2; log_step "$apply" failed ""; exit "$EXIT_FAILED"; }
run() { printf '  $ %s\n' "$*"; "$@"; }
log_step() {   # <step> <result> <new credential ID or "">: never a value
  [[ -f "$log" ]] || printf 'time_utc\trecipe\tcredential\tstep\tresult\tnew_credential\n' > "$log"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$recipe" "${ref:-${key_id:-$which_key}@${user:-${app:-${account:-}}}}" "$1" "$2" "$3" >> "$log"
}
confirm() {    # <action>: ask on the terminal unless --yes
  ((yes)) && return 0
  local token="${key_id:-${token_id:-${auth_id:-$which_key}}}" answer
  if [[ ! -t 0 ]]; then
    echo "refusing to $1 without confirmation: run it on a terminal, or add --yes" >&2
    exit "$EXIT_USAGE"
  fi
  read -r -p "  $1 the $what. Type $token to confirm: " answer
  [[ "$answer" == "$token" ]] || { echo "  not confirmed; nothing changed" >&2; exit "$EXIT_USAGE"; }
}
store_put() {  # the new secret arrives on stdin and goes straight to the store
  case "$store_kind" in
    aws-sm) aws secretsmanager put-secret-value --secret-id "$store_ref" --secret-string file:///dev/stdin >/dev/null ;;
    azure-kv) az keyvault secret set --vault-name "${store_ref%%/*}" --name "${store_ref#*/}" --file /dev/stdin --encoding utf-8 -o none ;;
    gcp-sm) gcloud secrets versions add "$store_ref" --data-file=- >/dev/null ;;
  esac
}
store_check() {   # the store exists and answers, read from its metadata only (never its value)
  case "$store_kind" in
    aws-sm) aws secretsmanager describe-secret --secret-id "$store_ref" --query ARN --output text >/dev/null ;;
    azure-kv) az keyvault secret list-versions --vault-name "${store_ref%%/*}" --name "${store_ref#*/}" --maxresults 1 --query "[0].id" -o tsv >/dev/null ;;
    gcp-sm) gcloud secrets describe "$store_ref" --format 'value(name)' >/dev/null ;;
  esac
}
gl_api() {   # <method> <path>: GITLAB_TOKEN goes in a header on stdin, never argv. Prints the body, then the status on its own line.
  printf 'header = "PRIVATE-TOKEN: %s"\n' "${GITLAB_TOKEN//\"/}" \
    | curl -s --max-time 60 -K - -X "$1" -w '\n%{http_code}' "$gl_base$2" || printf '\n000'
}
http_status() { printf '%s' "${1##*$'\n'}"; }
http_body() { printf '%s' "${1%$'\n'*}"; }
ado_api() {   # <method> <query> [json]: the Entra token goes in a header on stdin, never argv. Body, then status.
  local args=(-s --max-time 60 -K - -X "$1" -w '\n%{http_code}' -H "Content-Type: application/json")
  [[ -n "${3:-}" ]] && args+=(--data-binary "$3")   # names, scope and expiry only: no secret
  printf 'header = "Authorization: Bearer %s"\n' "${ado_token//\"/}" \
    | curl "${args[@]}" "$ado_base?$2${2:+&}api-version=7.1-preview.1" || printf '\n000'
}
ado_sign_in() {   # an Entra token for Azure DevOps, for the user signed in to az (PATs belong to a user)
  ado_token="$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv 2>/dev/null)" \
    && [[ -n "$ado_token" ]] || fail "could not get an Azure DevOps token: az login as the token's owner (service principals cannot manage PATs)"
}
refusal() {   # <response>: why the service said no, from its error message (errors never carry a token)
  local msg; msg="$(http_body "$1" | jq -r '.message // .error // empty | tostring' 2>/dev/null | head -c 200)"
  printf 'HTTP %s%s' "$(http_status "$1")" "${msg:+: $msg}"
}

apply_step() {
  local new="" id=""
  case "$recipe:$apply" in
    aws-key:check)
      run aws iam get-access-key-last-used --access-key-id "$key_id" --output table || fail "could not read the key's last use"
      run aws iam list-access-keys --user-name "$user" --output table || fail "could not list the user's keys"
      run aws iam list-attached-user-policies --user-name "$user" \
        --query "AttachedPolicies[?starts_with(PolicyName, 'AWSCompromisedKeyQuarantine')].PolicyName" --output text \
        || fail "could not list the user's policies"
      echo "  A quarantine policy above means AWS found the key in public. Check CloudTrail from its first commit to now."
      log_step check ok "" ;;
    aws-key:replace)
      printf '  $ aws iam create-access-key --user-name %s   (kept in memory, piped to the store)\n' "$user"
      new="$(aws iam create-access-key --user-name "$user" --output json)" \
        || fail "could not create a key (a user can have two at most: delete an unused one first)"
      id="$(printf '%s' "$new" | jq -r '.AccessKey.AccessKeyId')"
      if printf '%s' "$new" | jq -cj '{AccessKeyId: .AccessKey.AccessKeyId, SecretAccessKey: .AccessKey.SecretAccessKey}' | store_put; then
        new=""; log_step replace ok "$id"
        echo "  New key $id is in $(store_label). Deploy it everywhere the old key is used, then --apply disable."
      else
        new=""; echo "  Could not store the new key, so it is being deleted again: $id" >&2
        aws iam delete-access-key --user-name "$user" --access-key-id "$id" || echo "  delete it by hand: aws iam delete-access-key --user-name $user --access-key-id $id" >&2
        fail "the store refused the new key; nothing else changed"
      fi ;;
    aws-key:disable)
      confirm "Disable"
      run aws iam update-access-key --user-name "$user" --access-key-id "$key_id" --status Inactive || fail "could not disable the key"
      log_step disable ok ""; echo "  Disabled. If nothing broke, --apply delete. To undo: the same command with --status Active." ;;
    aws-key:delete)
      confirm "Delete"
      run aws iam delete-access-key --user-name "$user" --access-key-id "$key_id" || fail "could not delete the key"
      log_step delete ok ""; echo "  Deleted. Record the time in the rotation plan." ;;

    azure-app-secret:check)
      run az ad app credential list --id "$app" --query "[].{keyId:keyId, name:displayName, start:startDateTime, end:endDateTime}" -o table \
        || fail "could not list the app's secrets"
      echo "  Usage: Entra ID → Sign-in logs → Service principal sign-ins, filtered by this app."
      log_step check ok "" ;;
    azure-app-secret:replace)
      local name; name="rotated-$(date -u +%Y%m%d-%H%M%S)"
      printf '  $ az ad app credential reset --id %s --append --display-name %s --years 1   (kept in memory, piped to the store)\n' "$app" "$name"
      new="$(az ad app credential reset --id "$app" --append --display-name "$name" --years 1 --query password -o tsv)" \
        || fail "could not add a secret to the app"
      id="$(az ad app credential list --id "$app" --query "[?displayName=='$name'].keyId | [0]" -o tsv 2>/dev/null || true)"
      if printf '%s' "$new" | store_put; then
        new=""; log_step replace ok "${id:-$name}"
        echo "  New secret $name${id:+ ($id)} is in $(store_label). Deploy it, then --apply delete."
      else
        new=""; echo "  Could not store the new secret, so it is being removed again: $name" >&2
        [[ -n "$id" ]] && az ad app credential delete --id "$app" --key-id "$id" \
          || echo "  remove it by hand: az ad app credential list --id $app, then credential delete" >&2
        fail "the store refused the new secret; the leaked one is unchanged"
      fi ;;
    azure-app-secret:delete)
      confirm "Delete"
      run az ad app credential delete --id "$app" --key-id "$key_id" || fail "could not delete the secret"
      log_step delete ok ""; echo "  Deleted. Record the time in the rotation plan." ;;

    gcp-sa-key:check)
      run gcloud iam service-accounts keys list --iam-account "$account" \
        --format "table(name.basename(), validAfterTime, disabled, keyType)" || fail "could not list the account's keys"
      run gcloud policy-intelligence query-activity --activity-type=serviceAccountKeyLastAuthentication --project "$project" \
        || echo "  (last use needs the Policy Analyzer API; or check the audit logs for this key ID)"
      log_step check ok "" ;;
    gcp-sa-key:replace)
      printf '  $ gcloud iam service-accounts keys create /dev/stdout --iam-account %s   (kept in memory, piped to the store)\n' "$account"
      new="$(gcloud iam service-accounts keys create /dev/stdout --iam-account "$account")" \
        || fail "could not create a key (the organisation may block key creation: prefer workload identity federation)"
      id="$(printf '%s' "$new" | jq -r '.private_key_id // empty')"
      if printf '%s' "$new" | store_put; then
        new=""; log_step replace ok "$id"
        echo "  New key $id is in $(store_label). Deploy it, then --apply disable."
      else
        new=""; echo "  Could not store the new key, so it is being deleted again: $id" >&2
        [[ -n "$id" ]] && gcloud iam service-accounts keys delete "$id" --iam-account "$account" --quiet \
          || echo "  delete it by hand: gcloud iam service-accounts keys list --iam-account $account" >&2
        fail "the store refused the new key; nothing else changed"
      fi ;;
    gcp-sa-key:disable)
      confirm "Disable"
      run gcloud iam service-accounts keys disable "$key_id" --iam-account "$account" || fail "could not disable the key"
      log_step disable ok ""; echo "  Disabled. If nothing broke, --apply delete. To undo: keys enable." ;;
    gcp-sa-key:delete)
      confirm "Delete"
      run gcloud iam service-accounts keys delete "$key_id" --iam-account "$account" --quiet || fail "could not delete the key"
      log_step delete ok ""; echo "  Deleted. Record the time in the rotation plan." ;;

    azure-storage-key:check)
      run az storage account keys list -g "$group" -n "$account" --query "[].{key:keyName, created:creationTime}" -o table \
        || fail "could not list the account's keys"
      echo "  Usage: the account's Insights or diagnostic logs (StorageRead, StorageWrite)."
      log_step check ok "" ;;
    azure-storage-key:renew)
      confirm "Regenerate"
      run az storage account keys renew -g "$group" -n "$account" --key "$which_key" -o none || fail "could not regenerate the key"
      log_step renew ok ""
      if [[ -n "$store" ]]; then
        local slot=primary; [[ "$which_key" == key2 ]] && slot=secondary
        az storage account show-connection-string -g "$group" -n "$account" --key "$slot" --query connectionString -o tsv | store_put \
          || fail "the key was regenerated but the store refused the new connection string"
        echo "  Regenerated. The new connection string is in $(store_label)."
      else
        echo "  Regenerated. Consumers read the new key from the portal, Key Vault or a managed identity."
      fi ;;
    gitlab-token:check)
      local resp
      if [[ -z "$token_id" ]]; then
        printf '  $ GET %s\n' "$gl_base$tokens_path?per_page=100"
        resp="$(gl_api GET "$tokens_path?per_page=100")"
        [[ "$(http_status "$resp")" == 200 ]] || fail "could not list the tokens ($(refusal "$resp"))"
        http_body "$resp" | jq -r '(["ID","NAME","SCOPES","LAST USED","EXPIRES"] | @tsv),
          (.[] | select(.active) | [(.id|tostring), .name, (.scopes|join(",")), (.last_used_at // "never"), (.expires_at // "never")] | @tsv)' | table
        echo "  Active tokens only, first 100. Run check again with --token-id ID for the leaked one."
      else
        printf '  $ GET %s\n' "$gl_base$tokens_path/$token_id"
        resp="$(gl_api GET "$tokens_path/$token_id")"
        [[ "$(http_status "$resp")" == 200 ]] || fail "could not read the token ($(refusal "$resp"))"
        http_body "$resp" | jq -r '"  name:       \(.name)", "  scopes:     \(.scopes | join(", "))",
          "  state:      \(if .revoked then "revoked" elif .active then "active" else "inactive (expired)" end)",
          "  created:    \(.created_at // "unknown")",
          "  last used:  \(.last_used_at // "never")\(if (.last_used_ips // []) != [] then " from \(.last_used_ips | join(", "))" else "" end)",
          "  expires:    \(.expires_at // "never")"'
        echo "  Usage before that: the audit events of the user, group or project the token belongs to."
      fi
      log_step check ok "" ;;
    gitlab-token:rotate)
      confirm "Rotate (and at once revoke)"
      printf '  Checking %s first: a revoked token cannot be brought back\n' "$(store_label)"
      store_check || fail "could not read $(store_label): it must exist and you need read access to its metadata. Nothing changed"
      printf '  $ POST %s   (the new token is kept in memory, piped to the store)\n' "$gl_base$tokens_path/$token_id/rotate?expires_at=$expires"
      local resp why; resp="$(gl_api POST "$tokens_path/$token_id/rotate?expires_at=$expires")"
      if [[ "$(http_status "$resp")" != 200 ]]; then
        why="$(refusal "$resp")"; resp=""
        fail "GitLab did not rotate the token ($why); the leaked one is unchanged"
      fi
      id="$(http_body "$resp" | jq -r '.id // empty')"
      if ! http_body "$resp" | jq -e '.token | type == "string" and length > 0' >/dev/null; then
        resp=""; fail "GitLab answered without a new token: check the token list, the leaked one may be revoked already"
      fi
      if http_body "$resp" | jq -j '.token' | store_put; then
        resp=""; log_step rotate ok "$id"
        echo "  The leaked token is revoked. Its replacement ($id, expires $expires) is in $(store_label)."
        echo "  Deploy it now: anything still using the old token fails until it reads the new one."
      else
        resp=""; echo "  Could not store the new token, so it is being revoked too: $id" >&2
        [[ -n "$id" && "$(http_status "$(gl_api DELETE "$tokens_path/$id")")" == 204 ]] \
          || echo "  revoke it by hand: GitLab → Access tokens, token $id" >&2
        fail "the store refused the new token. The leaked token is revoked; make its replacement in GitLab by hand"
      fi ;;
    gitlab-token:revoke)
      confirm "Revoke"
      printf '  $ DELETE %s\n' "$gl_base$tokens_path/$token_id"
      local resp; resp="$(gl_api DELETE "$tokens_path/$token_id")"
      [[ "$(http_status "$resp")" == 204 ]] || fail "could not revoke the token ($(refusal "$resp"))"
      log_step revoke ok ""; echo "  Revoked. Record the time in the rotation plan." ;;
    azure-devops-pat:check)
      ado_sign_in
      local resp
      if [[ -z "$auth_id" ]]; then
        printf '  $ GET %s\n' "$ado_base?displayFilterOption=active"
        resp="$(ado_api GET "displayFilterOption=active&isSortAscending=false")"
        [[ "$(http_status "$resp")" == 200 ]] || fail "could not list the tokens ($(refusal "$resp"))"
        http_body "$resp" | jq -r '(["AUTHORIZATION ID","NAME","SCOPE","EXPIRES"] | @tsv),
          (.patTokens[] | [.authorizationId, .displayName, .scope, (.validTo // "")[:10]] | @tsv)' | table
        echo "  Active tokens of the signed-in user, first page. Run check again with --authorization-id for the leaked one."
      else
        printf '  $ GET %s\n' "$ado_base?authorizationId=$auth_id"
        resp="$(ado_api GET "authorizationId=$auth_id")"
        [[ "$(http_status "$resp")" == 200 ]] || fail "could not read the token ($(refusal "$resp"))"
        http_body "$resp" | jq -r '.patToken | "  name:       \(.displayName)", "  scope:      \(.scope)",
          "  created:    \(.validFrom // "unknown")", "  expires:    \(.validTo // "unknown")",
          "  for:        \(if .targetAccounts then "this organisation" else "all organisations (global: retired by Microsoft on 2026-12-01)" end)"'
        echo "  Already revoked by Azure DevOps? Organization settings → Auditing: Token.PatSystemRevokeEvent, Token.PatPublicDiscoveryEvent."
      fi
      log_step check ok "" ;;
    azure-devops-pat:replace)
      ado_sign_in
      local resp old body
      resp="$(ado_api GET "authorizationId=$auth_id")"
      [[ "$(http_status "$resp")" == 200 ]] || fail "could not read the leaked token to copy its scope ($(refusal "$resp"))"
      old="$(http_body "$resp")"
      body="$(printf '%s' "$old" | jq -c --arg d "$(date -u +%Y-%m-%d)" --arg to "${expires}T23:59:59Z" \
        '{displayName: ((.patToken.displayName // "token") + " (rotated " + $d + ")")[:200], scope: .patToken.scope, validTo: $to, allOrgs: false}')"
      printf '  $ POST %s   (same scope; the new token is kept in memory, piped to the store)\n' "$ado_base"
      resp="$(ado_api POST "" "$body")"
      if [[ "$(http_status "$resp")" != 200 ]] || ! http_body "$resp" | jq -e '.patTokenError == "none" and (.patToken.token | type == "string" and length > 0)' >/dev/null 2>&1; then
        local why; why="$(http_body "$resp" | jq -r '.patTokenError // empty' 2>/dev/null || true)"; why="${why:-$(refusal "$resp")}"; resp=""
        fail "Azure DevOps did not create a token ($why; an organisation policy may limit scopes or lifetime); nothing changed"
      fi
      id="$(http_body "$resp" | jq -r '.patToken.authorizationId')"
      if http_body "$resp" | jq -j '.patToken.token' | store_put; then
        resp=""; log_step replace ok "$id"
        echo "  New token $id (expires $expires) is in $(store_label). Deploy it everywhere the old one is used, then --apply revoke."
      else
        resp=""; echo "  Could not store the new token, so it is being revoked again: $id" >&2
        [[ "$(http_status "$(ado_api DELETE "authorizationId=$id")")" =~ ^20[04]$ ]] \
          || echo "  revoke it by hand: User settings → Personal access tokens" >&2
        fail "the store refused the new token; the leaked one is unchanged"
      fi ;;
    azure-devops-pat:revoke)
      confirm "Revoke"
      ado_sign_in
      printf '  $ DELETE %s\n' "$ado_base?authorizationId=$auth_id"
      local resp; resp="$(ado_api DELETE "authorizationId=$auth_id")"
      [[ "$(http_status "$resp")" =~ ^20[04]$ ]] || fail "could not revoke the token ($(refusal "$resp"))"
      log_step revoke ok ""; echo "  Revoked. Record the time in the rotation plan." ;;
    *)
      [[ "$apply" == deploy ]] && usage_fail "deploying the new secret is yours to do: there is no --apply deploy"
      usage_fail "$recipe has no step '$apply' (steps: $steps)" ;;
  esac
}

if [[ -z "$apply" ]]; then
  dry_run
  exit "$EXIT_OK"
fi
[[ " $steps " == *" $apply "* ]] || usage_fail "$recipe has no step '$apply' (steps: $steps)"
[[ "$recipe:$apply" == gitlab-token:check ]] && need=()   # without --token-id, check lists the tokens
[[ "$recipe:$apply" == azure-devops-pat:check ]] && need=(org)
for v in "${need[@]}"; do
  [[ -n "${!v}" ]] || usage_fail "--apply needs --${v//_/-} for $recipe"
done
if [[ "$apply" == replace || "$apply" == rotate ]]; then
  [[ -n "$store" ]] || usage_fail "$apply needs --store, so the new secret goes straight into your secret store"
fi
if [[ "$recipe" == gitlab-token ]]; then
  [[ -n "${GITLAB_TOKEN:-}" ]] || usage_fail "gitlab-token needs GITLAB_TOKEN: a token with the api scope that may manage this one (not the leaked token)"
  [[ "$gl_base" == https://* ]] || usage_fail "GITLAB_URL must start with https://"
  [[ "$expires" != "<"* ]] || usage_fail "could not work out a default expiry: give --expires YYYY-MM-DD"
fi
if [[ "$recipe" == azure-devops-pat && "$expires" == "<"* ]]; then usage_fail "could not work out a default expiry: give --expires YYYY-MM-DD"; fi
for c in "$cli" jq ${store_kind:+"$(store_cli)"}; do
  command -v "$c" >/dev/null || usage_fail "missing: $c (install it and sign in first; 'leak doctor' lists what each command needs)"
done
[[ -d "$(dirname "$log")" ]] || usage_fail "log folder does not exist: $(dirname "$log")"
echo "==> $apply: $what"
apply_step
