using DeepLittre.Source: read_corpus, slice, covers, laminar
using DeepLittre.Census: census
using DeepLittre.Adjudication: present, commit, check, Decision, SubLemmaSelection, ReviewItem,
	sublemma_pass, eligible, SubLemma, fatal, applicable

@testset "authoring harness" begin
	documents = read_corpus(sample_source)
	corpus = census(documents)
	harness = build_harness(documents, corpus)
	block = angoisse_block(harness, corpus)
	document = harness.documents[block.raw_span.file]
	item = present(harness, sublemma_pass, block)

	positive = Decision(
		:positive;
		exhaustive = true,
		selections = [SubLemmaSelection(
			"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
			"Avaler des poires d'angoisse",
			"subir des mortifications, de vifs déplaisirs.",
		)],
		residuals = ["Familièrement."],
	)

	@testset "eligible population is version 1" begin
		pool = eligible(sublemma_pass, corpus)
		@test length(pool) == 351
		@test all(candidate -> candidate.kind isa DeepLittre.Census.Indent ||
			candidate.kind isa DeepLittre.Census.Variante, pool)
	end

	@testset "constituents anchor to exactly their source text" begin
		record = commit(harness, sublemma_pass, item, positive; adjudicator = "test")
		assertion = only(record.assertions)

		@test assertion.node_type isa SubLemma
		@test String(slice(document.raw_text, assertion.span)) ==
			"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."
		forms = Dict(constituent.name => constituent.span for constituent in assertion.constituents)
		@test String(slice(document.raw_text, forms["form"])) == "Avaler des poires d'angoisse"
		@test String(slice(document.raw_text, forms["gloss"])) ==
			"subir des mortifications, de vifs déplaisirs."
		@test String(slice(document.raw_text, only(record.residuals))) == "Familièrement."

		@test covers(record.source, assertion.span)
		@test all(constituent -> covers(assertion.span, constituent.span), assertion.constituents)
		@test record.raw_sha256 == DeepLittre.Source.raw_sha256(document, record.source)
		@test record.outcome == :positive
		@test record.exhaustive
		@test record.method == :human
		@test !isempty(record.context)
	end

	@testset "ids are minted, never derived from coordinates" begin
		first_record = commit(harness, sublemma_pass, item, positive; adjudicator = "test")
		second_record = commit(harness, sublemma_pass, item, positive; adjudicator = "test")
		@test first_record.record_id != second_record.record_id
		@test only(first_record.assertions).node_id != only(second_record.assertions).node_id
		@test first_record.source == second_record.source
	end

	@testset "negative and unresolved outcomes need no assertion" begin
		negative = commit(harness, sublemma_pass, item, Decision(:negative); adjudicator = "test")
		@test negative.outcome == :negative
		@test isempty(negative.assertions)
		@test !negative.exhaustive

		unresolved = commit(
			harness, sublemma_pass, item, Decision(:unresolved; notes = "scope unclear");
			adjudicator = "test",
		)
		@test unresolved.outcome == :unresolved
		@test unresolved.notes == "scope unclear"
	end

	@testset "schema violations fail closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item, Decision(:maybe); adjudicator = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item, Decision(:positive); adjudicator = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:negative; selections = [SubLemmaSelection("Familièrement.", "Familièrement.")]);
			adjudicator = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item, Decision(:negative; exhaustive = true); adjudicator = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item, positive; method = :guess, adjudicator = "test",
		)
	end

	@testset "unmappable selections fail closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [SubLemmaSelection("not in the target", "nope")]);
			adjudicator = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [SubLemmaSelection("des", "des")]);
			adjudicator = "test",
		)
	end

	@testset "constituent escaping its node fails closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [SubLemmaSelection(
				"Avaler des poires d'angoisse", "Familièrement.",
			)]);
			adjudicator = "test",
		)
	end

	@testset "crossing node spans fail closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [
				SubLemmaSelection("Familièrement. Avaler des poires", "Avaler des poires"),
				SubLemmaSelection("Avaler des poires d'angoisse", "d'angoisse"),
			]);
			adjudicator = "test",
		)
	end

	@testset "residual overlapping a node fails closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive;
				selections = [SubLemmaSelection(
					"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
					"Avaler des poires d'angoisse",
				)],
				residuals = ["subir des mortifications"],
			);
			adjudicator = "test",
		)
	end

	@testset "target checks" begin
		record = commit(harness, sublemma_pass, item, positive; adjudicator = "test")
		@test check(harness, record) == :valid
		@test applicable(check(harness, record))

		moved = typeof(record)(
			record.record_id, record.pass, record.pass_version, record.population,
			record.population_version,
			DeepLittre.Source.RawSpan(record.source.file, record.source.start_byte + 1, record.source.end_byte),
			record.raw_sha256, record.synthetic_boundary, record.projection,
			record.projection_version, record.view_sha256, record.context, record.llm_input_sha256,
			record.outcome, record.exhaustive, record.assertions, record.residuals, record.method,
			record.adjudicator, record.model, record.created, record.notes,
		)
		@test check(harness, moved) == :raw_mismatch
		@test fatal(check(harness, moved))

		restated = typeof(record)(
			record.record_id, record.pass, record.pass_version, record.population,
			record.population_version, record.source, record.raw_sha256, record.synthetic_boundary,
			record.projection, record.projection_version, repeat("0", 64), record.context,
			record.llm_input_sha256, record.outcome, record.exhaustive, record.assertions,
			record.residuals, record.method, record.adjudicator, record.model, record.created,
			record.notes,
		)
		@test check(harness, restated) == :view_mismatch
		@test !fatal(check(harness, restated))
		@test !applicable(check(harness, restated))
	end
end
