# Agent Safety Guardrails

Rules for safe agent operation. These protect against accidental data loss, credential exposure, and destructive operations.

## Git Safety

**Never:**
- Force-push to `main` or `master`
- Use `--no-verify` to skip hooks
- Use `git reset --hard` without understanding what you'll lose
- Amend published commits
- Delete branches without checking if they contain unmerged work

**Always:**
- Create new commits rather than amending existing ones
- Stage specific files by name (`git add path/to/file`) — never `git add -A` or `git add .`
- Check `git status` and `git diff` before committing
- Investigate merge conflicts rather than discarding changes
- Investigate lock files before deleting them

## Secrets

**Never commit:**
- `.env` files
- API keys, tokens, passwords
- `credentials.json`, service account keys
- Private SSH keys
- Database connection strings with passwords

**If you find a secret in code:**
1. Remove it immediately
2. Use environment variables instead
3. Add the file pattern to `.gitignore`
4. If already committed, the secret is compromised — rotate it

## Destructive Operations

Before running any of these, pause and confirm:
- `rm -rf` — are you deleting the right path?
- `DROP TABLE` / `DELETE FROM` without WHERE
- `git push --force`
- `docker system prune`
- Any command that modifies shared infrastructure

## File Operations

- Read files before editing them — understand existing code before changing it
- Prefer editing existing files over creating new ones
- Don't create files unless they're necessary for the task
- Check that parent directories exist before writing files

## External Communication

Confirm before taking actions visible to others:
- Pushing code to remote repositories
- Creating/closing/commenting on PRs or issues
- Sending messages (Slack, email, notifications)
- Modifying shared infrastructure or permissions
