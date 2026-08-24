using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: present, commit, Decision, SubLemmaSelection, sublemma_pass,
	canonical_json, write_pass!, read_pass, Store, sort_key, write_json_string

@testset "canonical store" begin
	documents = read_corpus(sample_source)
	corpus = census(documents)
	harness = build_harness(documents, corpus)
	block = angoisse_block(harness, corpus)
	item = present(harness, sublemma_pass, block)

	record = commit(
		harness, sublemma_pass, item,
		Decision(:positive;
			exhaustive = true,
			selections = [SubLemmaSelection(
				"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)],
			residuals = ["Familièrement."],
			notes = "quote \" and backslash \\ and tab \t",
		);
		adjudicator = "test",
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

	@testset "round trip through the store" begin
		store = Store(mktempdir())
		write_pass!(store, "sublemma", [record])
		recovered = read_pass(store, "sublemma")
		@test length(recovered) == 1
		@test canonical_json(only(recovered)) == canonical_json(record)
		@test only(recovered).source == record.source
		@test only(recovered).notes == record.notes
		@test only(only(recovered).assertions).node_type isa DeepLittre.Adjudication.SubLemma
	end

	@testset "regeneration is byte-identical" begin
		store = Store(mktempdir())
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
		earlier = commit(harness, sublemma_pass, other, Decision(:negative); adjudicator = "test")

		store = Store(mktempdir())
		write_pass!(store, "sublemma", [record, earlier])
		recovered = read_pass(store, "sublemma")
		@test [entry.source.start_byte for entry in recovered] ==
			sort([record.source.start_byte, earlier.source.start_byte])
		@test issorted(recovered; by = sort_key)
	end

	@testset "a pass writes only its own records" begin
		store = Store(mktempdir())
		@test_throws ErrorException write_pass!(store, "voice_variant", [record])
	end
end
