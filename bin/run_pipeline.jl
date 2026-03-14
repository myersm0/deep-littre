#!/usr/bin/env julia

using DeepLittre

function main()
	if length(ARGS) < 2
		println(stderr, "Usage: julia run_pipeline.jl <source_dir> <output_dir> [--patches PATH] [--verdicts PATH]")
		exit(1)
	end

	source_dir = ARGS[1]
	output_dir = ARGS[2]

	patches_path = nothing
	verdicts_path = nothing
	i = 3
	while i <= length(ARGS)
		if ARGS[i] == "--patches" && i < length(ARGS)
			patches_path = ARGS[i + 1]
			i += 2
		elseif ARGS[i] == "--verdicts" && i < length(ARGS)
			verdicts_path = ARGS[i + 1]
			i += 2
		else
			println(stderr, "Unknown argument: $(ARGS[i])")
			exit(1)
		end
	end

	mkpath(output_dir)

	@info "Phase 1: Parse"
	entries = parse_all(source_dir; patches_path)

	@info "Phases 2–4: Enrich"
	enrich!(entries; verdicts_path)

	@info "Phase 5: Scope transitions"
	scope_all!(entries)

	tei_path = joinpath(output_dir, "littre.tei.xml")
	@info "Emit TEI → $tei_path"
	emit_tei(entries, tei_path)

	sqlite_path = joinpath(output_dir, "littre.db")
	@info "Emit SQLite → $sqlite_path"
	emit_sqlite(entries, sqlite_path)

	@info "Done."
end

main()

