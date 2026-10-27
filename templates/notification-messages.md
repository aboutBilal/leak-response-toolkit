# Notification messages

Ready-to-adapt messages for the people you need to tell. Keep every message **factual, short and dated**: what happened, what you have done, what you need from them, when they will hear next. Never include a secret value, even a revoked one.

> [!TIP]
> Send the first message early with what you know, and say when the next update comes. A short message on time beats a complete one a day late.

---

## 1 · Internal: first alert to leadership and security

**Subject:** Security incident: `<repository or system>` exposed publicly. Containment in progress

> At `<time UTC>` we learned that `<what: e.g. source code / credentials>` from `<repository or system>` was publicly accessible on `<where>` from approximately `<start>` to `<end>`.
>
> **Done so far:** `<e.g. public copy removed, N credentials rotated>`
> **In progress:** `<e.g. remaining rotations, log review, search for copies>`
> **Not yet known:** `<e.g. whether any credential was used, whether personal data was included>`
>
> Incident lead: `<name>`. Next update: `<time>`.

---

## 2 · Affected customer or data owner

**Subject:** Security notice regarding `<project or service>`

> We are writing to inform you of a security incident affecting `<project or service>`.
>
> **What happened:** On `<date>`, `<plain description, e.g. a copy of the project's source code was published to a public repository>` for approximately `<duration>`.
>
> **What was involved:** `<code / configuration / credentials / personal data: be specific>`
>
> **What we have done:** `<removed the copy; rotated all credentials; reviewed access logs from <start> to <end>; searched public sources for copies: none found / found and removed>`
>
> **What we found:** `<e.g. no evidence that any credential was used>`
>
> **What you may need to do:** `<nothing / rotate keys you manage / watch for …>`
>
> **What we are changing:** `<prevention measures>`
>
> We are sorry this happened. `<name, role>` is your contact for any questions: `<email>`. We will send a final report by `<date>`.

Check with legal before sending: contracts and regulations (for example GDPR) can set the deadline, the recipients and the required content.

---

## 3 · The person who caused the leak

Keep it private, calm and practical. The goal is removal and facts, not blame; consequences are a separate conversation for management or HR.

> Hi `<name>`, the repository `<url>` on your account contains `<project>` code, which must not be public. Please delete it now (Settings → Delete this repository) and let me know when it is done.
>
> Before deleting, could you also send screenshots of **Insights → Traffic** for that repository, and tell me roughly when it was created and made public? That helps us understand who may have seen it.
>
> Thanks. I'll follow up separately about next steps.

---

## 4 · Someone who reported the leak

> Thank you for reporting this. We have `<removed the content and rotated the affected credentials>`. Please delete any copy you kept. We appreciate you telling us; it made a real difference to how fast we could act.

---

## 5 · Status update (repeat until closed)

> **Update `<n>` · `<time UTC>`** · Status: `<Investigating / Contained / Monitoring / Closed>`
>
> Since the last update: `<changes>`
> Open items: `<what remains, with owners>`
> Next update: `<time>`
