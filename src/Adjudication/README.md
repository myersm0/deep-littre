# Adjudication

Adjudication stores semantic judgments that are not explicit in XMLittré, i.e. the outcomes of the forthcoming "classification campaign."

The record shape and the applicability rules are specified in `docs/architecture/adjudication-authoring.md`. This file covers how the module is arranged, and the implementation behaviour behind those rules.

## Files

`harness.jl` is the boundary a producer works against: `present` builds an item, `surface_json` serializes what the producer sees, `commit!` validates a `Decision` and returns a record or a `ReviewItem`. `store.jl` owns the on-disk store. `records.jl` holds the record types, `canonical.jl` the deterministic serialization the hash runs over, and `projection.jl` the `block_text` projection.

`surface_json` emits everything `surface_sha256` covers plus the pass, its question, and the locator and hash a response must quote. Nothing is interpreted on the way back in: the producer answers in text and `commit!` locates it.

## Passes

A pass is defined in code by its name/version, population, projection, and question. The current structural passes are `sublemma` and `voice_variant`; `qualification_scope` records departures from the default containment scope of explicit qualification markup, while `bare_qualification` identifies qualification markers printed as unmarked prose and records what they govern. The latter adjudicates only the marker boundary and scope; semantic routing of the selected text remains deterministic resolver-side enrichment.

`current_passes` is the only place a pass is declared. Whether a pass asserts nodes or asserts marker scope is read off its `node_type`, which `commit` already requires to be one or the other, and `structural_passes`/`scope_passes` are derived from it. Adding a pass to that tuple is therefore enough to put it into closure, scope application, and coverage. The resolver keeps no second list to fall behind. Adding a structural pass tightens closure immediately: blocks it has not examined stop deriving an ordinary `Sense` until it has.

`exhaustive_extraction` belongs to the pass contract, not to the durable record. For a structural pass, a positive decision must completely partition the projected target into asserted nodes plus explicit residual text. The harness verifies that partition before writing the record, and application verifies persisted geometry again.

## Cross-pass conflict

Committing a positive structural verdict checks the other structural passes for an applicable positive verdict on the same block, and rejects a claim whose node span coincides with or crosses one already asserted there. Two passes may not carve the same stretch of text into incompatible structures.

The check reads the persisted store, so it sees verdicts that have been written and not ones still held in memory from the current session. Authoring one structural pass to completion and writing it before beginning the next is what makes the check meaningful; a conflict that slips past it is still caught at resolution, where the block fails closure and both verdicts are withheld.

Records are indexed by block anchor on first use and the index is rebuilt when the pass directory changes, so the cost of the check does not grow with the size of the store.

## Classification surface

The classifier acts on a canonical projected target rather than raw XML. The stale-verdict check is one `surface_sha256` over exactly the canonical information supplied for classification: target kind, projected target text, explicit qualification markers, and deterministic citation context.

A verdict therefore becomes stale when the material the classifier actually judged changes. XML serialization or coordinates may move without invalidating the verdict if the classification surface remains identical. Citation context is intentionally part of that surface, so editing cited evidence may stale a structural verdict even when the target text itself is unchanged.

## Durable record

A record contains:

- record id
- pass and pass version
- current raw block span as a locator
- `surface_sha256`
- outcome
- node, scope and residual selections as byte intervals in the projected target
- minimal producer provenance (`decision_procedure`, optional reference, timestamp, notes)

The raw locator is not semantic identity. Projected intervals survive coordinate drift because they refer to the classifier-facing text rather than to XML coordinates.

## Applicability

Application is deliberately conservative:

1. try the stored locator
2. if it still names an eligible block, require its classification surface hash to match
3. if the locator no longer names a block, search the same source file for an eligible block with the same surface hash, and accept only a unique match
4. otherwise mark the record stale

The fallback is for coordinate drift, not changed content. If a block still exists at the old locator but its surface changed, no fallback is attempted.

Development resolution skips stale records and reports them. `--strict-adjudications` makes any stale record fatal and is used for releases.

Malformed JSONL, duplicate records, impossible projected spans, invalid structural geometry, invalid marker references, or an incomplete structural partition are store-integrity errors rather than stale verdicts.

## Store

The store is pass directories containing deterministic JSONL shards, sharded by source file. Pass, population and projection definitions live in code, and the record keeps only the pass version needed to say that the semantic question itself changed.

`write_pass!` replaces a pass atomically through a staging directory, so a pass is written whole rather than appended to. `merge_pass!` adds a batch to a pass and refuses any record whose locator the pass already holds, so superseding a verdict has to be intentional, by regenerating the pass. Both go through the same staging path.

Over the full corpus, one verdict per structural block in each of the two current structural passes is 682,250 records (341,125 blocks × 2). Storage cost is measured by the stress harness rather than fixed here because record size depends on the verdict geometry and evolves with the contract.
