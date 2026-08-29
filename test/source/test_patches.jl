using DeepLittre.Source: Patch, PatchViolation, apply_patches, minimal_edit, load_patches

@testset "patches" begin
	@testset "minimal edit trims shared affixes" begin
		@test minimal_edit("Substantivement.", "</indent><indent>Substantivement.") == (0, ncodeunits("Substantivement."))
		@test minimal_edit("</cit> Substantivement.", "</cit></indent><indent>Substantivement.") ==
			(ncodeunits("</cit>"), ncodeunits("Substantivement."))
		@test minimal_edit("abc", "abc") == (3, 0)
		@test minimal_edit("é", "éé") == (2, 0)
	end

	@testset "guards" begin
		path = tempname()
		open(path, "w") do handle
			println(handle, "[[patches]]")
			println(handle, "file = \"f.xml\"")
			println(handle, "line = 1")
			println(handle, "old = \"\"")
			println(handle, "new = \"anything\"")
		end
		@test_throws PatchViolation load_patches(path)

		text = "alpha alpha\nbeta\n"
		@test_throws PatchViolation apply_patches(text, "f.xml", [Patch("f.xml", 1, "alpha", "gamma")])
		@test_throws PatchViolation apply_patches(text, "f.xml", [Patch("f.xml", 2, "delta", "gamma")])
		@test_throws PatchViolation apply_patches(text, "f.xml", [Patch("other.xml", 2, "beta", "gamma")])
	end

	@testset "free-form replacements may change line count" begin
		text = "alpha\nbeta gamma\ndelta\n"
		patches = [Patch("f.xml", 2, "beta gamma\ndelta", "beta\nnew line\ndelta!")]
		(view, edits) = apply_patches(text, "f.xml", patches)
		@test view == "alpha\nbeta\nnew line\ndelta!\n"
		@test length(edits) == 1
		@test edits[1].raw_start < edits[1].raw_end
		@test edits[1].view_start < edits[1].view_end
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

	@testset "committed corpus patches load deterministically" begin
		grouped = load_patches(joinpath(repository_root, "patches", "patches.toml"))
		@test !isempty(grouped)
		for (file, patches) in grouped
			@test all(patch -> patch.file == file, patches)
			@test issorted(patches; by = patch -> patch.line)
		end
	end
end
