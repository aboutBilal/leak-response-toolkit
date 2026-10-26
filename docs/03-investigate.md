# 03 · Investigate: was a leaked secret used?

**Window:** from the **first public push** (see `metadata.json` from the snapshot, and the earliest pushed commit) until the **moment each secret was revoked**. A copied key keeps working until it is revoked, even after the repo is deleted.

**Look for:** unfamiliar IPs or countries · new resources (especially large VMs or GPU nodes) · new users, keys or role assignments · large reads or exports · cost spikes.

---

## 📬 Free early warnings

Before querying anything, check the inboxes of your cloud and SaaS admins. GitHub's **secret scanning partner programme** forwards keys found in public repos to their issuers (Microsoft, AWS, Google, Slack, Stripe and many more), and some revoke them automatically. An alert email confirms the key was seen publicly and gives you a timestamp.

---

## ☁️ Azure

### Service principal sign-ins (Log Analytics, Entra diagnostic logs enabled)

```kusto
AADServicePrincipalSignInLogs
| where TimeGenerated between (datetime(<first-push-utc>) .. datetime(<revoked-at-utc>))
| where AppId == "<app-id>"
| summarize SignIns = count(), Failures = countif(ResultType != "0")
    by IPAddress, Location, ResourceDisplayName
| order by SignIns desc
```

Any IP that is not your pipelines, servers or office is a finding.

### What the identity changed (Activity Log)

```kusto
AzureActivity
| where TimeGenerated between (datetime(<first-push-utc>) .. now())
| where Caller == "<app-id-or-object-id>"
| where OperationNameValue endswith "/WRITE" or OperationNameValue endswith "/DELETE"
| project TimeGenerated, OperationNameValue, ResourceGroup, _ResourceId, CallerIpAddress, ActivityStatusValue
| order by TimeGenerated asc
```

Without Log Analytics, the CLI covers the last 90 days:

```bash
az monitor activity-log list --start-time <first-push-utc> --caller <app-id-or-object-id> \
  --query "[].{time:eventTimestamp, op:operationName.value, rg:resourceGroupName, ip:claims.ipaddr}" -o table
```

### New role assignments anywhere in the subscription

```bash
az role assignment list --all \
  --query "[?createdOn>='<first-push-utc>'].{who:principalName, role:roleDefinitionName, scope:scope, at:createdOn}" -o table
```

### Storage accounts accessed with the account key

```kusto
StorageBlobLogs
| where TimeGenerated between (datetime(<first-push-utc>) .. datetime(<revoked-at-utc>))
| where AuthenticationType in ("AccountKey", "SAS")
| summarize Requests = count(), Bytes = sum(ResponseBodySize) by CallerIpAddress, OperationName, AccountName
| order by Bytes desc
```

### Cost

*Cost Management → Cost analysis*, daily granularity, grouped by **resource**, for the window. Mining shows up as compute you did not create.

---

## 🟧 AWS

```bash
# Everything the leaked key did (CloudTrail event history covers 90 days)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=<AKIA-key-id> \
  --start-time <first-push-utc> \
  --query "Events[].{time:EventTime, event:EventName, source:EventSource}" --output table
```

Also check **every region** for new EC2 instances, IAM users and access keys created in the window, and *Billing → Cost Explorer* by service.

---

## 🗄️ Databases

| Engine | Where logins show up |
|---|---|
| PostgreSQL | `log_connections = on` server logs; Azure: `PostgreSQLLogs` / `AzureDiagnostics` |
| Azure SQL / SQL Server | Auditing logs (`SQLSecurityAuditEvents`); failed and successful logins with client IP |
| MySQL | General or audit log; Azure: `AzureDiagnostics` with `Category == "MySqlAuditLogs"` |

Look for client IPs outside your network and for unusually large `SELECT` volumes.

---

## 🐙 GitHub-side facts

| Fact | Where |
|---|---|
| When it became public | Snapshot `metadata.json` (`created_at`, `pushed_at`), and the owner's account security log |
| Who cloned it | **Insights → Traffic** (owner only, last 14 days, **gone when the repo is deleted**) |
| Who copied it | Forks (`list-forks.sh`); stars and watchers in the snapshot |

---

## 📝 Write it down

For each secret: *seen used? yes/no* · *by which IPs* · *what was done* · *evidence location*. "No evidence of use" is a valid finding, but only for the logs you actually had. Say which logs were **not** available.
