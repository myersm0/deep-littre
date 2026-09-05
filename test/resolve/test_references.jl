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

	@testset "a homograph index follows source sens, not document position" begin
		local_documents = read_corpus(joinpath(fixture_root, "synthetic", "references"))
		local_corpus = census(local_documents)
		local_index = cross_reference_index(local_corpus)
		pairs = filter(e -> e.headword == "PAIR", all_entries(local_corpus))
		@test [entry.homograph for entry in pairs] == [2, 1]
		@test resolve_reference(local_index, "pair") === nothing
		@test resolve_reference(local_index, "pair.1") ==
			only(e for e in pairs if e.homograph == 1).raw_span
		@test resolve_reference(local_index, "pair.2") ==
			only(e for e in pairs if e.homograph == 2).raw_span
		@test resolve_reference(local_index, "pair.3") === nothing
	end

	@testset "a homograph index does not fall back to candidate position" begin
		local_documents = read_corpus(joinpath(fixture_root, "synthetic", "references"))
		local_corpus = census(local_documents)
		local_index = cross_reference_index(local_corpus)
		solo = only(e for e in all_entries(local_corpus) if e.headword == "SOLO")
		@test solo.homograph == 2
		@test resolve_reference(local_index, "solo.1") === nothing
		@test resolve_reference(local_index, "solo.2") == solo.raw_span
	end

	@testset "a reference with a dot that is not a homograph index stays a lemma" begin
		@test resolve_reference(index, "angoisse.x") === nothing
	end

	@testset "a rubrique fragment reaches that rubrique" begin
		local_documents = read_corpus(joinpath(fixture_root, "synthetic", "fragments"))
		local_corpus = census(local_documents)
		local_index = cross_reference_index(local_corpus)
		local_entries = Dict(entry.headword => entry for entry in all_entries(local_corpus))
		named(entry, name) = only(filter(rubrique -> rubrique.name == name, entry.rubriques))

		tache = local_entries["TACHE"]
		@test resolve_reference(local_index, "tache#etymologie") ==
			named(tache, "ÉTYMOLOGIE").raw_span
		# The fragment is unaccented and abbreviated against a three-word @nom.
		@test resolve_reference(local_index, "tache#supplement") ==
			named(tache, "SUPPLÉMENT AU DICTIONNAIRE").raw_span
		# The entry carries no rubrique of that name, so nothing rather than the entry.
		@test resolve_reference(local_index, "tache#historique") === nothing

		# A plural fragment reaches a singular @nom, at whatever depth the source printed it.
		battant = local_entries["BATTANT, ANTE"]
		@test resolve_reference(local_index, "battant#proverbes") ==
			named(battant, "PROVERBE").raw_span

		# Two rubriques of one name inside senses: the source names no one of them.
		@test resolve_reference(local_index, "indice#proverbes") === nothing
	end

	@testset "a homograph index narrows to the exact headword first" begin
		local_documents = read_corpus(joinpath(fixture_root, "synthetic", "fragments"))
		local_corpus = census(local_documents)
		local_index = cross_reference_index(local_corpus)
		homograph(headword, number) = only(filter(
			entry -> entry.headword == headword && entry.homograph == number,
			all_entries(local_corpus),
		))

		# PRIME and PRIME, ÉE both carry sens="1"; only the exact headword set separates them.
		@test resolve_reference(local_index, "prime.1") == homograph("PRIME", 1).raw_span

		# The exact set answers, so the wider one is never consulted.
		@test resolve_reference(local_index, "garde.1") == homograph("GARDE", 1).raw_span

		# The exact set carries no sens 4, so the lemma set still has to be tried.
		@test resolve_reference(local_index, "garde.4") == homograph("GARDE, ÉE", 4).raw_span

		# Neither set carries it.
		@test resolve_reference(local_index, "garde.9") === nothing

		# A bare lemma several entries share stays unresolved under either set.
		@test resolve_reference(local_index, "garde") === nothing
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
