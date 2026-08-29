using DeepLittre.Source: read_corpus, slice, covers
using DeepLittre.Census: census
using DeepLittre.Adjudication: Harness, Store
using DeepLittre.Resolve: resolve, segment_etymology, EtymCit, EtymConnector, EtymProse,
	EtymSuspect, EtymCrossReference, EtymSegment, etym_language_table

@testset "etymology" begin
	documents = read_corpus(corpus_source)
	corpus = census(documents)
	resolved = resolve(build_harness(documents, corpus))

	entry_named(headword) = first(filter(e -> e.headword == headword, resolved.entries))
	etymology_of(headword) = first(filter(r -> r.name == "ÉTYMOLOGIE", entry_named(headword).rubriques))

	@testset "cues resolve against the committed table" begin
		segments = segment_etymology(
			"<i>angouche</i>; provenç. <i>angoissa</i>; du latin <i>angustia</i>",
		)
		cits = filter(segment -> segment isa EtymCit, segments)
		@test length(cits) >= 3

		provencal = first(filter(cit -> cit.language == "pro", cits))
		@test provencal.cue.printed == "provenç."
		@test provencal.cue.expand == "provençal"
		@test provencal.forms == ["angoissa"]
		@test provencal.cit_type == :cognate

		latin = first(filter(cit -> cit.language == "la", cits))
		@test latin.cit_type == :etymon
		@test latin.forms == ["angustia"]
	end

	@testset "a lang attribute wins over the preceding cue" begin
		segments = segment_etymology("ital. <i lang=\"it\">angoscia</i>")
		cit = first(filter(segment -> segment isa EtymCit, segments))
		@test cit.language == "it"
	end

	@testset "non-language abbreviations do not become cues" begin
		for token in ("s. m.", "plur.", "voy.")
			segments = segment_etymology("$(token) <i>forme</i>")
			cits = filter(segment -> segment isa EtymCit, segments)
			@test all(cit -> cit.cue === nothing || cit.cue.printed != token, cits)
		end
	end

	@testset "content with unrecognized markup falls back to prose" begin
		segments = segment_etymology("Voy. <b>autre</b> chose <i>forma</i>")
		@test length(segments) == 1
		@test only(segments) isa EtymProse
		@test !occursin('<', only(segments).text)
	end

	@testset "empty content yields no segments" begin
		@test isempty(segment_etymology(""))
		@test isempty(segment_etymology("   "))
	end

	@testset "a labelled anchor becomes a cross-reference" begin
		chever = etymology_of("CHEVER")
		reference = only(filter(a -> a.segment isa EtymCrossReference, chever.etymology)).segment
		@test reference.label == "voy."
		@test reference.target == "caver"
		@test reference.printed == "ce mot"
	end

	@testset "segments anchor back into raw source" begin
		document = first(filter(d -> d.file == "a.xml", documents))
		angoisse = etymology_of("ANGOISSE")
		@test !isempty(angoisse.etymology)
		for anchored in angoisse.etymology
			@test covers(angoisse.span, anchored.span)
			anchored.segment isa EtymCit || continue
			isempty(anchored.segment.forms) && continue
			text = String(slice(document.raw_text, anchored.span))
			@test occursin(first(anchored.segment.forms), text)
		end
	end

	@testset "the whole corpus segments without markup leaking through" begin
		cits = 0
		for entry in resolved.entries, rubrique in entry.rubriques
			rubrique.name == "ÉTYMOLOGIE" || continue
			for anchored in rubrique.etymology
				segment = anchored.segment
				if segment isa EtymCit
					cits += 1
					@test all(form -> !occursin('<', form), segment.forms)
					@test !occursin('<', segment.gloss)
				elseif segment isa EtymProse
					@test !occursin('<', segment.text)
				end
			end
		end
		@test cits >= 30
	end

	@testset "suspect tokens become review findings, not stored judgments" begin
		segments = segment_etymology("du bas-lat. <i>forma</i>, et zz. <i>autre</i>")
		suspects = filter(segment -> segment isa EtymSuspect, segments)
		@test length(suspects) == 1
		@test only(suspects).token == "zz."

		@test all(finding -> finding.category != "etymology_suspect", resolved.review) ||
			any(finding -> finding.category == "etymology_suspect", resolved.review)
	end
end
