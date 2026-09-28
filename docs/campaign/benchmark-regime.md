# Benchmark regime

How Deep-Littré builds ground truth for the classification campaign, draws samples, develops adjudication methods, and measures them. Adapted 2026-09-08 from a working sketch, after the first partial pilot runs; revised 2026-09-27 after the first two `decomposition` development samples.

This is campaign method rather than pipeline contract. The adjudication guidance for the `decomposition` pass is in [`decomposition-guidance.md`](decomposition-guidance.md), and the samples and findings to date in [`decomposition-notes.md`](decomposition-notes.md).

## Ground truth is per pass

There is no holistic classification label. Ground truth is a judgment on one adjudication pass for one eligible block. A block's complete analysis is the union of its per-pass records.

Each pass is a question over an eligible population and a projection. For every eligible item the judgment is `positive`, `negative`, or `unresolved`.

A positive records the semantic output the pass requires. For a structural pass, this consists of the node and its constituents (form, gloss, residual), exhaustively partitioning the projected target. For a scope pass, it is the marker selection and the material it governs. The output contract comes from the production pass definition.

## Gold is authored through the production harness

Gold uses the same projections, pass definitions, validators, and authoring harness as production adjudication. The producer (me) supplies semantic decisions and exact selections against the classification surface. The harness maps selections to source anchors, validates geometry, computes hashes, and writes out the records.

## Benchmark data is separate from production adjudications

`data/adjudication/` holds production judgments used to build the edition. `benchmark/` holds evaluation assets used to develop and measure methods. A benchmark record never enters the production build.

## Two independent dimensions

Every benchmark sample is classified on two axes.

**Frame** — how the sample was drawn. `population`: from the pass's versioned eligible population with known inclusion probabilities, so corpus-level rates can be estimated. `challenge`: deliberately enriched with informative cases. `cross_pass_core`: a small varied set adjudicated through every applicable pass.

**Role** — what the sample is for. `development`: fully visible, used to inspect failures, write prompts, develop rules, choose thresholds, and supply few-shot examples. `protected`: used repeatedly for comparative scoring but never as prompt examples. `final`: drawn and adjudicated only after a method is frozen.

A protected set may be a challenge set, and a development sample may be a true population sample. Both are required arguments to the sampler and recorded in every manifest.

## Population samples

A population sample answers questions about ordinary corpus behaviour: prevalence of the phenomenon, prevalence of ambiguity, real-corpus precision and recall, what fraction can be routed automatically, and unexpected failure modes.

The sampling unit is the eligible adjudication *block* rather than at the level of *entries*. Large entries contribute more blocks.

The default design is simple random sampling without replacement, n = 100 per pass pilot.

A useful consequence of this design is that every block has a known, nonzero inclusion probability. Building a sample only from candidate heuristics (commas, known locutions, headword matches, old classifications) would prevent recall estimation.

## Challenge samples

Challenge samples are deliberately enriched for likely positives, near misses, known historical positives and negatives, heuristic successes and failures, mixed structures, multiple units in one block, grammatical false positives, unusual form and gloss geometry, and prior model failures.

They may be opportunistic and need no probability weights. Challenge accuracy is a stress-test statistic.

The spring locution decomposition experiments are a good source of challenge material and development examples.

## Cross-pass core

A small set of blocks adjudicated through every applicable pass, to reveal collisions between semantic facts, multiple structural nodes in one block, interactions between structural and qualification decisions, geometry problems, and weaknesses in the surface or harness. Thirty to fifty deliberately varied blocks is enough to start. It does not need to be representative and must not be a prerequisite for pass-specific work.

Drawing pilot samples for different passes with the same seed produces a cross-pass core at no extra cost, provided the passes share a population — the manifest's population hash is what confirms they did.

## Contamination and demotion

Development gold is expected to be overfit to, in the constructive engineering sense.

Protected sets are scored repeatedly but exposed only in aggregate while methods are being tuned. If an individual protected failure is inspected and its correct answer becomes known to the developer, that item is contaminated for protection purposes and should be demoted to development. Demotion is cheap; pretending is not.

The final holdout protocol: freeze the method at a commit, draw the sample, run the frozen system and store its predictions, adjudicate without seeing them, and compare only afterward. If the method changes materially after final evaluation, a new holdout is required rather than pretending the old one is still pristine. Not every pass needs one, and none needs one before its method is mature.

