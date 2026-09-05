# Development corpus

26 XMLittré entries and the adjudication records made against them. Most of the test suite reads this committed corpus; it does not depend on `data/source`.

## Contents

`source/` holds one file per source letter so `read_corpus` reads it exactly as it reads the full corpus. Each entry is a byte-identical slice of Gannaz's markup rather than a re-serialization, so spans and the census behave here as they do on the full corpus. `manifest.tsv` records why each entry was selected.

`.a.xml.swp` is deliberate. `source_paths` excludes dotfiles so a stray editor file or macOS sidecar cannot enter the census as an extra document.

## The adjudication store

`adjudication/` is a real committed store holding six records across the three version-1 passes. It is not the production store; `data/adjudication` remains untracked until corpus adjudication begins.

Each record carries a raw block span only as its current locator and one `surface_sha256` over the deterministic classification surface. Semantic selections are stored in projection-relative coordinates. At load time a matching record is materialized onto current raw source spans. If the locator has moved, the harness may recover the uniquely matching surface in the same source file. If the surface itself changed, the record is stale.

`test/adjudication/test_committed_store.jl` validates this store against the corpus beside it, regenerates the canonical JSONL byte-for-byte, and resolves through it.

## Building against it

```
julia --project=. bin/run_pipeline.jl test/corpus/source /tmp/out \
    --patches none \
    --store test/corpus/adjudication \
    --strict-adjudications
```

`--patches none` is required because the committed patch set targets the full source corpus rather than these extracted entries.
