using Test
using DeepLittre

const dl = DeepLittre

function classified(content::String, role; canonical_form = "", canonical_form_source = :none,
		citations = Citation[], children = Indent[])
	indent = Indent(; content, citations, children, canonical_form, canonical_form_source)
	indent.classification = Classification(role = role, method = Manual)
	indent
end

render(f, args...) = (io = IOBuffer(); f(io, args...); String(take!(io)))

@testset "convert_italics language generalization" begin
	@test dl.convert_italics("<i lang=\"la\">volere</i>") == "<foreign xml:lang=\"la\">volere</foreign>"
	@test dl.convert_italics("<i lang=\"it\">volere</i>") == "<foreign xml:lang=\"it\">volere</foreign>"
	@test dl.convert_italics("<i>mot</i>") == "<mentioned>mot</mentioned>"
	@test dl.convert_italics("<i class=\"botanique\">rosa</i>") == "<i class=\"botanique\">rosa</i>"
	@test dl.convert_italics("<i lang=\"es\">a <i>b</i> c</i>") ==
		"<foreign xml:lang=\"es\">a <mentioned>b</mentioned> c</foreign>"
end

@testset "strip_nested_xr" begin
	converted = "Voy. <xr type=\"related\"><lbl>Voy.</lbl><ref type=\"entry\" target=\"#a\">A</ref></xr>"
	@test dl.strip_nested_xr(converted) ==
		"Voy. <lbl>Voy.</lbl><ref type=\"entry\" target=\"#a\">A</ref>"
end

@testset "citation typing and ana routing" begin
	cit = Citation(text = "Un corps tronqué de teste", author = "RONS.", reference = "675")
	@test occursin("<cit type=\"example\">", render(dl.emit_citation, cit, 0))
	attested = render((io, c, l) -> dl.emit_citation(io, c, l; ana = "attestation"), cit, 0)
	@test occursin("<cit type=\"example\" ana=\"attestation\">", attested)
	hidden = Citation(text = "t", hide = "oui")
	both = render((io, c, l) -> dl.emit_citation(io, c, l; ana = "attestation"), hidden, 0)
	@test occursin("ana=\"attestation hidden\"", both)
end

@testset "content finishers" begin
	@test dl.flatten_phrase_wrappers("<mentioned>veloi</mentioned>") ==
		"<hi rend=\"italic\">veloi</hi>"
	@test dl.flatten_phrase_wrappers("<foreign xml:lang=\"la\">volere</foreign>") ==
		"<hi rend=\"italic\" xml:lang=\"la\">volere</hi>"
	@test dl.flatten_phrase_wrappers("<i class=\"botanique\">rosa</i>") ==
		"<hi rend=\"italic\">rosa</hi>"
	@test dl.note_markup("Ce mot <semantique>fig.</semantique> et <nature>absolument</nature>.") ==
		"Ce mot fig. et absolument."
	routed = dl.etym_markup("du lat. fictif <semantique>fig.</semantique>")
	@test occursin("<usg type=\"meaningType\" norm=\"figurative\">fig.</usg>", routed)
end

@testset "inline usg extraction" begin
	@test dl.usg_position("établissement où", "") == "def_end"
	@test dl.usg_position("courte glose ", " finale.") == "single_clause"
	@test dl.usg_position("Première phrase. Puis", " la suite ; encore.") == "uncertain"

	empty!(dl.def_usg_records)
	hoisted, cleaned = dl.extract_inline_usg(
		"Se dit du vin, <usg type=\"sem\">terme de commerce</usg>, en gros.", "x_s1")
	@test cleaned == "Se dit du vin, en gros."
	@test length(hoisted) == 1
	@test occursin("terme de commerce", only(hoisted))
	@test length(dl.def_usg_records) == 1
	@test dl.def_usg_records[1][1] == "x_s1"
end

