---
name: webapp-testing
description: Use when testing web applications with agent-browser, including visual inspection, interaction testing, and end-to-end validation of dynamic web pages. Use this whenever the user wants to test a web app, verify frontend behavior, capture screenshots, or debug UI issues.
compatibility: Requires agent-browser (npx agent-browser) for browser automation.
---

# Web Application Testing

Manually test web applications by navigating them with agent-browser. Open pages, inspect what rendered, interact with elements, and verify behavior — all through direct CLI commands.

## Workflow

1. **Start the app** if it isn't already running
2. **Open the page** and wait for it to load
3. **Inspect** — screenshot and snapshot to understand what's on screen
4. **Interact** — click, fill, type to exercise the feature
5. **Verify** — screenshot again, check state, read content to confirm behavior

## Opening a Page

```bash
npx agent-browser open http://localhost:5173
npx agent-browser wait --load networkidle    # CRITICAL: wait for JS to finish
```

Always wait for `networkidle` before doing anything else on dynamic apps.

## Inspecting

```bash
npx agent-browser screenshot /tmp/page.png   # see what rendered
npx agent-browser snapshot                    # accessibility tree with @refs
npx agent-browser get text "main"             # read text content
npx agent-browser get html                    # full page HTML
npx agent-browser eval "document.title"       # run arbitrary JS
```

`snapshot` returns an accessibility tree where every element has a `@ref` identifier. Use these refs to target elements precisely.

## Interacting

```bash
npx agent-browser click "button"              # CSS selector
npx agent-browser click @ref                  # accessibility ref from snapshot
npx agent-browser fill "input[name='email']" "test@example.com"
npx agent-browser type "#search" "query"      # character by character
npx agent-browser press Enter
npx agent-browser select "#country" "Canada"
npx agent-browser check "#agree"
npx agent-browser scroll down 500
npx agent-browser hover ".menu-trigger"
```

## Verifying

```bash
npx agent-browser screenshot /tmp/after.png
npx agent-browser is visible ".success-message"
npx agent-browser is enabled "button[type='submit']"
npx agent-browser get text ".result"
npx agent-browser get count ".list-item"
npx agent-browser console                     # check for errors
npx agent-browser errors                      # page errors only
```

## Mobile Testing

```bash
npx agent-browser set device "iPhone 15"
npx agent-browser open http://localhost:5173
npx agent-browser wait --load networkidle
npx agent-browser screenshot /tmp/mobile.png
```

## Best Practices

- Always wait for `networkidle` before inspecting dynamic pages
- Use `snapshot` for element discovery — `@ref` identifiers are the most reliable selectors
- Screenshot after each significant action to verify visual state
- Use `console` and `errors` to catch JS issues that aren't visible on screen
- For multi-step flows, inspect between steps — don't assume the next state
