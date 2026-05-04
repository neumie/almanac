---
name: client-update-email
description: Use when creating a client-facing email summarizing project work. Gathers changes from git history (typically deploy branch diffs), reads the actual code to understand each change, proposes a tiered outline grouped by client-perceived impact, and generates a markdown draft with HTML conversion and optional screenshot capture. Use this whenever the user says write client email, summarize what's new, client update, or what changed since last deploy.
---

# Client Update Email

Generate a client-facing email summarizing project work. Five phases: gather → outline → draft → screenshots → output.

## Inputs

Ask the user for these if not already provided in conversation context:

- **Scope:** What to compare. Default: `deploy/prod..deploy/stage`. Alternatives: date range, specific PRs, specific commits, or any two git refs.
- **Tone:** Formal, informal, friendly-professional, or custom description.
- **Language:** English, Czech, or other.

## Phase 1 — Deep Gather

### Step 1: Get change list

Run these commands, adapting refs to the user's scope:

- Commit list: !`git log deploy/prod..deploy/stage --oneline --no-merges 2>/dev/null || echo "SCOPE_ERROR: adjust refs"`
- Diff stat: !`git diff deploy/prod..deploy/stage --stat 2>/dev/null`
- Merged PRs: !`gh pr list --state merged --limit 50 --json number,title,body,url 2>/dev/null`

If the default refs don't exist, ask the user which branches or refs to compare.

### Step 2: Deep-read each change

For each PR or logical group of commits:

1. Read the full diff for that change (`git diff <commit-range> -- <files>`).
2. Read the source files that changed — components, routes, handlers, templates — enough to understand the feature in context.
3. Read PR descriptions and linked issues (`gh issue view <N>`) if available.
4. Synthesize an internal summary per change:
   - What it does from the **client's perspective** (not the developer's)
   - Which part of the app it touches
   - Which routes/pages/URLs are involved (save these for Phase 4 screenshots)
   - How visible the change is to the client

Spend time here. Read the code. Understand what was built, not just what files changed.

### Step 3: Present raw list

Show the synthesized list to the user:

```
Found N changes:

1. [Short name] — [What it does for the client]. Touches [area]. Route: /path
2. [Short name] ��� [What it does for the client]. Touches [area]. Route: /path
...
```

Ask: **"Anything missing or wrong? You can add changes that aren't in git (design work, config changes, manual deployments)."**

Wait for confirmation before proceeding to Phase 2.

## Phase 2 — Editable Outline

### Tiering

Group and tier the confirmed changes by **client-perceived impact** — not code complexity, not diff size:

- **Big:** Things the client will notice or asked for. New features, visible UI changes, workflow changes. A one-line copy change on the homepage can be "big." A 500-line refactor the client never sees is not.
- **Medium:** Improvements that affect their experience but aren't headline items. Performance gains, UX polish, minor new capabilities.
- **Small:** Worth mentioning but not dwelling on. Bug fixes, stability improvements, behind-the-scenes work.

### Grouping

Cluster related changes under a single heading. Three commits touching export become one "Export improvements" item.

### Present the outline

```
## Big Changes
- [Feature Name] — 1-line description of what it does for the client
- [Feature Name] — ...

## Medium Changes
- [Feature Name] — ...

## Small Changes
- [Fix/improvement] — ...
```

Tell the user they can:
- **Move** items between tiers
- **Remove** items entirely
- **Reorder** items within a tier
- **Rename** or rewrite descriptions
- **Add** items not in the original list

Wait for the user to approve the outline before proceeding to Phase 3.

## Phase 3 — Draft Generation

Create the output directory:

```bash
mkdir -p client-updates/screenshots
```

Write the email as markdown to `client-updates/<YYYY-MM-DD>-update.md` using the approved outline.

### Email structure

Follow this structure exactly. Apply the user's chosen **tone** and **language** consistently throughout.

