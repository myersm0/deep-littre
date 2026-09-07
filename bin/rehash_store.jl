# recompute surface_sha256 for every record in a store, leaving all other fields alone
# use only when the classification surface changed and the projection did not

using DeepLittre.Source: read_corpus
using DeepLittre.Census: census
using DeepLittre.Adjudication: Harness, Store, ExaminationRecord, current_passes,
	read_pass, write_pass!, present, surface_sha256, anchor_key

function rehash(harness::Harness, pass, record::ExaminationRecord)::ExaminationRecord
	block = harness.blocks[anchor_key(record.source)]
	return ExaminationRecord(
		record.record_id,
		record.pass,
		record.pass_version,
		record.source,
		surface_sha256(present(harness, pass, block)),
		record.outcome,
		record.assertions,
		record.scopes,
		record.residuals,
		record.decision_procedure,
		record.decision_reference,
		record.created,
		record.notes,
	)
end

function rehash_store(source_directory::AbstractString, store_directory::AbstractString)
	documents = read_corpus(source_directory)
	harness = Harness(documents, census(documents), Store(store_directory))
	for pass in current_passes
		records = read_pass(harness.store, pass.pass)
		isempty(records) && continue
		write_pass!(harness.store, pass.pass, [rehash(harness, pass, r) for r in records])
		println("$(pass.pass): $(length(records)) records rewritten")
	end
	return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
	rehash_store(ARGS[1], ARGS[2])
end