@testset "proverb form extraction" begin
	indent = classified("Prov. Petite pluie abat grand vent, c.-à-d. peu de chose suffit pour calmer une grande querelle.", Proverb())
	@test dl.extract_proverb_form!(indent)
	@test indent.canonical_form == "Petite pluie abat grand vent"
	@test indent.canonical_form_source == :prose

	self_glossing = classified("Prov. Le doute est le commencement de la sagesse.", Proverb())
	@test dl.extract_proverb_form!(self_glossing)
	@test self_glossing.canonical_form == "Le doute est le commencement de la sagesse"
end

@testset "process_mentioned dedup and lifting" begin
	form = "Tenir cabinet"
	content = "La glose. <mentioned>Tenir cabinet</mentioned>. <mentioned>Une partie du cabinet fut changée</mentioned>."
	cleaned, lifted = dl.process_mentioned(content, form, Citation[])
	@test cleaned == "La glose."
	@test lifted == ["Une partie du cabinet fut changée"]
end

@testset "strip_form_prefix" begin
	@test dl.strip_form_prefix("Tenir cabinet, tenir conseil.", "Tenir cabinet") == "tenir conseil."
	@test dl.strip_form_prefix("La glose sans écho.", "Autre forme") == "La glose sans écho."
	@test dl.normalized_phrase(dl.strip_form_prefix(
		"Le doute est le commencement de la sagesse.",
		"Le doute est le commencement de la sagesse")) == ""
end

@testset "relatedEntry emission" begin
	locution = classified("<exemple>Avoir bon marché</exemple>, obtenir à bas prix.", Locution();
		canonical_form = "Avoir bon marché", canonical_form_source = :exemple)
	# markup_to_tei converts <exemple> to <mentioned>, which dedups against the form
	out = render((io, i) -> dl.emit_indent(io, i, 1, "abc_s1.1"), locution)
	@test occursin("type=\"relatedEntry\"", out)
	@test occursin("xml:id=\"abc_s1.1.avoir_bon_marche\"", out)
	@test occursin("<orth>Avoir bon marché</orth>", out)
	@test occursin("<def>obtenir à bas prix.</def>", out)
	@test !occursin(r"<re[ >]", out)
	@test !occursin("<mentioned>Avoir bon marché</mentioned>", out)

	proverb = classified("Prov. Petite pluie abat grand vent, c.-à-d. peu de chose suffit.", Proverb();
		canonical_form = "Petite pluie abat grand vent", canonical_form_source = :prose)
	out = render((io, i) -> dl.emit_indent(io, i, 1, "abattre_s5.1"), proverb)
	@test occursin("<orth value=\"Petite pluie abat grand vent\"/>", out)
	@test occursin("norm=\"proverbial\">Prov.</usg>", out)
	@test occursin("c.-à-d. peu de chose suffit.", out)

	self_glossing = classified("Le doute est le commencement de la sagesse.", Locution();
		canonical_form = "Le doute est le commencement de la sagesse", canonical_form_source = :prose)
	out = render((io, i) -> dl.emit_indent(io, i, 1, "doute_s6.1"), self_glossing)
	@test occursin("<usg type=\"meaningType\" norm=\"proverbial\"/>", out)
	@test occursin("<def>Le doute est le commencement de la sagesse.</def>", out)

	formless = classified("Locution sans forme extraite.", Locution())
	out = render((io, i) -> dl.emit_indent(io, i, 1, "x_s1.1"), formless)
	@test occursin("<sense", out)
	@test !occursin("relatedEntry", out)
end

@testset "cross-reference wrapper swap" begin
	indent = classified("Voy. <a ref=\"AGAME\">AGAME</a>.", CrossReference())
	out = render((io, i) -> dl.emit_indent(io, i, 1, "agamie_s1.1"), indent)
	@test occursin("<xr type=\"related\" xml:id=\"agamie_s1.1\">", out)
	@test occursin("<lbl>Voy.</lbl>", out)
	@test occursin("<ref type=\"entry\" target=\"#agame\">AGAME</ref>", out)
	@test occursin("<seg>.</seg>", out)
	@test !occursin("<note type=\"xref\"", out)
	@test !occursin("<xr type=\"related\"><lbl>", out)
	@test !occursin(r">[^<>]*[^<>\s][^<>]*<(?:lbl|ref|seg|/xr)", replace(out, r"<seg>[^<]*</seg>" => "<seg/>"))
