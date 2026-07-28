using Test
using DeepLittre

const fixtures_real = joinpath(@__DIR__, "fixtures", "real")
const fixtures_synthetic = joinpath(@__DIR__, "fixtures", "synthetic")

function parse_fixture(path)
	xml = """
<xmlittre>
$(read(path, String))
</xmlittre>
"""
	tmp = tempname() * ".xml"
	write(tmp, xml)
	try
		entries = parse_file(tmp)
		@test length(entries) == 1
		return entries
	finally
		rm(tmp; force = true)
	end
end

function emit_single_entry(entries)
	buf = IOBuffer()
	DeepLittre.emit_entry(buf, entries[1], 0)
	String(take!(buf))
end

@testset "TEI nature-indent emission" begin
	@testset "reflexive form emits form + usg + def" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "nature_reflexive_form.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<form type=\"lemma\"><orth>S'ACCOUTUMER</orth></form>", tei)
		@test occursin("<gram type=\"pos\" norm=\"verb\">v.</gram>", tei)
		@test occursin("<gram type=\"valency\" norm=\"reflexive\">réfl.</gram>", tei)
		@test occursin("<def>Contracter une habitude.</def>", tei)
		@test !occursin("s'accoutumer, v. réfl.", lowercase(tei))
	end

	@testset "locution form emits form + usg + def" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "nature_locution_form.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<orth>En l'air</orth>", tei)
		@test occursin("<gram type=\"pos\" norm=\"phrase\">loc.</gram>", tei)
		@test occursin("<gram type=\"pos\" norm=\"adverb\">adv.</gram>", tei)
		@test occursin("<def>Au milieu de l'air.</def>", tei)
	end

	@testset "headword echo does not emit variant form" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "nature_headword_echo.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<gram type=\"pos\" norm=\"verb\">v.</gram>", tei)
		@test occursin("<gram type=\"valency\" norm=\"intransitive\">n.</gram>", tei)
		@test occursin("<def>Devenir aigre.</def>", tei)
		@test !occursin("<orth>AIGRIR</orth>", tei)
	end

	@testset "label-only case still emits bare usg" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "nature_label_only.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<def>Sens principal.</def>", tei)
		@test occursin("<gram type=\"pos\" norm=\"noun\">s.</gram>", tei)
		@test occursin("<gram type=\"gender\" norm=\"masculine\">m.</gram>", tei)
		@test !occursin("<sense xml:id=\"testlabelonly_s1.1\">", tei)
	end
end
