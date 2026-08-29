println("== load test environment")
flush(stdout)
load_started = time_ns()
using Test
using DeepLittre
using XML
using DeepLittre: Source, Census, Adjudication, Resolve, Render
println("   complete in ", round((time_ns() - load_started) / 1e9; digits = 2), "s")
flush(stdout)

const repository_root = normpath(joinpath(@__DIR__, ".."))
const fixture_root = joinpath(@__DIR__, "fixtures")
const corpus_source = joinpath(@__DIR__, "corpus", "source")
const corpus_adjudication = joinpath(@__DIR__, "corpus", "adjudication")

function all_qualifications(entry)
	found = []
	gather(nodes) = for node in nodes
		append!(found, node.qualifications)
		gather(node.children)
	end
	gather(entry.nodes)
	append!(found, entry.grammar)
	found
end

source_of(documents, block) = first(filter(d -> d.file == block.raw_span.file, documents))

function build_harness(documents, corpus)
	Adjudication.Harness(documents, corpus, Adjudication.Store(mktempdir()))
end

function angoisse_block(harness, corpus)
	first(filter(Census.all_blocks(corpus)) do block
		block.kind isa Census.Indent || return false
		document = harness.documents[block.raw_span.file]
		occursin("Avaler des poires", Source.slice(document.raw_text, block.raw_span))
	end)
end

const test_timings = Pair{String, Float64}[]

function run_test_file(path::AbstractString)
	println("== test ", path)
	flush(stdout)
	started = time_ns()
	try
		include(path)
	finally
		elapsed = (time_ns() - started) / 1e9
		push!(test_timings, String(path) => elapsed)
		println("   complete in ", round(elapsed; digits = 2), "s")
		flush(stdout)
	end
end

suite_started = time_ns()
try
	@testset "DeepLittre" begin
		run_test_file("source/test_spans.jl")
		run_test_file("source/test_encoding.jl")
		run_test_file("source/test_patches.jl")
		run_test_file("source/test_transform.jl")
		run_test_file("source/test_parser.jl")
		run_test_file("census/test_census.jl")
		run_test_file("adjudication/test_projection.jl")
		run_test_file("adjudication/test_harness.jl")
		run_test_file("adjudication/test_store.jl")
		run_test_file("adjudication/test_committed_store.jl")
		run_test_file("adjudication/test_voice_variant.jl")
		run_test_file("adjudication/test_scope.jl")
		run_test_file("resolve/test_resolve.jl")
		run_test_file("resolve/test_references.jl")
		run_test_file("resolve/test_etymology.jl")
		run_test_file("resolve/test_authors.jl")
		run_test_file("render/test_render.jl")
		run_test_file("render/test_rubriques.jl")
	end
finally
	suite_elapsed = (time_ns() - suite_started) / 1e9
	println("\n== test timings")
	for (path, elapsed) in sort(test_timings; by = pair -> pair.second, rev = true)
		println("   ", rpad(path, 44), lpad(string(round(elapsed; digits = 2)), 8), "s")
	end
	println("   ", rpad("total", 44), lpad(string(round(suite_elapsed; digits = 2)), 8), "s")
end