## Authoring workflow

`tools/benchmark/sample_population.jl` draws a sample and writes `manifest.toml`, `membership.tsv`, and `surfaces.jsonl` under `benchmark/samples/<sample_id>/`.

`tools/benchmark/adjudicate_sample.jl` walks the frozen membership in order, reconstructs each item through the production harness, verifies its classification-surface hash against the one recorded at sampling time, displays a compact surface, accepts `positive`, `negative`, `unresolved`, `skip`, or `quit`, takes exact selections for positives, submits a `Decision` through the production harness, and writes the canonical record to the benchmark store. It resumes by skipping items already recorded.

Selections are entered as token index ranges against the displayed target, or as literal substrings. The adjudicator never types byte positions or JSON. Node spans and residuals are derived from the form and gloss selections.

Per-item wall time goes to a `session.tsv` sidecar. Sidecar notes are development observations, not semantic gold.

Correcting a recorded verdict currently means deleting its line from the store shard and re-running, because the store deliberately refuses to overwrite a locator a pass already holds. Superseding a verdict is meant to be intentional.

The authoring tool locates each item by its exact anchor from `membership.tsv`, with no fallback. The production harness will recover a block that has moved within its file by a unique surface-hash match; the authoring tool does not, so anything that shifts byte offsets mid-sample makes later items in the same file unreachable.

`tools/benchmark/render_gold.jl` renders committed shards as annotated text: `⟦⟧` for node spans, `[form …]` and `[gloss …]` for constituents, `«»` for residuals, followed by notes and a tally of outcomes, nodes, and gloss presence. Text inside `⟦⟧` but inside no constituent is unassigned, which is the fastest way to spot a node that swallowed something unintended. Records that no longer materialize print as `STALE`.

## Patches during a sample

Adjudication is a source of patches as well as build and validation failures: a labelling pass finds transcription choices that are locally plausible and only look wrong beside their neighbours.

A patch changes source bytes, so it changes the projection and surface hash of its block and shifts offsets for everything after it in the file. Patch before a draw where possible. Patching mid-sample costs the patched item's record, if already authored, and every not-yet-authored item later in the same file.

## Sampling provenance

Every committed sample records enough to reconstruct the methods and audit what happened:

```text
sample_id, creation timestamp
role, frame, design, sampling unit
pass, pass_version
population, population_version, population_size, population_hash
projection, projection_version
sample size, seed, RNG implementation
strata, stratum sizes, inclusion probabilities, if any
ordered realized membership, sample hash
patched source corpus hash
repository commit, dirty-tree status, Julia version
all exclusions or replacements, with reasons
```

The realized membership is authoritative. The seed is important provenance but must never be the only reconstruction path, because RNG behaviour can change between software versions.

Never silently replace a sampled item that proves inconvenient.

An explicit `--sample-id` must name the pass being drawn. The first pilot draw was written to a directory named for one pass while its items carried another, and because `sample_id` is embedded in every `item_id`, the error propagated into all hundred identifiers. The sampler now refuses.

Drawing a protected or final sample from a dirty working tree is refused, because the recorded commit would not identify the code that drew it.

## Experiment provenance

Model and rule-development runs are versioned research runs. For each, preserve the experiment id, repository commit, sample id, method identity and version, prompt or rule text, model and parameters, raw outputs, parsed decisions, and scores.

The pass version is the invalidation unit and changes only when the canonical question changes. Prompts and rules are methods, and they evolve continuously toward answering the same question. A guidance revision that changes answers without changing the question is invisible to the pass version, so `decision_procedure` — which is producer-owned and opaque to the pipeline — should carry a versioned guidance identifier, so that items judged under superseded guidance can be found and re-adjudicated. `adjudicate_sample.jl` takes it as `--procedure` and defaults to `human/pilot`, which names no guidance version.

Predictions from any method, including trivial deterministic rules, are written as JSONL keyed by `item_id`:

```text
{"item_id": …, "outcome": …, "method": "trivial_rules@1", "rule": …}
```

The same format for a regex and for a model means the scorer is written once, and a deterministic rule can serve as the first method evaluated before any model exists. Predictions are frozen to disk before the corresponding items are labelled, and the adjudicator does not see them.

## Evaluation priorities

The objective is not maximum overall accuracy. It is: what fraction of the eligible population can be adjudicated automatically at sufficiently high precision, with the remainder safely routed to review?

