using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: present, commit, Decision, FormSelection, FormReading,
	ScopeSelection, ReviewItem, ExaminationRecord, StoreIntegrityError, Store, write_pass!,
	read_pass, projected_text, sublemma_pass, voice_variant_pass, qualification_scope_pass,
	bare_qualification_pass, eligible
using DeepLittre.Resolve: resolve

# What one verdict can and cannot say. Each testset states a capability claim about the durable
# record and exercises it against real corpus material, so the boundary is executable rather than
# described. `@test_broken` marks a claim the record shape admits but the pipeline does not honour;
# it reports Broken now and errors the moment the capability lands.
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

		# Only `form` and `gloss` are constructible, and a node carries at most one gloss. There is
		# no third constituent name and no authoring surface that could supply one.
		@test fieldnames(FormSelection) == (:node, :forms, :gloss)
	end

	@testset "nodes nest by geometry and may not cross" begin
		# Nesting is expressible where the inner node falls in the part of the outer node that its
		# own constituents do not claim.
		nesting = present(harness, sublemma_pass, block_containing("Mener une entreprise à bien"))
		@test accepts(sublemma_pass, nesting, Decision(
			:positive; exhaustive = true,
			selections = [
				FormSelection(
					"À bien, loc. adv. D'une façon qui réussit. Mener une entreprise à bien, faire qu'elle réussisse.",
					"À bien",
					"D'une façon qui réussit.",
				),
				FormSelection(
					"Mener une entreprise à bien, faire qu'elle réussisse.",
					"Mener une entreprise à bien",
					"faire qu'elle réussisse.",
				),
			],
			residuals = ["Aller à bien, venir à bien, se terminer à bien, réussir."],
		))

		@test rejection(sublemma_pass, angoisse_item, Decision(
			:positive; exhaustive = true,
			selections = [
				FormSelection("Avaler des poires d'angoisse, subir", "Avaler des poires"),
				FormSelection("d'angoisse, subir des mortifications, de vifs déplaisirs.", "mortifications"),
			],
			residuals = ["Familièrement."],
		)) == "structural_conflict"

		# A node asserted inside another node's constituent makes a sub-lemma of part of a form.
		@test rejection(sublemma_pass, angoisse_item, Decision(
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

		# Coincident spans are alternative editorial readings of one printed form, so they are
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

		# Resolution applies the first scope it finds for a marker, so a second target could only
		# be accepted and then silently dropped. It is refused at commit instead.
		@test rejection(qualification_scope_pass, item, Decision(
			:positive;
			scopes = [
				ScopeSelection("loc. adv.", "À bien"),
				ScopeSelection("loc. adv.", "Mener une entreprise à bien"),
			],
		)) == "schema_violation"

		# Distinct markers still govern distinct material.
		bare = present(harness, bare_qualification_pass, a_bien)
		@test accepts(bare_qualification_pass, bare, Decision(
			:positive;
			scopes = [
				ScopeSelection("D'une façon qui réussit.", "Mener une entreprise à bien"),
				ScopeSelection("réussisse.", "Aller à bien"),
			],
		))
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

		# There is no confidence field: `unresolved` is the only hedge the record can express.
		@test :confidence ∉ fieldnames(ExaminationRecord)
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

		function findings_for(voice_decision)
			store = Store(mktempdir())
			write_pass!(store, sublemma_pass.pass, [sublemma_record])
			if voice_decision !== nothing
				write_pass!(store, voice_variant_pass.pass, [commit(
					harness, voice_variant_pass, present(harness, voice_variant_pass, angoisse),
					voice_decision; decision_procedure = "expressiveness",
				)])
			end
			resolved = resolve(DeepLittre.Adjudication.Harness(documents, corpus, store))
			[finding.category for finding in resolved.review
				if finding.span == angoisse.raw_span]
		end

		@test node_type_for(Decision(:negative)) isa DeepLittre.Adjudication.Sense
		@test node_type_for(Decision(:unresolved; notes = "cannot tell")) === nothing
		@test node_type_for(nothing) === nothing

		# Both leave the block short of closure, so the distinction is carried by the review queue
		# rather than by the node: an examined-but-unresolved block raises a finding, an unexamined
		# one does not.
		@test findings_for(Decision(:unresolved; notes = "cannot tell")) == ["unresolved"]
		@test isempty(findings_for(nothing))
	end
end
