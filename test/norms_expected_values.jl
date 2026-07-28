using DeepLittre
using Test

const register_inventory_path =
	joinpath(@__DIR__, "sampling", "register_labels_full.tsv")

format_routing(target::UsgTarget)::String =
	isempty(target.norm) ? target.kind : "$(target.kind)/$(target.norm)"

route_label(label::AbstractString)::String =
	join((format_routing(route_usg_atom(atom)) for atom in split_atoms(label)), "; ")

function register_inventory()::Vector{Tuple{String, String}}
	rows = Tuple{String, String}[]
	for (index, line) in enumerate(eachline(register_inventory_path))
		index == 1 && continue
		fields = split(line, '\t')
		length(fields) == 3 && push!(rows, (String(fields[2]), String(fields[3])))
	end
	rows
end

@testset "atom normalization contract" begin
	@test normalize_atom("  Substantivement.  ") == "substantivement"
	@test normalize_atom("<usg>Par extension,</usg>") == "par extension"
	@test normalize_atom("Fig.") == "fig"
	@test normalize_atom("TERME   DE\tMARINE") == "terme de marine"

	rows = register_inventory()
	@test length(rows) == 216
	@testset "inventory labels are normalization fixed points" begin
		for (label, _) in rows
			@test normalize_atom(label) == label
		end
	end
end

@testset "printed spans" begin
	@test split_atom_spans("Familièrement et par dénigrement.") ==
		[("familièrement", "familièrement"), ("par dénigrement", "par dénigrement.")]
	@test split_atom_spans("Fig.") == [("fig", "fig.")]
	@test split_atoms("Familièrement et par dénigrement.") ==
		["familièrement", "par dénigrement"]

	spans = route_spans("absolument et familièrement")
	@test length(spans) == 2
	@test first(spans[1]) isa Vector{GramElement}
	@test last(spans[1]) == "absolument"
	@test first(spans[2]) isa UsgTarget
	@test last(spans[2]) == "familièrement"
end

@testset "register inventory routing" begin
	mismatches = [
		(label, routing, route_label(label))
		for (label, routing) in register_inventory() if route_label(label) != routing
	]
	foreach(row -> println(stderr, join(row, "  |  ")), mismatches)
	@test_broken isempty(mismatches)
end

