using DeepLittre.Source: read_corpus, slice, covers
using DeepLittre.Census: census
using DeepLittre.Adjudication: Harness, Store
using DeepLittre.Resolve: resolve, segment_etymology, EtymCit, EtymComponent, EtymLiteral,
	EtymConnector, EtymProse, EtymSuspect, EtymCrossReference, EtymSegment, etym_language_table

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

	@testset "compound constituents, regional scope, and punctuation remain distinct" begin
		segments = segment_etymology(
			"<i>À</i> et <i>couple</i> ; Berry, <i>accoubler</i>.";
			headword = "ACCOUPLER",
		)
		components = filter(segment -> segment isa EtymComponent, segments)
		@test length(components) == 2
		@test [only(component.forms) for component in components] == ["À", "couple"]
		@test all(component -> component.italic, components)
		connectors = [segment.printed for segment in segments if segment isa EtymConnector]
		@test connectors == ["et"]

		cognates = filter(segment -> segment isa EtymCit, segments)
		@test length(cognates) == 1
		berry = only(cognates)
		@test berry.cit_type == :cognate
		@test berry.language == "fr-x-berrich"
		@test berry.cue.printed == "Berry"
		@test berry.cue.trailing == ","
		@test berry.forms == ["accoubler"]
		@test berry.italic

		literals = [segment.printed for segment in segments if segment isa EtymLiteral]
		@test literals == [";", "."]

		io = IOBuffer()
		names = DeepLittre.Render.Names(
			Dict{DeepLittre.Source.RawSpan, String}(),
			Dict{DeepLittre.Source.RawSpan, DeepLittre.Render.NodeNames}(),
			Dict{DeepLittre.Source.RawSpan, String}(),
		)
		for segment in segments
			DeepLittre.Render.render_etym_segment(io, segment, names)
		end
		rendered = String(take!(io))
		@test occursin(
			"<cit type=\"etymon\" xml:lang=\"fr\"><form><orth rend=\"italic\">À</orth></form></cit> et <cit type=\"etymon\" xml:lang=\"fr\"><form><orth rend=\"italic\">couple</orth></form></cit> <pc>;</pc> ",
			rendered,
		)
		@test occursin(
			"<cit type=\"cognate\" xml:lang=\"fr-x-berrich\"><lang expand=\"berrichon\" norm=\"fr-x-berrich\">Berry</lang><pc>,</pc><form><orth rend=\"italic\">accoubler</orth></form></cit><pc>.</pc>",
			rendered,
		)
		@test !occursin("type=\"component\"", rendered)
	end

	@testset "a lang attribute wins over the preceding cue" begin
		segments = segment_etymology("ital. <i lang=\"it\">angoscia</i>")
		cit = first(filter(segment -> segment isa EtymCit, segments))
		@test cit.language == "it"
	end


	@testset "language lookup normalizes article and terminal dot variants" begin
		cases = [
			("l'allem. <i>Form</i>", "de", "l'allem."),
			("L'ital. <i>forma</i>", "it", "L'ital."),
			("ital <i>forma</i>", "it", "ital"),
			("lat <i>forma</i>", "la", "lat"),
			("l'anglo-sax. <i>form</i>", "ang", "l'anglo-sax."),
			("espag. <i>forma</i>", "es", "espag."),
		]
		for (text, language, printed) in cases
			segments = segment_etymology(text)
			cit = only(filter(segment -> segment isa EtymCit, segments))
			@test cit.language == language
			@test cit.cue.printed == printed
			@test isempty(filter(segment -> segment isa EtymSuspect, segments))
		end
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
		@test only(segments).fallback == :unrecognized_markup
	end

	@testset "the fallback records why it fired" begin
		unmarked = segment_etymology("Provenç libertat ; du latin libertatem, de liber, libre.")
		@test only(unmarked) isa EtymProse
		@test only(unmarked).fallback == :no_events

		segmented = segment_etymology("du latin <i lang=\"la\">angustia</i>, resserrement")
		prose = filter(segment -> segment isa EtymProse, segmented)
		@test all(segment -> segment.fallback == :none, prose)
	end

	@testset "an unsegmented etymology becomes a review finding" begin
		unsegmented = filter(
			finding -> finding.category == "etymology_unsegmented", resolved.review,
		)
		marked = [
			anchored for entry in resolved.entries for rubrique in entry.rubriques
			for anchored in rubrique.etymology
			if anchored.segment isa EtymProse && anchored.segment.fallback != :none
		]
		@test length(unsegmented) == length(marked)
		@test !isempty(unsegmented)
		@test all(finding -> finding.detail in ("no_events", "unrecognized_markup"), unsegmented)

		liberte = etymology_of("LIBERTÉ")
		@test all(anchored -> anchored.segment isa EtymProse, liberte.etymology)
		@test only(liberte.etymology).segment.fallback == :no_events
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
