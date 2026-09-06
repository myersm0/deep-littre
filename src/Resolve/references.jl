"""
Littré writes a cross-reference as a lemma, optionally with a homograph index and a
fragment: `abject`, `avoir.1`, `zéro#var2`, `faux.1#var26`, `tache#etymologie`. A
homograph index names the source entry whose `sens` attribute carries that number; it is
not an ordinal in document order. A fragment names either a variante of the target entry
or one of its named rubriques. None of those references is an identifier of anything the
pipeline emits, so the reference has to be resolved against the corpus before either
renderer can point at its destination.

Resolution produces a raw anchor, not a rendered identifier. `xml:id` values are the TEI
renderer's business and SQLite keys on anchors, so the resolver states which entry,
variante or rubrique is meant and each renderer names it in its own terms. A reference
that does not resolve carries no anchor, and the compliance contract then requires a
textual reference rather than a guessed pointer.
"""
struct CrossReferenceIndex
	by_headword::Dict{String, Vector{Census.SourceEntry}}
	by_lemma::Dict{String, Vector{Census.SourceEntry}}
end

fold_headword(text::AbstractString)::String =
	Unicode.normalize(lowercase(strip(text)); stripmark = true)

lemma_of(headword::AbstractString)::String = fold_headword(first(split(headword, ',')))

function cross_reference_index(corpus::Census.CorpusCensus)::CrossReferenceIndex
	by_headword = Dict{String, Vector{Census.SourceEntry}}()
	by_lemma = Dict{String, Vector{Census.SourceEntry}}()
	for entry in Census.all_entries(corpus)
		headword = fold_headword(entry.headword)
		push!(get!(by_headword, headword, Census.SourceEntry[]), entry)
		push!(get!(by_lemma, lemma_of(entry.headword), Census.SourceEntry[]), entry)
	end
	return CrossReferenceIndex(by_headword, by_lemma)
end

const SourceEntries = Vector{Census.SourceEntry}

exact_entries(index::CrossReferenceIndex, lemma::AbstractString)::SourceEntries =
	get(index.by_headword, fold_headword(lemma), Census.SourceEntry[])

lemma_entries(index::CrossReferenceIndex, lemma::AbstractString)::SourceEntries =
	get(index.by_lemma, fold_headword(lemma), Census.SourceEntry[])

function only_or_nothing(entries)::Union{Nothing, Census.SourceEntry}
	found = nothing
	for entry in entries
		isnothing(found) || return nothing
		found = entry
	end
	return found
end

"""
	select_entry(candidates, homograph)

The one entry a candidate set names, or `nothing` where it names none or several. A bare
lemma resolves only against a single candidate; a homograph index selects the candidate
whose source `sens` carries that number, and selects nothing when several do.
"""
function select_entry(
	candidates::Vector{Census.SourceEntry}, homograph::AbstractString,
)::Union{Nothing, Census.SourceEntry}
	isempty(candidates) && return nothing
	if isempty(homograph)
		length(candidates) == 1 && return only(candidates)
		return nothing
	end
	number = tryparse(Int, homograph)
	isnothing(number) && return nothing
	return only_or_nothing(entry for entry in candidates if entry.homograph == number)
end

"""
	select_target(index, lemma, homograph)

Exact-headword candidates are tried before lemma candidates. `MI` is a headword in its
own right while `abject` is the lemma of `ABJECT, ECTE` and matches no headword, so the
two need different lookups and the exact one is the more specific claim. A homograph
index is printed per headword form, so narrowing to the exact set before applying one
disambiguates `prime.1` where the lemma set holds a `PRIME` and a `PRIME, ÉE` both
carrying `sens="1"`.

The lemma set is a superset of the exact set, and it is tried whenever the narrower set
answers nothing: `garde.4` must still reach `GARDE, ÉE` when the exact `GARDE` entries
stop at three.
"""
function select_target(
	index::CrossReferenceIndex, lemma::AbstractString, homograph::AbstractString,
)::Union{Nothing, Census.SourceEntry}
	narrowed = select_entry(exact_entries(index, lemma), homograph)
	isnothing(narrowed) || return narrowed
	return select_entry(lemma_entries(index, lemma), homograph)
