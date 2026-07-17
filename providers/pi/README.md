# Pi Setup

To use almanac skills with [Pi](https://github.com/earendil-works/pi), run:

```bash
almanac install pi
```

The installer links each skill into Pi's shared Agent Skills location:

```text
~/.agents/skills/almanac/<name>
```

Run `/reload` in an active Pi session, or restart Pi. Skills are then available as `/skill:<name>` commands and can be loaded automatically when their descriptions match a task.

Pi and Codex both discover `~/.agents/skills/`, so one shared installation makes the skills available to both harnesses. Almanac records separate ownership markers, ensuring `almanac uninstall pi` retains links still installed for Codex.
