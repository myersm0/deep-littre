using DeepLittre.Adjudication: declared_passes, current_passes, structural_passes,
	scope_passes, pass_definition, decomposition_pass, CitedForm, form_bearing,
	Store, Harness, validate_store

@testset "a declared pass need not be a pipeline pass" begin
	@testset "the registry is a superset of what the pipeline consumes" begin
		@test Set(current_passes) ⊆ Set(declared_passes)
		@test Set(vcat(collect(structural_passes), collect(scope_passes))) ==
			Set(current_passes)
	end

	@testset "decomposition is authorable but invisible to closure" begin
		@test pass_definition("decomposition") === decomposition_pass
		@test decomposition_pass in declared_passes
		@test !(decomposition_pass in current_passes)
		# Closure demands a verdict from every structural pass, so an eval-only pass that
		# reached this tuple would un-close every block already adjudicated.
		@test !(decomposition_pass in structural_passes)
		@test decomposition_pass.node_type isa CitedForm
		@test form_bearing(decomposition_pass.node_type)
	end

	@testset "the store accepts records for any declared pass" begin
		store = Store(mktempdir())
		mkpath(joinpath(store.root, "decomposition"))
		touch(joinpath(store.root, "decomposition", "a.jsonl"))
		harness = Harness(
			read_corpus(corpus_source),
			census(read_corpus(corpus_source)),
			store,
		)
		@test validate_store(harness) == :valid
	end
end
