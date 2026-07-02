# Claude Context

**Before responding to any message, read these files:**

1. `docs/PROGRESS.md` — Status: progress per phase, blockers, known issues, next steps
2. `docs/SPEC.md` — The PCL language: lexical rules, grammar, types, semantics, stdlib,
   CLI/build contract
3. `docs/IMPLEMENTATION.md` — Our own toolchain/pipeline decisions

These three documents are the source of truth, split by who owns the content and how often
it changes: SPEC.md is external and frozen (the course's requirements — we don't get to
change these; fix the file if it's wrong, don't patch around it). IMPLEMENTATION.md is
internal and rarely changes (our settled choices — toolchain, pipeline shape). PROGRESS.md
is internal and changes constantly (status — update it at the end of each session).

**Do not read `docs/instructions.pdf`** (the raw course handout) unless SPEC.md fails to
answer the question at hand — e.g. it contradicts the code, or is silent on something you
need. SPEC.md was extracted from it in full; treat the PDF as a fallback, not a routine
read.

**Symbol table design (data structure, tracked fields) is not specified by the course and
has not been decided.** Don't design or implement it unilaterally — ask the user first. See
the note in `docs/SPEC.md` §4.

**Don't ask the user for context.** It's in the docs.

**After doing substantive implementation work** (a new phase, a significant chunk of a
phase, a nontrivial bugfix), write a step-by-step walkthrough into `guide/` explaining what
was built and why — see `guide/LEXER_WALKTHROUGH.md` for the shape/depth expected (what the
files are for, how the mechanism actually works, what was verified and how, what's still a
placeholder). These are human-facing explainers, not part of the SPEC/IMPLEMENTATION/
PROGRESS context set — don't add them to the required-reading list above, and don't expect
them to stay in sync with later changes automatically.
