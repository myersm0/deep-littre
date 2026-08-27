using DeepLittre.Source: read_corpus, RawSpan
using DeepLittre.Census: census, all_entries
using DeepLittre.Resolve: cross_reference_index, resolve_reference

@testset "cross-reference resolution" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	index = cross_reference_index(corpus)
	entries = Dict(entry.headword => entry for entry in all_entries(corpus))

	@testset "a lemma reaches an inflected headword" begin
		# Littré's headwords carry the feminine, so the entry is DÉGOÛTÉ, ÉE while every
		# cross-reference to it says dégoûté. Slugging the reference could never reach it.
		for (headword, reference) in
				(("MESSAGER, ÈRE", "messager"), ("ANGOISSE", "angoisse"))
			haskey(entries, headword) || continue
			@test resolve_reference(index, reference) == entries[headword].raw_span
		end
	end

	@testset "an exact headword wins over a lemma" begin
		@test resolve_reference(index, "angoisse") == entries["ANGOISSE"].raw_span
	end

	@testset "a variante number reaches that variante" begin
		entry = entries["ANGOISSE"]
		variantes = filter(block -> block.kind isa DeepLittre.Census.Variante, entry.blocks)
		@test resolve_reference(index, "angoisse#var1") == first(variantes).raw_span
		@test resolve_reference(index, "angoisse#var$(length(variantes) + 1)") === nothing
	end

	@testset "no honest answer resolves to nothing" begin
		@test resolve_reference(index, "") === nothing
		@test resolve_reference(index, "motquinexistepas") === nothing
		@test resolve_reference(index, "angoisse.9") === nothing
		@test resolve_reference(index, "angoisse#var0") === nothing
	end

	@testset "a homograph index selects among entries sharing a lemma" begin
		shared = filter(collect(keys(index.by_lemma))) do lemma
			length(index.by_lemma[lemma]) > 1
		end
		if !isempty(shared)
			lemma = first(shared)
			candidates = index.by_lemma[lemma]
			# Bare, the source declined to disambiguate and so does the resolver.
			@test resolve_reference(index, lemma) === nothing
			@test resolve_reference(index, "$(lemma).1") == first(candidates).raw_span
			@test resolve_reference(index, "$(lemma).$(length(candidates))") ==
				last(candidates).raw_span
			@test resolve_reference(index, "$(lemma).$(length(candidates) + 1)") === nothing
		end
	end

	@testset "a reference with a dot that is not a homograph index stays a lemma" begin
		@test resolve_reference(index, "angoisse.x") === nothing
	end

	@testset "a multibyte lemma splits on a codepoint boundary" begin
		# `zéro#var2` puts `#` immediately after a two-byte character, so slicing by byte
		# arithmetic lands mid-codepoint. Absent from the 25-entry corpus; found on the full one.
		local_documents = read_corpus(joinpath(fixture_root, "synthetic", "references"))
		local_index = cross_reference_index(census(local_documents))
		zero = first(filter(e -> e.headword == "ZÉRO", all_entries(census(local_documents))))
		variantes = filter(b -> b.kind isa DeepLittre.Census.Variante, zero.blocks)
		@test resolve_reference(local_index, "zéro") == zero.raw_span
		@test resolve_reference(local_index, "zéro#var2") == variantes[2].raw_span
		@test resolve_reference(local_index, "zéro#var9") === nothing
	end
end
