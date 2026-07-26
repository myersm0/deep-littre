using DeepLittre
using Test

@testset "tier ordering" begin
	@test route_usg_atom("terme familier") == UsgTarget("socioCultural", "familiar")
	@test route_usg_atom("terme vieilli") == UsgTarget("temporal", "archaic")
	@test route_usg_atom("terme peu usité") == UsgTarget("frequency", "rare")
	@test route_usg_atom("terme de mépris") == UsgTarget("attitude", "derogatory")
	@test route_usg_atom("terme de perspective") == UsgTarget("domain", "")
	@test route_usg_atom("de médecine") == UsgTarget("domain", "")
end

@testset "atom splitting" begin
	@test split_atoms("Fig. et familièrement.") == ["fig", "familièrement"]
	@test split_atoms("<usg>Par extension,</usg>") == ["par extension"]
	@test normalize_atom("  Substantivement.  ") == "substantivement"
end

@testset "pos parser" begin
	@test parse_pos("s. m.") == [GramElement("pos", "noun", "s."), GramElement("gender", "masculine", "m.")]
	@test parse_pos("v. réfl.") == [GramElement("pos", "verb", "v."), GramElement("valency", "reflexive", "réfl.")]
	@test parse_pos("v. n.")[2].norm == "intransitive"
	@test parse_pos("s. n.")[2].norm == "neuter"
	@test parse_pos("part. passé.")[2].kind == "tense"
	@test parse_pos("s. m. et f.") !== nothing
	@test parse_pos("adv. de temps") === nothing
end

@testset "cross-population routing" begin
	@test route_atom("absolument") isa Vector{GramElement}
	@test route_atom("au plur") isa Vector{GramElement}
	@test route_atom("familièrement") isa UsgTarget
	@test length(route_content("Absolument et familièrement")) == 2
end

@testset "century table" begin
	@test century_range("XVIe s.") == (1501, 1600)
	@test century_range("XIIe s.") == (1101, 1200)
	@test century_range("Ajoutez :") === nothing
	@test occursin("notBefore=\"1401\"", century_date_markup("XVe s."))
end
