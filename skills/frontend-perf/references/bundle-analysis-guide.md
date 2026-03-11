# Bundle Analysis Guide

## Universal Tools

### source-map-explorer
Works with any bundler that produces source maps:
```bash
npx source-map-explorer dist/**/*.js
npx source-map-explorer dist/**/*.js --json  # machine-readable
npx source-map-explorer dist/**/*.js --html report.html  # visual treemap
```

### size-limit
CI-friendly size checking:
```bash
npm install --save-dev size-limit @size-limit/preset-app
```

Add to `package.json`:
```json
{
  "size-limit": [
    { "path": "dist/**/*.js", "limit": "100 KB", "gzip": true },
    { "path": "dist/**/*.css", "limit": "30 KB", "gzip": true }
  ],
  "scripts": {
    "size": "size-limit",
    "size:why": "size-limit --why"
  }
}
```

## Framework-Specific

### Webpack
```bash
# webpack-bundle-analyzer
npm install --save-dev webpack-bundle-analyzer

# Add to webpack.config.js
const { BundleAnalyzerPlugin } = require('webpack-bundle-analyzer');
module.exports = { plugins: [new BundleAnalyzerPlugin()] };

# Or run standalone on stats file
npx webpack --json > stats.json
npx webpack-bundle-analyzer stats.json
```

### Vite
```bash
npm install --save-dev rollup-plugin-visualizer
```

```javascript
// vite.config.js
import { visualizer } from 'rollup-plugin-visualizer';
export default defineConfig({
  plugins: [visualizer({ open: true, gzipSize: true })],
});
```

### Next.js
```bash
npm install --save-dev @next/bundle-analyzer
```

```javascript
// next.config.js
const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true',
});
module.exports = withBundleAnalyzer({ /* config */ });
```

Run: `ANALYZE=true npm run build`

### Remix / React Router
Check `build/client/assets/` directory after build. Use `source-map-explorer` on the output.

## Common Issues and Fixes

### Duplicate packages
```bash
npx npm-dedupe  # or yarn dedupe
```
Check `package-lock.json` for multiple versions of the same package.

### Missing tree-shaking
- Use ESM imports: `import { pick } from 'lodash-es'` not `import _ from 'lodash'`
- Avoid barrel files that re-export everything: `import { Button } from '@/components'` pulls in all components
- Check `sideEffects` in library `package.json`

### Large dependencies — smaller alternatives
| Large | Size | Alternative | Size |
|-------|------|-------------|------|
| moment | 72KB | date-fns | 12KB (tree-shakeable) |
| lodash | 72KB | lodash-es | tree-shakeable |
| axios | 13KB | fetch (built-in) | 0KB |
| uuid | 5KB | crypto.randomUUID() | 0KB |
| classnames | 1KB | clsx | 0.5KB |

### Code splitting
```javascript
// React lazy loading
const Dashboard = React.lazy(() => import('./Dashboard'));

// Next.js dynamic import
const Chart = dynamic(() => import('./Chart'), { ssr: false });

// Route-based splitting (React Router)
const routes = [
  { path: '/dashboard', lazy: () => import('./pages/Dashboard') },
];
```

## Size Thresholds

| Category | Budget (gzipped) |
|----------|-----------------|
| Initial JS | < 100KB |
| Total JS | < 300KB |
| CSS | < 50KB |
| Images (per page) | < 500KB |
| Web fonts | < 100KB |
| Total page weight | < 1MB |
