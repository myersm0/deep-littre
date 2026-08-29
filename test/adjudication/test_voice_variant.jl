using DeepLittre.Source: read_corpus, slice, covers
using DeepLittre.Census: census, all_blocks, Variante, Indent
using DeepLittre.Adjudication: Harness, Store, present, commit, Decision, FormSelection,
	voice_variant_pass, sublemma_pass, write_pass!, VoiceVariant, SubLemma, Sense, ReviewItem,
	form_bearing, structural_passes, scope_passes, current_passes
using DeepLittre.Resolve: resolve, plain_text

@testset "voice variant pass" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)

	fresh() = build_harness(documents, corpus)

	block_containing(harness, needle, kind) = first(filter(all_blocks(corpus)) do candidate
		candidate.kind isa kind || return false
		occursin(needle, slice(harness.documents[candidate.raw_span.file].raw_text, candidate.raw_span))
	end)

	find_node(nodes, predicate) = begin
		for node in nodes
			predicate(node) && return node
			found = find_node(node.children, predicate)
			found === nothing || return found
		end
		nothing
	end

	entry_named(resolved, headword) = first(filter(e -> e.headword == headword, resolved.entries))

	@testset "the alternative set is form-bearing" begin
		@test length(structural_passes) == 2
		@test all(pass -> form_bearing(pass.node_type), structural_passes)
		# The resolver reaches passes only through these two groups, so a pass in neither would be
		# declared and then silently never applied.
		@test Set(vcat(collect(structural_passes), collect(scope_passes))) == Set(current_passes)
		@test !form_bearing(Sense())
		@test voice_variant_pass.node_type isa VoiceVariant
		@test sublemma_pass.node_type isa SubLemma
		@test voice_variant_pass.population == sublemma_pass.population
		@test voice_variant_pass.population_version == sublemma_pass.population_version
		@test occursin("form-bearing", voice_variant_pass.question)
	end

	@testset "a pass asserts its own node type" begin
		harness = fresh()
		block = block_containing(harness, "Se dispenser,", Variante)
		record = commit(harness, voice_variant_pass, present(harness, voice_variant_pass, block),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Se dispenser, v. réfl. Être départi. Les honneurs se dispensent quelquefois au hasard.",
				"Se dispenser",
				"Être départi. Les honneurs se dispensent quelquefois au hasard.",
			)]); decision_procedure = "test")
		@test only(record.assertions).node_type isa VoiceVariant
		@test record.pass == "voice_variant"
	end

	@testset "structure and grammatical construction are orthogonal" begin
		harness = fresh()
		block = block_containing(harness, "Se dispenser,", Variante)
		write_pass!(harness.store, "voice_variant", [commit(
			harness, voice_variant_pass, present(harness, voice_variant_pass, block),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Se dispenser, v. réfl. Être départi. Les honneurs se dispensent quelquefois au hasard.",
				"Se dispenser",
				"Être départi. Les honneurs se dispensent quelquefois au hasard.",
			)]); decision_procedure = "test")])

		resolved = resolve(harness)
		variant = find_node(entry_named(resolved, "DISPENSER").nodes,
			node -> node.node_type isa VoiceVariant)
		@test variant !== nothing
		@test variant.form == "Se dispenser"
		@test plain_text(variant.definition) ==
			"Être départi. Les honneurs se dispensent quelquefois au hasard."

		# the deterministic grammatical fact rides along and is not what created the node
		@test [(q.type, q.norm) for q in variant.qualifications] ==
			[("pos", "verb"), ("valency", "reflexive")]
		@test all(q -> q.channel == :gram, variant.qualifications)

		# and it attached by containment, so it did not stay on the enclosing block
		parent = find_node(entry_named(resolved, "DISPENSER").nodes,
			node -> any(child -> child.node_type isa VoiceVariant, node.children))
		@test isempty(parent.qualifications)
	end

	@testset "a lemma-level reflexive label makes no node" begin
		resolved = resolve(fresh())
		evader = entry_named(resolved, "ÉVADER (S')")
		@test [(q.type, q.norm) for q in evader.grammar] == [("pos", "verb"), ("valency", "reflexive")]
		@test find_node(evader.nodes, node -> node.node_type isa VoiceVariant) === nothing
	end

	@testset "markup between constituents is not a separator" begin
		harness = fresh()
		block = block_containing(harness, "Se dispenser,", Variante)
		write_pass!(harness.store, "voice_variant", [commit(
			harness, voice_variant_pass, present(harness, voice_variant_pass, block),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Se dispenser, v. réfl. Être départi. Les honneurs se dispensent quelquefois au hasard.",
				"Se dispenser",
				"Être départi. Les honneurs se dispensent quelquefois au hasard.",
			)]); decision_procedure = "test")])
		resolved = resolve(harness)
		variant = find_node(entry_named(resolved, "DISPENSER").nodes,
			node -> node.node_type isa VoiceVariant)
		# the gap holds <nature>v. réfl.</nature>, which is a marker, not punctuation
		@test variant.separator === nothing
	end

	@testset "both alternatives close a block together" begin
		harness = fresh()
		angoisse = block_containing(harness, "Avaler des poires", Indent)
		write_pass!(harness.store, "sublemma", [commit(
			harness, sublemma_pass, present(harness, sublemma_pass, angoisse),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)], residuals = ["Familièrement."]); decision_procedure = "test")])
		write_pass!(harness.store, "voice_variant", [commit(
			harness, voice_variant_pass, present(harness, voice_variant_pass, angoisse),
			Decision(:negative); decision_procedure = "test")])

		resolved = resolve(harness)
		derived = find_node(entry_named(resolved, "ANGOISSE").nodes, node -> node.node_type isa Sense)
		@test derived !== nothing
		@test derived.span == angoisse.raw_span
	end
end
