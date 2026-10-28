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
# Steps, in this order (deploy the new secret before revoking the old one):
#   check     who used the leaked credential, and when (read-only)
#   replace   create the new credential and put it in --store (not azure-storage-key)
#   disable   switch the leaked one off; can be undone (aws-key, gcp-sa-key)
#   delete    delete the leaked one for good (renew, for azure-storage-key)
# Options:
#   --store TARGET   where the new secret goes: aws-sm:<secret-id> (AWS Secrets Manager),
#                    azure-kv:<vault>/<name> (Azure Key Vault) or gcp-sm:<secret> (Secret Manager)
#   --yes            do not ask before disable, delete or renew (without it they ask on a terminal)
#   --log FILE       append each applied step to FILE (default: ./rotation-log.tsv); never values
# Exit:  0 done (or dry run printed), 2 bad arguments, missing CLI or not confirmed,
#        4 the provider refused or failed (the step did not complete)
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

recipe=""; user=""; key_id=""; app=""; account=""; group=""; which_key="key1"
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
  *) usage_fail "unknown recipe: $recipe (aws-key, azure-app-secret, gcp-sa-key, azure-storage-key)" ;;
esac

store_kind=""; store_ref=""
if [[ -n "$store" ]]; then
  store_kind="${store%%:*}"; store_ref="${store#*:}"
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
project="${account#*@}"; project="${project%%.*}"   # sa@PROJECT.iam.gserviceaccount.com
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
  esac
  echo
  echo "Being abused right now? Revoke first (disable, delete or renew) and accept the downtime."
  echo "Each applied step is logged with its time in $log, ready for the incident timeline."
}

# ---------- Applying a step ----------
fail() { echo "  failed: $1" >&2; log_step "$apply" failed ""; exit "$EXIT_FAILED"; }
run() { printf '  $ %s\n' "$*"; "$@"; }
log_step() {   # <step> <result> <new credential ID or "">: never a value
  [[ -f "$log" ]] || printf 'time_utc\trecipe\tcredential\tstep\tresult\tnew_credential\n' > "$log"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$recipe" "${key_id:-$which_key}@${user:-${app:-${account:-}}}" "$1" "$2" "$3" >> "$log"
}
confirm() {    # <action>: ask on the terminal unless --yes
  ((yes)) && return 0
  local token="${key_id:-$which_key}" answer
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
      if printf '%s' "$new" | jq -c '{AccessKeyId: .AccessKey.AccessKeyId, SecretAccessKey: .AccessKey.SecretAccessKey}' | store_put; then
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
for v in "${need[@]}"; do
  [[ -n "${!v}" ]] || usage_fail "--apply needs --${v//_/-} for $recipe"
done
if [[ "$apply" == replace ]]; then
  [[ -n "$store" ]] || usage_fail "replace needs --store, so the new secret goes straight into your secret store"
fi
for c in "$cli" jq ${store_kind:+"$(store_cli)"}; do
  command -v "$c" >/dev/null || usage_fail "missing: $c (install it and sign in first; 'leak doctor' lists what each command needs)"
done
[[ -d "$(dirname "$log")" ]] || usage_fail "log folder does not exist: $(dirname "$log")"
echo "==> $apply: $what"
apply_step
