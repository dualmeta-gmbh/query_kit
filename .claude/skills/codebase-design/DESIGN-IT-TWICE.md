# Design it twice

When a deepening candidate is chosen, design its interface several radically different ways before building one (Ousterhout: the first idea is rarely the best). Uses the vocabulary of [SKILL.md](SKILL.md) and the domain terms of `CONTEXT.md`.

## Process

### 1. Frame the problem space

Write the frame before spawning anything:

- The constraints any interface must satisfy: the candidate's own, plus the standing ones in [REPOSITORY.md](REPOSITORY.md) (ported suites unchanged; the public-surface class the design may fall in: internal, compatible addition or major).
- The dependencies and their category ([DEEPENING.md](DEEPENING.md)).
- Which decisions and PORTING_NOTES divergence rows the candidate touches (REPOSITORY.md, "Decisions already made"). ADR-0003 fixes the ownership rules of core operations; a design that moves run ownership must keep its contract table.
- The current design, as the baseline every alternative is compared against. Keeping it is one of the outcomes.
- A short code sketch to make the constraints concrete. Not a proposal.

In an AFK run (REPOSITORY.md, "Who decides", the default) the frame goes into the ticket's resolution comment or the report. When the conversation asked for an interview, show the frame and continue without waiting.

### 2. Spawn sub-agents

Spawn three or more in parallel, each with the same technical brief (file paths, coupling, dependency category, what sits behind the seam) and a different constraint. Without delegation, write the designs yourself in separate passes and label the comparison self-review.

- Agent 1: minimise the interface: one to three entry points, maximum leverage each.
- Agent 2: maximise flexibility: many uses, extension without a new export.
- Agent 3: optimise the common caller: the default case trivial. In the binding this means the four call styles, which must stay equal (`CLAUDE.md`, "the four call styles are presented as equal alternatives").
- Agent 4, when a dependency crosses a seam: ports and adapters.

Put both vocabularies in the brief: SKILL.md's for architecture, `CONTEXT.md`'s for the domain (query options, observer options, shape, type slot, call style, teardown).

Each agent returns: the interface (types, members, invariants, ordering, error modes); a usage example in Dart; what the implementation hides; the dependency strategy; where leverage is high and where thin; the public-surface class (internal, compatible addition, major), naming the exports if any change; the migration cost (which ported suites' imports, which port-only tests, which call sites); and the test that would disprove the design if it is wrong.

### 3. Compare and decide

Compare in prose on depth, locality and seam placement, on the standing constraints (ported suites untouched, public-surface class, type inference at call sites), and on cost: migration, proof, and what a caller must relearn. The baseline is in the comparison. Then recommend one, a hybrid, or the baseline, with the reason it beats the others. A hybrid is a new design: it needs one owner for each piece of state and its own disproving test, not the sum of its parents' proofs.

In an AFK run the recommendation is the decision, recorded as REPOSITORY.md's "Who decides" says: the options, the answer and why. When the conversation asked for an interview, present the designs one at a time and give the recommendation.
