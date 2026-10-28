# Leaked a secret or code? The first 15 minutes

Print this, pin it, or keep it open during an incident. The full guide is in the [README](README.md).

| When | Do this | Not this |
|:-:|---|---|
| **0–2 min** | Say it out loud: tell your lead or security channel. Start a timeline with times in UTC | Quietly delete the commit and hope |
| **2–5 min** | If you control the copy and it was **public by mistake**, make it **private** (keeps evidence). Otherwise ask the owner for **Insights → Traffic** screenshots before anything is deleted | Delete first: you lose clone counts and the exact contents |
| **5–10 min** | **Rotate the most powerful secret first**: cloud keys, service accounts, database passwords. Revoke the old value, not just add a new one | Wait to "see if anyone used it" |
| **10–15 min** | Scan the **whole history** for the rest: `./leak scan <repo>`, then `./leak plan secrets-report.json` for the order to rotate them in | Trust that "it was only in one file" |
| **Then** | Remove copies (owner deletes, or DMCA with every fork) → `./leak hunt` → check logs from first push to rotation → notify | Treat deletion as the fix |

## Five rules that never change

1. **Public for a minute = stolen.** Attackers have used exposed keys within [five minutes](https://unit42.paloaltonetworks.com/malicious-operations-of-exposed-iam-keys-cryptojacking/).
2. **Rotation is the fix.** Deleting, rewriting history and takedowns only limit further spread.
3. **History counts.** A secret removed in a later commit is still in every earlier one.
4. **Never test a leaked key** to see if it works. Rotate it.
5. **Write it down as you go.** Times, actions, who did what. You will need it for the review and any notification.

## Who to call

| Need | Person or channel | Contact |
|---|---|---|
| Incident lead | | |
| Cloud admin (can rotate keys) | | |
| Database admin | | |
| Security | | |
| Legal / data protection | | |

*Fill this table in now, before you need it.*