end

function variante_span(entry::Census.SourceEntry, number::Int)::Union{Nothing, RawSpan}
	position = 0
	for block in entry.blocks
		block.kind isa Census.Variante || continue
		position += 1
		position == number && return block.raw_span
	end
	return nothing
end

"""
	fold_rubrique(name)

The comparison key for a rubrique name and for a fragment naming one. Fragments are
printed lowercase, unaccented and sometimes pluralised against a `@nom` that is none of
those: `#supplement` names `SUPPLÉMENT AU DICTIONNAIRE` and `#proverbes` names both
`PROVERBE` and `PROVERBES`. Folding the first word and dropping a final `s` states that
correspondence as a rule rather than an enumeration; a fragment that no rubrique name
folds onto resolves to nothing.
"""
fold_rubrique(name::AbstractString)::String =
	rstrip(fold_headword(first(split(strip(name), ' '))), 's')

"""
	rubrique_span(entry, fragment)

The rubrique the fragment names, or `nothing`. Littré prints PROVERBE inside the sense
it illustrates as well as at entry level, so an entry can carry several rubriques of one
name; entry-level ones are preferred, and a fragment that still names more than one
resolves to nothing rather than picking among them.
"""
function rubrique_span(
	entry::Census.SourceEntry, fragment::AbstractString,
)::Union{Nothing, RawSpan}
	folded = fold_rubrique(fragment)
	isempty(folded) && return nothing
	matched = filter(
		rubrique -> fold_rubrique(rubrique.name) == folded, entry.rubriques,
	)
	isempty(matched) && return nothing
	outer = filter(rubrique -> isnothing(rubrique.parent_id), matched)
	candidates = isempty(outer) ? matched : outer
	length(candidates) == 1 && return only(candidates).raw_span
	return nothing
end

const variante_fragment = r"^var(\d+)$"

function variante_number(fragment::AbstractString)::Union{Nothing, Int}
	matched = match(variante_fragment, fragment)
	isnothing(matched) && return nothing
	return tryparse(Int, matched[1])
end

"""
	resolve_reference(index, reference)

The raw anchor a `<a ref="...">` names, or `nothing` where no honest answer exists: a
lemma no entry carries, a homograph index that no candidate carries in its source `sens`
attribute, a variante number the entry does not have, a fragment naming no rubrique of
the entry or naming several, or a bare lemma shared by several entries that the source
declined to disambiguate.
"""
function resolve_reference(
	index::CrossReferenceIndex, reference::AbstractString,
)::Union{Nothing, RawSpan}
	isempty(reference) && return nothing
	(body, fragment) = partition_reference(reference)
	(lemma, homograph) = partition_homograph(body)
	entry = select_target(index, lemma, homograph)
	isnothing(entry) && return nothing
	isempty(fragment) && return entry.raw_span
	number = variante_number(fragment)
	isnothing(number) && return rubrique_span(entry, fragment)
	return variante_span(entry, number)
end

function partition_reference(reference::AbstractString)
	position = findfirst('#', reference)
	isnothing(position) && return (reference, "")
	return (
		reference[1:prevind(reference, position)],
		reference[nextind(reference, position):end],
	)
end

function partition_homograph(body::AbstractString)
	position = findlast('.', body)
	isnothing(position) && return (body, "")
	tail = body[nextind(body, position):end]
	isempty(tail) && return (body, "")
	all(isdigit, tail) || return (body, "")
	return (body[1:prevind(body, position)], tail)
end

resolve_segment(segment, ::CrossReferenceIndex) = segment

resolve_segment(segment::EtymCrossReference, index::CrossReferenceIndex) =
	EtymCrossReference(
		segment.label, segment.target, segment.printed, segment.range,
		resolve_reference(index, segment.target),
	)
