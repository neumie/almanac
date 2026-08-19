# unslop mimic

Single-pass voiced writing. Draft or rewrite in a taught voice, then clear the
full gate battery. Route here on "write this like me", "match my voice", or
"mimic this author" once a voice card exists. Read `references/mimic.md` for card
anatomy, scoring, and failure modes.

## Flow

1. Load the situation sheet the task needs. Read `card.md` for the always-on core
   (rhythm, contraction habits, punctuation, openers, the Never list) and the
   one `card/<situation>.md` sheet that matches what you are writing. Load only
   what the task needs; the card is layered so generation stays cheap.
2. Draft or rewrite in that voice. Follow the card's measured markers and
   verbatim snippets; do not invent a habit the samples cannot support.
3. Run the output through **every** removal gate:

   ```bash
   python3 "$UNSLOP_DIR/scripts/banned_phrase_scan.py" <<< "$OUTPUT"
   python3 "$UNSLOP_DIR/scripts/structure_scan.py" <<< "$OUTPUT"
   python3 "$UNSLOP_DIR/scripts/readability_metrics.py" <<< "$OUTPUT"
   python3 "$UNSLOP_DIR/scripts/validate_preservation.py" original.txt "$OUTPUT_FILE"
   python3 "$UNSLOP_DIR/scripts/diff_check.py" original.txt "$OUTPUT_FILE"
   ```

4. Score the voice against the bundled impostor corpus and the approved samples:

   ```bash
   python3 "$UNSLOP_DIR/scripts/voice_score.py" \
     --profile .unslop/voice/<name>/profile.json \
     --impostors "$UNSLOP_DIR/assets/voice-impostors" \
     --seed 7 --samples .unslop/voice/<name>/samples "$OUTPUT_FILE"
   ```

## The rule

A mimic that scores well on voice but trips a slop gate is **rejected**. Voice
never buys an exemption from the constitution — the removal gates are hard, the
voice score is a guide. Meaning preservation versus the original draft is its own
hard gate, never blended into the voice score.

## Refine — when one pass is not enough

Most users teach once and mimic cheaply thereafter. If one pass misses the
voice, refine conservatively:

1. Keep the first clean candidate and its score as the baseline.
2. Use its two largest metric deltas to generate at most two targeted variants.
3. Run every removal and preservation gate on each variant, then rerun
   `voice_score.py` with the same profile, impostor corpus, seed, and samples.
4. Accept only a gate-clean variant with a lower composite; never trade meaning
   or copy sample wording for a better score.
5. Stop after three rounds or one round with no improvement. Return the best
   clean candidate and describe the remaining voice mismatch without claiming
   statistical proof.

## Voice check

"Does this sound like me?" means score only and change nothing:

```bash
python3 "$UNSLOP_DIR/scripts/voice_score.py" \
  --profile .unslop/voice/<name>/profile.json \
  --impostors "$UNSLOP_DIR/assets/voice-impostors" \
  --seed 7 --samples .unslop/voice/<name>/samples draft.md
```

Report the composite (lower is more like the taught voice), the GI rank, and the
two or three metric deltas that explain the score in plain words. Do not rewrite
unless asked.