```
# What's New — [date or period]

[Opening paragraph — friendly summary of the update, 1-2 sentences.]

## Big Changes

### [Feature Name]
[2-3 sentences: what it does and why it matters to the client.]
**Where to find it:** [Navigation path, URL, or description — whatever communicates clearest]

[Screenshot: <descriptive-filename.png> — <what to capture and what state to show>]

---

### [Next Feature]
...

## Medium Changes

### [Feature Name]
[1-2 sentences.]
**Where to find it:** [Navigation path or URL]

[Screenshot: <filename.png> — <description>]  ← only if the change is visual

---

## Small Changes

- **[Name]** — one-line description
- **[Name]** — one-line description

[Closing line — tone-appropriate sign-off.]
```

### Rules

- Big changes: full treatment — description + where to find it + screenshot placeholder.
- Medium changes: description + where to find it. Screenshot placeholder only if the change is visual.
- Small changes: bullet list only. No screenshots, no "where to find it."
- No emojis unless the chosen tone calls for them.
- Screenshot placeholders use the format: `[Screenshot: filename.png — description of what to capture]`

After writing the draft, show it to the user. Wait for approval or edits before proceeding to Phase 4.

## Phase 4 — Screenshot Capture

### Step 1: Dev server

Check if a local dev server is already running by testing common ports (3000, 3001, 5173, 8080):

```bash
lsof -i :3000 -i :3001 -i :5173 -i :8080 -sTCP:LISTEN 2>/dev/null
```

If not running, detect the start command from `package.json` (look for `dev`, `start`, or `serve` scripts) and start it. Wait for it to be ready before proceeding.

### Step 2: Plan captures

For each screenshot placeholder in the draft, propose a capture plan. Use the route and component knowledge from Phase 1:

```
Screenshot captures:

1. [filename.png] — Navigate to http://localhost:<port>/path → click "Tab Name" → scroll to section
2. [filename.png] — Navigate to http://localhost:<port>/other-path → open modal via "Button Text"
...
```

The skill already knows which routes and components are involved from the Phase 1 deep-read. Use that knowledge to plan the navigation steps.

Ask user to **confirm or adjust** the capture plan. Some screenshots may need specific data or login state — the user should flag these.

### Step 3: Execute captures

For each planned screenshot, use browser automation tools:

1. Navigate to the URL on the local dev server.
2. Perform click, scroll, wait, or other interaction steps to reach the right visual state.
3. Capture a screenshot.
4. Save to `client-updates/screenshots/<descriptive-filename>.png`.

### Step 4: Review

Show the user which screenshots were captured and their file paths. The user can:
- Ask to **recapture** any that aren't good enough (different viewport, different state, etc.)
- **Skip** any and replace manually later
- **Accept** and move to output

Wait for approval before proceeding to Phase 5.

## Phase 5 — Output

### Generate HTML

Convert the markdown draft to HTML. The HTML must look like a **normal composed email** — not a newsletter, not a marketing template.

Styling rules:
- Inline all CSS (email clients strip `<style>` tags)
- Use `<b>` or `<strong>` for headings — not styled `<h1>`/`<h2>` tags
- Simple `<p>` paragraphs
- `<hr>` between sections
- `[Screenshot: filename.png]` markers stay as plain text — the user drags images into the email client manually
- No colored backgrounds, no fancy layout, no web fonts
- The email should look like something a human composed in a mail app

Save to `client-updates/<YYYY-MM-DD>-update.html`.

### Final output

Report what was produced:

```
Done. Files in client-updates/:

  Markdown: <date>-update.md (for editing)
  HTML:     <date>-update.html (open in browser → select all → paste into Mail)
  Screenshots: screenshots/<name>.png (drag into Mail at marked positions)

Workflow: open the HTML in a browser, Cmd+A, Cmd+C, paste into macOS Mail. Then drag each screenshot from the screenshots/ folder to replace the [Screenshot: ...] markers.
```
