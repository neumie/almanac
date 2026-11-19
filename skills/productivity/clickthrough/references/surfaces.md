# Surfaces, login and env gotchas

## Which surface

- **"Vyzkoušet" means the real running app** with the real flow (save, upload, PDF, e-mail sandbox). Storybook links for a "can I try it" request get bounced: "chci link na local aplikaci. ne storybook."
- **Storybook is for choosing**: variants, edge states that are hard to set up (Sunday, multi-day, failed save), component states. Once a variant is picked and built, hand over the app.
- **Variants in the real app** behind a URL param (`?toggleVariant=2`) beat Storybook for layout calls, because the surrounding page is real.
- **Escalation the user went through once**: screenshots → Storybook → local app → stage under their own login. Start as high on that ladder as the work allows.
- **Stage/prod** after deploy, or when only real data shows the case. Never write to prod; warn about clicks with real side effects.
- **HTML page (Artifact where the host offers it)** for: many decisions at once (previews, recommended pick marked, one-click choice, "copy choices" button so the answer can be pasted back), a live surface that keeps shifting (lazy-loaded images, motion: use settled screenshots and a short video), flows on another role's surface, or when screenshots were requested. Pages with real personal data stay off Artifacts: serve them from the scratchpad over localhost (a static server you start and check) or open them for the user, and say they are open.
- **Preview vs app:** say where the preview differs from the real app: width (dialog 512 px in the app vs 720 px in the story), states reachable only in Storybook because of role or data, mock vs real data.
- **Variants that look alike** at default size: one side-by-side comparison link plus the one action that shows the difference („zúž okno pod 1000 px").
- **Variant URLs** stay unique and stable: the user often answers by pasting the URL back.
- **Long write-up** (multi-task PR, 10+ checks): a document opened in the user's viewer, or a checklist per task (what changed, login as whom, link, steps, known limits). Chat keeps only the link and the top clicks.

## Links

- Full URL, clickable, in the final message text. Long URLs may go in a code block so they don't get mangled.
- Deep: record id, tab param (`?projectTab=commercial`, `?tab=activities`), story id with the representative populated state (`--busy`, not `--empty`).
- Worktree routing: if the dev setup routes by worktree (e.g. `?_hatch=<worktree>`), put the param in every link.
- Percent-encode non-ASCII characters in Storybook story ids (Czech diacritics break the click otherwise).
- A URL param the page ignores (an id copied from the ticket URL that the page doesn't filter by) makes the link look wrong. Drop it or explain it.
- If the exact spot can't be deep-linked (state in sessionStorage, a tab without a param), say so and give the one or two clicks to get there, with the expected count or label.
- Below the fold? Say where on the page to look.
- Markdown links with the state name as text (`[Inventura zrušená](…)`) keep a long list scannable.
- Before/after: same record on prod (old code) next to local (new code), or a record created before the change next to one created after.
- Localhost links work only on the user's machine while the server runs. If they might open it elsewhere (phone, client), use stage/preview or a page.

## Server checks

- Verify in the user's real state where it differs from a fresh test user (already logged in, existing session, data on their device). Any precondition (log in once via „Účty", hard refresh, narrow the window) is step 1 of „Co zkusit", never a closing remark.

- Check right before the handover, not from memory. Old "server běží" claims go stale.
- Confirm the port serves **this** worktree's build: port collisions (another project's Storybook on the default port), a second stale server on a neighbouring port, Vite bound to `[::1]` so `127.0.0.1` fails.
- Fresh worktrees often lack gitignored generated files: the first load shows an error overlay. Open it yourself.
- New CSS classes not showing → restart the dev server/Storybook before handing over.
- Rebase or DB reset breaks the running server or wipes seeded data: re-seed and re-check, or say the link is dead.
- Background processes you started for the test (trigger.dev dev, workers, tunnels): list them and offer to stop them.

## Login

- Say whether login is needed and as whom: "otevře se jako lokální admin", "Pokračovat jako výchozí uživatel", DevBar "Login", the "Účty" switcher in mobile.
- Role-gated features: name the role that sees it and why it matters (admin sees everything, so a role change can't be checked as admin).
- Verify as the role/account you name. Check which user the browser session is actually signed in as.
- Stage with magic link / their own account: the agent can't log in; say so and verify with HTTP + data queries.
- Temporary local accounts: list who → what for (a short table works), offer to delete them afterwards.
- Never paste real passwords of non-local accounts.

## Mobile web

- Tell them to narrow the browser to phone width, or give device-mode instructions.
- Mention dev-only overlays that cover fields (dev account button).

## Native mobile

- The simulator/device runs this worktree's build (Metro/Expo on the right port).
- Deep link via the app scheme (`myapp://projects/<id>`) or the Expo URL, opened by you first (`xcrun simctl openurl booted …`). No deep link? Give the one or two taps from the home screen.
- Say whether you checked on a simulator, a device, or not at all.
