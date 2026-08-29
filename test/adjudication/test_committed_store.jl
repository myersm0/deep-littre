using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: Harness, Store, validate_store, read_pass, current_passes,
	applicable, check, write_pass!
using DeepLittre.Resolve: resolve

@testset "committed development store" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	harness = Harness(documents, corpus, Store(corpus_adjudication))

	@testset "the store validates against the corpus beside it" begin
		validate_store(harness)
		@test true
	end

	records = Dict(pass.pass => read_pass(harness.store, pass.pass) for pass in current_passes)

	@testset "committed store uses the simplified durable shape" begin
		@test !isfile(joinpath(corpus_adjudication, "manifest.toml"))
		positive = only(filter(record -> record.outcome == :positive, records["sublemma"]))
		@test only(positive.assertions).span isa DeepLittre.Adjudication.ProjectedSpan
		@test only(positive.residuals) isa DeepLittre.Adjudication.ProjectedSpan
	end

	@testset "every committed record applies" begin
		for (pass, found) in records, record in found
			@test applicable(check(harness, record))
		end
		@test sum(length, values(records)) == 6
	end

	@testset "regeneration is byte-identical" begin
		mirror = Store(mktempdir())
		for (pass, found) in records
			isempty(found) && continue
			write_pass!(mirror, pass, found)
		end
		for (root, _, names) in walkdir(corpus_adjudication), name in names
			endswith(name, ".jsonl") || continue
			original = joinpath(root, name)
			regenerated = joinpath(mirror.root, relpath(original, corpus_adjudication))
			@test read(regenerated) == read(original)
		end
	end

	@testset "resolution through the committed store" begin
		resolved = resolve(harness)
		coverage = Dict(record.pass => record for record in resolved.coverage)
		@test coverage["sublemma"].positive == 1
		@test coverage["voice_variant"].positive == 1
		@test coverage["voice_variant"].negative == 2
		@test coverage["qualification_scope"].positive == 1
		@test coverage["qualification_scope"].negative == 1
		for record in values(coverage)
			@test record.unresolved == 0
			@test record.stale == 0
			@test record.population_size == 351
		end
	end
end
