using SQLite, DBInterface
using DeepLittre.Source: read_corpus, read_document, Patch, slice, covers, anchor_id
using DeepLittre.Census: census, all_blocks, RubriqueDirect
using DeepLittre.Adjudication: Harness, Store, present, commit, Decision, FormSelection, sublemma_pass, write_pass!
using DeepLittre.Resolve: resolve, plain_text, RubriqueLabel, RubriqueCitation, RubriqueProse,
	RubriqueNode, conventions_for, rubrique_heading, century_pattern, supplement_label
using DeepLittre.Render: render_tei, render_sqlite

@testset "rubrique structure" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	resolved = resolve(build_harness(documents, corpus))

	entry_named(headword) = first(filter(e -> e.headword == headword, resolved.entries))
	rubriques(headword, name) = filter(r -> r.name == name, entry_named(headword).rubriques)

	source_citations = sum(
		count("<cit ", document.raw_text) for document in documents
	)

	@testset "every source citation survives" begin
		in_senses = sum(
			length(DeepLittre.Resolve.entry_citations(entry)) for entry in resolved.entries
		)
		in_rubriques = sum(
			count(item -> item isa RubriqueCitation, rubrique.items)
			for entry in resolved.entries for rubrique in entry.rubriques
		)
		@test source_citations == 831
		@test in_senses + in_rubriques == source_citations
		@test in_rubriques == 269
	end

	@testset "nested rubrique blocks are recursed into" begin
		# COTRET's supplement holds citations at two depths: rubrique > variante > cit, and
		# rubrique > variante > indent > cit. A one-level walk finds only the first.
		supplement = only(rubriques("COTRET", "SUPPLÉMENT AU DICTIONNAIRE"))
		found = filter(item -> item isa RubriqueCitation, supplement.items)
		@test length(found) == 2
		quotations = [plain_text(item.citation.quotation) for item in found]
		@test any(text -> occursin("Cotrets de taillis", text), quotations)
		@test any(text -> occursin("Danser sous le cotret", text), quotations)
	end


	@testset "nested rubriques retain their source position" begin
		hardeau = entry_named("HARDEAU")
		supplement = only(filter(r -> r.name == "SUPPLÉMENT AU DICTIONNAIRE", hardeau.rubriques))
		nested = sort(
			filter(r -> r.parent_id == anchor_id(supplement.span), hardeau.rubriques);
			by = r -> r.span.start_byte,
		)
		@test [rubrique.name for rubrique in nested] == ["HISTORIQUE", "ÉTYMOLOGIE"]

		directory = mktempdir()
		tei_path = render_tei(resolved, joinpath(directory, "littre.tei.xml"))
		text = read(tei_path, String)
		positions = [
			findfirst("Diminutif de hart.", text),
			findfirst("HARDEAU. Ajoutez", text),
			findfirst("Il eut ung fils nommé Tenot Dandin", text),
			findfirst("Hardeau, au sens de vaurien", text),
		]
		@test all(position -> position !== nothing, positions)
		starts = [first(position) for position in positions if position !== nothing]
		@test length(starts) == 4
		@test issorted(starts)

		database_path = render_sqlite(resolved, joinpath(directory, "littre.db"))
		database = SQLite.DB(database_path)
		rows = collect(Tuple(row) for row in DBInterface.execute(
			database,
			"select name, parent_rubrique_id, position from rubriques where entry_id = ? order by position",
			(hardeau.entry_id,),
		))
		@test [row[1] for row in rows] == [
			"ÉTYMOLOGIE", "SUPPLÉMENT AU DICTIONNAIRE", "HISTORIQUE", "ÉTYMOLOGIE",
		]
		supplement_id = anchor_id(supplement.span)
		@test rows[1][2] === missing
		@test rows[2][2] === missing
		@test rows[3][2] == supplement_id
		@test rows[4][2] == supplement_id
		SQLite.close(database)
	end

	@testset "a century header becomes a label, once per paragraph" begin
		historical = only(rubriques("ANGOISSE", "HISTORIQUE"))
		labels = filter(item -> item isa RubriqueLabel, historical.items)
		@test [label.text for label in labels] == ["XIIe s.", "XIIIe s.", "XVe s.", "XVIe s."]
		@test all(label -> label.kind == "dateRange", labels)
		for label in labels
			document = first(filter(d -> d.file == label.span.file, documents))
			@test strip(slice(document.raw_text, label.span)) == label.text
			@test covers(historical.span, label.span)
		end
	end

	@testset "the century pattern is a committed rule with counted residue" begin
		for good in ("Xe s.", "XIIe s.", "XIIe. s.", "(*) XVe s.", "XVIe s.")
			@test occursin(century_pattern, good)
		end
		for bad in ("Ajoutez :", "XVIe siècle", "REM. quelque chose", "")
			@test !occursin(century_pattern, bad)
		end
		@test all(f -> f.category != "century_unrecognized", resolved.review)
	end


	@testset "HISTORIQUE lead grammar separates supplement, century, and residue" begin
		directory = mktempdir()
		path = joinpath(directory, "historique.xml")
		write(path, """<?xml version="1.0" encoding="UTF-8"?>
<xmlittre>
<entree terme="HISTORIQUE TEST">
<entete><prononciation>x</prononciation><nature>s. m.</nature></entete>
<corps><rubrique nom="HISTORIQUE">
<indent>XVIe s. Ajoutez : Texte A. <cit aut="A" ref="1">Citation A.</cit></indent>
<indent>Ajoutez : XIIIe s. Texte B. <cit aut="B" ref="2">Citation B.</cit></indent>
<indent>Ajoutez : Texte C. <cit aut="C" ref="3">Citation C.</cit></indent>
<indent>XIIe. s. Texte D. <cit aut="D" ref="4">Citation D.</cit></indent>
<indent>(*) XVe s. Texte E. <cit aut="E" ref="5">Citation E.</cit></indent>
<indent>Prose sans siècle. <cit aut="F" ref="6">Citation F.</cit></indent>
</rubrique></corps>
</entree>
</xmlittre>
""")
		document = read_document(path)
		local_corpus = census([document])
		local_resolved = resolve(build_harness([document], local_corpus))
		historical = only(only(local_resolved.entries).rubriques)
		labels = filter(item -> item isa RubriqueLabel, historical.items)
		@test [label.kind for label in labels] == [
			"dateRange", supplement_label, supplement_label, "dateRange", supplement_label,
			"dateRange", "dateRange",
		]
		@test [label.text for label in labels] == [
			"XVIe s.", "Ajoutez :", "Ajoutez :", "XIIIe s.", "Ajoutez :",
			"XIIe. s.", "(*) XVe s.",
		]
		prose = [plain_text(item.content) for item in historical.items if item isa RubriqueProse]
		@test prose == ["Texte A.", "Texte B.", "Texte C.", "Texte D.", "Texte E.", "Prose sans siècle."]
		findings = filter(finding -> finding.category == "century_unrecognized", local_resolved.review)
		@test length(findings) == 1
		@test occursin("Prose sans siècle", only(findings).detail)
		citations = filter(item -> item isa RubriqueCitation, historical.items)
		@test (citations[1].not_before, citations[1].not_after) == (1501, 1600)
		@test (citations[2].not_before, citations[2].not_after) == (1201, 1300)
		@test (citations[4].not_before, citations[4].not_after) == (1101, 1200)
		@test (citations[5].not_before, citations[5].not_after) == (1401, 1500)
	end

	@testset "explicit phrase wrappers survive coarse rubrique resolution" begin
		proverb = only(rubriques("MESSAGER, ÈRE", "PROVERBE"))
		prose = only(filter(item -> item isa RubriqueProse, proverb.items))
		emphasis = only(filter(item -> item isa DeepLittre.Resolve.Emphasis, prose.content))
		@test emphasis.text == "On ne trouva jamais meilleur messager que soi-même"
		@test emphasis.source_element == "exemple"
	end

	@testset "rubrique prose anchors remain raw after a length-changing patch" begin
		directory = mktempdir()
		path = joinpath(directory, "r.xml")
		write(path, """<?xml version="1.0" encoding="UTF-8"?>
<xmlittre>
<entree terme="PATCHED">
<entete><prononciation>x</prononciation><nature>s. m.</nature></entete>
<corps><variante num="1">Définition.</variante><rubrique nom="REMARQUE"><indent>Texte de remarque.</indent></rubrique></corps>
</entree>
</xmlittre>
""")
		document = read_document(path; patches = [Patch("r.xml", 4, ">x<", ">prononciation-longue<")])
		local_corpus = census([document])
		local_resolved = resolve(build_harness([document], local_corpus))
		rubrique = only(only(local_resolved.entries).rubriques)
		prose = only(filter(item -> item isa RubriqueProse, rubrique.items))
		@test String(slice(document.raw_text, prose.span)) == "Texte de remarque."
		@test covers(rubrique.span, prose.span)
	end

	@testset "a cross-reference in rubrique prose stays inside what <seg> admits" begin
		local_documents = read_corpus(joinpath(fixture_root, "synthetic", "references"))
		local_resolved = resolve(build_harness(local_documents, census(local_documents)))
		tei_path = render_tei(local_resolved, joinpath(mktempdir(), "littre.tei.xml"))
		text = read(tei_path, String)

		# The lemma NOTRE is the headword NOTRE, NÔTRE, which no slug of the source ref would reach.
		@test occursin("<ref type=\"entry\" target=\"#notre_notre\">NOTRE</ref>", text)
		# Nothing carries this lemma, so a textual reference rather than a guessed pointer.
		@test occursin("<ref type=\"entry\">INTROUVABLE</ref>", text)
		# A variante number reaches the sense minted for that variante.
		@test occursin("<ref type=\"entry\" target=\"#zero_s2\">ZÉRO</ref>", text)
		for segment in eachmatch(r"<seg\b.*?</seg>"s, text)
			@test !occursin("<xr", segment.match)
		end
		if have_validator()
			@test jing_errors(tei_path) == String[]
		else
			@test_skip "jing or java unavailable"
		end
	end

	@testset "a rubrique inside a block is not absorbed into its definition" begin
		path = joinpath(fixture_root, "synthetic", "nested_rubrique.xml")
		document = read_document(path)
		local_corpus = census([document])
		local_resolved = resolve(build_harness([document], local_corpus))
		entry = only(local_resolved.entries)

		# The rubrique is hoisted to entry level whatever its depth in the source.
		@test only(entry.rubriques).name == "PROVERBE"
		proverb = "À l'impossible nul n'est tenu"
		definitions = String[]
		collect_definitions(nodes) = for node in nodes
			push!(definitions, plain_text(node.definition))
			collect_definitions(node.children)
		end
		collect_definitions(entry.nodes)
		@test !any(text -> occursin(proverb, text), definitions)
		@test any(text -> occursin("supposition qui paraît impossible", text), definitions)

		tei_path = render_tei(local_resolved, joinpath(mktempdir(), "littre.tei.xml"))
		text = read(tei_path, String)
		@test length(collect(eachmatch(Regex(proverb), text))) == 1
		# Littré put PROVERBE inside variante 5; emitting it at entry level would keep the
		# material and lose which sense it belonged to.
		sense = match(r"<sense xml:id=\"impossible_s1\".*?\n        </sense>"s, text)
		@test sense !== nothing
		@test !occursin("<note type=\"proverb\" subtype=\"label\">", sense.match)
		@test occursin("<note type=\"proverb\" xml:id=", sense.match)
		@test occursin("<seg type=\"label\">Proverbe.</seg>", sense.match)
		@test occursin("<seg type=\"example\">", sense.match)
		if have_validator()
			@test jing_errors(tei_path) == String[]
		else
			@test_skip "jing or java unavailable"
		end
	end

	@testset "citations carry their rubrique's subtype" begin
		@test conventions_for("PROVERBE") == (note = "proverb", subtype = "proverb")
		@test conventions_for("PROVERBES") == (note = "proverb", subtype = "proverb")
		@test rubrique_heading("PROVERBE") == "Proverbe."
		@test rubrique_heading("PROVERBES") == "Proverbes."
		@test rubrique_heading("HISTORIQUE") === nothing
		@test conventions_for("HISTORIQUE").subtype == "attestation"
		@test conventions_for("REMARQUE").subtype == "remark"
		@test conventions_for("SUPPLÉMENT AU DICTIONNAIRE").subtype == "supplement"
		@test conventions_for("UNKNOWN RUBRIQUE") == (note = "other", subtype = "other")

		historical = only(rubriques("ANGOISSE", "HISTORIQUE"))
		for item in filter(i -> i isa RubriqueCitation, historical.items)
			@test item.subtype == "attestation"
		end
	end

	@testset "rubrique citations join the ID. anaphora" begin
		resolutions = Set(
			item.citation.resolution
			for entry in resolved.entries for rubrique in entry.rubriques
			for item in rubrique.items if item isa RubriqueCitation
		)
		@test :printed in resolutions
		@test :absent in resolutions
	end

	@testset "rubriques render in source order" begin
		directory = mktempdir()
		text = read(render_tei(resolved, joinpath(directory, "littre.tei.xml")), String)
		entry = text[findfirst("<entry xml:id=\"angoisse\"", text)[1]:end]
		entry = entry[1:findfirst("</entry>", entry)[1]]

		historical = findfirst("<lbl type=\"dateRange\">", entry)[1]
		etymology = findfirst("<etym>", entry)[1]
		supplement = findfirst("<note type=\"supplement\">", entry)[1]
		@test historical < etymology < supplement
	end

	@testset "etymology segments retain paragraph order during rubrique ordering" begin
		directory = mktempdir()
		write(joinpath(directory, "a.xml"), """<?xml version="1.0" encoding="UTF-8"?>
<xmlittre>
<entree terme="ACCOUPLER">
<entete><prononciation>a-kou-plé</prononciation><nature>v. a.</nature></entete>
<corps><variante num="1">Disposer par couples.</variante></corps>
<rubrique nom="ÉTYMOLOGIE"><indent><i>À</i> et <i>couple</i> ; Berry, <i>accoubler</i>.</indent></rubrique>
</entree>
</xmlittre>
""")
		local_documents = read_corpus(directory)
		local_corpus = census(local_documents)
		local_resolved = resolve(build_harness(local_documents, local_corpus))
		tei_path = render_tei(local_resolved, joinpath(directory, "littre.tei.xml"))
		text = read(tei_path, String)
		@test occursin(
			"<cit type=\"etymon\" xml:lang=\"fr\"><form><orth rend=\"italic\">À</orth></form></cit> et <cit type=\"etymon\" xml:lang=\"fr\"><form><orth rend=\"italic\">couple</orth></form></cit> <pc>;</pc> <cit type=\"cognate\" xml:lang=\"fr-x-berrich\">",
			text,
		)
		@test occursin("<orth rend=\"italic\">accoubler</orth>", text)
		@test !occursin("type=\"component\"", text)
		@test occursin("</cit><pc>.</pc></etym>", text)
		@test !occursin("<lbl>et</lbl>", text)
		if have_validator()
			@test jing_errors(tei_path) == String[]
		else
			@test_skip "jing or java unavailable"
		end
	end

	@testset "lifted citations validate and keep their anchors" begin
		directory = mktempdir()
		tei_path = render_tei(resolved, joinpath(directory, "littre.tei.xml"))
		text = read(tei_path, String)
		@test occursin(r"<cit type=\"example\" xml:id=\"[^\"]+\" subtype=\"attestation\">", text)
		@test occursin("<lbl type=\"dateRange\">", text)
		@test occursin(
			"<seg type=\"example\">On ne trouva jamais meilleur messager que soi-même</seg>.",
			text,
		)
		@test !occursin("<seg type=\"example\"><hi", text)
		# <note> cannot hold <cit> under Lex-0, so no citation may be nested inside one
		for note in eachmatch(r"<note\b.*?</note>", text)
			@test !occursin("<cit ", note.match)
		end
		if have_validator()
			@test jing_errors(tei_path) == String[]
		else
			@test_skip "jing or java unavailable"
		end

		database_path = render_sqlite(resolved, joinpath(directory, "littre.db"))
		database = SQLite.DB(database_path)
		count_of(query) = first(DBInterface.execute(database, query))[1]
		@test count_of("select count(*) from citations") == 831
		@test count_of("select count(*) from citations where origin = 'rubrique'") == 269
		@test count_of("select count(*) from citations where origin = 'rubrique' and rubrique is null") == 0

		row = first(DBInterface.execute(database,
			"select file, start_byte, end_byte from citations where origin = 'rubrique' limit 1"))
		document = first(filter(d -> d.file == row[1], documents))
		@test startswith(slice(document.raw_text, DeepLittre.Source.RawSpan(row[1], row[2], row[3])), "<cit ")
		close(database)
	end


	@testset "coarse proverb notes link lifted attestations" begin
		directory = mktempdir()
		write(joinpath(directory, "p.xml"), """<?xml version="1.0" encoding="UTF-8"?>
<xmlittre>
<entree terme="PROVERBIAL">
<entete><prononciation>x</prononciation><nature>s. m.</nature></entete>
<corps><variante num="1">Définition.</variante></corps>
<rubrique nom="PROVERBE"><indent><exemple>Qui dort dîne</exemple>, formule proverbiale.<cit aut="TEST" ref="1">Attestation.</cit></indent></rubrique>
</entree>
</xmlittre>
""")
		local_documents = read_corpus(directory)
		local_resolved = resolve(build_harness(local_documents, census(local_documents)))
		tei_path = render_tei(local_resolved, joinpath(directory, "littre.tei.xml"))
		text = read(tei_path, String)
		@test !occursin("<note type=\"proverb\" subtype=\"label\">", text)
		@test occursin("<seg type=\"label\">Proverbe.</seg>", text)
		@test !occursin("<note type=\"proverb\" xml:id=\"proverbial_proverb_1\"><seg>", text)
		linked = match(
			r"<note type=\"proverb\" xml:id=\"([^\"]+)\"><seg type=\"label\">Proverbe\.</seg> .*?</note>.*?<cit type=\"example\" xml:id=\"[^\"]+\" subtype=\"proverb\" corresp=\"#([^\"]+)\">"s,
			text,
		)
		@test linked !== nothing
		if linked !== nothing
			@test linked.captures[1] == linked.captures[2]
		end
		if have_validator()
			@test jing_errors(tei_path) == String[]
		else
			@test_skip "jing or java unavailable"
		end
	end

	@testset "rubrique structural verdicts become semantic nodes" begin
		directory = mktempdir()
		write(joinpath(directory, "r.xml"), """<?xml version="1.0" encoding="UTF-8"?>
<xmlittre>
<entree terme="DORMIR">
<entete><prononciation>dor-mir</prononciation><nature>v. n.</nature></entete>
<corps>
<variante num="1">Être dans le sommeil.</variante>
<rubrique nom="PROVERBE"><exemple>Qui dort dîne</exemple>, signifie que le sommeil trompe la faim.<cit aut="TEST" ref="1">Attestation du proverbe.</cit></rubrique>
</corps>
</entree>
</xmlittre>
""")
		local_documents = read_corpus(directory)
		local_corpus = census(local_documents)
		harness = build_harness(local_documents, local_corpus)
		direct = only(filter(block -> block.kind isa RubriqueDirect, all_blocks(local_corpus)))
		record = commit(
			harness, sublemma_pass, present(harness, sublemma_pass, direct),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Qui dort dîne, signifie que le sommeil trompe la faim.",
				"Qui dort dîne",
				"signifie que le sommeil trompe la faim.",
			)]); decision_procedure = "test",
		)
		write_pass!(harness.store, "sublemma", [record])
		local_resolved = resolve(harness)
		rubrique = only(only(local_resolved.entries).rubriques)
		semantic = only(filter(item -> item isa RubriqueNode, rubrique.items))
		@test semantic.node.form == "Qui dort dîne"
		@test plain_text(semantic.node.definition) == "signifie que le sommeil trompe la faim."
		@test length(semantic.node.citations) == 1
		@test plain_text(only(semantic.node.citations).quotation) == "Attestation du proverbe."
		@test isempty(filter(item -> item isa RubriqueProse, rubrique.items))
		@test isempty(filter(item -> item isa RubriqueCitation, rubrique.items))

		tei_path = render_tei(local_resolved, joinpath(directory, "littre.tei.xml"))
		text = read(tei_path, String)
		@test occursin("<note type=\"proverb\" subtype=\"label\">Proverbe.</note>", text)
		@test occursin("<entry xml:id=\"dormir_qui_dort_dine\"", text)
		@test occursin("<orth>Qui dort dîne</orth>", text)
		@test occursin("<def>signifie que le sommeil trompe la faim.</def>", text)
		@test occursin(r"<cit type=\"example\" xml:id=\"[^\"]+\" subtype=\"proverb\">", text)
		@test length(collect(eachmatch(r"Attestation du proverbe\.", text))) == 1
		if have_validator()
			@test jing_errors(tei_path) == String[]
		else
			@test_skip "jing or java unavailable"
		end

		database_path = render_sqlite(local_resolved, joinpath(directory, "littre.db"))
		database = SQLite.DB(database_path)
		node_row = only(Tuple(row) for row in DBInterface.execute(database,
			"select origin, rubrique, rubrique_id from nodes where node_type = 'SubLemma'"))
		@test node_row[1] == "rubrique"
		@test node_row[2] == "PROVERBE"
		@test node_row[3] !== missing
		citation_row = only(Tuple(row) for row in DBInterface.execute(database,
			"select origin, rubrique, subtype, node_id from citations"))
		@test citation_row[1] == "rubrique"
		@test citation_row[2] == "PROVERBE"
		@test citation_row[3] == "proverb"
		@test citation_row[4] !== missing
		close(database)
	end

end
