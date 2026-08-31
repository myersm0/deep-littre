using DeepLittre.Source: read_corpus, slice, covers
using DeepLittre.Census: census, all_blocks, Indent, RubriqueDirect
using DeepLittre.Adjudication: project, locate, locate_projected, to_projected, to_view, projected_text, SelectionFailure,
	block_text_projection, block_text_version, ProjectedSpan

@testset "adjudication projection" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	harness = build_harness(documents, corpus)
	block = angoisse_block(harness, corpus)
	document = harness.documents[block.raw_span.file]
	projection = project(document, DeepLittre.Adjudication.element_at(document, block.view_span))

	@testset "direct content only" begin
		@test projection.name == block_text_projection
		@test projection.version == block_text_version
		@test projection.text ==
			"Familièrement. Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."
		@test !occursin("Je vous présente", projection.text)
		@test !occursin('<', projection.text)
		@test !occursin('\n', projection.text)
	end

	@testset "rubrique direct projection excludes child blocks" begin
		hardeau = only(filter(entry -> entry.headword == "HARDEAU", DeepLittre.Census.all_entries(corpus)))
		supplement = only(filter(
			rubrique -> rubrique.name == "SUPPLÉMENT AU DICTIONNAIRE", hardeau.rubriques,
		))
		direct = only(filter(candidate -> candidate.kind isa RubriqueDirect, supplement.blocks))
		target = harness.documents[direct.raw_span.file]
		direct_projection = project(
			target, DeepLittre.Adjudication.element_at(target, direct.view_span),
		)
		@test direct_projection.text == "HARDEAU. Ajoutez :"
		@test !occursin("Vaurien", direct_projection.text)
		@test !occursin("XVIe", direct_projection.text)
	end

	@testset "every rubrique direct block has a nonempty projection" begin
		for candidate in all_blocks(corpus)
			candidate.kind isa RubriqueDirect || continue
			target = harness.documents[candidate.raw_span.file]
			direct_projection = project(
				target, DeepLittre.Adjudication.element_at(target, candidate.view_span),
			)
			@test !isempty(direct_projection.text)
		end
	end

	@testset "literal segments are byte-identical copies" begin
		for candidate in projection.segments
			(candidate.synthetic || !candidate.literal) && continue
			projected = slice(projection.text, DeepLittre.Source.RawSpan(
				projection.file, candidate.projected_start, candidate.projected_end,
			))
			source = slice(document.parser_view, DeepLittre.Source.ViewSpan(
				projection.file, candidate.view_start, candidate.view_end,
			))
			@test String(projected) == String(source)
		end
	end


	@testset "entity references retain source provenance" begin
		directory = mktempdir()
		path = joinpath(directory, "entities.xml")
		write(path, "<root><indent>A &amp; B &#233; C &#x26; D</indent></root>")
		entity_document = DeepLittre.Source.read_document(path)
		root = DeepLittre.Source.root_element(entity_document)
		indent = only(DeepLittre.Source.element_children(root, "indent"))
		entity_projection = project(entity_document, indent)

		@test entity_projection.text == "A & B é C & D"
		@test entity_projection.version == block_text_version

		amp = locate(entity_projection, "A & B")
		amp_source = String(slice(entity_document.parser_view, amp))
		@test amp_source == "A &amp; B"
		@test projected_text(entity_projection, amp) == "A & B"

		eacute = locate(entity_projection, "é")
		@test String(slice(entity_document.parser_view, eacute)) == "&#233;"
		@test projected_text(entity_projection, eacute) == "é"

		hex_amp = locate(entity_projection, "C & D")
		@test String(slice(entity_document.parser_view, hex_amp)) == "C &#x26; D"
		@test projected_text(entity_projection, hex_amp) == "C & D"

		mapped = filter(candidate -> !candidate.synthetic && !candidate.literal, entity_projection.segments)
		@test length(mapped) == 3
		for candidate in mapped
			@test candidate.view_end - candidate.view_start !=
				candidate.projected_end - candidate.projected_start
		end
	end

	@testset "synthetic segments carry no source interval" begin
		for candidate in projection.segments
			candidate.synthetic || continue
			@test candidate.view_start == 0
			@test candidate.view_end == 0
			@test candidate.projected_end - candidate.projected_start == 1
		end
	end

	@testset "markup-free selections resolve to exactly their own text" begin
		for selection in (
			"Familièrement.",
			"Avaler des poires d'angoisse",
			"de vifs déplaisirs.",
			"subir des mortifications, de vifs déplaisirs.",
		)
			span = locate(projection, selection)
			@test String(slice(document.parser_view, span)) == selection
		end
	end

	@testset "a stored source interval recovers projected text rather than XML" begin
		span = locate(projection, projection.text)
		@test projected_text(projection, span) == projection.text
		@test !occursin('<', projected_text(projection, span))
	end

	@testset "a selection spanning inline markup covers it" begin
		# The result is the smallest view interval covering the selected source-visible
		# characters, so interior markup is included by construction.
		span = locate(projection, projection.text)
		covered = String(slice(document.parser_view, span))
		@test startswith(covered, "Familièrement.")
		@test endswith(covered, "de vifs déplaisirs.")
		@test occursin("</semantique>", covered)
		@test covers(block.raw_span, DeepLittre.Source.to_raw(document.transform, span)[1])
	end

	@testset "selections fail closed" begin
		@test_throws SelectionFailure locate(projection, "")
		@test_throws SelectionFailure locate(projection, "not present in the target")
		@test_throws SelectionFailure locate(projection, "des")
		@test_throws SelectionFailure locate(projection, " ")
	end

	@testset "projected and view coordinates round-trip" begin
		selected = locate_projected(projection, "Avaler des poires d'angoisse")
		view = to_view(projection, selected.start_byte, selected.end_byte)
		@test view !== nothing
		@test to_projected(projection, view) == selected
		@test projected_text(projection, selected) == "Avaler des poires d'angoisse"
	end

	@testset "every eligible corpus block projects" begin
		for candidate in all_blocks(corpus)
			candidate.kind isa Indent || continue
			target = harness.documents[candidate.raw_span.file]
			@test project(target, DeepLittre.Adjudication.element_at(target, candidate.view_span)) isa
				DeepLittre.Adjudication.ProjectedView
		end
	end
end
