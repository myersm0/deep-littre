using Test
using DeepLittre
using DeepLittre: Source, Census, Adjudication

const repository_root = normpath(joinpath(@__DIR__, ".."))
const fixture_root = joinpath(@__DIR__, "fixtures")
const sample_source = joinpath(repository_root, "sample", "source")

source_of(documents, block) = first(filter(d -> d.file == block.raw_span.file, documents))

build_harness(documents, corpus) =
	Adjudication.Harness(documents, corpus, Adjudication.Store(mktempdir()))

function angoisse_block(harness, corpus)
	first(filter(Census.all_blocks(corpus)) do block
		block.kind isa Census.Indent || return false
		document = harness.documents[block.raw_span.file]
		occursin("Avaler des poires", Source.slice(document.raw_text, block.raw_span))
	end)
end

@testset "DeepLittre" begin
	include("source/test_spans.jl")
	include("source/test_encoding.jl")
	include("source/test_patches.jl")
	include("source/test_transform.jl")
	include("source/test_parser.jl")
	include("census/test_census.jl")
	include("adjudication/test_projection.jl")
	include("adjudication/test_harness.jl")
	include("adjudication/test_store.jl")
end
