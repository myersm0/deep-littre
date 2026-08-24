using DeepLittre.Source: EncodingViolation, check_encoding, line_starts, line_count, line_bounds, segment

@testset "encoding policy" begin
	@testset "accepts declared form" begin
		@test check_encoding(Vector{UInt8}("<a>é</a>\n"), "f.xml") === nothing
	end

	@testset "rejects byte order mark" begin
		bytes = vcat(UInt8[0xef, 0xbb, 0xbf], Vector{UInt8}("<a/>"))
		@test_throws EncodingViolation check_encoding(bytes, "f.xml")
	end

	@testset "rejects carriage returns" begin
		@test_throws EncodingViolation check_encoding(Vector{UInt8}("<a/>\r\n"), "f.xml")
	end

	@testset "rejects malformed utf-8" begin
		@test_throws EncodingViolation check_encoding(UInt8[0x3c, 0xff, 0x3e], "f.xml")
	end

	@testset "line bounds exclude the newline" begin
		text = "alpha\nbêta\ngamma"
		starts = line_starts(text)
		@test line_count(text) == 3
		@test segment(text, line_bounds(text, starts, 1)...) == "alpha"
		@test segment(text, line_bounds(text, starts, 2)...) == "bêta"
		@test segment(text, line_bounds(text, starts, 3)...) == "gamma"
		@test_throws ErrorException line_bounds(text, starts, 4)
	end

	@testset "trailing newline yields a final empty line" begin
		text = "alpha\n"
		starts = line_starts(text)
		@test line_count(text) == 2
		@test segment(text, line_bounds(text, starts, 2)...) == ""
	end
end
