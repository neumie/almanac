---
name: frontend-perf
description: Use when assessing web page performance, diagnosing slow loads, optimizing Core Web Vitals, analyzing bundle size, or auditing runtime performance. Guides systematic measurement using agent-browser and Lighthouse before optimization.
compatibility: Requires agent-browser (Vercel CLI, npx agent-browser) for browser measurement. Lighthouse CLI optional for full audits.
---

# Frontend Performance Assessment

Measure first, optimize second. Never guess at performance — use real metrics from real pages.

## Process

### 1. Establish Baseline

Capture initial measurements before any changes:

**Browser metrics via agent-browser:**
```bash
npx agent-browser open <url>
npx agent-browser wait --load networkidle
npx agent-browser eval "JSON.stringify(performance.getEntriesByType('navigation')[0])"
npx agent-browser eval "JSON.stringify(performance.getEntriesByType('paint'))"
```

**Lighthouse audit for comprehensive baseline:**
```bash
npx lighthouse <url> --output=json --output-path=./baseline.json --chrome-flags="--headless"
```

Record: TTFB, FCP, LCP, TBT, CLS, SI. These are your before numbers.

### 2. Core Web Vitals Assessment

Extract and evaluate against thresholds:

| Metric | Good | Needs Improvement | Poor |
|--------|------|--------------------|------|
| LCP | ≤ 2.5s | ≤ 4.0s | > 4.0s |
| INP | ≤ 200ms | ≤ 500ms | > 500ms |
| CLS | ≤ 0.1 | ≤ 0.25 | > 0.25 |

Extract via Performance API:
```bash
npx agent-browser eval "
  new Promise(resolve => {
    new PerformanceObserver(list => {
      const entries = list.getEntries();
      resolve(JSON.stringify(entries.map(e => ({name: e.name, value: e.value || e.startTime}))));
    }).observe({type: 'largest-contentful-paint', buffered: true});
  })
"
```

**Decision tree:**
- All green → skip to Bundle Size (step 6)
- LCP poor → go to Network/Loading (step 4)
- CLS poor → go to Network/Loading (step 4, CLS diagnosis)
- INP poor → go to Runtime Performance (step 7)

### 3. Visual Inspection

Capture visual state for comparison:

```bash
# Full-page baseline screenshot
npx agent-browser screenshot --full-page --output baseline.png

# Annotate to identify key elements
npx agent-browser screenshot --annotate --output annotated.png

# After changes, capture and diff
npx agent-browser screenshot --full-page --output after.png
npx agent-browser diff screenshot baseline.png after.png
```

Look for: layout shifts, oversized images, invisible text during font loading, content jumps.

### 4. Network and Loading Analysis

**LCP diagnosis decision tree:**
- TTFB > 600ms → server response is the bottleneck, check backend
- TTFB OK but FCP late → render-blocking resources (CSS/JS in `<head>`)
- FCP OK but LCP late → LCP element loading slowly (large image, lazy-loaded hero, web font)

**CLS diagnosis:**
- Images/videos without dimensions → add `width`/`height` attributes
- Dynamically injected content above viewport → reserve space with CSS
- Web fonts causing FOIT/FOUT → use `font-display: swap` + preload
- Ads/embeds without reserved space → set explicit container dimensions

**Render-blocking resources:**
```bash
npx agent-browser eval "
  JSON.stringify(performance.getEntriesByType('resource')
    .filter(r => r.renderBlockingStatus === 'blocking')
    .map(r => ({name: r.name, duration: r.duration})))
"
```

### 5. Mobile Testing

Test mobile performance — it's often significantly worse:

```bash
npx agent-browser viewport --device "iPhone 15"
npx agent-browser open <url>
npx agent-browser wait --load networkidle
npx agent-browser screenshot --full-page --output mobile.png
```

Run Lighthouse with mobile profile:
```bash
npx lighthouse <url> --preset=perf --form-factor=mobile --output=json
```

Compare mobile vs desktop scores. Common mobile issues:
- Unoptimized images served at desktop resolution
- Heavy JS bundles on slower processors
- Touch targets too small (< 48x48px)
- Viewport not configured (`<meta name="viewport">`)

### 6. Bundle Size Analysis

**Thresholds:**
- Initial JS bundle: < 100KB gzipped
- Total JS: < 300KB gzipped
- CSS: < 50KB gzipped

**Measure current size:**
```bash
# For webpack/vite projects, check build output
npm run build 2>&1 | tail -20

# Use source-map-explorer for detailed breakdown
npx source-map-explorer dist/**/*.js --json
```

**Decision tree:**
- Over threshold → identify largest modules, check for:
  - Unused dependencies (`npx depcheck`)
  - Duplicate packages in bundle
  - Missing tree-shaking (barrel exports, CommonJS imports)
  - Large libraries with smaller alternatives (moment→date-fns, lodash→lodash-es)
- Under threshold → no action needed

See `references/bundle-analysis-guide.md` for framework-specific tools.

### 7. Runtime Performance

**Total Blocking Time (TBT) and long tasks:**
```bash
npx agent-browser eval "
  new Promise(resolve => {
    const longTasks = [];
    new PerformanceObserver(list => {
      longTasks.push(...list.getEntries().map(e => ({duration: e.duration, start: e.startTime})));
    }).observe({type: 'longtask', buffered: true});
    setTimeout(() => resolve(JSON.stringify(longTasks)), 3000);
  })
"
```

**Framework-specific checks:**
- **React**: unnecessary re-renders (React DevTools Profiler), missing `memo`/`useMemo` for expensive computations
- **Vue**: excessive watchers, large reactive objects
- **Next.js/Nuxt**: pages that should be static but are SSR'd, missing ISR
- **Svelte**: reactive statement chains, large component trees

### 8. Image Optimization

Check images on the page:
```bash
npx agent-browser eval "
  JSON.stringify(Array.from(document.images).map(img => ({
    src: img.currentSrc,
    rendered: img.width + 'x' + img.height,
    natural: img.naturalWidth + 'x' + img.naturalHeight,
    loading: img.loading,
    decoding: img.decoding
  })))
"
```

**Issues to flag:**
- Natural size >> rendered size (serving oversized images)
- Missing `loading="lazy"` on below-fold images
- Non-modern formats (use WebP/AVIF instead of PNG/JPEG)
- Missing `width`/`height` attributes (causes CLS)
- Hero/LCP image not preloaded

### 9. Report Findings

Organize by severity:

**Critical** (blocking user experience):
- LCP > 4s, CLS > 0.25, INP > 500ms
- Initial JS > 200KB gzipped
- Render-blocking resources on critical path

**Improvements** (measurable impact):
- LCP 2.5-4s, CLS 0.1-0.25, INP 200-500ms
- Unoptimized images, missing lazy loading
- Bundle size over threshold but not extreme

**Observations** (minor or preventive):
- Opportunities for caching, preloading, prefetching
- Code splitting candidates
- Future optimization opportunities

Always include before/after metrics when recommending changes.
