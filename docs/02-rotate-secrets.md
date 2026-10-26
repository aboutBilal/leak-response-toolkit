# 02 · Rotate and revoke, per secret type

**Pattern for every secret:** create the new one → deploy it everywhere it is used → **revoke the old one** → record the time.

If the leaked secret is actively being abused, reverse the order: **revoke first** and accept the downtime.

Everything in `<angle brackets>` is a placeholder.

---

## ☁️ Azure

### Service principal / app registration secret

```bash
# See the app's current secrets (key IDs and expiry, never values)
az ad app credential list --id <app-id> -o table

# Add a new secret alongside the old one
az ad app credential reset --id <app-id> --append --display-name "rotated-$(date +%F)" --years 1

# After updating every consumer (Key Vault, pipelines, app settings): remove the leaked one
az ad app credential delete --id <app-id> --key-id <leaked-key-id>
```

Better still: replace the secret with a **managed identity** or **workload identity federation** (OIDC), so there is no secret to leak next time.

### Storage account keys

```bash
# Every SAS token signed with this key stops working too
az storage account keys renew -g <rg> -n <account> --key key1
az storage account keys renew -g <rg> -n <account> --key key2

# If user-delegation SAS tokens leaked
az storage account revoke-delegation-keys -g <rg> -n <account>
```

### Cosmos DB, Service Bus, Event Hubs, Redis

```bash
az cosmosdb keys regenerate -g <rg> -n <account> --key-kind primary
az servicebus namespace authorization-rule keys renew -g <rg> --namespace-name <ns> -n <rule> --key PrimaryKey
az eventhubs namespace authorization-rule keys renew -g <rg> --namespace-name <ns> -n <rule> --key PrimaryKey
az redis regenerate-keys -g <rg> -n <cache> --key-type Primary
```

### Azure SQL admin password

```bash
az sql server update -g <rg> -n <server> --admin-password '<new-password>'
```

### Azure DevOps personal access token

*User settings → Personal access tokens → Revoke.* Organisation admins can revoke any user's tokens from *Organization settings*.

---

## 🟧 AWS

```bash
# When was the key last used, and for what service?
aws iam get-access-key-last-used --access-key-id <AKIA-key-id>

# New key, then disable and delete the leaked one
aws iam create-access-key --user-name <user>
aws iam update-access-key --user-name <user> --access-key-id <AKIA-key-id> --status Inactive
aws iam delete-access-key  --user-name <user> --access-key-id <AKIA-key-id>
```

If AWS has already attached the `AWSCompromisedKeyQuarantine` policy to the user, that is a confirmation the key was found publicly.

---

## 🐙 GitHub

| Secret | Revoke at |
|---|---|
| Personal access token | *Settings → Developer settings → Personal access tokens* |
| Deploy key | *Repo → Settings → Deploy keys* |
| GitHub App private key | *App settings → Private keys → Delete* (generate a new one first) |
| Actions secrets that were also in the repo | *Repo or org → Settings → Secrets and variables* → update |

---

## 🗄️ Databases

```sql
-- PostgreSQL
ALTER ROLE <app_user> WITH PASSWORD '<new-password>';

-- SQL Server / Azure SQL (contained or server login)
ALTER LOGIN <app_user> WITH PASSWORD = '<new-password>';

-- MySQL
ALTER USER '<app_user>'@'%' IDENTIFIED BY '<new-password>';
```

Then check for logins or roles you do not recognise, and narrow firewall rules to known addresses.

---

## 🔑 SSH keys and certificates

```bash
# New key pair
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_<service>_<account> -C "<user>@<host> <service> $(date +%F)"

# On every server that trusted the leaked key: remove its line
grep -n '<leaked-key-comment-or-fingerprint>' ~/.ssh/authorized_keys
```

TLS private keys (`.pem`, `.pfx`, `.key`): **revoke the certificate** with the issuing CA and issue a new one with a new key. Reusing the key with a new certificate does not help.

---

## 🧾 Application secrets

| Secret | Rotation | Side effect |
|---|---|---|
| JWT / session signing key | New key; accept old **and** new briefly if you can, then drop the old | Users are logged out |
| Webhook signing secret | Rotate on both sender and receiver | Brief failed deliveries |
| Encryption key (data at rest) | New key **plus re-encrypting** data | Plan it; it is a migration |
| SMTP / email API key | Regenerate in the provider | None |
| Payment provider key | Roll in the provider dashboard; most support an overlap period | None if overlap used |

---

## 🧭 Order of operations, when there are many

1. Anything that can **create resources or read customer data**.
2. Anything with **billing** attached.
3. Anything that grants **further access** (SSH, CI, deploy keys).
4. The rest.

Keep a table as you go: secret · where it was used · rotated at (UTC) · old one revoked at (UTC) · by whom. It becomes part of the timeline.
