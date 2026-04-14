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

@testset "TEI variante-level bare register labels" begin
	@testset "familièrement at sense level splits into usg + def" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "variante_bare_register.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<usg type=\"register\">familièrement et par exagération.</usg>", tei)
		@test occursin("<def>C'est un homme atroce, très méchant.</def>", tei)
		@test !occursin("<def>Familièrement et par exagération.", tei)
	end

	@testset "populairement at sense level splits into usg + def" begin
		entries = parse_fixture(joinpath(fixtures_synthetic, "variante_bare_populaire.xml"))
		enrich!(entries)
		scope_all!(entries)
		tei = emit_single_entry(entries)

		@test occursin("<usg type=\"register\">populairement.</usg>", tei)
		@test occursin("<def>Se dit d'un homme fort maladroit.</def>", tei)
	end
end
