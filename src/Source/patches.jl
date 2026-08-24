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
		occursin('\n', patch.old) && throw(PatchViolation(patch, "target text contains a newline"))
		occursin('\n', patch.new) && throw(PatchViolation(patch, "replacement contains a newline"))
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

"""
	minimal_edit(old, new)

Byte lengths of the shared prefix and shared suffix of the two strings, on codepoint
boundaries. Trimming them narrows a patch to the material it actually changes, so that a
split patch inserting `</indent><indent>` records an insertion rather than a replacement of
the whole line fragment.
"""
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

function sole_occurrence(line::AbstractString, patch::Patch)::Int
	first_match = findfirst(patch.old, line)
	first_match === nothing &&
		throw(PatchViolation(patch, "target text does not occur on its line"))
	tail = findnext(patch.old, line, nextind(line, first(first_match)))
	tail === nothing ||
		throw(PatchViolation(patch, "target text occurs more than once on its line"))
	first(first_match)
end

"""
	apply_patches(raw, file, patches)

Returns the parser view and the ordered edits relating it to raw source. Every patch is
resolved against raw coordinates, so patches sharing a line do not shift one another.
"""
function apply_patches(raw::String, file::AbstractString, patches::Vector{Patch})
	isempty(patches) && return (raw, Edit[])
	starts = line_starts(raw)
	staged = Tuple{Int, Int, SubString{String}, Int}[]
	for patch in patches
		patch.file == file ||
			throw(PatchViolation(patch, "patch addressed to $(patch.file) applied to $(file)"))
		(line_start, line_end) = line_bounds(raw, starts, patch.line)
		line = segment(raw, line_start, line_end)
		offset = sole_occurrence(line, patch)
		(prefix, suffix) = minimal_edit(patch.old, patch.new)
		match_start = line_start + offset - 1
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

function assert_line_count_preserved(raw::AbstractString, view::AbstractString, file::AbstractString)
	raw_lines = line_count(raw)
	view_lines = line_count(view)
	raw_lines == view_lines ||
		error("$(file): patching changed line count from $(raw_lines) to $(view_lines)")
	nothing
end

"""
	assert_untouched_lines(raw, view, lines, file)

Byte identity outside the patched line set. This is what makes a source line number a stable
navigation field and keeps unpatched material at identical raw and view coordinates.
"""
function assert_untouched_lines(
	raw::AbstractString, view::AbstractString, lines::Set{Int}, file::AbstractString,
)
	raw_starts = line_starts(raw)
	view_starts = line_starts(view)
	for line in 1:length(raw_starts)
		line in lines && continue
		(raw_start, raw_end) = line_bounds(raw, raw_starts, line)
		(view_start, view_end) = line_bounds(view, view_starts, line)
		segment(raw, raw_start, raw_end) == segment(view, view_start, view_end) ||
			error("$(file): line $(line) changed but is not named by a patch")
	end
	nothing
end
