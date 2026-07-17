# Codex Setup

To use almanac skills with Codex, run:

```bash
almanac install codex
```

The installer links each skill into:

```bash
~/.agents/skills/almanac/<name>
```

Skills in `SKILL.md` format are discovered by Codex after restarting the session. For example, the `ship` skill is available as `$ship`, and installed skills can be browsed from `/skills`.

Pi discovers the same shared location. Almanac records separate ownership markers, ensuring `almanac uninstall codex` retains links still installed for Pi.
