# Teach & Mimic — internals

The routed flows live in `references/commands/teach.md`,
`references/commands/mimic.md`, and the refine section of that mimic command
file. This file holds the deep material those flows link to: card anatomy,
sample requirements, scoring, conservative refinement, and failure modes.

Reconstruction runs under detection's constitution: a mimic or refined output
that reintroduces slop is a failure. Every artifact here is deterministic and
testable; the model is used only to generate prose, never to score itself.

## Teach — the artifacts

`teach` distills a writer's samples into a reusable voice, stored under
`.unslop/voice/<name>/` (keep it uncommitted unless the user asks otherwise):

1. `scripts/voice_profile.py samples/ -o profile.json` — the machine
   fingerprint (char 3-grams, function-word delta, sentence-length EMD,
   punctuation, contractions, MTLD, word-length, impostor z-scores, GI rank).
   This is the referee the scorer uses.
2. `scripts/voice_card.py --profile profile.json --samples samples/ --out .
   --name <name>` — the **layered voice card** the generating model actually
   follows. `--name` labels the card (`# Voice card: <name>`); default `voice`.
   voice_card recomputes the profile from `--samples` and refuses (exit 2, named
   field) if the supplied `--profile` does not describe those samples, so a stale
   profile can never silently drive a card.
3. Add `--provenance` to write `provenance.json` (per-sample sha256, word
   counts, doc count, genre note, low-confidence flag) so a teach run is
   auditable.

**Sample files.** Both scripts read only `.txt` and `.md` files, recursively,
under the samples directory (nothing else — a directory of `.docx` or extensionless
files reads as empty and both scripts exit 2 with a diagnostic naming the
requirement). Convert samples to `.txt`/`.md` first.

**Sample requirements.** Use at least 5 documents, 2-3k words total, in the
**same genre** as the target. Fewer than ~2000 words or cross-genre samples set
`low_confidence` in the profile and provenance; the card still builds but its
claims are noisier. **Surface `low_confidence` to the user** — tell them the voice
is provisional and ask for more same-genre samples before trusting a mimic.
Cross-domain style attribution degrades sharply, so do not teach on blog posts
and score legal memos.

## The voice card (layered)

The card is a directory, not one file, so the generator loads only what the
current writing task needs:

- `card.md` — the always-loaded core, kept under 300 words: rhythm (median
  sentence length, IQR, burstiness), contraction habits with real examples,
  punctuation the writer uses and avoids, top sentence openers, a **Never**
  list of at/near-zero features, and an **index table** — "when writing X, read
  `card/X.md`".
- `card/<situation>.md` — one sheet per **covered** situation from the taxonomy
  (explaining-technical, anecdote, argument, disagreement, praise,
  hedging-uncertainty, numbers-data, addressing-reader, openings, closings).
  Each sheet gives how this author handles that situation, 1-3 verbatim sample
  snippets, and measured markers.

**No fabrication.** A dimension with no sample evidence gets **no sheet**; it is
named under "Uncovered" in `card.md`. The card never invents a voice the
samples cannot support.

**Coverage classification.** `voice_card.py --coverage` emits a deterministic
lexical coverage matrix over the taxonomy. It is intentionally coarse: it
DRIVES which sheets get written and which teach prompts to ask the user, and a
misclassified sentence can only add or drop a sheet — it can never change a card
claim, because claims come from measured facts and verbatim snippets. So
misclassification is low-stakes by construction. A sample set missing numeric
writing, for instance, leaves `numbers-data` uncovered and named as a gap.

**Coverage → prompt procedure.** When a dimension the target writing will need is
uncovered, ask the user for a short sample that exercises it. **Only ask for
dimensions the task requires** — do not fish for all ten. Templates:

| Dimension | Prompt to the user |
|-----------|--------------------|
| explaining-technical | "Share something you wrote that explains how a thing works or why it behaves the way it does." |
| anecdote | "Share a few sentences where you tell a small story about something that happened to you." |
| argument | "Share something you wrote that argues a position — a claim you defended." |
| disagreement | "Share something where you pushed back on or disagreed with an idea." |
| praise | "Share something where you praised or recommended something you liked." |
| hedging-uncertainty | "Share something where you were unsure and said so — thinking out loud." |
| numbers-data | "Share something you wrote that works with numbers, quantities, or measurements." |
| addressing-reader | "Share something written directly to a reader — instructions or a note to someone." |

`openings` and `closings` are structural (first/last sentence of every document)
and are covered as soon as there is one document, so they need no prompt.

The card is pack-sized (~1-2k tokens loaded) so it rides in the generation
context cheaply. Same inputs give byte-identical files.

## Scoring and conservative refinement

Score a candidate against the taught profile, bundled impostor corpus, and
approved samples:

```bash
python3 "$UNSLOP_DIR/scripts/voice_score.py" \
  --profile .unslop/voice/<name>/profile.json \
  --impostors "$UNSLOP_DIR/assets/voice-impostors" \
  --seed 7 --samples .unslop/voice/<name>/samples candidate.md
```

The composite is `0.5·(1−GI) + 0.5·zsum` (lower is more author-like). GI is the
fraction of random feature subsets in which the candidate beats every bundled
impostor. `zsum` is a clipped, weighted distance from the taught profile,
normalized against those impostors. Meaning preservation remains a separate
hard gate; a lower voice score never excuses a changed claim or copied sample
wording.

Most users should teach once and mimic once. When one pass misses the voice,
keep the first gate-clean candidate as the baseline. Generate at most two
variants aimed at its largest metric deltas, run the complete slop and
preservation gates, then score with the same profile, impostors, seed, and
samples. Keep only a clean candidate with a lower composite. Stop after three
rounds or one round without improvement, and describe any remaining mismatch
without claiming statistical proof.

## Cost

| Step | Calls |
| teach (profile + card) | free and deterministic |
| mimic | one strong generation call |
| refine | at most two generation calls per round, capped at three rounds |

## Failure modes

| Failure | Symptom | Guard |
| Topic bleed | Imports what samples discuss rather than how they read. | Compare claims to the source and reject new facts. |
| Verbatim copying | Lifts sample phrasing. | Pass `--samples`; reject a triggered copy gate. |
| Register lock | Copies one sample's context into another genre. | Use same-genre samples and the matching situation sheet. |
| Reward chasing | Score improves while meaning or readability worsens. | Preservation and slop gates remain blocking. |
| Slop reintroduced | AI tells return in voiced prose. | Banned-phrase, structure, and silhouette gates. |
