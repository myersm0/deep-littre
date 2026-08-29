struct Patch
	file::String
	line::Int
	old::String
	new::String
end

struct PatchViolation <: Exception
	patch::Patch
	reason::String
end

Base.showerror(io::IO, violation::PatchViolation) = print(
	io, "patch violation in ", violation.patch.file, " line ", violation.patch.line,
	": ", violation.reason,
)

function load_patches(path::AbstractString)::Dict{String, Vector{Patch}}
	grouped = Dict{String, Vector{Patch}}()
	isfile(path) || return grouped
	for entry in get(TOML.parsefile(path), "patches", Dict{String, Any}[])
		patch = Patch(entry["file"], entry["line"], entry["old"], entry["new"])
		isempty(patch.old) && throw(PatchViolation(patch, "target text is empty"))
		push!(get!(grouped, patch.file, Patch[]), patch)
	end
	for patches in values(grouped)
		sort!(patches; by = patch -> patch.line)
	end
	grouped
end

patches_for(grouped::Dict{String, Vector{Patch}}, file::AbstractString)::Vector{Patch} =
	get(grouped, file, Patch[])

function minimal_edit(old::AbstractString, new::AbstractString)::Tuple{Int, Int}
	old_characters = collect(old)
	new_characters = collect(new)
	shortest = min(length(old_characters), length(new_characters))
	prefix = 0
	while prefix < shortest && old_characters[prefix + 1] == new_characters[prefix + 1]
		prefix += 1
	end
	suffix = 0
	while suffix < shortest - prefix &&
			old_characters[end - suffix] == new_characters[end - suffix]
		suffix += 1
	end
	prefix_bytes = sum(ncodeunits, @view(old_characters[1:prefix]); init = 0)
	suffix_bytes = sum(ncodeunits, @view(old_characters[(end - suffix + 1):end]); init = 0)
	(prefix_bytes, suffix_bytes)
end

function sole_occurrence(raw::AbstractString, starts::Vector{Int}, patch::Patch)::Int
	(line_start, line_end) = line_bounds(raw, starts, patch.line)
	matches = filter(findall(patch.old, raw)) do match
		line_start <= first(match) < line_end
	end
	isempty(matches) && throw(PatchViolation(
		patch, "target text does not begin on the specified line",
	))
	length(matches) == 1 || throw(PatchViolation(
		patch, "target text begins more than once on the specified line",
	))
	first(only(matches))
end

function apply_patches(raw::String, file::AbstractString, patches::Vector{Patch})
	isempty(patches) && return (raw, Edit[])
	starts = line_starts(raw)
	staged = Tuple{Int, Int, SubString{String}, Int}[]
	for patch in patches
		patch.file == file ||
			throw(PatchViolation(patch, "patch addressed to $(patch.file) applied to $(file)"))
		match_start = sole_occurrence(raw, starts, patch)
		(prefix, suffix) = minimal_edit(patch.old, patch.new)
		raw_start = match_start + prefix
		raw_end = match_start + ncodeunits(patch.old) - suffix
		replacement = segment(patch.new, prefix + 1, ncodeunits(patch.new) - suffix + 1)
		push!(staged, (raw_start, raw_end, replacement, patch.line))
	end
	sort!(staged; by = first)
	for index in 2:length(staged)
		staged[index - 1][2] <= staged[index][1] ||
			error("overlapping patches in $(file) at raw byte $(staged[index][1])")
	end
	buffer = IOBuffer()
	edits = Edit[]
	cursor = 1
	position = 1
	for (raw_start, raw_end, replacement, line) in staged
		carried = segment(raw, cursor, raw_start)
		write(buffer, carried)
		position += ncodeunits(carried)
		view_start = position
		write(buffer, replacement)
		position += ncodeunits(replacement)
		push!(edits, Edit(raw_start, raw_end, view_start, position, line))
		cursor = raw_end
	end
	write(buffer, segment(raw, cursor, ncodeunits(raw) + 1))
	(String(take!(buffer)), edits)
end
