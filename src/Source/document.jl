"""
The three source views. `raw_text` is upstream XMLittré as distributed and is the durable
anchoring layer. `parser_view` is raw source after committed patches; v0.3 applies no text
normalization, so the two are byte-identical outside patched lines.
"""
struct SourceDocument
	file::String
	path::String
	raw_text::String
	raw_sha256::String
	parser_view::String
	parser_view_sha256::String
	transform::TransformMap
	document::XML.FlatNode
	elements::Dict{Tuple{Int, Int}, XML.FlatNode}
end

function read_document(path::AbstractString; patches::Vector{Patch} = Patch[])::SourceDocument
	file = basename(path)
	raw = read_source_text(path)
	(view, edits) = apply_patches(raw, file, patches)
	assert_line_count_preserved(raw, view, file)
	assert_untouched_lines(raw, view, Set(patch.line for patch in patches), file)
	parsed = XML.parse(XML.FlatNode, view)
	SourceDocument(
		file,
		path,
		raw,
		text_sha256(raw),
		view,
		text_sha256(view),
		TransformMap(file, edits),
		parsed,
		element_index(file, view, parsed),
	)
end

"""
	element_index(file, view, parsed)

Map every element's parser-view interval to its node, built in one pass at construction.

Without it, locating an element by span means searching from the document root, which at the top
level scans every entry in the file. That is O(blocks × entries) across a build and is
comfortably quadratic on a real letter file.
"""
function element_index(
	file::AbstractString, view::AbstractString, parsed::XML.FlatNode,
)::Dict{Tuple{Int, Int}, XML.FlatNode}
	index = Dict{Tuple{Int, Int}, XML.FlatNode}()
	function walk(node)
		for child in XML.children(node)
			if XML.nodetype(child) == XML.Element
				range = XML.sourcespan(child)
				index[(first(range), nextind(view, last(range)))] = child
			end
			walk(child)
		end
	end
	walk(parsed)
	index
end

element_at(document::SourceDocument, span::ViewSpan)::XML.FlatNode =
	get(document.elements, (span.start_byte, span.end_byte)) do
		error("$(document.file): no element at $(span)")
	end

"""
	source_paths(directory)

The corpus files in `directory`, in a deterministic order. Dotfiles are excluded: an editor swap
file or a macOS AppleDouble sidecar can be named `._a.xml`, which would otherwise enter the census
as another document and change the population hash. One function owns this selection so that
nothing can disagree with the pipeline about which files the corpus contains.
"""
source_paths(directory::AbstractString)::Vector{String} = sort(filter(
	path -> endswith(path, ".xml") && !startswith(basename(path), "."),
	readdir(directory; join = true),
))

"""
	read_corpus(directory; patches_path, progress)

`progress` is called after each file with its name, byte count, patch count and elapsed seconds.
A full-corpus build is long enough that a silent read looks like a hang, and per-file timings are
what localize a slow file without a second run.
"""
function read_corpus(
	directory::AbstractString;
	patches_path::Union{Nothing, AbstractString} = nothing,
	progress = nothing,
)
	grouped = patches_path === nothing ? Dict{String, Vector{Patch}}() : load_patches(patches_path)
	paths = source_paths(directory)
	documents = SourceDocument[]
	for path in paths
		patches = patches_for(grouped, basename(path))
		elapsed = @elapsed document = read_document(path; patches)
		push!(documents, document)
		progress === nothing ||
			progress(document.file, ncodeunits(document.raw_text), length(patches), elapsed)
	end
	documents
end

function root_element(document::SourceDocument)::XML.FlatNode
	for child in XML.children(document.document)
		XML.nodetype(child) == XML.Element && return child
	end
	error("$(document.file): no root element")
end

node_view_span(document::SourceDocument, node::XML.FlatNode)::ViewSpan =
	view_span(document.file, document.parser_view, XML.sourcespan(node))

function node_raw_span(document::SourceDocument, node::XML.FlatNode)::Tuple{RawSpan, Bool}
	(span, synthetic) = to_raw(document.transform, node_view_span(document, node))
	validate_span(document.raw_text, span)
	(span, synthetic)
end

raw_text(document::SourceDocument, span::RawSpan)::SubString = slice(document.raw_text, span)
view_text(document::SourceDocument, span::ViewSpan)::SubString = slice(document.parser_view, span)

raw_sha256(document::SourceDocument, span::RawSpan)::String = span_sha256(document.raw_text, span)

function elements(node::XML.FlatNode)::Vector{XML.FlatNode}
	[child for child in XML.children(node) if XML.nodetype(child) == XML.Element]
end

function element_children(node::XML.FlatNode, name::AbstractString)::Vector{XML.FlatNode}
	[child for child in elements(node) if XML.tag(child) == name]
end

attribute(node::XML.FlatNode, key::AbstractString)::Union{Nothing, String} =
	get(node, key, nothing)
