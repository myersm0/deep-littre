# Development corpus

25 XMLittré entries and the adjudication records made against them. Committed because most of the suite reads it: twelve of sixteen test files call `read_corpus(corpus_source)`, and the four that do not are the span, encoding, patch, and transform-map tests.

## Contents

`source/` holds the entries, one file per source letter so `read_corpus` reads this directory exactly as it reads `data/source`. Each entry is a byte-identical slice of Gannaz's markup rather than a re-serialization, so spans, patches, and the census behave here as they do on the full corpus. `manifest.tsv` records what each entry was selected for.

Selection is reproducible from `scripts/build_sample_corpus.jl`, which strata-samples by entry size and requires coverage of the features named in `feature_probes`: `<exemple>`, proverbs, supplements, HISTORIQUE, wrapped etymons, `<nature>`, domain labels, cross-references, reflexive forms, and homographs.

`.a.xml.swp` is deliberate. `source_paths` excludes dotfiles so that a stray editor file or a macOS AppleDouble sidecar cannot enter the census as an extra document and move the population hash; the fixture is what proves it.

## The adjudication store

`adjudication/` is a real store in the committed format, holding six records across the three version-1 passes. Its byte anchors are relative to `source/`, so it applies to this corpus and no other. It is not the production store — that is `data/adjudication`, which is untracked and empty until corpus adjudication begins.

The six records exist so the store format, the manifest gates, the raw and view checks, and the resolver's reading of verdicts are exercised by something committed. `test/adjudication/test_committed_store.jl` validates the store against the corpus beside it, asserts every record still applies, regenerates the JSONL and requires it byte-identical, and resolves through it. A projection version bump or a census kind change fails that test rather than surfacing at the next full build.

Repair after such a change is `scripts/reanchor.jl`, which re-anchors a record only where the projected text is byte-identical to what the verdict was made against, and reports the rest stranded.

## Building against it

```
julia --project=. scripts/build.jl test/corpus/source /tmp/out --patches none --store test/corpus/adjudication
```

`--patches none` is required. The committed `patches/patches.toml` is line-targeted against the full source files, and these entries are slices, so its line numbers do not exist here.
