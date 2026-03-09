---
name: webapp-testing
description: Use when testing web applications with Playwright, including visual inspection, interaction testing, and end-to-end validation of dynamic web pages. Use this whenever the user wants to test a web app, verify frontend behavior, capture screenshots, or debug UI issues.
metadata:
  upstream: anthropics/skills/webapp-testing
  upstream-sha: 4726215301db64a0cc4d41fc3219c61f37a30f4a
  adapted-date: "2026-03-09"
---

# Web Application Testing

Test local web applications using native Python Playwright scripts.

**Helper script:** `scripts/with_server.py` — manages server lifecycle (supports multiple servers). Run with `--help` first.

## Decision Tree

```
User task → Is it static HTML?
    ├─ Yes → Read HTML file directly to identify selectors
    │         ├─ Success → Write Playwright script using selectors
    │         └─ Fails/Incomplete → Treat as dynamic (below)
    │
    └─ No (dynamic webapp) → Is the server already running?
        ├─ No → Use scripts/with_server.py helper
        └─ Yes → Reconnaissance-then-action (below)
```

## Using with_server.py

**Single server:**
```bash
python scripts/with_server.py --server "npm run dev" --port 5173 -- python your_automation.py
```

**Multiple servers (backend + frontend):**
```bash
python scripts/with_server.py \
  --server "cd backend && python server.py" --port 3000 \
  --server "cd frontend && npm run dev" --port 5173 \
  -- python your_automation.py
```

## Automation Script Pattern

Servers are managed by the helper — your script only needs Playwright logic:

```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    page.goto('http://localhost:5173')
    page.wait_for_load_state('networkidle')  # CRITICAL: wait for JS
    # ... your automation logic
    browser.close()
```

## Reconnaissance-Then-Action

1. **Inspect rendered DOM:**
   ```python
   page.screenshot(path='/tmp/inspect.png', full_page=True)
   content = page.content()
   page.locator('button').all()
   ```
2. **Identify selectors** from inspection results
3. **Execute actions** using discovered selectors

## Common Pitfall

Don't inspect the DOM before waiting for `networkidle` on dynamic apps. Always `page.wait_for_load_state('networkidle')` first.

## Best Practices

- Use `sync_playwright()` for synchronous scripts
- Always close the browser when done
- Use descriptive selectors: `text=`, `role=`, CSS selectors, or IDs
- Add waits: `page.wait_for_selector()` or `page.wait_for_timeout()`
- Use bundled scripts as black boxes — `--help` first, don't read source
