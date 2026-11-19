---
name: clickthrough
description: Use when handing work to the user to try, review or pick (task end, fix, merge-ready PR, deploy, variants), or when they ask for a link, where to see a change, or say they can't find it.
---

# Clickthrough

Hand finished work over so the user can click through it on their own, in one short message. In the user's words: *„proveď mě tím. potřebuju odkazy na local, co se přidalo, co se odebralo, na co se kouknout, co zkusit… nechci dlouhej seznam, mam hodně práce."*

A handover is **one live link per place to look, to the exact record in the right state, checked by you, plus a few lines on what changed**.

## When

- A user-visible change is done: end of task, after a fix, after an iteration on feedback, after a deploy.
- A PR is green and merge-ready. "CI passed + merge command" with no link is the most common miss; the user always comes back with "dej mi link".
- You ask the user to pick a variant or decide something, including status pings and re-pings that still wait on the answer.
- The user asks: "dej mi link", "kde to uvidím", "co se změnilo", "proveď mě tím", "i need a link to see it".
- The user says "nevidím to" / "jak to tam uvidím", often with a screenshot. First find the screen they are on (from the screenshot), then link that exact place. If visibility depends on data ("shown only when an open deliverable exists"), say the condition and hand over a record where it shows.

Backend, perf or data change? Link the 1–2 pages where the effect shows most, with action + before → after (measured, e.g. „Report za říjen: ~4 s → ~0,4 s"), or say plainly "Vzhled se nezměnil". A change that adds queries or heavier rendering gets one measured speed line too.

No app at all (library, CLI, docs, CI config)? Skip this skill; give a normal 2–3 sentence report.

## Step 1 — Pick the surface

| Situation | Surface |
|---|---|
| Built change, "vyzkoušet" | **Local running app** (default) |
| Choosing between variants | Variants behind a URL param in the real app when the surrounding page matters (layout); a Storybook story per variant when the states are hard to reach |
| Direction already agreed | Real app. Never leave agreed work in Storybook only ("chci to i v appce") |
| Change on several surfaces (admin + mobile + scan + PDF/e-mail) | One link per surface; say which surfaces are **not** touched |
| Deployed, or only real data shows it | Stage/prod deep link + which account |
| Many decisions at once, a live surface that keeps shifting (lazy images, motion), another role's flow, or screenshots requested | One HTML page (an Artifact where available) with settled, cropped, highlighted screenshots and pick buttons |

Small change → 1–2 deep links, no page. Screenshots answer "how does it look", never "where can I try it": give the live link too. Link format, login, native mobile and env gotchas: [references/surfaces.md](references/surfaces.md).

## Step 2 — Prepare data and accounts

The user must not hunt for a record or an account.

- **One concrete record per state** the change treats differently, already in that state. Prefer the record from the ticket or client screenshot; if it no longer shows the state, say so and give one that does.
- **Local:** seed, shift dates to today, click earlier steps yourself. No permission needed. **Stage:** test records are fine; find the user's own stage account, assign the record to them, copy the real case's setup. **Prod / client-facing envs:** read only, warn about the one click with real side effects.
- **Account:** always say which account/role to log in as and how (dev login, account switcher, seed user). Never paste passwords; point to the dev login or the seed file.
- **Scan/hardware flows:** also hand over what gets scanned: QR codes/barcodes of the seeded items on one HTML page, scannable from a screen and printable.

Details (backups, freshness, expiry, revert, PDFs): [references/data.md](references/data.md).

## Step 3 — Verify every link

Before the message goes out, for every link:

1. The server is running **now** and serves this worktree's build (right port, routing param, not a stale server from another branch).
2. The URL returns 200 **and** the page renders the change for the named account. Open it in a browser tool or check the DOM; a 200 on an SPA shell proves nothing.
3. The URL is complete: no `…`, no bare root or port, no tree path, no "change the end of the URL". Non-ASCII story ids percent-encoded.
4. Look at it as the user would, in their real state (already logged in, existing session). Mention only problems you saw (layout, slowness, wrong role).

Can't verify something (their login, magic link, real device)? Say what you checked and what you didn't. If a later step kills the server (DB reset, merge cleanup), say the link is dead.

## Step 4 — Write the handover

Language of the user's latest message (usually Czech), addressed to them directly. Use the domain words and the UI labels as shown on screen („Nerealizováno"), never code identifiers (`notRealized`) or internal labels.

**Must stay:** the links with a state label each, login/role, 1–3 lines on what changed, one `Data:` line if you changed data, anything with real side effects. **Budget:** ≤ 15 lines; 3 lines for a small change. Over budget → drop, in this order: what you checked (unless something failed), qualifying conditions the link label already says, untouched surfaces, cleanup offers. The references list what *may* be said, not what must.

```markdown
**Kde:** <jen lokál / PR „Krátký název" (#N) / stage>
- <Záznam ve stavu X>: <plná URL>
- <Záznam ve stavu Y / mobil>: <plná URL>
Přihlášení: <účet/role a jak se přepnout>.
Data: <co jsem připravil/změnil, platí do …>. Vrátím, až skončíš. | Kód: beze změny (jen u ukázky)

**Co zkusit:**
1. <předpoklad, pokud je: přihlas se přes „Účty“, obnov tab>
2. <klik> → <co uvidíš>

**Co se změnilo:** Přidáno <…> · Změněno <dřív → teď> · Odebráno <…> · Navíc (nechtěl jsi, vratné) <…>

**Dřív:** <u opravy: co bylo špatně, konkrétní hodnotou>. Stará verze: <stejný záznam na prod>.

**Pozor:** <neověřeno, lokálně se neukáže, odchylky od plánu, největší riziko mimo feature>

**Od tebe potřebuju:**
1. <Krátký název> (<obrazovka>): <jak to je teď>. <otázka>?
   [A](URL) <co se stane> (doporučuju) · [B](URL) <co se stane>. <vratné / nevratné>. Stačí písmeno.
```

- **Fix:** link first; steps walk the old problem's path on the same record and show it fixed; then one **Dřív:** line with the concrete wrong value.
- **Variant pick:** the message is only the decision block: what is being decided, a „Dnes" link to today's state, one unique URL + one line per variant (same cases on each, shared fixes in all), recommendation, "Stačí písmeno." No other sections, no link twice.
- **Each decision stands on its own** (UIs cut titles off): screen, current state, what each answer does, link per option. A visual choice goes out as rendered variants, never as a prose question.
- **Long multi-task write-up:** a document or per-task checklist the user opens; chat keeps its link and the top clicks. Multi-topic update: one block per topic with its own links.

Real good and bad handovers: [references/examples.md](references/examples.md).

## Step 5 — Re-hand after every round

Each iteration, re-pick and deploy gets a fresh handover with fresh links. After a deploy: a deployed-env link to a record that shows the change now, plus "obnov tab, pokud byl otevřený před nasazením". When the user picks, act on it; don't send the picked variant back for re-approval.

## Hard rules

- **Links live in this message.** Never "link above", "odkazy jsou v minulé zprávě", "v jiném nástroji", or links only in tool output. Every place you name (screen, record, project, option) gets its link here. Asks already tracked elsewhere need not be re-listed, but any you mention carry their links.
- **Prep is not the handover.** After seeding data or creating accounts, the same message still carries links, login, what changed and what to try.
- **Names, not numbers.** No bare `#123`, `5a`, `D3` without a short plain name and a link.
- **No bare local file paths** (`/private/tmp/…png`, `file://`). A page that must stay local (real personal data): serve it on localhost or open it for the user yourself, and say it is open.
- **Never hand over a command to run** to see the change ("spusť `bun run storybook`"). Start it, check it, then hand over.
- **One dev stack per task.** Several surfaces of one stack are fine; never make the user choose between two servers of the same surface.
