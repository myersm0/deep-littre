using DeepLittre.Source: RawSpan, ViewSpan, slice, segment, covers, disjoint, crosses,
	laminar, is_boundary, validate_span, view_span, text_sha256, span_sha256

@testset "spans" begin
	text = "abcéfg"

	@testset "slicing is half-open" begin
		@test slice(text, RawSpan("f", 1, 4)) == "abc"
		@test slice(text, RawSpan("f", 1, 1)) == ""
		@test slice(text, RawSpan("f", 4, 6)) == "é"
		@test slice(text, RawSpan("f", 1, ncodeunits(text) + 1)) == text
	end

	@testset "boundaries" begin
		@test is_boundary(text, 4)
		@test !is_boundary(text, 5)
		@test is_boundary(text, ncodeunits(text) + 1)
		@test_throws ErrorException validate_span(text, RawSpan("f", 4, 5))
		@test_throws ErrorException validate_span(text, RawSpan("f", 5, 6))
	end

	@testset "geometry" begin
		outer = RawSpan("f", 10, 20)
		inner = RawSpan("f", 12, 15)
		later = RawSpan("f", 20, 30)
		straddling = RawSpan("f", 15, 25)

		@test covers(outer, inner)
		@test !covers(inner, outer)
		@test disjoint(outer, later)
		@test !crosses(outer, inner)
		@test !crosses(outer, later)
		@test crosses(outer, straddling)
		@test laminar(outer, inner)
		@test !laminar(outer, straddling)
		@test disjoint(outer, RawSpan("other", 12, 15))
	end

	@testset "layers do not mix" begin
		@test_throws MethodError covers(RawSpan("f", 1, 5), ViewSpan("f", 2, 3))
	end

	@testset "xml range conversion takes nextind" begin
		source = "<a>é</a>"
		span = view_span("f", source, 1:ncodeunits(source))
		@test span.end_byte == ncodeunits(source) + 1
		@test slice(source, span) == source
	end

	@testset "hashing" begin
		@test text_sha256("abcéfg") == "bfec70d6fc19212149b950a680db521f230c825eb0ce33860fb35e6912c6ca7c"
		@test text_sha256(SubString("XXabcéfgYY", 3, 9)) == text_sha256("abcéfg")

		@test span_sha256(text, RawSpan("f", 1, 4)) == span_sha256("abcXY", RawSpan("f", 1, 4))
		@test span_sha256(text, RawSpan("f", 1, 4)) != span_sha256(text, RawSpan("f", 1, 3))
	end
end
