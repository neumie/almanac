# Upstream provenance

Adapted from [Cloudflare's security-audit-skill](https://github.com/cloudflare/security-audit-skill), distributed under the [MIT license](../LICENSE), copyright 2025–2026 Cloudflare, Inc.

Reviewed upstream commit: `c1c8a8c1471069fb0e188eeaff69b8e8db6564a8` (2026-09-30).
Reviewed `SKILL.md` blob: `92178dad304d3f63e37582a297026a7874e12c62`.

## Local adaptations

- Compact `Use when` description, compatibility information, license, and Almanac sync metadata.
- Phase guides and all ten domain companions moved into `references/`, preserving their filenames and canonical attack-block IDs.
- Dependency-free validators and their adjacent schema moved into `scripts/`; validator code and schema are unchanged.
- Relative links and validator commands adjusted for the bundled layout and both installed directory-symlink roots.
- Delegation follows the host's authorization and lifecycle rules, using available equivalent roles rather than requiring provider-specific agent profiles. Full audits still require fresh independent verification; no single-context substitute.
- Source-only guidance remains lightweight. Full audits retain all six phases, profiles, budgets, sandbox restrictions, artifact-promotion safeguards, and distinct verdicts.
- Upstream validator tests live in `tests/security-audit/` with only their module/CLI paths adjusted. Installation-layout checks are local additions. No upstream README, agent configuration, or install mechanism is vendored.

The JSON validators do not supply a sandbox or implement artifact promotion. If those capabilities are missing, follow the execution blockers in [SKILL.md](../SKILL.md); do not execute target code or claim reproduced evidence.

## Maintenance

From the Almanac repository root:

```sh
bash tests/test-skills.sh
bash tests/test-structure.sh
node --test tests/security-audit/*.test.cjs
almanac sync
```

`almanac sync` checks the tracked `SKILL.md` blob only. When reviewing an upstream update, also compare every bundled reference, validator, schema, and upstream validator test against the reviewed commit above. Preserve the local path/delegation adaptations and update both the frontmatter and this provenance record.
