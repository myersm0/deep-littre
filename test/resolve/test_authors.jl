using DeepLittre.Source: read_corpus, slice
using DeepLittre.Census: census
using DeepLittre.Adjudication: Harness, Store, present, commit, Decision, FormSelection,
	sublemma_pass, write_pass!
using DeepLittre.Resolve: resolve, entry_citations

@testset "author resolution" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	resolved = resolve(build_harness(documents, corpus))

	all_citations = reduce(vcat, (entry_citations(entry) for entry in resolved.entries))

	@testset "ID. resolves to its antecedent" begin
		anaphoric = filter(citation -> citation.author == "ID.", all_citations)
		@test !isempty(anaphoric)
		@test all(citation -> citation.resolution in (:resolved, :unresolved), anaphoric)
		for citation in filter(c -> c.resolution == :resolved, anaphoric)
			@test citation.resolved_author != "ID."
			@test !isempty(citation.resolved_author)
		end
	end

	@testset "the printed form is retained alongside the resolution" begin
		for citation in filter(c -> c.resolution == :resolved, all_citations)
			@test citation.author == "ID."
			document = first(filter(d -> d.file == citation.span.file, documents))
			@test occursin("aut=\"ID.\"", String(slice(document.raw_text, citation.span)))
		end
	end

	@testset "printed authors pass through untouched" begin
		named = filter(citation -> citation.resolution == :printed, all_citations)
		@test !isempty(named)
		@test all(citation -> citation.resolved_author == citation.author, named)
		@test all(citation -> citation.author != "ID.", named)
	end

	@testset "an absent author is not an unresolved one" begin
		absent = filter(citation -> citation.resolution == :absent, all_citations)
		@test all(citation -> isempty(citation.author), absent)
		@test all(citation -> isempty(citation.resolved_author), absent)
	end

	@testset "resolution follows source order, not semantic order" begin
		# The ANGOISSE sub-lemma reattaches its citation to a nested node; the antecedent must be
		# unaffected by that reparenting.
		harness = build_harness(documents, corpus)
		block = angoisse_block(harness, corpus)
		write_pass!(harness.store, "sublemma", [commit(
			harness, sublemma_pass, present(harness, sublemma_pass, block),
			Decision(:positive; exhaustive = true, selections = [FormSelection(
				"Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.",
				"Avaler des poires d'angoisse",
				"subir des mortifications, de vifs déplaisirs.",
			)], residuals = ["Familièrement."]); decision_procedure = "test")])

		adjudicated = resolve(harness)
		before = Dict(
			(citation.span.file, citation.span.start_byte) => citation.resolved_author
			for citation in all_citations
		)
		after = Dict(
			(citation.span.file, citation.span.start_byte) => citation.resolved_author
			for entry in adjudicated.entries for citation in entry_citations(entry)
		)
		@test !isempty(after)
		for (anchor, author) in after
			@test before[anchor] == author
		end
	end


	@testset "ID. distinguishes an antecedent with no author" begin
		directory = mktempdir()
		write(joinpath(directory, "authors.xml"), """<?xml version="1.0" encoding="UTF-8"?>
<xmlittre>
<entree terme="AUTHORS">
<entete><prononciation>x</prononciation><nature>s. m.</nature></entete>
<corps><variante num="1">
<cit ref="Mémoire de Chenier">Premier.</cit>
<cit aut="ID." ref="ib.">Deuxième.</cit>
<cit aut="TEST" ref="III">Troisième.</cit>
<cit aut="ID." ref="ib.">Quatrième.</cit>
</variante></corps>
</entree>
</xmlittre>
""")
		local_documents = read_corpus(directory)
		local_corpus = census(local_documents)
		local_resolved = resolve(build_harness(local_documents, local_corpus))
		citations = entry_citations(only(local_resolved.entries))
		@test [citation.resolution for citation in citations] ==
			[:absent, :antecedent_absent, :printed, :resolved]
		@test isempty(citations[2].resolved_author)
		@test citations[4].resolved_author == "TEST"
		@test all(finding -> finding.category != "author_unresolved", local_resolved.review)
	end

	@testset "an unresolved ID. becomes a review finding" begin
		unresolved = filter(citation -> citation.resolution == :unresolved, all_citations)
		findings = filter(f -> f.category == "author_unresolved", resolved.review)
		@test length(findings) == length(unresolved)
	end
end
