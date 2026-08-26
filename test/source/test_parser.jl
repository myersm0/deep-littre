using XML
using DeepLittre.Source: read_document, read_corpus, node_view_span, node_raw_span,
	root_element, slice, elements, EncodingViolation

# Assertions about the exact pinned XML.jl version. If the dependency changes these run
# before any release is accepted.

function walk(action, node)
	action(node)
	for child in XML.children(node)
		walk(action, child)
	end
	nothing
end

@testset "parser verification" begin
	documents = read_corpus(corpus_source)

	@testset "pinned reader version" begin
		@test pkgversion(XML) == v"0.4.6"
	end

	@testset "sourcetext equals the slice named by sourcespan" begin
		mismatches = 0
		nodes = 0
		for document in documents
			walk(document.document) do node
				nodes += 1
				String(XML.sourcetext(node)) ==
					String(SubString(document.parser_view, XML.sourcespan(node))) || (mismatches += 1)
			end
		end
		@test nodes > 4000
		@test mismatches == 0
	end

	@testset "element spans cover the closing tag" begin
		document = first(filter(d -> d.file == "a.xml", documents))
		entry = first(elements(root_element(document)))
		text = slice(document.parser_view, node_view_span(document, entry))
		@test startswith(text, "<entree ")
		@test endswith(text, "</entree>")
	end

	@testset "non-ascii element names round-trip" begin
		found = 0
		for document in documents
			walk(document.document) do node
				XML.nodetype(node) == XML.Element && XML.tag(node) == "résumé" || return
				found += 1
				span = node_view_span(document, node)
				text = slice(document.parser_view, span)
				@test startswith(text, "<résumé>")
				@test endswith(text, "</résumé>")
			end
		end
		@test found == 2
	end

	@testset "flat and lazy readers agree on the development corpus" begin
		for document in documents
			flat = XML.FlatNode[]
			walk(node -> push!(flat, node), document.document)
			lazy = XML.LazyNode[]
			walk(node -> push!(lazy, node), XML.parse(XML.LazyNode, document.parser_view))
			@test length(flat) == length(lazy)
			@test [XML.sourcespan(node) for node in flat] == [XML.sourcespan(node) for node in lazy]
			@test [XML.tag(node) for node in flat] == [XML.tag(node) for node in lazy]
		end
	end

	@testset "unpatched documents anchor at identity" begin
		for document in documents
			@test document.raw_text == document.parser_view
			walk(document.document) do node
				XML.nodetype(node) == XML.Element || return
				view = node_view_span(document, node)
				(raw, synthetic) = node_raw_span(document, node)
				@test !synthetic
				@test raw.start_byte == view.start_byte
				@test raw.end_byte == view.end_byte
			end
		end
	end

	@testset "corpus satisfies the encoding policy" begin
		# The same selection the pipeline uses, so a stray editor or AppleDouble file in the source
		# directory is neither read here nor read there.
		for path in DeepLittre.Source.source_paths(corpus_source)
			@test read(path) |> bytes -> begin
				DeepLittre.Source.check_encoding(bytes, basename(path))
				true
			end
		end
	end

	@testset "patched document anchors back into raw source" begin
		document = read_document(
			joinpath(fixture_root, "patching", "split.xml");
			patches = DeepLittre.Source.patches_for(
				DeepLittre.Source.load_patches(joinpath(fixture_root, "patching", "patches.toml")),
				"split.xml",
			),
		)
		@test document.raw_text != document.parser_view
		@test count(==('\n'), document.raw_text) == count(==('\n'), document.parser_view)

		indents = XML.FlatNode[]
		walk(document.document) do node
			XML.nodetype(node) == XML.Element && XML.tag(node) == "indent" && push!(indents, node)
		end
		@test length(indents) == 3

		created = indents[2]
		@test occursin("Substantivement", String(XML.sourcetext(created)))
		(raw, synthetic) = node_raw_span(document, created)
		@test synthetic
		@test occursin("Substantivement", slice(document.raw_text, raw))
		@test !occursin("<indent>", slice(document.raw_text, raw))
	end
end
