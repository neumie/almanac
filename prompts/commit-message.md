# Commit Message Template

## Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

## Subject Line

- **Type**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`
- **Scope**: module or area affected (optional but helpful)
- **Subject**: imperative mood ("add" not "added"), under 72 chars, no trailing period
- Focus on **what changed**, not how

## Body (optional)

- Explain **why** this change was made
- What was the problem or motivation?
- Are there any side effects or consequences?
- Wrap at 72 characters

## Footer (optional)

- Reference issues: `Fixes #123`, `Relates to #456`
- Breaking changes: `BREAKING CHANGE: description`
- Co-authors: `Co-Authored-By: Name <email>`

## Examples

```
feat(auth): add JWT token refresh before expiry

Tokens silently expired after 1 hour, causing 401 errors for
long-running sessions. Now refreshes 5 minutes before expiry.

Fixes #234
```

```
fix(api): handle null user in profile endpoint

The GET /profile endpoint crashed when called with an expired
session token because the user lookup returned null.
```

```
refactor(db): extract connection pool into shared module

Three services duplicated the same pool configuration. Extracted
to lib/db.ts so changes only need to happen in one place.
```
