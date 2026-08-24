using DeepLittre.Source: Patch, PatchViolation, apply_patches, minimal_edit, load_patches,
	patches_for, assert_line_count_preserved, assert_untouched_lines, line_count

@testset "patches" begin
	@testset "minimal edit trims shared affixes" begin
		@test minimal_edit("Substantivement.", "</indent><indent>Substantivement.") == (0, ncodeunits("Substantivement."))
		@test minimal_edit("</cit> Substantivement.", "</cit></indent><indent>Substantivement.") ==
			(ncodeunits("</cit>"), ncodeunits("Substantivement."))
		@test minimal_edit("abc", "abc") == (3, 0)
		@test minimal_edit("é", "éé") == (2, 0)
	end

	@testset "guards" begin
		newline_patch = Dict("file" => "f.xml", "line" => 1, "old" => "a", "new" => "a\nb")
		path = tempname()
		open(path, "w") do handle
			println(handle, "[[patches]]")
			println(handle, "file = \"f.xml\"")
			println(handle, "line = 1")
			println(handle, "old = \"a\"")
			println(handle, "new = \"a\\nb\"")
		end
		@test_throws PatchViolation load_patches(path)

		text = "alpha alpha\nbeta\n"
		@test_throws PatchViolation apply_patches(text, "f.xml", [Patch("f.xml", 1, "alpha", "gamma")])
		@test_throws PatchViolation apply_patches(text, "f.xml", [Patch("f.xml", 2, "delta", "gamma")])
		@test_throws PatchViolation apply_patches(text, "f.xml", [Patch("other.xml", 2, "beta", "gamma")])
	end

	@testset "application preserves lines and untouched bytes" begin
		text = "alpha\nbeta gamma\ndelta\n"
		patches = [Patch("f.xml", 2, "beta", "<indent>beta")]
		(view, edits) = apply_patches(text, "f.xml", patches)
		@test view == "alpha\n<indent>beta gamma\ndelta\n"
		@test line_count(view) == line_count(text)
		assert_line_count_preserved(text, view, "f.xml")
		assert_untouched_lines(text, view, Set([2]), "f.xml")
		@test_throws ErrorException assert_untouched_lines(text, view, Set{Int}(), "f.xml")
		@test length(edits) == 1
		@test edits[1].raw_start == edits[1].raw_end
	end

	@testset "several patches on one line resolve against raw coordinates" begin
		text = "one two three\n"
		patches = [Patch("f.xml", 1, "one", "ONE!"), Patch("f.xml", 1, "three", "THREE")]
		(view, edits) = apply_patches(text, "f.xml", patches)
		@test view == "ONE! two THREE\n"
		@test length(edits) == 2
		@test issorted(edits; by = edit -> edit.raw_start)
	end

	@testset "overlapping patches are rejected" begin
		text = "alpha beta\n"
		patches = [Patch("f.xml", 1, "alpha beta", "x"), Patch("f.xml", 1, "beta", "y")]
		@test_throws ErrorException apply_patches(text, "f.xml", patches)
	end

	@testset "committed corpus patches satisfy the guards" begin
		grouped = load_patches(joinpath(repository_root, "patches", "patches.toml"))
		@test !isempty(grouped)
		for (file, patches) in grouped
			for patch in patches
				@test !occursin('\n', patch.old)
				@test !occursin('\n', patch.new)
				@test patch.file == file
			end
			@test issorted(patches; by = patch -> patch.line)
		end
	end
end
