using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: present, commit, check, materialize_record, Decision, FormSelection,
	ReviewItem, sublemma_pass, voice_variant_pass, eligible, SubLemma, applicable, validate_store,
	StoreIntegrityError, Store, write_pass!, projected_text

@testset "authoring harness" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	harness = build_harness(documents, corpus)
	block = angoisse_block(harness, corpus)
	item = present(harness, sublemma_pass, block)

	positive = Decision(
		:positive;
		exhaustive = true,
		selections = [FormSelection(
			"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
			"Avaler des poires d'angoisse",
			"subir des mortifications, de vifs déplaisirs.",
		)],
		residuals = ["Familièrement."],
	)

	function tiny_source(blocks::Vector{String}; shifted::Bool = false)
		gap = shifted ? "\n" : ""
		body = join(("<indent>$(text)</indent>" for text in blocks), "")
		"<?xml version=\"1.0\" encoding=\"UTF-8\"?><xmlittre>$(gap)<entree terme=\"TEST\"><entete><nature>s. m.</nature></entete><corps><variante>$(body)</variante></corps></entree></xmlittre>"
	end

	function tiny_harness(source::String)
		directory = mktempdir()
		write(joinpath(directory, "a.xml"), source)
		found_documents = read_corpus(directory)
		found_corpus = census(found_documents)
		(
			DeepLittre.Adjudication.Harness(found_documents, found_corpus, Store(mktempdir())),
			found_corpus,
		)
	end

	@testset "absent store remains a supported coarse mode" begin
		root = joinpath(mktempdir(), "missing")
		empty = DeepLittre.Adjudication.Harness(documents, corpus, Store(root))
		@test validate_store(empty) == :empty
		@test !ispath(root)
	end

	@testset "unknown pass directories fail closed" begin
		@test validate_store(harness) == :empty
		unknown = joinpath(harness.store.root, "unknown_pass")
		mkpath(unknown)
		write(joinpath(unknown, "a.jsonl"), "{}\n")
		@test_throws StoreIntegrityError validate_store(harness)
		rm(unknown; recursive = true)
	end

	@testset "eligible population is version 1" begin
		pool = eligible(sublemma_pass, corpus)
		@test length(pool) == 351
		@test all(candidate -> candidate.kind isa DeepLittre.Census.Indent ||
			candidate.kind isa DeepLittre.Census.Variante, pool)
	end

	@testset "durable selections are projection-relative" begin
		record = commit(harness, sublemma_pass, item, positive; decision_procedure = "test")
		assertion = only(record.assertions)
		@test assertion.node_type isa SubLemma
		@test projected_text(item.projection, assertion.span) ==
			"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."
		forms = Dict(constituent.name => constituent.span for constituent in assertion.constituents)
		@test projected_text(item.projection, forms["form"]) == "Avaler des poires d'angoisse"
		@test projected_text(item.projection, forms["gloss"]) ==
			"subir des mortifications, de vifs déplaisirs."
		@test projected_text(item.projection, only(record.residuals)) == "Familièrement."
		@test length(record.surface_sha256) == 64
		@test record.outcome == :positive
		@test record.decision_procedure == "test"
		@test record.decision_reference === nothing

		applied = materialize_record(harness, record)
		@test applied !== nothing
		document = harness.documents[block.raw_span.file]
		anchored = only(applied.assertions)
		@test String(DeepLittre.Source.slice(document.raw_text, anchored.span)) ==
			"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."
	end

	@testset "ids are minted, never derived from coordinates" begin
		first_record = commit(harness, sublemma_pass, item, positive; decision_procedure = "test")
		second_record = commit(harness, sublemma_pass, item, positive; decision_procedure = "test")
		@test first_record.record_id != second_record.record_id
		@test only(first_record.assertions).node_id != only(second_record.assertions).node_id
		@test first_record.source == second_record.source
	end

	@testset "negative and unresolved outcomes need no assertion" begin
		negative = commit(harness, sublemma_pass, item, Decision(:negative); decision_procedure = "test")
		@test negative.outcome == :negative
		@test isempty(negative.assertions)
		unresolved = commit(
			harness, sublemma_pass, item, Decision(:unresolved; notes = "scope unclear");
			decision_procedure = "test",
		)
		@test unresolved.outcome == :unresolved
		@test unresolved.notes == "scope unclear"
	end

	@testset "schema violations fail closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item, Decision(:maybe); decision_procedure = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item, Decision(:positive); decision_procedure = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:negative; selections = [FormSelection("Familièrement.", "Familièrement.")]);
			decision_procedure = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item, Decision(:negative; exhaustive = true);
			decision_procedure = "test",
		)
	end

	@testset "unmappable selections fail closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; exhaustive = true, selections = [FormSelection("not in the target", "nope")]);
			decision_procedure = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; exhaustive = true, selections = [FormSelection("des", "des")]);
			decision_procedure = "test",
		)
	end

	@testset "constituent escaping its node fails closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Avaler des poires d'angoisse", "Familièrement.",
			)]); decision_procedure = "test",
		)
	end

	@testset "crossing node spans fail closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; exhaustive = true, selections = [
				FormSelection("Familièrement. Avaler des poires", "Avaler des poires"),
				FormSelection("Avaler des poires d'angoisse", "d'angoisse"),
			]); decision_procedure = "test",
		)
	end

	@testset "a new structural pass cannot cross an applicable other-pass assertion" begin
		other = build_harness(documents, corpus)
		other_block = angoisse_block(other, corpus)
		other_item = present(other, sublemma_pass, other_block)
		write_pass!(other.store, "sublemma", [commit(
			other, sublemma_pass, other_item, positive; decision_procedure = "test",
		)])
		@test_throws ReviewItem commit(
			other, voice_variant_pass, present(other, voice_variant_pass, other_block),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Familièrement. Avaler des poires", "Avaler des poires",
			)]); decision_procedure = "test",
		)
	end

	@testset "residual overlapping a node fails closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive;
				exhaustive = true,
				selections = [FormSelection(
					"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
					"Avaler des poires d'angoisse",
				)],
				residuals = ["subir des mortifications"],
			);
			decision_procedure = "test",
		)
	end

	@testset "one stale check" begin
		record = commit(harness, sublemma_pass, item, positive; decision_procedure = "test")
		@test check(harness, record) == :valid
		@test applicable(check(harness, record))

		old_pass = DeepLittre.Adjudication.with(record; pass_version = record.pass_version + 1)
		@test check(harness, old_pass) == :stale

		changed_surface = DeepLittre.Adjudication.with(record; surface_sha256 = repeat("0", 64))
		@test check(harness, changed_surface) == :stale
		@test !applicable(check(harness, changed_surface))

		moved_locator = DeepLittre.Adjudication.with(record; source = DeepLittre.Source.RawSpan(
			record.source.file, record.source.start_byte + 1, record.source.end_byte + 1,
		))
		@test check(harness, moved_locator) == :valid
		@test materialize_record(harness, moved_locator).source == record.source
	end

	@testset "coordinate drift is salvaged by the surface hash" begin
		record = commit(harness, sublemma_pass, item, positive; decision_procedure = "test")
		directory = mktempdir()
		for path in DeepLittre.Source.source_paths(corpus_source)
			cp(path, joinpath(directory, basename(path)))
		end
		path = joinpath(directory, "a.xml")
		text = read(path, String)
		write(path, replace(text, "<entree terme=\"ANGOISSE\">" => "\n<entree terme=\"ANGOISSE\">"; count = 1))
		moved_documents = read_corpus(directory)
		moved_corpus = census(moved_documents)
		moved_harness = DeepLittre.Adjudication.Harness(moved_documents, moved_corpus, Store(mktempdir()))
		applied = materialize_record(moved_harness, record)
		@test applied !== nothing
		@test applied.source != record.source
		@test check(moved_harness, record) == :valid

		document = moved_harness.documents[applied.source.file]
		assertion = only(applied.assertions)
		@test String(DeepLittre.Source.slice(document.raw_text, assertion.span)) ==
			"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."
		constituents = Dict(candidate.name => candidate.span for candidate in assertion.constituents)
		@test String(DeepLittre.Source.slice(document.raw_text, constituents["form"])) ==
			"Avaler des poires d'angoisse"
		@test String(DeepLittre.Source.slice(document.raw_text, constituents["gloss"])) ==
			"subir des mortifications, de vifs déplaisirs."
		@test String(DeepLittre.Source.slice(document.raw_text, only(applied.residuals))) ==
			"Familièrement."
	end

	@testset "ambiguous surface recovery fails closed" begin
		original_harness, original_corpus = tiny_harness(tiny_source(["Alpha beta."]))
		original_block = only(filter(candidate -> candidate.kind isa DeepLittre.Census.Indent, eligible(sublemma_pass, original_corpus)))
		record = commit(
			original_harness, sublemma_pass, present(original_harness, sublemma_pass, original_block),
			Decision(:negative); decision_procedure = "test",
		)

		changed_harness, _ = tiny_harness(tiny_source(["Alpha beta.", "Alpha beta."]; shifted = true))
		@test check(changed_harness, record) == :stale
		@test materialize_record(changed_harness, record) === nothing
	end

	@testset "changed occupied locator never falls back elsewhere" begin
		original_harness, original_corpus = tiny_harness(tiny_source(["Alpha beta."]))
		original_block = only(filter(candidate -> candidate.kind isa DeepLittre.Census.Indent, eligible(sublemma_pass, original_corpus)))
		record = commit(
			original_harness, sublemma_pass, present(original_harness, sublemma_pass, original_block),
			Decision(:negative); decision_procedure = "test",
		)

		changed_harness, changed_corpus = tiny_harness(tiny_source(["Gamma zeta.", "Alpha beta."]))
		blocks = filter(candidate -> candidate.kind isa DeepLittre.Census.Indent, eligible(sublemma_pass, changed_corpus))
		@test first(blocks).raw_span == record.source
		@test check(changed_harness, record) == :stale
		@test materialize_record(changed_harness, record) === nothing
	end

	@testset "citation context participates in the surface hash" begin
		record = commit(harness, sublemma_pass, item, positive; decision_procedure = "test")
		directory = mktempdir()
		for path in DeepLittre.Source.source_paths(corpus_source)
			cp(path, joinpath(directory, basename(path)))
		end
		path = joinpath(directory, "a.xml")
		text = read(path, String)
		write(path, replace(text, "Je vous présente des poires" => "Je vous apporte des poires"; count = 1))
		changed_documents = read_corpus(directory)
		changed_corpus = census(changed_documents)
		changed_harness = DeepLittre.Adjudication.Harness(changed_documents, changed_corpus, Store(mktempdir()))
		@test check(changed_harness, record) == :stale
	end
end
