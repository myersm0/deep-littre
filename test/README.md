# Test suite

```
julia --project=. -e 'using Pkg; Pkg.test()'
```

Needs no build and no `data/source`. Everything it reads is committed: the development corpus in `corpus/`, the routing tables in `data/`, the fixtures in `fixtures/`, and the pinned schema in `vendor/`. Schema validation runs where `java` and `vendor/jing.jar` are present and skips cleanly where they are not.

## Layout

`runtests.jl` is the driver. It defines `corpus_source` and `corpus_adjudication`, the shared accessors, and the include order, which runs bottom-up: spans and encoding before parsing, parsing before the census, the census before adjudication, adjudication before resolution, resolution before the renderers. A failure low in that order usually explains the failures above it.

`source/` covers span arithmetic, the encoding and BOM policy, patch guards and their invariants, the transform map between raw and parser-view coordinates, and the XML.jl assertions in `test_parser.jl` — the ones that pin `sourcetext`/`sourcespan` behaviour to the exact version in `Project.toml`. Those are assertions about the dependency, not about Deep-Littré, and they run before any release that moves the pin.

`census/` checks block geometry, kind assignment by ancestry, and the population hash that fixes the adjudication denominator.

`adjudication/` covers the projection and its provenance map, the authoring harness including stale-surface and geometry checks, the canonical store writer, the committed development store, and the `voice_variant` and `qualification_scope` passes.

`resolve/` covers sense derivation and closure, etymology segmentation, and author resolution through the `ID.` anaphora chain. `render/` covers both renderers, their cross-output parity, and rubrique structure.

## Reading the assertion count

The total is around 28,400, which overstates behavioural coverage by a wide margin. Two files produce 91% of it:

| file | assertions |
|---|---|
| `census/test_census.jl` | 20,749 |
| `source/test_parser.jl` | 5,063 |
| everything else, 15 files | ~2,600 |

Both are loops asserting an invariant over every block or node in the corpus. That is the right shape for an invariant and a poor proxy for how much behaviour is pinned. The adjudication core — harness, store, committed store, and the two passes beyond `sublemma` — is 138 assertions.

Line coverage is a separate measurement and sits near 95%:

```
julia --project=. -e 'using Pkg; Pkg.test(coverage = true)'
```

It is also a poor proxy here, and the reason is worth keeping in mind when adding tests. `<xr>` inside `<note><seg>` was schema-invalid for the whole corpus while the emitting line ran on all 58 rubriques in the development corpus, because none of them happened to contain a cross-reference. The gap was in the input space, not the line coverage. Twenty-five entries cannot span the input space, so a construct that matters should get a synthetic fixture rather than a hope that the corpus happens to carry it.

## Test data

`corpus/` is the 25-entry development corpus and its adjudication store; see `corpus/README.md`.

`fixtures/synthetic/` holds hand-written entries isolating one construct each — a résumé indent, a bare register label, a nature-wrapped reflexive form, a cross-reference in rubrique prose. These are where a construct absent from the development corpus gets pinned. `fixtures/real/` holds entries lifted from XMLittré whose behaviour is worth keeping stable, and `fixtures/patching/` holds a split-patch case with its own patch file.

`probe_lex0.xml` isolates one Lex-0 construct per minimal entry, paired with controls, and `probe_expected.tsv` records the verdict each one should get. Seven are invalid by design. The probe is the arbiter for schema questions: when the validator and the schema appear to disagree, a new probe entry settles it before anyone debugs by hand. It runs through `test/validate_probe.jl` rather than through this suite, because it needs `jing`.

`lex0_baseline.tsv` records the committed validation totals, ranked error signatures, and invalid entry ids for the full corpus. `sampling/` holds v0.2-era calibration artifacts retained for provenance review; nothing in the suite reads them.
