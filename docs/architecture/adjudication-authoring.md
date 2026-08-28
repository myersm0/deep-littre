# Adjudication authoring

The harness is the controlled boundary between a human/LLM classifier and the authoritative adjudication store. Producers answer semantic questions in text; they do not author source coordinates, hashes, ids, or JSONL directly.

## Pass contract

Each pass declares in code its name/version, population, projection, structural node type if any, whether positive structural extraction must be exhaustive, and the question shown to the producer.

The pass version is the semantic invalidation knob. It changes when the actual classification question changes.

## Classification surface

For each eligible block the harness constructs a canonical classification surface consisting of:

- block kind;
- projected direct-content text;
- explicit `<semantique>`/`<nature>` marker locations and text;
- deterministic citation context supplied with the target.

The serialization is deterministic and length-prefixed and is hashed once as `surface_sha256`.

## Selections

The producer selects exact substrings in projected text. The harness requires each selection to have exactly one match and converts it to a half-open `ProjectedSpan`.

Durable structural assertions therefore store projected node, form, gloss, and residual intervals. Scope assertions store projected marker and target intervals. Current raw spans are reconstructed only when a valid record is applied.

## Structural decisions

`sublemma` and `voice_variant` are exhaustive structural alternatives. A positive answer must provide a complete partition of source-visible projected text into asserted node spans and residual spans. Negative and unresolved answers carry no assertions.

Crossing/coincident structural claims and constituents outside their node fail closed.

## Scope decisions

`qualification_scope` only changes where an explicit source marker applies. The meaning of the marker is still resolved deterministically by the committed normalization tables. A scope marker must correspond to an explicit marker detected in the current classification surface.

## Record applicability

The raw source block span is a lookup hint. `surface_sha256` is the stale-verdict check.

At load/application time:

1. if the old locator still names an eligible block, its surface must hash identically;
2. if that locator no longer names a block, a unique same-file eligible block with the same surface hash may be recovered automatically;
3. zero/multiple matches or changed content make the record stale.

This intentionally handles ordinary coordinate drift while refusing to guess about changed classification material.

## Store integrity

Malformed persisted geometry is not “stale.” It is an integrity error. The store also rejects duplicate record ids and multiple records for the same locator in one pass.

The store has no manifest. Pass metadata belongs to code; producer provenance belongs to each record.
