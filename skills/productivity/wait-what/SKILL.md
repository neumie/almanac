---
name: wait-what
description: Use when the user says “wait what” or does not understand the immediately preceding substantive assistant response.
metadata:
  dependencies:
    - explain
  upstream: mattpocock/skills/skills/productivity/wait-what
  upstream-sha: f8854f1b4527bca90378baf5430557172136a1bf
  adapted-date: "2026-09-08"
---

# Wait What

Find the immediately preceding substantive assistant response in the current
conversation. Exclude tool calls and outputs, hidden reasoning or instructions,
and this invocation itself.

If the user gives a hint about what was confusing, use it to focus the
explanation. If no qualifying assistant response exists, say so plainly; do not
invent prior context or an answer.

Follow the `explain` skill to re-explain the selected response. This wrapper
only selects the context and focus; it does not duplicate the explanation
process.
