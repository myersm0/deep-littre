using SQLite
using DBInterface
using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: Harness, Store, present, commit, Decision, FormReading, FormSelection,
	ReviewItem, sublemma_pass, voice_variant_pass, write_pass!, eligible, materialize_record
using DeepLittre.Resolve: resolve, plain_text
using DeepLittre.Render: render_tei, render_sqlite

@testset "multi-form structural nodes" begin
	directory = mktempdir()
	write(joinpath(directory, "a.xml"), """<?xml version="1.0" encoding="UTF-8"?>
<xmlittre><entree terme="TEST"><entete><nature>s. m.</nature></entete><corps><variante>
<indent>Alpha, ou Beta, première définition.</indent>
<indent>Enfanter une âme en ou à Jésus-Christ, seconde définition.</indent>
</variante></corps></entree></xmlittre>""")
	documents = read_corpus(directory)
	corpus = census(documents)
	harness = Harness(documents, corpus, Store(mktempdir()))
	blocks = filter(block -> block.kind isa DeepLittre.Census.Indent, eligible(sublemma_pass, corpus))
	alpha = only(filter(block -> occursin("Alpha", DeepLittre.Source.slice(
		harness.documents[block.raw_span.file].raw_text, block.raw_span,
	)), blocks))
	christ = only(filter(block -> occursin("Jésus-Christ", DeepLittre.Source.slice(
		harness.documents[block.raw_span.file].raw_text, block.raw_span,
	)), blocks))

	alpha_record = commit(
		harness, sublemma_pass, present(harness, sublemma_pass, alpha),
		Decision(:positive; exhaustive = true, selections = [FormSelection(
			"Alpha, ou Beta, première définition.",
			["Alpha", "Beta"],
			"première définition.",
		)]); decision_procedure = "test",
	)
	christ_surface = "Enfanter une âme en ou à Jésus-Christ"
	christ_record = commit(
		harness, sublemma_pass, present(harness, sublemma_pass, christ),
		Decision(:positive; exhaustive = true, selections = [FormSelection(
			"Enfanter une âme en ou à Jésus-Christ, seconde définition.",
			FormReading[
				FormReading(christ_surface, "enfanter une âme en Jésus-Christ"),
				FormReading(christ_surface, "enfanter une âme à Jésus-Christ"),
			],
			"seconde définition.",
		)]); decision_procedure = "test",
	)

	@testset "durable shape carries both geometries" begin
		alpha_forms = filter(item -> item.name == "form", only(alpha_record.assertions).constituents)
		@test length(alpha_forms) == 2
		@test all(item -> item.value === nothing, alpha_forms)
		@test alpha_forms[1].span != alpha_forms[2].span

		christ_forms = filter(item -> item.name == "form", only(christ_record.assertions).constituents)
		@test length(christ_forms) == 2
		@test christ_forms[1].span == christ_forms[2].span
		@test [item.value for item in christ_forms] == [
			"enfanter une âme en Jésus-Christ",
			"enfanter une âme à Jésus-Christ",
		]
		anchored = only(materialize_record(harness, christ_record).assertions)
		anchored_forms = filter(item -> item.name == "form", anchored.constituents)
		@test anchored_forms[1].span == anchored_forms[2].span
		@test [item.value for item in anchored_forms] == [item.value for item in christ_forms]
	end

	@testset "invalid form geometries fail closed" begin
		item = present(harness, sublemma_pass, alpha)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [FormSelection(
				"Alpha, ou Beta, première définition.", ["Alpha", "Alpha"],
			)]); decision_procedure = "test",
		)
		@test_throws ReviewItem commit(
			harness, sublemma_pass, item,
			Decision(:positive; selections = [FormSelection(
				"Alpha, ou Beta, première définition.", ["Alpha", "Alpha, ou Beta"],
			)]); decision_procedure = "test",
		)
	end

	write_pass!(harness.store, "sublemma", [alpha_record, christ_record])
	write_pass!(harness.store, "voice_variant", [
		commit(
			harness, voice_variant_pass, present(harness, voice_variant_pass, block),
			Decision(:negative); decision_procedure = "test",
		)
		for block in (alpha, christ)
	])
	resolved = resolve(harness)
	entry = only(resolved.entries)
	found = DeepLittre.Resolve.ResolvedNode[]
	function gather(nodes)
		for node in nodes
			node.node_type isa DeepLittre.Adjudication.SubLemma && push!(found, node)
			gather(node.children)
		end
	end
	gather(entry.nodes)
	@test length(found) == 2
	alpha_node = only(filter(node -> node.form == "Alpha", found))
	christ_node = only(filter(node -> node.form == "enfanter une âme en Jésus-Christ", found))

	@testset "resolution keeps every form" begin
		@test [DeepLittre.Resolve.form_value(form) for form in alpha_node.forms] == ["Alpha", "Beta"]
		@test [form.printed for form in alpha_node.forms] == ["Alpha", "Beta"]
		@test all(form -> form.value === nothing, alpha_node.forms)
		@test alpha_node.separator == ","
		@test plain_text(alpha_node.definition) == "première définition."

		@test length(christ_node.forms) == 2
		@test christ_node.forms[1].span == christ_node.forms[2].span
		@test [DeepLittre.Resolve.form_value(form) for form in christ_node.forms] == [
			"enfanter une âme en Jésus-Christ",
			"enfanter une âme à Jésus-Christ",
		]
		@test all(form -> form.printed == christ_surface, christ_node.forms)
		@test christ_node.separator == ","
	end

	@testset "both output formats preserve the forms" begin
		output = mktempdir()
		tei_path = render_tei(resolved, joinpath(output, "littre.tei.xml"))
		tei = read(tei_path, String)
		@test occursin("<form type=\"lemma\"><orth>Alpha</orth></form>", tei)
		@test occursin("<form type=\"variant\"><orth>Beta</orth></form>", tei)
		@test occursin("<form type=\"lemma\"><orth value=\"enfanter une âme en Jésus-Christ\"/></form>", tei)
		@test occursin("<form type=\"variant\"><orth value=\"enfanter une âme à Jésus-Christ\"/></form>", tei)
		if have_validator()
			@test jing_errors(tei_path) == String[]
		end

		database_path = render_sqlite(resolved, joinpath(output, "littre.db"))
		database = SQLite.DB(database_path)
		alpha_rows = [Tuple(row) for row in DBInterface.execute(database, """
			select text, value from constituents
			where node_id = ? and name = 'form' order by start_byte
		""", (alpha_node.node_id,))]
		@test isequal(alpha_rows, [("Alpha", missing), ("Beta", missing)])
		christ_rows = [Tuple(row) for row in DBInterface.execute(database, """
			select text, value from constituents
			where node_id = ? and name = 'form' order by value desc
		""", (christ_node.node_id,))]
		@test Set(christ_rows) == Set([
			(christ_surface, "enfanter une âme en Jésus-Christ"),
			(christ_surface, "enfanter une âme à Jésus-Christ"),
		])
		close(database)
	end
end
