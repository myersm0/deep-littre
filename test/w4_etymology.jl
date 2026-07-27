using DeepLittre
using Test

serialize_segments(content::String)::String = begin
	buffer = IOBuffer()
	for segment in segment_etymology(content)
		DeepLittre.print_etym_segment(buffer, segment, 0)
	end
	String(take!(buffer))
end

const tronquer_content = "Provenç. et espagn. troncar ; ital. troncare ; " *
	"du latin truncare (voy. <a ref=\"tronc\">TRONC</a>)."

const vouloir_content = "Bourg. <i>veloi</i> ; wallon, <i>voleur</i> ; " *
	"provenç. <i>voler</i> ; ital. <i lang=\"it\">volere</i> ; " *
	"du lat. fictif <i lang=\"la\">volere</i>, dérivé de l'indicatif latin " *
	"<i lang=\"la\">volo</i>, je veux ; re ϐούλομαι, ϐόλομαι ; " *
	"goth. <i>viljan</i> ; all. <i>wollen</i> ; angl. <i>to will</i> ; " *
	"radical sanscr. <i>var, vri</i>, choisir."

const fleurer_content = "Autre forme de flairer ; Génev. fleurer, sentir ; " *
	"de fleur, comme flairer vient du latin fragrare."

@testset "language table" begin
	table = load_etym_language_table()
	@test table.languages["bas-bret."] == ("br", "bas-breton")
	@test table.languages["provenç."][1] == "pro"
	@test table.languages["anc. haut allem."][1] == "goh"
	@test "voy." in table.skip
	@test haskey(table.languages, "cornw.") && isempty(table.languages["cornw."][2])
end

@testset "cue matching" begin
	table = load_etym_language_table()
	cue, consumed, key = DeepLittre.match_cue_at(["anc.", "haut", "allem."], 1, table)
	@test cue !== nothing && cue.code == "goh" && consumed == 3
	cue, consumed, _ = DeepLittre.match_cue_at(["radical", "sanscr."], 1, table)
	@test cue !== nothing && cue.printed == "radical sanscr." &&
		cue.expand == "sanscrit" && cue.code == "sa" && consumed == 2
end

@testset "tronquer segmentation" begin
	segments = segment_etymology(tronquer_content)
	@test length(segments) == 7
	@test segments[1] isa EtymCit && segments[1].cit_type == :cognate &&
		segments[1].language == "pro" && segments[1].cue.printed == "Provenç." &&
		segments[1].forms == ["troncar"]
	@test segments[2] isa EtymConnector && segments[2].printed == "et"
	@test segments[3] isa EtymCit && segments[3].language == "es" &&
		segments[3].forms == ["troncar"]
	@test segments[4] isa EtymCit && segments[4].language == "it" &&
		segments[4].forms == ["troncare"]
	@test segments[5] isa EtymConnector && segments[5].printed == "du"
	@test segments[6] isa EtymCit && segments[6].cit_type == :etymon &&
		segments[6].language == "la" && segments[6].cue.printed == "latin"
	@test segments[7] isa EtymCrossReference && segments[7].label == "voy." &&
		segments[7].target == "tronc" && segments[7].printed == "TRONC"
	@test !any(segment -> segment isa EtymCit && segment.defaulted, segments)
end

@testset "tronquer serialization" begin
	output = serialize_segments(tronquer_content)
	@test occursin("<cit type=\"cognate\" xml:lang=\"pro\">", output)
	@test occursin("<lang expand=\"provençal\" norm=\"pro\">Provenç.</lang>", output)
	@test occursin("<lang expand=\"latin\" norm=\"la\">latin</lang>", output)
	@test occursin("<cit type=\"etymon\" xml:lang=\"la\">", output)
	@test occursin("<lbl>et</lbl>", output)
	@test occursin("<lbl>du</lbl>", output)
	@test occursin(
		"<xr type=\"related\"><lbl>voy.</lbl><ref type=\"entry\" target=\"#tronc\">TRONC</ref></xr>",
		output)
	@test !occursin("mentioned", output) && !occursin("foreign", output)
end

