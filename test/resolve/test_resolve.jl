using DeepLittre.Source: read_corpus, slice, RawSpan
using DeepLittre.Census: census, all_blocks, Indent
using DeepLittre.Adjudication: Harness, Store, present, commit, Decision, FormSelection,
	sublemma_pass, voice_variant_pass, write_pass!, SubLemma, VoiceVariant, Sense, ExaminationRecord
using DeepLittre.Resolve: resolve, plain_text, IntegrityFailure, route_spans, UsgTarget,
	GramElement, closure, adjudication_state

@testset "resolve" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)

	function fresh_harness()
		build_harness(documents, corpus)
	end

	function angoisse_record(harness)
		block = angoisse_block(harness, corpus)
		item = present(harness, sublemma_pass, block)
		commit(harness, sublemma_pass, item, Decision(
			:positive;
			exhaustive = true,
			selections = [FormSelection(
				"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)],
			residuals = ["Familièrement."],
		); decision_procedure = "test")
	end

	find_node(nodes, predicate) = begin
		for node in nodes
			predicate(node) && return node
			found = find_node(node.children, predicate)
			found === nothing || return found
		end
		nothing
	end

	entry_named(resolved, headword) = first(filter(e -> e.headword == headword, resolved.entries))

	@testset "an empty store still yields every explicit fact" begin
		resolved = resolve(fresh_harness())
		@test length(resolved.entries) == 25

		angoisse = entry_named(resolved, "ANGOISSE")
		@test angoisse.pronunciation == "an-goi-s', et non an-goi-z'"
		@test [(q.type, q.norm) for q in angoisse.grammar] ==
			[("pos", "noun"), ("gender", "feminine")]
		@test !isempty(angoisse.rubriques)
		@test any(rubrique -> rubrique.name == "ÉTYMOLOGIE", angoisse.rubriques)

		familiar = find_node(angoisse.nodes, node ->
			any(q -> q.norm == "familiar", node.qualifications))
		@test familiar !== nothing
		@test occursin("Avaler des poires", plain_text(familiar.definition))
	end

	@testset "residual text anchors do not cover carved facts" begin
		resolved = resolve(fresh_harness())
		function check(nodes)
			for node in nodes
				carved = DeepLittre.Source.RawSpan[
					[qualification.span for qualification in node.qualifications]...,
					[citation.span for citation in node.citations]...,
					[child.span for child in node.children]...,
				]
				for item in node.definition
					item isa DeepLittre.Resolve.TextRun || continue
					@test all(span -> !DeepLittre.Source.covers(item.span, span), carved)
				end
				check(node.children)
			end
		end
		for entry in resolved.entries
			check(entry.nodes)
		end
	end

	@testset "no node claims a type without closure" begin
		resolved = resolve(fresh_harness())
		types = Any[]
		for entry in resolved.entries
			walk(nodes) = for node in nodes
				push!(types, node.node_type)
				walk(node.children)
			end
			walk(entry.nodes)
		end
		@test !isempty(types)
		@test all(isnothing, types)
	end

	@testset "nested structural assertions derive parentage from containment" begin
		harness = fresh_harness()
		block = angoisse_block(harness, corpus)
		sublemma = angoisse_record(harness)
		voice = commit(
			harness, voice_variant_pass, present(harness, voice_variant_pass, block),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"subir des mortifications", "subir des mortifications",
			)], residuals = ["Familièrement. Avaler des poires d'angoisse,", ", de vifs déplaisirs."]);
			decision_procedure = "test",
		)
		write_pass!(harness.store, "sublemma", [sublemma])
		write_pass!(harness.store, "voice_variant", [voice])

		resolved = resolve(harness)
		angoisse = entry_named(resolved, "ANGOISSE")
		outer = find_node(angoisse.nodes, node -> node.node_type isa SubLemma)
		@test outer !== nothing
		@test length(outer.children) == 1
		@test only(outer.children).node_type isa VoiceVariant
		@test DeepLittre.Source.covers(outer.span, only(outer.children).span)
	end

	@testset "persisted cross-pass crossings fail closed to review" begin
		harness = fresh_harness()
		block = angoisse_block(harness, corpus)
		sublemma = angoisse_record(harness)
		voice = commit(
			harness, voice_variant_pass, present(harness, voice_variant_pass, block),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Familièrement. Avaler des poires", "Avaler des poires",
			)], residuals = ["d'angoisse, subir des mortifications, de vifs déplaisirs."]);
			decision_procedure = "test",
		)
		write_pass!(harness.store, "sublemma", [sublemma])
		write_pass!(harness.store, "voice_variant", [voice])

		resolved = resolve(harness)
		angoisse = entry_named(resolved, "ANGOISSE")
		@test any(finding -> finding.category == "structural_conflict", resolved.review)
		@test find_node(angoisse.nodes, node -> node.node_type isa SubLemma) === nothing
		@test find_node(angoisse.nodes, node -> node.node_type isa VoiceVariant) === nothing
	end

	@testset "adjudication enriches without recreating" begin
		harness = fresh_harness()
		write_pass!(harness.store, "sublemma", [angoisse_record(harness)])
		resolved = resolve(harness)
		angoisse = entry_named(resolved, "ANGOISSE")

		sublemma = find_node(angoisse.nodes, node -> node.node_type isa SubLemma)
		@test sublemma !== nothing
		@test sublemma.form == "Avaler des poires d'angoisse"
		@test plain_text(sublemma.definition) == "subir des mortifications, de vifs déplaisirs."
		@test sublemma.separator == ","

		anchors = Dict(item.name => item.span for item in sublemma.constituents)
		@test sort(collect(keys(anchors))) == ["form", "gloss"]
		document = first(filter(d -> d.file == sublemma.span.file, documents))
		gap = DeepLittre.Source.RawSpan(
			sublemma.span.file, anchors["form"].end_byte, anchors["gloss"].start_byte,
		)
		@test String(slice(document.raw_text, gap)) == ", "
		for constituent in sublemma.constituents
			@test String(slice(document.raw_text, constituent.span)) == constituent.text
		end

		parent = find_node(angoisse.nodes, node ->
			any(child -> child.node_type isa SubLemma, node.children))
		@test parent !== nothing
		@test !occursin("Avaler des poires", plain_text(parent.definition))
		@test any(q -> q.norm == "familiar", parent.qualifications)

		@test entry_named(resolved, "ANGOISSE").pronunciation ==
			entry_named(resolve(fresh_harness()), "ANGOISSE").pronunciation
	end

	@testset "inline markup never leaks into adjudicated constituent text" begin
		directory = mktempdir()
		write(joinpath(directory, "markup.xml"), """<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<xmlittre>
<entree terme=\"MARKUP\">
<entete><prononciation>markup</prononciation><nature>s. m.</nature></entete>
<corps>
<variante num=\"1\"><i>Prendre</i> feu, devenir <i lang=\"la\">calidus</i>.</variante>
<variante num=\"2\">Avant <i lang=\"la\">verbum</i> après.</variante>
<variante num=\"3\">alpha<cit aut=\"TEST\" ref=\"1\">removed</cit>beta</variante>
</corps>
</entree>
</xmlittre>
""")
		local_documents = read_corpus(directory)
		local_corpus = census(local_documents)
		harness = build_harness(local_documents, local_corpus)
		blocks = filter(Census.all_blocks(local_corpus)) do candidate
			candidate.kind isa DeepLittre.Census.Variante
		end
		first_block = first(blocks)
		record = commit(
			harness, sublemma_pass, present(harness, sublemma_pass, first_block),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Prendre feu, devenir calidus.", "Prendre feu", "devenir calidus.",
			)]); decision_procedure = "test",
		)
		write_pass!(harness.store, "sublemma", [record])
		local_resolved = resolve(harness)
		entry = only(local_resolved.entries)
		sublemma = find_node(entry.nodes, node -> node.node_type isa SubLemma)
		@test sublemma.form == "Prendre feu"
		@test plain_text(sublemma.definition) == "devenir calidus."
		form_constituent = only(filter(item -> item.name == "form", sublemma.constituents))
		@test form_constituent.text == "Prendre feu"
		document = only(local_documents)
		@test occursin("</i>", String(slice(document.raw_text, form_constituent.span)))
		@test !occursin('<', form_constituent.text)

		emphasis_node = find_node(entry.nodes, node -> occursin("Avant verbum après.", plain_text(node.definition)))
		@test emphasis_node !== nothing
		emphasis = only(filter(item -> item isa DeepLittre.Resolve.Emphasis, emphasis_node.definition))
		@test emphasis.text == "verbum"
		@test emphasis.source_element == "i"
		@test emphasis.language == "la"
		tei = read(DeepLittre.Render.render_tei(local_resolved, joinpath(directory, "markup.tei.xml")), String)
		@test occursin("<hi rend=\"italic\" xml:lang=\"la\">verbum</hi>", tei)

		citation_node = find_node(entry.nodes, node -> plain_text(node.definition) == "alpha beta")
		@test citation_node !== nothing
		citation = only(citation_node.citations)
		for item in citation_node.definition
			item isa DeepLittre.Resolve.TextRun || continue
			@test !DeepLittre.Source.covers(item.span, citation.span)
		end
	end

	@testset "coverage reports the derived denominator" begin
		harness = fresh_harness()
		write_pass!(harness.store, "sublemma", [angoisse_record(harness)])
		resolved = resolve(harness)
		sublemma = first(filter(record -> record.pass == "sublemma", resolved.coverage))
		@test sublemma.population_size == 351
		@test sublemma.examined == 1
		@test sublemma.positive == 1
		@test sublemma.quarantined == 0
		@test length(sublemma.population_hash) == 64
	end

	# The store holds current verdicts, not their history. Two records for one target have no
	# honest precedence rule between them, so the store refuses to hold both rather than picking.
	@testset "one target carries at most one verdict per pass" begin
		harness = fresh_harness()
		block = angoisse_block(harness, corpus)
		old = DeepLittre.Adjudication.with(
			angoisse_record(harness); created = "2026-08-24T01:00:00Z",
		)
		new = commit(
			harness, sublemma_pass, present(harness, sublemma_pass, block), Decision(:negative);
			decision_procedure = "test", now = "2026-08-24T02:00:00Z",
		)
		write_pass!(harness.store, "sublemma", [old, new])
		@test_throws DeepLittre.Adjudication.StoreIntegrityError resolve(harness)

		write_pass!(harness.store, "sublemma", [new])
		resolved = resolve(harness)
		sublemma = first(filter(record -> record.pass == "sublemma", resolved.coverage))
		@test sublemma.examined == 1
		@test sublemma.negative == 1
		angoisse = entry_named(resolved, "ANGOISSE")
		@test find_node(angoisse.nodes, node -> node.node_type isa SubLemma) === nothing
	end

	voice_negative(harness, block; exhaustive = false) = commit(
		harness, voice_variant_pass, present(harness, voice_variant_pass, block),
		Decision(:negative); decision_procedure = "test",
	)

	@testset "closure needs every structural alternative" begin
		harness = fresh_harness()
		block = angoisse_block(harness, corpus)
		write_pass!(harness.store, "sublemma", [angoisse_record(harness)])
		state = adjudication_state(harness, ["sublemma", "voice_variant"])
		(resolved, reason) = closure(harness, state, block)
		@test !resolved
		@test occursin("voice_variant", reason)
	end

	@testset "closure derives an ordinary Sense" begin
		harness = fresh_harness()
		block = angoisse_block(harness, corpus)
		write_pass!(harness.store, "sublemma", [angoisse_record(harness)])
		write_pass!(harness.store, "voice_variant", [voice_negative(harness, block)])

		state = adjudication_state(harness, ["sublemma", "voice_variant"])
		(passed, reason) = closure(harness, state, block)
		@test passed
		@test isempty(reason)

		resolved = resolve(harness)
		angoisse = entry_named(resolved, "ANGOISSE")
		derived = find_node(angoisse.nodes, node -> node.node_type isa Sense)
		@test derived !== nothing
		@test derived.span == block.raw_span
		@test any(child -> child.node_type isa SubLemma, derived.children)
		@test isempty(resolved.review)

		# closure is derived per block, so a block nobody examined stays underdetermined
		untouched = find_node(angoisse.nodes, node ->
			node.node_type === nothing && occursin("bâillon", plain_text(node.definition)))
		@test untouched !== nothing
	end

	# The harness rejects the overclaim at authoring, where there is still an item to re-author. The
	# resolver keeps the same check for records written by anything that bypassed the harness.
	@testset "an exhaustive claim over unaccounted material fails closed" begin
		harness = fresh_harness()
		block = angoisse_block(harness, corpus)
		overclaiming = Decision(
			:positive;
			exhaustive = true,
			selections = [FormSelection(
				"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
				"Avaler des poires d'angoisse",
			)],
		)
		@test_throws DeepLittre.Adjudication.ReviewItem commit(
			harness, sublemma_pass, present(harness, sublemma_pass, block), overclaiming;
			decision_procedure = "test",
		)
		overclaim = DeepLittre.Adjudication.with(angoisse_record(harness); residuals = RawSpan[])
		write_pass!(harness.store, "sublemma", [overclaim])
		write_pass!(harness.store, "voice_variant", [voice_negative(harness, block)])

		state = adjudication_state(harness, ["sublemma", "voice_variant"])
		(passed, reason) = closure(harness, state, block)
		@test !passed
		@test occursin("Familièrement.", reason)

		resolved = resolve(harness)
		@test any(finding -> finding.category == "incomplete_partition", resolved.review)
		@test find_node(entry_named(resolved, "ANGOISSE").nodes,
			node -> node.node_type isa Sense) === nothing
	end

	@testset "unexamined blocks are not review findings" begin
		resolved = resolve(fresh_harness())
		@test isempty(resolved.review)
	end

	@testset "a stale view hash quarantines rather than aborting" begin
		harness = fresh_harness()
		record = angoisse_record(harness)
		stale = DeepLittre.Adjudication.with(record; view_sha256 = repeat("0", 64))
		write_pass!(harness.store, "sublemma", [stale])

		resolved = resolve(harness)
		@test length(resolved.review) == 1
		@test first(resolved.review).category == "view_mismatch"
		@test length(resolved.entries) == 25

		angoisse = entry_named(resolved, "ANGOISSE")
		@test find_node(angoisse.nodes, node -> node.node_type isa SubLemma) === nothing
		@test_throws ErrorException resolve(harness; strict = true)
	end

	@testset "a stale raw anchor aborts the build" begin
		harness = fresh_harness()
		record = angoisse_record(harness)
		broken = DeepLittre.Adjudication.with(record; raw_sha256 = repeat("0", 64))
		write_pass!(harness.store, "sublemma", [broken])
		@test_throws IntegrityFailure resolve(harness)
	end

	# Semantic text is what Littré wrote, not what XML syntax required. The projection already
	# decoded references; the inline path did not, so the two disagreed about the same characters and
	# the renderer escaped an already-escaped ampersand.
	@testset "entity references decode into semantic text" begin
		directory = mktempdir()
		write(joinpath(directory, "z.xml"), """<?xml version="1.0" encoding="UTF-8"?>
<xmlittre>
<entree terme="ESPERLUETTE">
<entete><prononciation>è-sp&#232;r</prononciation><nature>s. f.</nature></entete>
<corps>
<variante num="1">Fer &amp; feu, dit &lt;ainsi&gt; par <semantique type="indicateur">Familièrement.</semantique>
<cit aut="MOL." ref="Test 1">Ni &amp; ni</cit>
</variante>
</corps>
</entree>
</xmlittre>
""")
		documents = read_corpus(directory)
		corpus = census(documents)
		harness = build_harness(documents, corpus)
		resolved = resolve(harness)
		entry = only(resolved.entries)
		node = only(entry.nodes)

		@test plain_text(node.definition) == "Fer & feu, dit <ainsi> par"
		@test plain_text(only(node.citations).quotation) == "Ni & ni"
		@test entry.pronunciation == "è-spèr"

		directory_out = mktempdir()
		text = read(DeepLittre.Render.render_tei(
			resolved, joinpath(directory_out, "littre.tei.xml"),
		), String)
		@test occursin("<def>Fer &amp; feu, dit &lt;ainsi&gt; par</def>", text)
		@test !occursin("&amp;amp;", text)
		@test !occursin("&amp;lt;", text)
		@test XML.parse(XML.Node, text) !== nothing
	end

	@testset "salvaged routing keeps its pinned targets" begin
		route(text) = first(first(route_spans(text)))
		@test route("familièrement") == UsgTarget("socioCultural", "familiar")
		@test route("terme familier") == UsgTarget("socioCultural", "familiar")
		@test route("terme vieilli") == UsgTarget("temporal", "archaic")
		@test route("terme peu usité") == UsgTarget("frequency", "rare")
		@test route("de médecine") == UsgTarget("domain", "")
		@test route("fig") == UsgTarget("meaningType", "figurative")
		@test route("par extension") == UsgTarget("meaningType", "byExtension")

		agreement = route("au plur")
		@test agreement isa Vector{GramElement}
		@test (first(agreement).kind, first(agreement).norm) == ("number", "plural")

		pos = route("s. m.")
		@test pos isa Vector{GramElement}
		@test [(element.kind, element.norm) for element in pos] ==
			[("pos", "noun"), ("gender", "masculine")]
	end
end
