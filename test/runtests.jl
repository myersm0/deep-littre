using Test
using DeepLittre

include("test_pipeline.jl")
include("test_classification_transitions.jl")
include("test_scope_synthetic.jl")
include("test_scope_real.jl")
include("test_gram_split.jl")
include("test_tei_nature_indent_emission.jl")
include("test_tei_bare_text_label_splitting.jl")
#include("test_tei_variante_register_labels.jl")  # todo: broken tests

