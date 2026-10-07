using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: present, commit!, Decision, FormSelection, ReviewItem,
	ProjectedSpan, decomposition_pass, sublemma_pass

function span_of(text::AbstractString, fragment::AbstractString; occurrence::Int = 1)
	found = findall(fragment, text)[occurrence]
	return ProjectedSpan(first(found), nextind(text, last(found)))
end

function geometry(record)
	return (
		record.outcome,
		[
			(
				assertion.span,
				[(part.name, part.span) for part in assertion.constituents],
			)
			for assertion in record.assertions
		],
		record.residuals,
	)
end

@testset "selections may be projected spans" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	harness = build_harness(documents, corpus)
	item = present(harness, sublemma_pass, angoisse_block(harness, corpus))
	text = item.projection.text

	node = "Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."
	form = "Avaler des poires d'angoisse"
	gloss = "subir des mortifications, de vifs déplaisirs."
	residual = "Familièrement."

	@testset "a span selects exactly what its text would" begin
		by_text = commit!(
			harness, sublemma_pass, item,
			Decision(
				:positive;
				exhaustive = true,
				selections = [FormSelection(node, form, gloss)],
				residuals = [residual],
			);
			decision_procedure = "test",
		)
		by_span = commit!(
			harness, sublemma_pass, item,
			Decision(
				:positive;
				exhaustive = true,
				selections = [FormSelection(
					span_of(text, node), span_of(text, form), span_of(text, gloss),
				)],
				residuals = [span_of(text, residual)],
			);
			decision_procedure = "test",
		)
		@test geometry(by_text) == geometry(by_span)
	end

	@testset "a span outside the target is unmappable" begin
		beyond = ProjectedSpan(1, ncodeunits(text) + 5)
		failure = try
			commit!(
				harness, sublemma_pass, item,
				Decision(
					:positive;
					exhaustive = true,
					selections = [FormSelection(beyond, form, gloss)],
					residuals = [residual],
				);
				decision_procedure = "test",
			)
			nothing
		catch caught
			caught
		end
		@test failure isa ReviewItem
		@test failure.category == "unmappable_selection"
	end

	@testset "a span can select text that occurs more than once" begin
		directory = mktempdir()
		block_text = "Voir. Un oiseau, une bête. Voir."
		write(
			joinpath(directory, "a.xml"),
			"<?xml version=\"1.0\" encoding=\"UTF-8\"?><xmlittre><entree terme=\"TEST\">" *
			"<entete><nature>s. m.</nature></entete><corps><variante>" *
			"<indent>$(block_text)</indent></variante></corps></entree></xmlittre>",
		)
		tiny_documents = read_corpus(directory)
		tiny_corpus = census(tiny_documents)
		tiny_harness = build_harness(tiny_documents, tiny_corpus)
		tiny_block = only(filter(
			block -> block.kind isa DeepLittre.Census.Indent,
			DeepLittre.Census.all_blocks(tiny_corpus),
		))
		tiny_item = present(tiny_harness, decomposition_pass, tiny_block)
		target = tiny_item.projection.text
		@test target == block_text
		selections = [FormSelection("Un oiseau, une bête.", "Un oiseau", "une bête.")]

		@test_throws ReviewItem commit!(
			tiny_harness, decomposition_pass, tiny_item,
			Decision(
				:positive;
				exhaustive = true,
				selections = selections,
				residuals = ["Voir.", "Voir."],
			);
			decision_procedure = "test",
		)

		record = commit!(
			tiny_harness, decomposition_pass, tiny_item,
			Decision(
				:positive;
				exhaustive = true,
				selections = selections,
				residuals = [
					span_of(target, "Voir."; occurrence = 1),
					span_of(target, "Voir."; occurrence = 2),
				],
			);
			decision_procedure = "test",
		)
		@test length(record.residuals) == 2
		@test record.residuals[1] != record.residuals[2]
	end
end
