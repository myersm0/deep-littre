using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: present, commit, Decision, FormSelection, sublemma_pass,
	canonical_json, write_pass!, read_pass, Store, sort_key, write_json_string, ExaminationRecord,
	StoreIntegrityError

@testset "canonical store" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	harness = build_harness(documents, corpus)
	block = angoisse_block(harness, corpus)
	item = present(harness, sublemma_pass, block)

	function fresh_store()
		store = Store(mktempdir())
		cp(joinpath(harness.store.root, "manifest.toml"), joinpath(store.root, "manifest.toml"))
		store
	end

	record = commit(
		harness, sublemma_pass, item,
		Decision(:positive;
			exhaustive = true,
			selections = [FormSelection(
				"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)],
			residuals = ["Familièrement."],
			notes = "quote \" and backslash \\ and tab \t",
		);
		decision_procedure = "test",
	)

	@testset "serialization is deterministic" begin
		@test canonical_json(record) == canonical_json(record)
		@test !occursin('\n', canonical_json(record))
	end

	@testset "key order is fixed by the writer" begin
		text = canonical_json(record)
		positions = [findfirst("\"$(key)\":", text) for key in
			("record_id", "pass", "source", "outcome", "assertions", "created", "notes")]
		@test all(position -> position !== nothing, positions)
		@test issorted([first(position) for position in positions])
	end

	@testset "escaping" begin
		buffer = IOBuffer()
		write_json_string(buffer, "quote \" slash \\ newline \n tab \t")
		@test String(take!(buffer)) == "\"quote \\\" slash \\\\ newline \\n tab \\t\""

		accented = IOBuffer()
		write_json_string(accented, "Familièrement")
		@test String(take!(accented)) == "\"Familièrement\""
	end

	@testset "writer requires a declared store" begin
		@test_throws StoreIntegrityError write_pass!(Store(mktempdir()), "sublemma", [record])
	end

	@testset "round trip through the store" begin
		store = fresh_store()
		write_pass!(store, "sublemma", [record])
		recovered = read_pass(store, "sublemma")
		@test length(recovered) == 1
		@test canonical_json(only(recovered)) == canonical_json(record)
		@test only(recovered).source == record.source
		@test only(recovered).notes == record.notes
		@test only(only(recovered).assertions).node_type isa DeepLittre.Adjudication.SubLemma
	end

	@testset "regeneration is byte-identical" begin
		store = fresh_store()
		write_pass!(store, "sublemma", [record])
		path = joinpath(store.root, "sublemma", "a.jsonl")
		before = read(path)
		write_pass!(store, "sublemma", read_pass(store, "sublemma"))
		@test read(path) == before
		@test last(before) == UInt8('\n')
	end

	@testset "records sort by durable anchor" begin
		other = present(harness, sublemma_pass, first(filter(
			candidate -> candidate.raw_span.start_byte < block.raw_span.start_byte,
			DeepLittre.Adjudication.eligible(sublemma_pass, corpus),
		)))
		earlier = commit(harness, sublemma_pass, other, Decision(:negative); decision_procedure = "test")

		store = fresh_store()
		write_pass!(store, "sublemma", [record, earlier])
		recovered = read_pass(store, "sublemma")
		@test [entry.source.start_byte for entry in recovered] ==
			sort([record.source.start_byte, earlier.source.start_byte])
		@test issorted(recovered; by = sort_key)
	end

	@testset "a pass writes only its own records" begin
		store = fresh_store()
		@test_throws ErrorException write_pass!(store, "voice_variant", [record])
	end
	@testset "pass regeneration removes stale shards" begin
		store = fresh_store()
		other = present(harness, sublemma_pass, first(filter(
			candidate -> candidate.raw_span.file != record.source.file,
			DeepLittre.Adjudication.eligible(sublemma_pass, corpus),
		)))
		other_record = commit(harness, sublemma_pass, other, Decision(:negative); decision_procedure = "test")
		write_pass!(store, "sublemma", [record, other_record])
		stale_path = joinpath(store.root, "sublemma", first(splitext(other_record.source.file)) * ".jsonl")
		@test isfile(stale_path)
		write_pass!(store, "sublemma", [record])
		@test !isfile(stale_path)
		@test length(read_pass(store, "sublemma")) == 1
		write_pass!(store, "sublemma", ExaminationRecord[])
		@test isempty(read_pass(store, "sublemma"))
		@test isempty(filter(name -> endswith(name, ".jsonl"), readdir(joinpath(store.root, "sublemma"))))
	end

end
