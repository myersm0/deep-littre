using DeepLittre.Source: read_corpus, slice, covers, crosses
using DeepLittre.Census: census, all_blocks, all_entries, counts, anomalies, population_hash,
	kind_name, Indent, Variante, ResumeIndent, ResumeVariante, RubriqueIndent, RubriqueVariante,
	RubriqueDirect, EnteteNature

@testset "source block census" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	entries = all_entries(corpus)
	blocks = all_blocks(corpus)
	tally = counts(corpus)

	@testset "development corpus shape" begin
		@test length(entries) == 25
		@test isempty(anomalies(corpus))
		@test tally["indent"] == 181
		@test tally["variante"] == 170
		@test tally["resume_indent"] == 0
		@test tally["resume_variante"] == 69
		@test tally["rubrique_indent"] == 105
		@test tally["rubrique_variante"] == 3
		@test tally["rubrique_direct"] == 5
		@test tally["entete_nature"] == 25
		@test length(blocks) == sum(values(tally))
	end

	@testset "pronunciation is not a census block" begin
		for document in documents
			@test occursin("<prononciation>", document.parser_view)
		end
		@test !any(block -> kind_name(block.kind) == "prononciation", blocks)
	end

	@testset "inline nature is markup, not a block" begin
		natures = count(block -> block.kind isa EnteteNature, blocks)
		@test natures == 25
		for block in blocks
			block.kind isa EnteteNature || continue
			@test occursin("<nature>", slice(source_of(documents, block).raw_text, block.raw_span))
		end
	end

	@testset "résumé variantes are counted but distinguished" begin
		resumes = filter(block -> block.kind isa ResumeVariante, blocks)
		@test length(resumes) == 69
		for block in resumes
			@test occursin("option=\"résumé\"", slice(source_of(documents, block).raw_text, block.raw_span))
		end
	end

	@testset "block spans cover their children" begin
		for entry in entries
			for block in DeepLittre.Census.all_blocks(entry)
				for child in block.children
					@test covers(block.raw_span, child.raw_span)
					@test child.parent_id == block.source_id
				end
			end
		end
	end

	@testset "sibling blocks never cross" begin
		for entry in entries
			spans = [block.raw_span for block in DeepLittre.Census.all_blocks(entry)]
			for outer in eachindex(spans), inner in (outer + 1):lastindex(spans)
				@test !crosses(spans[outer], spans[inner])
			end
		end
	end

	@testset "blocks sit inside their entry" begin
		for entry in entries
			for block in DeepLittre.Census.all_blocks(entry)
				@test covers(entry.raw_span, block.raw_span)
				@test block.entry_id == entry.source_id
			end
		end
	end

	@testset "source ids are unique and deterministic" begin
		ids = [block.source_id for block in blocks]
		@test length(unique(ids)) == length(ids)
		@test population_hash(blocks) == population_hash(all_blocks(census(read_corpus(corpus_source))))
	end

	@testset "population hash tracks the denominator" begin
		@test population_hash(blocks) != population_hash(blocks[1:(end - 1)])
		@test population_hash(blocks) != population_hash(reverse(blocks))
	end

	@testset "rubrique blocks are addressable" begin
		rubriques = reduce(vcat, (entry.rubriques for entry in entries); init = [])
		@test !isempty(rubriques)
		for rubrique in rubriques
			for block in rubrique.blocks
				@test block.kind isa RubriqueIndent || block.kind isa RubriqueVariante ||
					block.kind isa RubriqueDirect
				@test covers(rubrique.raw_span, block.raw_span)
			end
		end
	end

	@testset "direct rubrique content is a census block" begin
		messager = only(filter(entry -> entry.headword == "MESSAGER, ÈRE", entries))
		proverb = only(filter(rubrique -> rubrique.name == "PROVERBE", messager.rubriques))
		direct = only(filter(block -> block.kind isa RubriqueDirect, proverb.blocks))
		@test direct.raw_span == proverb.raw_span
		@test direct.view_span == proverb.view_span
		@test direct.parent_id == proverb.source_id
		@test direct.source_id != proverb.source_id
	end

	# The full corpus contains three <indent> elements directly inside <résumé> (FAIRE, LAISSER,
	# PRENDRE). Résumé ancestry was consulted only on the <variante> branch, so those three were
	# admitted to the structural population as ordinary indents. PRENDRE's carries a <semantique>
	# marker and so looks entirely sense-like; only its ancestry distinguishes it.
	@testset "résumé ancestry is consulted for indents as well as variantes" begin
		directory = mktempdir()
		cp(joinpath(fixture_root, "synthetic", "resume_indent.xml"), joinpath(directory, "p.xml"))
		fixture = census(read_corpus(directory))
		tally = counts(fixture)
		@test tally["resume_indent"] == 1
		@test tally["resume_variante"] == 1
		@test tally["indent"] == 1
		@test tally["variante"] == 1
		resume = only(filter(block -> block.kind isa ResumeIndent, all_blocks(fixture)))
		@test occursin("Faire impression", String(slice(
			only(read_corpus(directory)).raw_text, resume.raw_span,
		)))
	end
end
