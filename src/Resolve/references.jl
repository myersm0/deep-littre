"""
Littré writes a cross-reference as a lemma, optionally with a homograph index and a variante
number: `abject`, `avoir.1`, `zéro#var2`, `faux.1#var26`. A homograph index names the source
entry whose `sens` attribute carries that number; it is not an ordinal in document order. None of
those references is an identifier of anything the pipeline emits, so the reference has to be resolved
against the corpus before either
renderer can point at its destination.

Resolution produces a raw anchor, not a rendered identifier. `xml:id` values are the TEI renderer's
business and SQLite keys on anchors, so the resolver states which entry or variante is meant and
each renderer names it in its own terms. A reference that does not resolve carries no anchor, and
the compliance contract then requires a textual reference rather than a guessed pointer.
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
		push!(get!(by_headword, fold_headword(entry.headword), Census.SourceEntry[]), entry)
		push!(get!(by_lemma, lemma_of(entry.headword), Census.SourceEntry[]), entry)
	end
	CrossReferenceIndex(by_headword, by_lemma)
end

"""
	target_entries(index, lemma)

An exact headword match wins over a lemma match. `MI` is a headword in its own right and also the
lemma of nothing else, while `abject` is the lemma of `ABJECT, ECTE` and matches no headword; the
two need different lookups and the exact one is the more specific claim.
"""
function target_entries(index::CrossReferenceIndex, lemma::AbstractString)::Vector{Census.SourceEntry}
	folded = fold_headword(lemma)
	exact = get(index.by_headword, folded, Census.SourceEntry[])
	length(exact) == 1 && return exact
	get(index.by_lemma, folded, Census.SourceEntry[])
end

function only_or_nothing(entries)::Union{Nothing, Census.SourceEntry}
	result = nothing
	for entry in entries
		result === nothing || return nothing
		result = entry
	end
	result
end

function variante_span(entry::Census.SourceEntry, number::Int)::Union{Nothing, RawSpan}
	position = 0
	for block in entry.blocks
		block.kind isa Census.Variante || continue
		position += 1
		position == number && return block.raw_span
	end
	nothing
end

"""
	resolve_reference(index, reference)

The raw anchor a `<a ref="...">` names, or `nothing` where no honest answer exists: a lemma no
entry carries, a homograph index that no candidate carries in its source `sens` attribute, a variante
number the entry does not have, or a bare lemma shared by several entries that the source declined
to disambiguate.
"""
function resolve_reference(
	index::CrossReferenceIndex, reference::AbstractString,
)::Union{Nothing, RawSpan}
	isempty(reference) && return nothing
	body, _, variante = partition_reference(reference)
	lemma, _, homograph = partition_homograph(body)
	candidates = target_entries(index, lemma)
	isempty(candidates) && return nothing
	entry = if isempty(homograph)
		length(candidates) == 1 ? only(candidates) : nothing
	else
		number = tryparse(Int, homograph)
		number === nothing ? nothing : only_or_nothing(
			entry for entry in candidates if entry.homograph == number
		)
	end
	entry === nothing && return nothing
	isempty(variante) && return entry.raw_span
	number = tryparse(Int, variante)
	number === nothing ? nothing : variante_span(entry, number)
end

function partition_reference(reference::AbstractString)
	position = findfirst("#var", reference)
	position === nothing && return (reference, "#var", "")
	(
		reference[1:prevind(reference, first(position))],
		"#var",
		reference[nextind(reference, last(position)):end],
	)
end

function partition_homograph(body::AbstractString)
	position = findlast('.', body)
	position === nothing && return (body, ".", "")
	tail = body[(nextind(body, position)):end]
	all(isdigit, tail) && !isempty(tail) ? (body[1:(prevind(body, position))], ".", tail) :
		(body, ".", "")
end

resolve_segment(segment, ::CrossReferenceIndex) = segment

resolve_segment(segment::EtymCrossReference, index::CrossReferenceIndex) = EtymCrossReference(
	segment.label, segment.target, segment.printed, segment.range,
	resolve_reference(index, segment.target),
)
