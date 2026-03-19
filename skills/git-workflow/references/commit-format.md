# Commit Message Template

## Format

```
<type>(<scope>): <short summary in imperative mood>

<body — only if the "why" isn't obvious>

<footer>
```

## Subject Line

- **Type**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`
- **Scope**: module or area affected (optional but helpful)
- **Subject**: imperative mood ("add" not "added"), lowercase, under 72 chars, no trailing period
- Focus on **what changed**, not how

## Body (optional)

- Only include if the **why** isn't obvious from the summary
- Explain motivation, not mechanics (the diff shows what)
- Wrap at 72 characters

## Footer (optional)

- Reference issues: `Fixes #123`, `Relates to #456`
- Breaking changes: `BREAKING CHANGE: description`

## Examples

```
feat(auth): add JWT token refresh before expiry

Tokens silently expired after 1 hour, causing 401 errors for
long-running sessions. Now refreshes 5 minutes before expiry.

Fixes #234
```

```
fix(api): handle null user in profile endpoint
```

```
refactor(db): extract connection pool into shared module

Three services duplicated the same pool configuration.
```