end

@testset "rubrique three-way split" begin
	historique = Rubrique(kind = Historique(), content = "XVIe s.",
		citations = [Citation(text = "Un corps tronqué de teste", author = "RONS.", reference = "675")])
	etymologie = Rubrique(kind = Etymologie(), content = "Diminutif de cabine ; génev. gabinet.")
	remarque = Rubrique(kind = Remarque(), content = "Commentaire.",
		citations = [Citation(text = "Exemple cité", author = "MOL.")])

	out = render((io,) -> dl.emit_rubriques(io, [remarque, historique, etymologie], 1))
	@test occursin("<note type=\"remarque\">", out)
	@test !occursin("dictScrap", out)
	@test !occursin("<note type=\"historique\">", out)
	@test count("<etym>", out) == 1
	@test occursin("<lbl>XVIe s.</lbl>", out)
	@test !occursin("<date", out)
	# attestation reading on ana; the remarque citation is a plain example
	@test count("ana=\"attestation\"", out) == 1
	@test count("<cit type=\"example\">", out) == 1
	# the remarque citation emits as a sibling after its note
	@test findfirst("</note>", out).start < findfirst("Exemple cité", out).start
	# account precedes attestations regardless of rubrique order
	@test findfirst("Diminutif", out).start < findfirst("<lbl>XVIe s.</lbl>", out).start
	@test !occursin("<p>", out)
end

@testset "synonyme rubrique becomes synonymy xr" begin
	rub = Rubrique(kind = Synonyme(), content = "Comparer avec <a ref=\"BONHEUR\">BONHEUR</a>.")
	out = render((io,) -> dl.emit_rubriques(io, [rub], 1))
	@test occursin("<xr type=\"synonymy\">", out)
	@test occursin("<seg>Comparer avec </seg>", out)
	@test occursin("<ref type=\"entry\" target=\"#bonheur\">BONHEUR</ref>", out)
	@test !occursin(r"<re[ >]", out)
	@test !occursin("<xr type=\"related\">", out)
end

@testset "strong transition emits homonymicEntry" begin
	group = TransitionGroup(kind = :strong, form = "S'ABAISSER", pos = "v. réfl.",
		transition_content = "S'ABAISSER, v. réfl.",
		sub_senses = BodyElement[Sense(content = "Devenir plus bas.")])
	out = render((io, g) -> dl.emit_body_element(io, g, 1, "abaisser_s3"), group)
	@test occursin("type=\"homonymicEntry\"", out)
	@test !occursin("grammaticalVariant", out)
end

@testset "metonymic gloss discriminator (flag-only)" begin
	metonymic = classified("Le cabinet tout entier donna sa démission, les membres du conseil.", Locution();
		canonical_form = "Le cabinet tout entier donna sa démission", canonical_form_source = :exemple)
	@test dl.is_metonymic_gloss(metonymic)

	idiom = classified("Avoir bon marché, obtenir à bas prix.", Locution();
		canonical_form = "Avoir bon marché", canonical_form_source = :prose)
	@test !dl.is_metonymic_gloss(idiom)
end

# Golden tests for the worked examples (cabinet, fleurer, tronquer, vouloir.1,
# agamie) are deferred until the W0-verified fixture dumps are available to
# this suite; per the work order their before side must come from those dumps,
# not the docs' hand-transcribed blocks. Expected layout once wired:
#   test/fixtures/real/<entry>.xml         (W0 dump, parse input)
#   test/golden/<entry>.tei.xml            (expected emit_tei output fragment)
