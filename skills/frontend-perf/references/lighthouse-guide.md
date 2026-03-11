# Lighthouse Guide

## CLI Usage

```bash
# Basic performance audit
npx lighthouse <url> --only-categories=performance --output=json --output-path=report.json

# Mobile (default) vs Desktop
npx lighthouse <url> --preset=perf --form-factor=mobile
npx lighthouse <url> --preset=perf --form-factor=desktop

# Headless Chrome
npx lighthouse <url> --chrome-flags="--headless=new"

# Multiple runs for stability (median)
npx lighthouse <url> --preset=perf -n 3 --output=json
```

## Programmatic Node.js API

```javascript
import lighthouse from 'lighthouse';
import * as chromeLauncher from 'chrome-launcher';

const chrome = await chromeLauncher.launch({ chromeFlags: ['--headless'] });
const result = await lighthouse(url, {
  port: chrome.port,
  onlyCategories: ['performance'],
  formFactor: 'mobile',
  screenEmulation: { mobile: true, width: 412, height: 823 },
  throttling: {
    cpuSlowdownMultiplier: 4,
    downloadThroughputKbps: 1600,
    uploadThroughputKbps: 750,
    rttMs: 150,
  },
});
console.log(result.lhr.categories.performance.score * 100);
await chrome.kill();
```

## Key Metrics in Report

| Metric | Weight | Good | JSON Path |
|--------|--------|------|-----------|
| FCP | 10% | < 1.8s | `audits.first-contentful-paint` |
| SI | 10% | < 3.4s | `audits.speed-index` |
| LCP | 25% | < 2.5s | `audits.largest-contentful-paint` |
| TBT | 30% | < 200ms | `audits.total-blocking-time` |
| CLS | 25% | < 0.1 | `audits.cumulative-layout-shift` |

## Performance Budgets

Create `budget.json`:
```json
[{
  "resourceSizes": [
    { "resourceType": "script", "budget": 300 },
    { "resourceType": "stylesheet", "budget": 50 },
    { "resourceType": "image", "budget": 500 },
    { "resourceType": "total", "budget": 1000 }
  ],
  "resourceCounts": [
    { "resourceType": "third-party", "budget": 10 }
  ],
  "timings": [
    { "metric": "interactive", "budget": 5000 },
    { "metric": "first-contentful-paint", "budget": 2000 }
  ]
}]
```

Run with budget:
```bash
npx lighthouse <url> --budget-path=budget.json --output=json
```

## Lighthouse CI

```bash
npm install -g @lhci/cli

# In CI pipeline
lhci autorun --collect.url=<url> --assert.preset=lighthouse:recommended
```

Basic `.lighthouserc.json`:
```json
{
  "ci": {
    "collect": {
      "numberOfRuns": 3,
      "url": ["http://localhost:3000/", "http://localhost:3000/dashboard"]
    },
    "assert": {
      "assertions": {
        "categories:performance": ["error", { "minScore": 0.9 }],
        "first-contentful-paint": ["warn", { "maxNumericValue": 2000 }],
        "largest-contentful-paint": ["error", { "maxNumericValue": 2500 }],
        "cumulative-layout-shift": ["error", { "maxNumericValue": 0.1 }]
      }
    },
    "upload": {
      "target": "temporary-public-storage"
    }
  }
}
```

## Mobile vs Desktop Profiles

**Mobile** (default): 4x CPU slowdown, throttled 3G network, 412x823 viewport
**Desktop**: no CPU slowdown, no network throttle, 1350x940 viewport

Always test mobile first — it's the more constrained environment and represents most web traffic.
