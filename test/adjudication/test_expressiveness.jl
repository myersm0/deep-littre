using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: present, commit, Decision, FormSelection, FormReading,
	ScopeSelection, ReviewItem, ExaminationRecord, StoreIntegrityError, Store, write_pass!,
	read_pass, projected_text, sublemma_pass, voice_variant_pass, qualification_scope_pass,
	bare_qualification_pass, eligible
using DeepLittre.Resolve: resolve

@testset "verdict expressiveness" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	harness = build_harness(documents, corpus)

	pool = eligible(sublemma_pass, corpus)
	block_containing(needle::AbstractString) = first(filter(pool) do block
		occursin(needle, present(harness, sublemma_pass, block).projection.text)
	end)

	# "Familièrement. Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."
	angoisse = angoisse_block(harness, corpus)
	angoisse_item = present(harness, sublemma_pass, angoisse)
	sublemma_text = "Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."

	accepts(pass, item, decision) = commit(
		harness, pass, item, decision; decision_procedure = "expressiveness",
	) isa ExaminationRecord

	rejection(pass, item, decision)::String = try
		commit(harness, pass, item, decision; decision_procedure = "expressiveness")
		""
	catch failure
		failure isa ReviewItem || rethrow()
		failure.category
	end

	@testset "a node is one contiguous interval carrying named constituents" begin
		@test accepts(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [FormSelection(
				sublemma_text,
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)],
			residuals = ["Familièrement."],
		))

		@test rejection(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [FormSelection(sublemma_text, String[])],
			residuals = ["Familièrement."],
		)) == "schema_violation"

		# Only `form` and `gloss` are constructible, and a node carries at most one gloss.
		@test fieldnames(FormSelection) == (:node, :forms, :gloss)
	end

	@testset "nodes nest by geometry and may not cross" begin
		@test accepts(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [
				FormSelection(
					sublemma_text,
					"Avaler des poires d'angoisse",
					"subir des mortifications, de vifs déplaisirs.",
				),
				FormSelection("poires d'angoisse", "poires d'angoisse"),
			],
			residuals = ["Familièrement."],
		))

		@test rejection(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [
				FormSelection("Avaler des poires d'angoisse, subir", "Avaler des poires"),
				FormSelection("d'angoisse, subir des mortifications, de vifs déplaisirs.", "mortifications"),
			],
			residuals = ["Familièrement."],
		)) == "structural_conflict"

		# A node asserted inside another node's constituent is incoherent (it makes a sub-lemma
		# of part of a form) but nothing rejects it, because constituent geometry is only ever
		# checked within a single assertion.
		@test_broken rejection(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [
				FormSelection(
					sublemma_text,
					"Avaler des poires d'angoisse",
					"subir des mortifications, de vifs déplaisirs.",
				),
				FormSelection("des poires", "des poires"),
			],
			residuals = ["Familièrement."],
		)) == "structural_conflict"
	end

	@testset "one node may carry several form readings" begin
		@test accepts(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [FormSelection(
				sublemma_text,
				["Avaler", "poires d'angoisse"],
				"subir des mortifications, de vifs déplaisirs.",
			)],
			residuals = ["Familièrement."],
		))

		# Coincident spans are alternative editorial readings of one printed form, so
		# admitted only when their values differ.
		@test accepts(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [FormSelection(sublemma_text, FormReading[
				FormReading("Avaler des poires d'angoisse", "avaler des poires d'angoisse"),
				FormReading("Avaler des poires d'angoisse", "poire d'angoisse (avaler des)"),
			])],
			residuals = ["Familièrement."],
		))

		@test rejection(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [FormSelection(
				sublemma_text,
				["poires d'angoisse", "Avaler"],
				"subir des mortifications, de vifs déplaisirs.",
			)],
			residuals = ["Familièrement."],
		)) == "schema_violation"
	end

	@testset "a positive structural verdict partitions the whole target" begin
		@test rejection(sublemma_pass, angoisse_item, Decision(
			:positive;
			selections = [FormSelection(
				sublemma_text,
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)],
		)) == "schema_violation"

		@test rejection(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [FormSelection(
				sublemma_text,
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)],
		)) == "incomplete_partition"
	end

	@testset "selection addresses the projected target by unique substring" begin
		# Citations are context, never selectable material: they are excluded from the projection.
		@test rejection(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [FormSelection("bon-chrétien", "bon-chrétien")],
			residuals = ["Familièrement."],
		)) == "unmappable_selection"

		# A string occurring twice in the block cannot be named at all. The durable record stores
		# byte intervals and could express it; the authoring surface cannot reach it, which matters
		# because the classifier returns text rather than offsets.
		@test_broken accepts(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [FormSelection("des", "des")],
			residuals = ["Familièrement."],
		))
	end

	@testset "scope moves where a marker applies, not what it means" begin
		# "À bien, loc. adv. D'une façon qui réussit. Mener une entreprise à bien, ..."
		a_bien = block_containing("Mener une entreprise à bien")
		item = present(harness, qualification_scope_pass, a_bien)

		@test accepts(qualification_scope_pass, item, Decision(
			:positive; scopes = [ScopeSelection("loc. adv.", "À bien")],
		))

		@test rejection(qualification_scope_pass, item, Decision(
			:positive;
			scopes = [ScopeSelection("loc. adv.", "À bien, loc. adv. D'une façon qui réussit.")],
		)) == "scope_contains_marker"

		@test rejection(qualification_scope_pass, item, Decision(
			:positive; scopes = [ScopeSelection("D'une façon qui réussit.", "À bien")],
		)) == "not_a_marker"

		# A partial marker selection snaps outward to the whole explicit marker, so a verdict
		# cannot address part of one `<nature>` or `<semantique>`.
		partial = commit(harness, qualification_scope_pass, item, Decision(
			:positive; scopes = [ScopeSelection("loc.", "À bien")],
		); decision_procedure = "expressiveness")
		@test projected_text(item.projection, only(partial.scopes).marker) == "loc. adv."
	end

	@testset "a marker governs one target" begin
		a_bien = block_containing("Mener une entreprise à bien")
		item = present(harness, qualification_scope_pass, a_bien)

		# Two targets for one marker commit and validate, but resolution applies only the first
		# and drops the rest silently. TOGO: fix this
		record = commit(harness, qualification_scope_pass, item, Decision(
			:positive;
			scopes = [
				ScopeSelection("loc. adv.", "À bien"),
				ScopeSelection("loc. adv.", "Mener une entreprise à bien"),
			],
		); decision_procedure = "expressiveness")
		@test length(record.scopes) == 2

		store = Store(mktempdir())
		write_pass!(store, qualification_scope_pass.pass, [record])
		resolved = resolve(DeepLittre.Adjudication.Harness(documents, corpus, store))
		targets = Set{String}()
		function collect_scopes(node)
			for qualification in node.qualifications
				qualification.scope isa DeepLittre.Resolve.AssertedScope || continue
				push!(targets, DeepLittre.Source.anchor_id(qualification.scope.target))
			end
			foreach(collect_scopes, node.children)
		end
		for entry in resolved.entries, node in entry.nodes
			collect_scopes(node)
		end
		@test_broken length(targets) == 2
	end

	@testset "the bare pass claims only material no explicit marker covers" begin
		a_bien = block_containing("Mener une entreprise à bien")
		item = present(harness, bare_qualification_pass, a_bien)

		@test accepts(bare_qualification_pass, item, Decision(
			:positive;
			scopes = [ScopeSelection("D'une façon qui réussit.", "Mener une entreprise à bien")],
		))

		@test rejection(bare_qualification_pass, item, Decision(
			:positive; scopes = [ScopeSelection("loc. adv.", "À bien")],
		)) == "not_a_marker"
	end

	@testset "a pass asserts nodes or scope, never both" begin
		@test rejection(qualification_scope_pass,
			present(harness, qualification_scope_pass, angoisse),
			Decision(:positive; selections = [FormSelection(sublemma_text, "Avaler")]),
		) == "schema_violation"

		@test rejection(qualification_scope_pass,
			present(harness, qualification_scope_pass, angoisse),
			Decision(:positive;
				scopes = [ScopeSelection("Familièrement.", sublemma_text)],
				residuals = ["Familièrement."]),
		) == "schema_violation"

		@test rejection(sublemma_pass, angoisse_item, Decision(
			:negative; selections = [FormSelection(sublemma_text, "Avaler")],
		)) == "schema_violation"
	end

	@testset "node type is a property of the pass, so one stretch is one kind of thing" begin
		decision = Decision(
			:positive; exhaustive = true,
			selections = [FormSelection(
				sublemma_text,
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)],
			residuals = ["Familièrement."],
		)
		staged = DeepLittre.Adjudication.Harness(documents, corpus, Store(mktempdir()))
		record = commit(staged, sublemma_pass, present(staged, sublemma_pass, angoisse), decision;
			decision_procedure = "expressiveness")
		write_pass!(staged.store, sublemma_pass.pass, [record])

		conflict = try
			commit(staged, voice_variant_pass,
				present(staged, voice_variant_pass, angoisse), decision;
				decision_procedure = "expressiveness")
			""
		catch failure
			failure isa ReviewItem || rethrow()
			failure.category
		end
		@test conflict == "structural_conflict"
	end

	@testset "one verdict per block per pass, with no room for a rival" begin
		decision = Decision(
			:positive; exhaustive = true,
			selections = [FormSelection(
				sublemma_text,
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)],
			residuals = ["Familièrement."],
		)
		first_record = commit(harness, sublemma_pass, angoisse_item, decision;
			decision_procedure = "expressiveness")
		second_record = commit(harness, sublemma_pass, angoisse_item, decision;
			decision_procedure = "expressiveness")
		store = Store(mktempdir())
		write_pass!(store, sublemma_pass.pass, [first_record, second_record])
		@test_throws StoreIntegrityError read_pass(store, sublemma_pass.pass)
	end

	@testset "an examined-but-unresolved block is indistinguishable from an unexamined one" begin
		decision = Decision(
			:positive; exhaustive = true,
			selections = [FormSelection(
				sublemma_text,
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)],
			residuals = ["Familièrement."],
		)
		sublemma_record = commit(harness, sublemma_pass, angoisse_item, decision;
			decision_procedure = "expressiveness")

		function node_type_for(voice_decision)
			store = Store(mktempdir())
			write_pass!(store, sublemma_pass.pass, [sublemma_record])
			if voice_decision !== nothing
				write_pass!(store, voice_variant_pass.pass, [commit(
					harness, voice_variant_pass, present(harness, voice_variant_pass, angoisse),
					voice_decision; decision_procedure = "expressiveness",
				)])
			end
			resolved = resolve(DeepLittre.Adjudication.Harness(documents, corpus, store))
			found = nothing
			function seek(node)
				node.span == angoisse.raw_span && (found = node)
				foreach(seek, node.children)
			end
			for entry in resolved.entries, node in entry.nodes
				seek(node)
			end
			found === nothing ? nothing : found.node_type
		end

		@test node_type_for(Decision(:negative)) isa DeepLittre.Adjudication.Sense
		@test node_type_for(Decision(:unresolved; notes = "cannot tell")) === nothing
		@test node_type_for(nothing) === nothing

		# Both leave the block short of closure and the model records no trace of which happened.
		# The distinction survives only in per-pass coverage counts.
		@test_broken node_type_for(Decision(:unresolved)) != node_type_for(nothing)
	end
end
