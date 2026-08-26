using DeepLittre.Source: read_corpus, slice, covers, laminar
using DeepLittre.Census: census
using DeepLittre.Adjudication: present, commit, check, Decision, FormSelection, ReviewItem,
	sublemma_pass, voice_variant_pass, eligible, SubLemma, fatal, applicable, validate_store, StoreIntegrityError,
	ContextReference, Store, write_pass!

@testset "authoring harness" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	harness = build_harness(documents, corpus)
	block = angoisse_block(harness, corpus)
	document = harness.documents[block.raw_span.file]
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

	@testset "absent store remains a supported coarse mode" begin
		root = joinpath(mktempdir(), "missing")
		empty = DeepLittre.Adjudication.Harness(documents, corpus, Store(root))
		@test validate_store(empty) == :empty
		@test !ispath(root)
	end

	@testset "store gates are the ones with no per-record equivalent" begin
		@test validate_store(harness) == :valid
		path = joinpath(harness.store.root, "manifest.toml")
		original = read(path, String)

		# A pass version or projection version in the manifest gates nothing: the record carries
		# its own, and `check` quarantines that one verdict rather than failing the store.
		write(path, replace(original, "projection_version = 2" => "projection_version = 7"))
		@test validate_store(harness) == :valid
		write(path, replace(original, r"\n\[passes\.qualification_scope\][\s\S]*$" => "\n"))
		@test validate_store(harness) == :valid

		# Closure protocol and alternative-set versions govern the resolver's derivation rather
		# than any single verdict, so they have nowhere else to be checked.
		write(path, replace(original, "closure_protocol_version = 1" => "closure_protocol_version = 2"))
		@test_throws StoreIntegrityError validate_store(harness)
		write(path, replace(original,
			"structural_alternative_set_version = 1" => "structural_alternative_set_version = 2"))
		@test_throws StoreIntegrityError validate_store(harness)

		# Records for a pass the code does not run would be read by nobody.
		write(path, original)
		unknown = joinpath(harness.store.root, "unknown_pass")
		mkpath(unknown)
		write(joinpath(unknown, "a.jsonl"), "{}\n")
		@test_throws StoreIntegrityError validate_store(harness)
		rm(unknown; recursive = true)
	end

	@testset "nonempty store without manifest fails closed" begin
		store = Store(mktempdir())
		record = commit(harness, sublemma_pass, item, Decision(:negative); decision_procedure = "test")
		directory = joinpath(store.root, "sublemma")
		mkpath(directory)
		write(joinpath(directory, "a.jsonl"), DeepLittre.Adjudication.canonical_json(record) * "\n")
		broken = DeepLittre.Adjudication.Harness(documents, corpus, store)
		@test_throws StoreIntegrityError validate_store(broken)
	end

	@testset "eligible population is version 1" begin
		pool = eligible(sublemma_pass, corpus)
		@test length(pool) == 351
		@test all(candidate -> candidate.kind isa DeepLittre.Census.Indent ||
			candidate.kind isa DeepLittre.Census.Variante, pool)
	end

	@testset "constituents anchor to exactly their source text" begin
		record = commit(harness, sublemma_pass, item, positive; decision_procedure = "test")
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
		@test record.decision_procedure == "test"
		@test record.decision_reference === nothing
		@test !isempty(record.context)
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
		@test !negative.exhaustive

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
			harness, sublemma_pass, item, Decision(:negative; exhaustive = true); decision_procedure = "test",
		)
	end

	@testset "unmappable selections fail closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [FormSelection("not in the target", "nope")]);
			decision_procedure = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [FormSelection("des", "des")]);
			decision_procedure = "test",
		)
	end

	@testset "constituent escaping its node fails closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [FormSelection(
				"Avaler des poires d'angoisse", "Familièrement.",
			)]);
			decision_procedure = "test",
		)
	end

	@testset "crossing node spans fail closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [
				FormSelection("Familièrement. Avaler des poires", "Avaler des poires"),
				FormSelection("Avaler des poires d'angoisse", "d'angoisse"),
			]);
			decision_procedure = "test",
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
			Decision(:positive; selections = [FormSelection(
				"Familièrement. Avaler des poires", "Avaler des poires",
			)]); decision_procedure = "test",
		)
	end

	@testset "residual overlapping a node fails closed" begin
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive;
				selections = [FormSelection(
					"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
					"Avaler des poires d'angoisse",
				)],
				residuals = ["subir des mortifications"],
			);
			decision_procedure = "test",
		)
	end

	@testset "target checks" begin
		record = commit(harness, sublemma_pass, item, positive; decision_procedure = "test")
		@test check(harness, record) == :valid
		@test applicable(check(harness, record))

		old_pass = DeepLittre.Adjudication.with(record; pass_version = record.pass_version + 1)
		@test check(harness, old_pass) == :pass_version_mismatch

		old_projection = DeepLittre.Adjudication.with(
			record; projection_version = record.projection_version + 1,
		)
		@test check(harness, old_projection) == :projection_version_mismatch

		reference = first(record.context)
		@test DeepLittre.Source.covers(record.source, reference.span)
		outside = ContextReference(
			DeepLittre.Source.RawSpan(record.source.file, record.source.end_byte,
				record.source.end_byte + 1),
			reference.role,
		)
		escaped = DeepLittre.Adjudication.with(record; context = [outside])
		@test check(harness, escaped) == :record_schema_mismatch

		moved = DeepLittre.Adjudication.with(record; source = DeepLittre.Source.RawSpan(
			record.source.file, record.source.start_byte + 1, record.source.end_byte,
		))
		@test check(harness, moved) == :raw_mismatch
		@test fatal(check(harness, moved))

		restated = DeepLittre.Adjudication.with(record; view_sha256 = repeat("0", 64))
		@test check(harness, restated) == :view_mismatch
		@test !fatal(check(harness, restated))
		@test !applicable(check(harness, restated))
	end
end