Useful metrics: positive precision and recall, exact semantic-output accuracy, exact form accuracy, exact gloss accuracy where applicable, all-nodes recovery for exhaustive passes, invalid-authoring rate, auto-accept coverage, precision among auto-accepted records, and review rate.

Three outcomes must be distinguished: **semantic error**, a validly authored but wrong decision; **authoring failure**, malformed output, an unlocatable selection, impossible geometry; and **abstention**, where the method declines to auto-adjudicate. A method that handles 70% of the population at very high precision and routes the rest may be preferable to one that answers everything less reliably.

Because positives assert spans, scoring is layered. Two producers can agree on the outcome and disagree about where a form ends. Report outcome agreement, then span agreement, and prefer both an exact-match figure and one tolerant of trailing separator punctuation, since the separator between constituents belongs to neither.

A human `unresolved` can never count as a machine error. How much of the corpus is genuinely undecidable is a finding in its own right.

## Deterministic rules and trivial cases

A deterministic negative is first-class where a rule genuinely establishes absence — where the projected target contains no material a positive could span at all. The absence of a heuristic trigger is not such a rule.

Trivial cases should be treated as a classification method rather than as a population edit. A predicate that predicts negatives runs over `surfaces.jsonl`, its predictions are frozen, the human labels the items anyway, and the disagreement rate is measured. That costs a few seconds per trivial item and converts an assumption into a bounded claim; it also surfaces anomalies a mechanical negative would have buried. One pilot item projected to an empty target while its citation context held what reads as definition prose, which an unverified "empty target implies negative" rule would have silently negated.

Changing a pass's eligible population is a heavier action, requiring the normal population versioning discipline and a redraw of any sample already taken from it. Count first, decide once.

It also stales records. Application checks population membership before it checks the surface hash, so a record whose block has left the population no longer materializes. Narrowing a population is therefore a way to retire records on purpose, and never a free change for records already made.

## Intra-adjudicator consistency

A second annotator is not required. Where practical, resurface roughly 5–10% of development items later, shuffled and without the earlier answer visible. Human self-agreement is the ceiling on any machine performance target worth setting, and if a pass's criteria are unstable this is where it shows.

This is optional and should not block work.

## Repository layout

```text
benchmark/
	samples/<sample_id>/{manifest.toml, membership.tsv, surfaces.jsonl, predictions/}
	gold/{development,protected,final}/<sample_id>/<pass>/<letter>.jsonl
	provenance/

tools/benchmark/
	sample_population.jl
	adjudicate_sample.jl
	render_gold.jl
	score.jl

experiments/<pass>/
```

`score.jl` and `experiments/` are planned and do not exist yet; neither does any `predictions/` directory.

Anything in `tools/` is re-runnable and produces a committed artifact under `benchmark/`. One-off corpus analysis goes in `experiments/`, whose gitignore is inverted — ignore everything, un-ignore `*.md`, `manifest.toml`, `metrics.toml`. The inverted default is what keeps that directory from becoming a catchall.

## Settled

**`sublemma` turned on neither geometry nor presentation.** It was replaced by a question that asks for a decomposition — which stretches are cited forms, and which text, if any, glosses each — and defers every judgment about what kind of thing a form/gloss pair is to a later stage. That is the `decomposition` pass; see [`decomposition-guidance.md`](decomposition-guidance.md). The `sublemma` pilot's case law does not carry over.

**`voice_variant` is merged.** A pronominal form is a form like any other, and the distinction is recoverable from the form afterward.

**`rubrique_indent` is split for `decomposition`.** Its population excludes blocks in HISTORIQUE and ÉTYMOLOGIE rubriques, which host century markers, etymological argument, and language-form lists rather than cited usage. The predicate keys on the single rubrique name the census assigns each block; whether that is always the right one where rubriques nest has not been confirmed with an XML-aware traversal.

## Open questions

**Whether a contextual-restriction pass should exist.** The `En parlant de` family is systematically untagged in the source rather than inconsistently tagged, which makes it a different phenomenon from the bare qualification markers. It is also what the README's flagship example promises. It is scope-shaped and so does not affect closure.

**Whether the marker span carries its trailing separator.** Token-range selection trims trailing commas from a marker, which is right for a form and may be wrong for a marker, depending on what the normalization tables key on.
