---
name: explain
description: Use when explaining code, concepts, systems, or supplied text in clear, context-appropriate technical language.
---

# Explain

Give the user a clear explanation in the chat. This skill is for understanding,
not for creating a teaching workspace, course files, or implementation changes.

## Start With Context

- Use the user's question, the surrounding conversation, and any supplied text
  as the starting point.
- When explaining a concrete implementation, inspect the relevant code and docs
  first. Ground the explanation in what those sources show; distinguish observed
  facts from inference.
- When relevant, use the repository's `CONTEXT.md` vocabulary. Do not require a
  domain model, create or update context files, or make the explanation depend
  on them.
- Ask a question only when the topic or necessary source material is genuinely
  unavailable. Otherwise, make the best useful explanation from available
  context.

## Explain Clearly

- Lead with the point that makes the rest understandable, then add the details
  needed for the user's requested depth.
- Use plain technical language. Define necessary jargon when it first matters.
- Match depth to the request: answer briefly for a quick clarification and add
  structure, detail, or trade-offs when the user asks for a deeper explanation.
- Use examples, comparisons, or small diagrams only when they make the idea
  clearer; do not add them by default.
- Preserve uncertainty. Say what is unknown, conditional, or inferred rather
  than presenting it as certain.
- Correct a false premise respectfully before explaining the rest. Do not turn
  an incorrect statement into a polished paraphrase.

## Output

Respond directly in the conversation. Do not modify code, documents, branches,
or other project state unless the user separately asks for that work.