@testset "vouloir segmentation" begin
	segments = segment_etymology(vouloir_content)
	cits = [segment for segment in segments if segment isa EtymCit]
	@test length(cits) == 12
	@test cits[1].language == "fr-x-bourguignon" && cits[1].cue.printed == "Bourg."
	@test cits[2].cue.printed == "wallon" && cits[2].language == "wa"
	@test cits[3].language == "pro"
	@test cits[5].cit_type == :etymon && cits[5].fictif &&
		cits[5].cue.printed == "lat." && cits[5].forms == ["volere"]
	@test cits[6].cit_type == :etymon && cits[6].cue === nothing &&
		cits[6].language == "la" && cits[6].forms == ["volo"] &&
		cits[6].gloss == "je veux"
	@test cits[7].language == "grc" && cits[7].forms == ["ϐούλομαι"]
	@test cits[8].language == "grc" && cits[8].forms == ["ϐόλομαι"]
	@test cits[9].language == "got" && cits[10].language == "de" &&
		cits[11].language == "en" && cits[11].forms == ["to will"]
	@test cits[12].cue.printed == "radical sanscr." &&
		cits[12].forms == ["var", "vri"] && cits[12].gloss == "choisir"
	suspects = [segment for segment in segments if segment isa EtymSuspect]
	@test length(suspects) == 1 && suspects[1].token == "re"
	proses = [segment for segment in segments if segment isa EtymProse]
	@test any(prose -> prose.markup == "dérivé de l'indicatif latin", proses)
	@test !any(cit -> cit.defaulted, cits)
end

@testset "vouloir serialization" begin
	output = serialize_segments(vouloir_content)
	@test occursin("<usg type=\"hint\">fictif</usg>", output)
	@test occursin("<lbl ana=\"suspect\">re</lbl>", output)
	@test occursin("<form type=\"variant\"><orth>var</orth></form>", output)
	@test occursin("<form type=\"variant\"><orth>vri</orth></form>", output)
	@test occursin("<gloss xml:lang=\"fr\">je veux</gloss>", output)
	@test occursin("<gloss xml:lang=\"fr\">choisir</gloss>", output)
	@test occursin("<cit type=\"cognate\" xml:lang=\"grc\">", output)
	@test occursin("<cit type=\"cognate\" xml:lang=\"fr-x-bourguignon\">", output)
	@test occursin("dérivé de l'indicatif latin", output)
	@test !occursin("<seg", output)
end

@testset "pure prose account" begin
	segments = segment_etymology(fleurer_content)
	@test length(segments) == 1
	@test segments[1] isa EtymProse && segments[1].markup == fleurer_content
end

@testset "suspect residue equality" begin
	for content in (tronquer_content, vouloir_content, fleurer_content)
		suspect_count = count(segment -> segment isa EtymSuspect,
			segment_etymology(content))
		@test suspect_count == length(collect(eachmatch(
			r"ana=\"suspect\"", serialize_segments(content))))
	end
end

@testset "century dates in bibl" begin
	citation = Citation(text = "Et se aucuns contrediseurs vouloient dire…",
		author = "DU CANGE", reference = "675")
	buffer = IOBuffer()
	DeepLittre.emit_etym_segment(buffer, "XVIe s.", [citation], 1; try_lbl = true)
	output = String(take!(buffer))
	@test occursin("<lbl>XVIe s.</lbl>", output)
	@test occursin("<cit type=\"example\" ana=\"attestation\">", output)
	@test occursin("<date notBefore=\"1501\" notAfter=\"1600\">XVIe s.</date>", output)
	@test findfirst("<bibl>", output).start < findfirst("<date", output).start <
		findfirst("</bibl>", output).start

	dateless = IOBuffer()
	bare = Citation(text = "sanz voleir mal faire")
	DeepLittre.emit_etym_segment(dateless, "XIIe s.", [bare], 1; try_lbl = true)
	bare_output = String(take!(dateless))
	@test occursin("<bibl>", bare_output)
	@test occursin("<date notBefore=\"1101\" notAfter=\"1200\">XIIe s.</date>", bare_output)

	plain = IOBuffer()
	DeepLittre.emit_etym_segment(plain, "Historique commentary.", [bare], 1; try_lbl = true)
	plain_output = String(take!(plain))
	@test !occursin("<date", plain_output)
end
