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
end

function read_document(path::AbstractString; patches::Vector{Patch} = Patch[])::SourceDocument
	file = basename(path)
	raw = read_source_text(path)
	(view, edits) = apply_patches(raw, file, patches)
	assert_line_count_preserved(raw, view, file)
	assert_untouched_lines(raw, view, Set(patch.line for patch in patches), file)
	SourceDocument(
		file,
		path,
		raw,
		bytes2hex(sha256(codeunits(raw))),
		view,
		bytes2hex(sha256(codeunits(view))),
		TransformMap(file, edits),
		XML.parse(XML.FlatNode, view),
	)
end

function read_corpus(directory::AbstractString; patches_path::Union{Nothing, AbstractString} = nothing)
	grouped = patches_path === nothing ? Dict{String, Vector{Patch}}() : load_patches(patches_path)
	paths = sort(filter(path -> endswith(path, ".xml"), readdir(directory; join = true)))
	[read_document(path; patches = patches_for(grouped, basename(path))) for path in paths]
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
