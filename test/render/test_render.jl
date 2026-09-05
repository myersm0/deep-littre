using SQLite, DBInterface
using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: Harness, Store, present, commit, Decision, FormSelection,
	sublemma_pass, write_pass!
using DeepLittre.Resolve: resolve
using DeepLittre.Render: render_tei, render_sqlite

@testset "renderers" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	harness = build_harness(documents, corpus)

	block = angoisse_block(harness, corpus)
	item = present(harness, sublemma_pass, block)
	write_pass!(harness.store, "sublemma", [commit(harness, sublemma_pass, item, Decision(
		:positive;
		exhaustive = true,
		selections = [FormSelection(
			"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
			"Avaler des poires d'angoisse",
			"subir des mortifications, de vifs déplaisirs.",
		)],
		residuals = ["Familièrement."],
	); decision_procedure = "test")])

	resolved = resolve(harness)
	directory = mktempdir()
	tei_path = render_tei(resolved, joinpath(directory, "littre.tei.xml"))
	database_path = render_sqlite(resolved, joinpath(directory, "littre.db"))

	@testset "TEI is well-formed and parses" begin
		document = XML.parse(XML.Node, read(tei_path, String))
		@test document !== nothing
		text = read(tei_path, String)
		@test count("<entry ", text) >= 25
		@test occursin("type=\"mainEntry\"", text)
	end

	@testset "entete material renders as a positional note" begin
		text = read(tei_path, String)
		@test occursin("<note type=\"header\">Technologie.</note>", text)
		@test occursin("<note type=\"header\">d'imager</note>", text)
		@test !occursin("<def>Technologie.</def>", text)
	end

	@testset "form-bearing nodes serialize entry-like" begin
		text = read(tei_path, String)
		@test occursin("type=\"relatedEntry\"", text)
		if have_validator()
			homonymic = replace(text, "type=\"relatedEntry\"" => "type=\"homonymicEntry\"")
			path = joinpath(mktempdir(), "homonymic.xml")
			write(path, homonymic)
			@test jing_errors(path) == String[]
		else
			@test_skip "jing or java unavailable"
		end
	end

	@testset "the sub-lemma nests as a relatedEntry" begin
		text = read(tei_path, String)
		@test occursin("type=\"relatedEntry\"", text)
		@test occursin("<orth>Avaler des poires d'angoisse</orth>", text)
		@test occursin("<def>subir des mortifications, de vifs déplaisirs.</def>", text)
		@test occursin("</form>\n", text)
		@test occursin("<pc>,</pc>\n", text)
	end

	@testset "explicit facts survive into TEI" begin
		text = read(tei_path, String)
		@test occursin("<pron>an-goi-s', et non an-goi-z'</pron>", text)
		@test occursin("<gram type=\"pos\" norm=\"noun\">", text)
		@test occursin("<usg type=\"socioCultural\" norm=\"familiar\">Familièrement.</usg>", text)
		@test occursin("<etym>", text)
		@test occursin("<cit type=\"etymon\" xml:lang=\"la\">", text)
		@test occursin("<lang expand=\"provençal\" norm=\"pro\">", text)
		@test occursin("<form><orth rend=\"italic\">angustia</orth></form>", text)
		@test occursin(r"<author corresp=\"#[^\"]+\">ID\.</author>", text)
		@test occursin(r"<biblScope corresp=\"#[^\"]+\">ib\.", text)
		@test !occursin("<author ana=\"resolved\">", text)
		@test occursin("<lbl type=\"dateRange\">", text)
	end

	@testset "grammatical marker separators survive serialization" begin
		text = read(tei_path, String)
		@test occursin(r"<gram[^>]*>v\.</gram> <gram[^>]*>a\.</gram>", text)
		@test occursin(
			r"<gram[^>]*>[Ss]\.</gram> <gram[^>]*>m\.</gram> et <gram[^>]*>f\.</gram>",
			text,
		)
	end

	@testset "no workflow state is published as markup" begin
		text = read(tei_path, String)
		# @ana carries epistemic provenance, which is legitimate; it must never carry pipeline
		# workflow state. Whitelist rather than ban, so a new value has to be considered.
		values = Set(match.captures[1] for match in eachmatch(r"ana=\"([^\"]+)\"", text))
		@test values ⊆ Set(["suspect"])
		for state in ("unclassified", "unresolved", "stale_context", "underdetermined")
			@test !occursin(state, text)
		end
	end

	# lbl/@type, cit/@subtype and note/@type are unconstrained by the schema, so their values are
	# ours alone and nothing outside this test would notice them drifting. Whitelisting them here
	# catches that at the output, which is where a downstream query would break.
	@testset "project conventions keep their committed vocabulary" begin
		text = read(tei_path, String)
		committed = DeepLittre.Resolve.rubrique_conventions
		subtypes = Set(match.captures[1] for match in eachmatch(r"subtype=\"([^\"]+)\"", text))
		@test subtypes ⊆ Set(value.subtype for value in values(committed)) ∪ Set(["other"])
		labels = Set(match.captures[1] for match in eachmatch(r"<lbl type=\"([^\"]+)\"", text))
		@test labels ⊆ Set([DeepLittre.Resolve.date_range_label, DeepLittre.Resolve.supplement_label])
		notes = Set(match.captures[1] for match in eachmatch(r"<note type=\"([^\"]+)\"", text))
		@test notes ⊆ Set(value.note for value in values(committed)) ∪
			Set(["other", DeepLittre.Resolve.header_note_type])
		@test !isempty(subtypes)
		@test !isempty(notes)
	end

	@testset "validates against the pinned Lex-0 schema" begin
		if have_validator()
			@test jing_errors(tei_path) == String[]
		else
			@test_skip "jing or java unavailable"
		end
	end

	@testset "SQLite mirrors the resolved model" begin
		database = SQLite.DB(database_path)
		count_of(query) = first(DBInterface.execute(database, query))[1]

		@test count_of("select count(*) from entries") == 26
		@test count_of("select count(*) from header_notes") == 3
		@test count_of("select count(*) from nodes") > 300
		@test count_of("select count(*) from citations") == 818
		@test count_of("select count(*) from rubriques") > 20
		@test count_of("select count(*) from etymology where kind = 'cit'") >= 30
		@test count_of("select count(*) from etymology where cit_type = 'etymon'") >= 1

		# The fallback is a fact about this parser, not about Littré or Gannaz, so it travels in
		# review beside the suspect residue and leaves the published edition alone.
		@test count_of(
			"select count(*) from review where category = 'etymology_unsegmented'",
		) >= 1
		@test !occursin("unsegmented", read(tei_path, String))
		@test count_of("select count(*) from citations where resolution = 'resolved'") >= 50
		@test count_of("select count(*) from citations where author = 'ID.' and resolved_author = 'ID.'") == 0
		@test count_of("select count(*) from citations where resolution = 'resolved' and author_antecedent_id is not null") >= 50
		@test count_of("select count(*) from citations where reference_resolution = 'resolved' and reference_antecedent_id is not null") >= 1

		@test count_of("select count(*) from nodes where node_type = 'SubLemma'") == 1
		@test count_of("select count(*) from nodes where node_type is null") ==
			count_of("select count(*) from nodes") - 1

		coverage = first(DBInterface.execute(database,
			"select population_size, examined, positive from coverage where pass = 'sublemma'"))
		@test coverage[1] == 466
		@test coverage[2] == 1
		@test coverage[3] == 1

		@test count_of(
			"select count(*) from review where category not like 'etymology_%'",
		) == 0
		@test count_of("select count(*) from constituents") == 2
		@test first(DBInterface.execute(database,
			"select separator from nodes where node_type = 'SubLemma'"))[1] == ","
		@test count_of(
			"select count(*) from qualifications where type = 'socioCultural' and norm = 'familiar'",
		) >= 1
		close(database)
	end

	# The flattened definition/content/quotation columns are for reading. Everything the resolver
	# recovered about inline structure lives here, or it is lost at the SQLite boundary while TEI
	# keeps it — which is exactly the parity failure the cross-output invariants exist to catch.
	@testset "inline structure survives into SQLite" begin
		database = SQLite.DB(database_path)
		count_of(query) = first(DBInterface.execute(database, query))[1]

		reference = first(DBInterface.execute(database, """
			select owner_kind, target, text, file, start_byte, end_byte from content_segments
			where kind = 'cross_reference' and text = 'SECRÉTAIRE'
		"""))
		@test reference[1] == "node"
		@test reference[2] == "secrétaire"
		document = harness.documents[reference[4]]
		@test occursin("SECRÉTAIRE", String(DeepLittre.Source.slice(
			document.raw_text, DeepLittre.Source.RawSpan(reference[4], reference[5], reference[6]),
		)))

		@test count_of("select count(*) from content_segments where kind = 'cross_reference'") >= 5
		@test count_of(
			"select count(*) from content_segments where source_element = 'exemple'",
		) >= 1
		@test count_of(
			"select count(*) from content_segments where source_element = 'exemple' and editorial_origin = 'gannaz'",
		) == count_of("select count(*) from content_segments where source_element = 'exemple'")
		@test count_of(
			"select count(*) from content_segments where source_element != 'exemple' and editorial_origin is not null",
		) == 0
		for owner in ("node", "rubrique", "citation")
			@test count_of(
				"select count(*) from content_segments where owner_kind = '$(owner)'",
			) > 0
		end
		@test count_of("""
			select count(*) from content_segments s
			left join nodes n on n.node_id = s.owner_id
			where s.owner_kind = 'node' and n.node_id is null
		""") == 0
		@test count_of("select count(*) from citations where citation_id is null") == 0
		close(database)
	end

	@testset "a rebuild reproduces both outputs exactly" begin
		again = resolve(harness)
		rebuilt = mktempdir()
		rebuilt_tei = render_tei(again, joinpath(rebuilt, "littre.tei.xml"))
		rebuilt_database = render_sqlite(again, joinpath(rebuilt, "littre.db"))

		@test read(rebuilt_tei) == read(tei_path)

		identifiers(corpus) = begin
			found = String[]
			visit(nodes) = for node in nodes
				push!(found, node.node_id)
				visit(node.children)
			end
			foreach(entry -> visit(entry.nodes), corpus.entries)
			found
		end
		@test identifiers(again) == identifiers(resolved)
		@test !isempty(identifiers(again))

		rows(path, query) = begin
			database = SQLite.DB(path)
			collected = [Tuple(row) for row in DBInterface.execute(database, query)]
			close(database)
			collected
		end
		for query in (
			"select * from nodes order by node_id",
			"select * from qualifications order by file, start_byte, end_byte, type",
			"select * from constituents order by node_id, name",
			"select * from content_segments order by owner_kind, owner_id, position",
			"select * from citations order by citation_id",
		)
			@test isequal(rows(rebuilt_database, query), rows(database_path, query))
		end
	end

	@testset "anchors survive into both outputs" begin
		database = SQLite.DB(database_path)
		row = first(DBInterface.execute(database,
			"select file, start_byte, end_byte, form from nodes where node_type = 'SubLemma'"))
		document = harness.documents[row[1]]
		@test String(DeepLittre.Source.slice(document.raw_text, DeepLittre.Source.RawSpan(
			row[1], row[2], row[3],
		))) == "Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs."
		close(database)
	end
end
