using DeepLittre.Source: read_corpus, slice, covers
using DeepLittre.Census: census, all_blocks, Indent, Variante
using DeepLittre.Adjudication: Harness, Store, present, commit, Decision, FormSelection,
	ScopeSelection, sublemma_pass, voice_variant_pass, qualification_scope_pass, bare_qualification_pass,
	write_pass!, ReviewItem, SubLemma, materialize_record
using DeepLittre.Resolve: resolve, plain_text, ContainedScope, AssertedScope, scope_name

@testset "qualification scope pass" begin
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

	sublemma_text = "Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."

	function with_sublemma(harness, block)
		write_pass!(harness.store, "sublemma", [commit(
			harness, sublemma_pass, present(harness, sublemma_pass, block),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				sublemma_text, "Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)], residuals = ["Familièrement."]); decision_procedure = "test")])
	end

	@testset "scope passes assert no node type" begin
		@test qualification_scope_pass.node_type === nothing
		@test bare_qualification_pass.node_type === nothing
		@test occursin("govern", qualification_scope_pass.question)
		@test occursin("bare prose", bare_qualification_pass.question)
	end

	@testset "containment is the default and needs no record" begin
		harness = fresh()
		block = block_containing(harness, "Avaler des poires", Indent)
		with_sublemma(harness, block)

		resolved = resolve(harness)
		parent = find_node(entry_named(resolved, "ANGOISSE").nodes, node ->
			any(child -> child.node_type isa SubLemma, node.children))
		familiar = only(filter(q -> q.norm == "familiar", parent.qualifications))
		@test familiar.scope isa ContainedScope
		@test scope_name(familiar.scope) == "containment"

		sublemma = find_node(entry_named(resolved, "ANGOISSE").nodes, n -> n.node_type isa SubLemma)
		@test isempty(sublemma.qualifications)
	end

	@testset "an adjudicated scope moves the marker" begin
		harness = fresh()
		block = block_containing(harness, "Avaler des poires", Indent)
		with_sublemma(harness, block)
		write_pass!(harness.store, "qualification_scope", [commit(
			harness, qualification_scope_pass, present(harness, qualification_scope_pass, block),
			Decision(:positive; scopes = [ScopeSelection("Familièrement.", sublemma_text)]);
			decision_procedure = "test")])

		resolved = resolve(harness)
		sublemma = find_node(entry_named(resolved, "ANGOISSE").nodes, n -> n.node_type isa SubLemma)
		familiar = only(filter(q -> q.norm == "familiar", sublemma.qualifications))
		@test familiar.scope isa AssertedScope
		@test familiar.scope.target == sublemma.span
		@test covers(block.raw_span, familiar.span)

		parent = find_node(entry_named(resolved, "ANGOISSE").nodes, node ->
			any(child -> child.node_type isa SubLemma, node.children))
		@test isempty(parent.qualifications)
	end

	@testset "scope moves where a marker applies, never what it means" begin
		harness = fresh()
		block = block_containing(harness, "Avaler des poires", Indent)
		with_sublemma(harness, block)
		before = resolve(harness)
		write_pass!(harness.store, "qualification_scope", [commit(
			harness, qualification_scope_pass, present(harness, qualification_scope_pass, block),
			Decision(:positive; scopes = [ScopeSelection("Familièrement.", sublemma_text)]);
			decision_procedure = "test")])
		after = resolve(harness)

		facts(resolved) = sort([
			(q.channel, q.type, q.norm, q.printed, q.span.start_byte)
			for entry in resolved.entries for q in all_qualifications(entry)
		])
		@test facts(before) == facts(after)
	end

	@testset "a marker selection must land on a printed marker" begin
		harness = fresh()
		block = block_containing(harness, "Avaler des poires", Indent)
		@test_throws ReviewItem commit(
			harness, qualification_scope_pass, present(harness, qualification_scope_pass, block),
			Decision(:positive; scopes = [ScopeSelection(
				"Avaler des poires d'angoisse", "subir des mortifications, de vifs déplaisirs.",
			)]); decision_procedure = "test")
	end


	@testset "bare qualification markers are adjudicated, then routed deterministically" begin
		harness = fresh()
		block = block_containing(harness, "Adverbialement. Parler français", Indent)
		item = present(harness, bare_qualification_pass, block)
		target = "Parler français, s'exprimer en langage français. Cet étranger parle français."
		record = commit(
			harness, bare_qualification_pass, item,
			Decision(:positive; scopes = [ScopeSelection("Adverbialement.", target)]);
			decision_procedure = "test",
		)
		applied = materialize_record(harness, record)
		@test applied !== nothing
		document = harness.documents[block.raw_span.file]
		scope = only(applied.scopes)
		@test slice(document.raw_text, scope.marker) == "Adverbialement."
		@test slice(document.raw_text, scope.target) == target

		write_pass!(harness.store, "bare_qualification", [record])
		resolved = resolve(harness)
		node = find_node(entry_named(resolved, "FRANÇAIS, AISE").nodes, candidate -> candidate.span == block.raw_span)
		@test node !== nothing
		@test plain_text(node.definition) == target
		qualification = only(node.qualifications)
		@test qualification.channel == :gram
		@test qualification.type == "construction"
		@test qualification.norm == "adverbial"
		@test qualification.printed == "Adverbialement."
		@test qualification.span == scope.marker
		@test qualification.scope isa AssertedScope
		@test qualification.scope.target == scope.target
	end

	@testset "bare qualification pass cannot duplicate explicit markup" begin
		harness = fresh()
		block = block_containing(harness, "Avaler des poires", Indent)
		@test_throws ReviewItem commit(
			harness, bare_qualification_pass, present(harness, bare_qualification_pass, block),
			Decision(:positive; scopes = [ScopeSelection("Familièrement.", sublemma_text)]);
			decision_procedure = "test",
		)
	end

	@testset "a marker may not sit inside what it governs" begin
		harness = fresh()
		block = block_containing(harness, "Avaler des poires", Indent)
		@test_throws ReviewItem commit(
			harness, qualification_scope_pass, present(harness, qualification_scope_pass, block),
			Decision(:positive; scopes = [ScopeSelection(
				"Familièrement.", "Familièrement. Avaler des poires d'angoisse",
			)]); decision_procedure = "test")
	end

	@testset "passes may not cross their assertion kinds" begin
		harness = fresh()
		block = block_containing(harness, "Avaler des poires", Indent)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, present(harness, sublemma_pass, block),
			Decision(:positive; scopes = [ScopeSelection("Familièrement.", sublemma_text)]);
			decision_procedure = "test")
		@test_throws ReviewItem commit(
			harness, qualification_scope_pass, present(harness, qualification_scope_pass, block),
			Decision(:positive; selections = [FormSelection(sublemma_text, "Avaler des poires d'angoisse")]);
			decision_procedure = "test")
	end

	@testset "a negative outcome is a confirmation, not an absence" begin
		harness = fresh()
		block = block_containing(harness, "Se dispenser,", Variante)
		record = commit(
			harness, qualification_scope_pass, present(harness, qualification_scope_pass, block),
			Decision(:negative); decision_procedure = "test")
		@test record.outcome == :negative
		@test isempty(record.scopes)
	end
end
