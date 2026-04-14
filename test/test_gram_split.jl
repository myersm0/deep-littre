using Test
using DeepLittre

@testset "GramSplit" begin
	@testset "leading gram label" begin
		s = DeepLittre.split_gram("<usg type=\"gram\">s. m.</usg> Les Achéménides.")
		@test s.pre_text == ""
		@test s.label_text == "s. m."
		@test s.def_text == "Les Achéménides."
		@test s.pre_kind == :none
	end

	@testset "reflexive form" begin
		s = DeepLittre.split_gram("S'ACCOUTUMER, <usg type=\"gram\">v. réfl.</usg> Contracter une habitude.")
		@test s.pre_text == "S'ACCOUTUMER"
		@test s.label_text == "v. réfl."
		@test s.def_text == "Contracter une habitude."
		@test s.pre_kind == :reflexive_form
	end

	@testset "locution form" begin
		s = DeepLittre.split_gram("En l'air, <usg type=\"gram\">loc. adv.</usg> Au milieu de l'air.")
		@test s.pre_text == "En l'air"
		@test s.label_text == "loc. adv."
		@test s.def_text == "Au milieu de l'air."
		@test s.pre_kind == :locution_form
	end

	@testset "headword echo" begin
		s = DeepLittre.split_gram("AIGRIR, <usg type=\"gram\">v. n.</usg> Devenir aigre.")
		@test s.pre_text == "AIGRIR"
		@test s.label_text == "v. n."
		@test s.def_text == "Devenir aigre."
		@test s.pre_kind == :headword_echo
	end
end
