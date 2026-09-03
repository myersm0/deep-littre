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

`surface_json(pass, item)` is the same surface as a producer receives it: one JSON object carrying the pass name, version, and question; the block's raw locator and `surface_sha256`; and the kind, target text, markers, and context that the hash covers. The producer answers in text against `target`, quoting `source` and `surface_sha256` so the answer can be matched to the item it was asked about and refused if the surface has since changed. The pipeline reads nothing else back from the producer; how the surface is turned into a prompt and the answer into a `Decision` lives with the producer.

## Selections

The producer selects exact substrings in projected text. The harness requires each selection to have exactly one match and converts it to a half-open `ProjectedSpan`.

Durable structural assertions therefore store projected node, form, gloss, and residual intervals. A structural selection may name several forms. Disjoint selections represent separately printed forms; repeated selection of one surface span is permitted only when every coincident form carries a distinct editorial value. Scope assertions store projected marker and target intervals. Current raw spans are reconstructed only when a valid record is applied.

## Structural decisions

`sublemma` and `voice_variant` are exhaustive structural alternatives. A positive answer must provide a complete partition of source-visible projected text into asserted node spans and residual spans. Negative and unresolved answers carry no assertions.

Crossing/coincident structural claims and constituents outside their node fail closed. Form constituents are the deliberate exception to coincident constituent spans: coincident forms are valid only as distinct editorial readings of the same printed surface. Partially overlapping form spans fail closed.

Nodes nest by geometry, but not into one another's constituents: a node whose span lies inside another node's form or gloss fails closed. Nesting is expressible only where the inner node falls in the part of the outer node that the outer's own constituents do not claim.

## Scope decisions

`qualification_scope` only changes where an explicit `<semantique>`/`<nature>` marker applies. Its marker selection must correspond to one of the explicit markers detected in the classification surface; a selection covering part of a marker resolves to the whole marker, so one `<nature>` holding two labels cannot be scoped in halves.

A marker governs one target. A second scope for a marker already scoped in the same decision fails closed rather than being accepted and dropped at resolution.

`bare_qualification` handles the complementary case in which the source prints a qualification label as ordinary prose. Its positive assertion selects that exact prose span as the marker and a projected target span as its scope; it may not claim text already represented by an explicit marker. Both passes adjudicate boundary/scope only. The meaning of the selected marker is still resolved deterministically by the committed normalization tables.

## Rejection categories

A decision the harness will not commit is returned as a `ReviewItem` carrying one of a closed set of categories. The set is `rejection_categories` in `harness.jl`; `ReviewItem` cannot be constructed with a category outside it.

- `schema_violation` — the decision's shape does not fit the pass: assertions on a non-positive outcome, a scope from a structural pass, a second target for one marker, no decision procedure, and the like;
- `ineligible_target` — the block is outside the pass's population;
- `unmappable_selection` — a selection has no match, or more than one, in the projected text;
- `structural_conflict` — node spans cross, coincide, lie inside another node's constituent, or collide with a span another pass has already claimed;
- `constituent_escapes_node` — a form or gloss lies outside its node;
- `residual_overlaps_node`, `residuals_overlap` — a residual is not disjoint from a node or from another residual;
- `incomplete_partition` — an exhaustive claim leaves source-visible text unaccounted for;
- `not_a_marker` — a scope selection does not name an explicit marker, or a bare selection overlaps one;
- `scope_contains_marker` — a scope target is not disjoint from its marker.

## Record applicability

The raw source block span is a lookup hint. `surface_sha256` is the stale-verdict check.

At load/application time:

1. if the old locator still names an eligible block, its surface must hash identically;
2. if that locator no longer names a block, a unique same-file eligible block with the same surface hash may be recovered automatically;
3. zero/multiple matches or changed content make the record stale.

This intentionally handles ordinary coordinate drift while refusing to guess about changed classification material.

## Store integrity

Malformed persisted geometry is not “stale.” It is an integrity error. The store also rejects duplicate record ids, multiple records for the same locator in one pass, and records that name no decision procedure.

`decision_procedure` and `decision_reference` are opaque to the pipeline. It requires the first to be present and interprets neither; what they mean, and how they trace a verdict back to the process that produced it, is the producer's convention.

The store has no manifest. Pass metadata belongs to code; producer provenance belongs to each record.
