using Test
using DeepLittre

include("helpers.jl")

@testset "DeepLittre" begin
	include("test_pipeline.jl")
	include("test_classification_transitions.jl")
	include("test_scope_synthetic.jl")
	include("test_scope_real.jl")
	include("test_gram_split.jl")
	include("test_rule_certainty.jl")
	include("norms_ordering.jl")
	include("norms_expected_values.jl")
	include("test_tei_nature_indent_emission.jl")
	include("test_tei_bare_text_label_splitting.jl")
	include("test_structural.jl")
	include("test_etymology.jl")
	include("classification_leads.jl")
end
