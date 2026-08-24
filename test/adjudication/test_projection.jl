using DeepLittre.Source: read_corpus, slice, covers
using DeepLittre.Census: census, all_blocks, Indent
using DeepLittre.Adjudication: project, locate, to_view, view_sha256, SelectionFailure,
	block_text_projection, block_text_version

@testset "adjudication projection" begin
	documents = read_corpus(sample_source)
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

	@testset "non-synthetic segments are byte-identical copies" begin
		for candidate in projection.segments
			candidate.synthetic && continue
			projected = slice(projection.text, DeepLittre.Source.RawSpan(
				projection.file, candidate.projected_start, candidate.projected_end,
			))
			source = slice(document.parser_view, DeepLittre.Source.ViewSpan(
				projection.file, candidate.view_start, candidate.view_end,
			))
			@test String(projected) == String(source)
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

	@testset "hash covers the projected text" begin
		@test view_sha256(projection) == view_sha256(project(
			document, DeepLittre.Adjudication.element_at(document, block.view_span),
		))
	end

	@testset "every eligible block projects without entity references" begin
		for candidate in all_blocks(corpus)
			candidate.kind isa Indent || continue
			target = harness.documents[candidate.raw_span.file]
			@test project(target, DeepLittre.Adjudication.element_at(target, candidate.view_span)) isa
				DeepLittre.Adjudication.ProjectedView
		end
	end
end
