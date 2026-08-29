using DeepLittre.Source: Edit, TransformMap, RawSpan, ViewSpan, to_raw, identity_transform,
	is_identity, apply_patches, Patch, slice

@testset "transform map" begin
	@testset "identity map" begin
		transform = identity_transform("f.xml")
		@test is_identity(transform)
		(span, synthetic) = to_raw(transform, ViewSpan("f.xml", 10, 20))
		@test span == RawSpan("f.xml", 10, 20)
		@test !synthetic
	end

	@testset "insertion maps to a zero-width raw boundary" begin
		# raw "abcdef"; "XY" inserted before index 4
		transform = TransformMap("f.xml", [Edit(4, 4, 4, 6, 1)])

		(before, _) = to_raw(transform, ViewSpan("f.xml", 1, 4))
		@test before == RawSpan("f.xml", 1, 4)

		(after, _) = to_raw(transform, ViewSpan("f.xml", 6, 9))
		@test after == RawSpan("f.xml", 4, 7)

		(inside, synthetic) = to_raw(transform, ViewSpan("f.xml", 5, 9))
		@test synthetic
		@test inside == RawSpan("f.xml", 4, 7)

		(spanning, spanning_synthetic) = to_raw(transform, ViewSpan("f.xml", 1, 9))
		@test !spanning_synthetic
		@test spanning == RawSpan("f.xml", 1, 7)
	end

	@testset "replacement covers the raw interval it replaced" begin
		# raw "ab CD ef"; " " at 3 replaced by "XYZ"
		transform = TransformMap("f.xml", [Edit(3, 4, 3, 6, 1)])

		(interior, synthetic) = to_raw(transform, ViewSpan("f.xml", 4, 5))
		@test synthetic
		@test interior == RawSpan("f.xml", 3, 4)

		(exact, exact_synthetic) = to_raw(transform, ViewSpan("f.xml", 3, 6))
		@test !exact_synthetic
		@test exact == RawSpan("f.xml", 3, 4)

		(trailing, _) = to_raw(transform, ViewSpan("f.xml", 6, 8))
		@test trailing == RawSpan("f.xml", 4, 6)
	end

	@testset "round trip through a real split patch" begin
		raw = "<indent>alpha</cit> Substantivement. beta\n"
		patches = [Patch("f.xml", 1, "</cit> Substantivement.", "</cit></indent><indent>Substantivement.")]
		(view, edits) = apply_patches(raw, "f.xml", patches)
		transform = TransformMap("f.xml", edits)

		inserted = findfirst("<indent>Substantivement.", view)
		created = ViewSpan("f.xml", first(inserted), ncodeunits(view) + 1)
		(anchor, synthetic) = to_raw(transform, created)

		@test synthetic
		@test occursin("Substantivement.", slice(raw, anchor))
		@test !occursin("<indent>", slice(raw, anchor))
	end

	@testset "span file must match" begin
		@test_throws ErrorException to_raw(identity_transform("a.xml"), ViewSpan("b.xml", 1, 2))
	end
end
