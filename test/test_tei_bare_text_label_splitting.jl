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
	return String(take!(buf))
end

@testset "TEI bare-text label splitting" begin
	@testset "bare substantivement indent splits into usg + def" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "bare_substantivement_indent.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<usg type=\"gram\">substantivement</usg>", tei)
		@test occursin("<def>homme cruel, inhumain. C'est un barbare qui se plaît à faire souffrir les animaux.</def>", tei)
		@test !occursin("<usg type=\"gram\">substantivement, homme cruel", tei)
	end

	@testset "bare register indent splits into usg + def" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "bare_register_indent.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<usg type=\"register\">familièrement</usg>", tei)
		@test occursin("<def>se dit d'un homme fort rusé.</def>", tei)
	end

	@testset "compound bare register label is preserved as full label phrase" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "compound_bare_register_indent.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<usg type=\"register\">familièrement et par dénigrement</usg>", tei)
		@test occursin("<def>Se dit d'un homme qui s'impose par le bruit.</def>", tei)
	end

	@testset "colon separator works for bare transition label" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "colon_bare_transition_indent.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<usg type=\"gram\">substantivement</usg>", tei)
		@test occursin("<def>l'adoptant et l'adopté.</def>", tei)
	end
end
