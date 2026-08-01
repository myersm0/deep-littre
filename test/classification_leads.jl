# Pins the fixes from 08_classification_leads.md: lead 1 (adverbial tolerance
# in bare_label_tail plus routing recovery) and lead 3 (proverb markers beat
# the exemple wrapper in Tier A).

using DeepLittre
using Test

@testset "lead 1: bare_label_tail adverbial tolerance" begin
	split = DeepLittre.split_bare_transition

	@test split("Populairement encore, une ficelle") ==
		("populairement encore", "une ficelle")
	@test split("Absolument aussi, il signifie cela") ==
		("absolument aussi", "il signifie cela")
	@test split("Adjectivement dans le même sens, il a la même valeur") ==
		("adjectivement dans le même sens", "il a la même valeur")
	@test split("Populairement aujourd'hui, une chose") ==
		("populairement aujourd'hui", "une chose")
	@test split("Substantivement au singulier, le tout") ==
		("substantivement au singulier", "le tout")

	@test split("Substantivement, le trois pour cent") ==
		("substantivement", "le trois pour cent")
	@test split("Absolument et familièrement, dire de quelqu'un") ==
		("absolument et familièrement", "dire de quelqu'un")
	@test split("Au singulier, la boisson") == ("au singulier", "la boisson")

	# Separator-absent: outside the adverbial fix by design (lead 2 audit).
	@test split("Familièrement être encore tout étourdi du bateau") === nothing
	# Label-only content stays with the routed-label path, not the splitter.
	@test split("Substantivement.") === nothing
	# The boundary keeps "aussi" from matching inside "aussitôt".
	@test split("Absolument aussitôt, quelque chose") === nothing
end

@testset "lead 1: routing recovery for discourse tails" begin
	strip_tail = DeepLittre.strip_discourse_tail

	@test strip_tail("populairement encore") == "populairement"
	@test strip_tail("absolument aussi") == "absolument"
	@test strip_tail("adjectivement dans le même sens") == "adjectivement"
	@test strip_tail("populairement encore aussi") == "populairement"
	@test strip_tail("au singulier") == "au singulier"
	@test strip_tail("encore") == "encore"

	@test route_atom("populairement encore") == route_atom("populairement")
	@test route_atom("absolument aussi") == route_atom("absolument")
	@test route_atom("xyzzy") == UsgTarget("hint", "")
end

@testset "lead 3: proverb markers beat the exemple wrapper" begin
	proverb_indent = Indent(
		content = "Prov. <exemple>Il n'est sauce que d'appétit</exemple>, " *
			"c'est-à-dire on trouve bon ce qu'on mange avec appétit",
	)
	@test DeepLittre.classify_deterministic!(proverb_indent)
	@test DeepLittre.role_of(proverb_indent) isa Proverb
	@test proverb_indent.classification.method == Deterministic

	locution_indent = Indent(
		content = "<exemple>Faire faux bond</exemple>, manquer au rendez-vous",
	)
	@test DeepLittre.classify_deterministic!(locution_indent)
	@test DeepLittre.role_of(locution_indent) isa Locution

	@test DeepLittre.extract_locution!(proverb_indent) == :skip
	@test DeepLittre.extract_proverb_form!(proverb_indent)
	@test proverb_indent.canonical_form == "Il n'est sauce que d'appétit"
	@test proverb_indent.canonical_form_source == :exemple

	prose_proverb = Indent(
		content = "Prov. Qui dort dîne, se dit pour exprimer que " *
			"le sommeil tient lieu de nourriture",
	)
	DeepLittre.classify!(prose_proverb, Proverb(), Heuristic)
	@test DeepLittre.extract_proverb_form!(prose_proverb)
	@test prose_proverb.canonical_form == "Qui dort dîne"
	@test prose_proverb.canonical_form_source == :prose
end
