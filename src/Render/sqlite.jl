"""
SQLite is a queryable mirror of the same resolved semantic model and provenance, never
an independent interpretation. `node_type` is null exactly where the semantic type is
underdetermined, so the coarse/derived distinction survives into the database rather
than being flattened into a generic sense.
"""
const schema = """
create table entries (
	entry_id text primary key,
	headword text not null,
	homograph integer,
	file text not null,
	start_byte integer not null,
	end_byte integer not null,
	pronunciation text
);

create table nodes (
	node_id text primary key,
	entry_id text not null references entries(entry_id),
	parent_id text references nodes(node_id),
	origin text not null,
	rubrique_id text,
	rubrique text,
	node_type text,
	position integer not null,
	number text,
	form text,
	separator text,
	definition text,
	file text not null,
	start_byte integer not null,
	end_byte integer not null
);

create table qualifications (
	node_id text references nodes(node_id),
	entry_id text not null references entries(entry_id),
	channel text not null,
	type text not null,
	norm text,
	printed text not null,
	scope text not null,
	scope_file text,
	scope_start_byte integer,
	scope_end_byte integer,
	file text not null,
	start_byte integer not null,
	end_byte integer not null
);

create table constituents (
	node_id text not null references nodes(node_id),
	name text not null,
	text text not null,
	value text,
	file text not null,
	start_byte integer not null,
	end_byte integer not null
);

create table citations (
	citation_id text primary key,
	node_id text references nodes(node_id),
	entry_id text not null references entries(entry_id),
	origin text not null,
	rubrique text,
	subtype text,
	position integer not null,
	not_before integer,
	not_after integer,
	quotation text not null,
	author text,
	resolved_author text,
	resolution text,
	author_antecedent_id text,
	reference text,
	reference_antecedent_id text,
	reference_resolution text,
	file text not null,
	start_byte integer not null,
	end_byte integer not null
);

create table header_notes (
	entry_id text not null references entries(entry_id),
	position integer not null,
	content text not null,
	file text not null,
	start_byte integer not null,
	end_byte integer not null
);

create table rubriques (
	rubrique_id text primary key,
	entry_id text not null references entries(entry_id),
	parent_rubrique_id text references rubriques(rubrique_id),
	name text not null,
	position integer not null,
	content text not null,
	file text not null,
	start_byte integer not null,
	end_byte integer not null
);

create table etymology (
	entry_id text not null references entries(entry_id),
	position integer not null,
	kind text not null,
	cit_type text,
	language text,
	cue_printed text,
	cue_expand text,
	fictif integer,
	forms text,
	gloss text,
	defaulted integer,
	text text,
	target text,
	file text not null,
	start_byte integer not null,
	end_byte integer not null
);

create table content_segments (
	owner_kind text not null,
	owner_id text not null,
	position integer not null,
	kind text not null,
	text text not null,
	target text,
	resolved_entry text,
	resolved_file text,
	resolved_start_byte integer,
	resolved_end_byte integer,
	source_element text,
	editorial_origin text,
	language text,
	file text not null,
	start_byte integer not null,
	end_byte integer not null
);

create table coverage (
	pass text not null,
	pass_version integer not null,
	population text not null,
	population_version integer not null,
	population_size integer not null,
	population_hash text not null,
	examined integer not null,
	positive integer not null,
	negative integer not null,
	unresolved integer not null,
	stale integer not null
);

create table review (
	category text not null,
	detail text not null,
	file text not null,
	start_byte integer not null,
	end_byte integer not null
);

create index nodes_by_entry on nodes(entry_id);
create index nodes_by_anchor on nodes(file, start_byte);
create index qualifications_by_node on qualifications(node_id);
create index citations_by_node on citations(node_id);
create index constituents_by_node on constituents(node_id);
create index content_segments_by_owner on content_segments(owner_kind, owner_id);
create index content_segments_by_target on content_segments(target);
"""

column(::Nothing) = missing
column(value) = value

text_column(::Nothing) = missing
text_column(text::AbstractString) = isempty(text) ? missing : text

anchor_column(::Nothing) = missing
anchor_column(span::RawSpan) = anchor_id(span)

scope_columns(qualification::Resolve.Qualification) = scope_columns(qualification.scope)

scope_columns(scope::Resolve.ContainedScope) =
	(Resolve.scope_name(scope), missing, missing, missing)

scope_columns(scope::Resolve.AssertedScope) = (
	Resolve.scope_name(scope),
	scope.target.file,
	scope.target.start_byte,
	scope.target.end_byte,
)

node_type_column(::Nothing) = missing
node_type_column(value::Adjudication.NodeType) = Adjudication.node_type_name(value)

# unresolved stays null rather than guessing, as when the TEI renderer declines @target
resolved_columns(::Nothing) = (missing, missing, missing, missing)

resolved_columns(span::RawSpan) =
	(anchor_id(span), span.file, span.start_byte, span.end_byte)

struct SqliteWriter
	database::SQLite.DB
	prepared::Dict{String, SQLite.Stmt}
end

function insert_row!(
	writer::SqliteWriter, statement::AbstractString, values::Tuple,
)
	prepare() = DBInterface.prepare(writer.database, statement)
	return DBInterface.execute(get!(prepare, writer.prepared, statement), values)
end


# ===== inline content =====

segment_kind(::Resolve.CrossReference) = "cross_reference"
segment_kind(::Resolve.Emphasis) = "emphasis"
segment_kind(::Resolve.TextRun) = "text"

segment_columns(item::Resolve.CrossReference) = (
	item.target, resolved_columns(item.resolved)..., missing, missing, missing,
)

segment_columns(item::Resolve.Emphasis) = (
	missing,
	resolved_columns(nothing)...,
	item.source_element,
	item.source_element == "exemple" ? "gannaz" : missing,
	column(item.language),
)

segment_columns(::Resolve.TextRun) = (
	missing, resolved_columns(nothing)..., missing, missing, missing,
)

"""
    insert_segments!(writer, owner_kind, owner_id, items)

The ordered inline pieces of a definition, a rubrique's prose, or a citation's
quotation, each with its own anchor. The flattened text column beside it stays for
reading and search; this is where the structure the resolver recovered remains queryable
— a cross-reference keeps its target, a source wrapper keeps which element it was and
what language it declared.
"""
function insert_segments!(
	writer,
	owner_kind::AbstractString,
	owner_id::AbstractString,
	items::Vector{Resolve.Inline},
	offset::Int = 0,
)::Int
	for (index, item) in enumerate(items)
		insert_row!(
			writer,
			"insert into content_segments values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
			(
				owner_kind, owner_id, offset + index,
				segment_kind(item), Resolve.inline_text(item),
				segment_columns(item)...,
				item.span.file, item.span.start_byte, item.span.end_byte,
			),
		)
	end
	return offset + length(items)
end


# ===== qualifications and citations =====

function insert_qualification!(
	writer, qualification::Resolve.Qualification, entry_id::AbstractString, node_id,
)
	insert_row!(
		writer,
		"insert into qualifications values (?,?,?,?,?,?,?,?,?,?,?,?,?)",
		(
			node_id, entry_id, String(qualification.channel), qualification.type,
			text_column(qualification.norm), qualification.printed,
			scope_columns(qualification)...,
			qualification.span.file,
			qualification.span.start_byte,
			qualification.span.end_byte,
		),
	)
	return nothing
end

function insert_citation!(
	writer,
	citation::Resolve.Citation,
	entry::Resolve.ResolvedEntry,
	position::Int;
	node_id = missing,
	origin::AbstractString,
	rubrique = missing,
	subtype = missing,
	not_before = missing,
	not_after = missing,
)
	citation_id = anchor_id(citation.span)
	insert_row!(
		writer,
		"insert into citations values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
		(
			citation_id, node_id, entry.entry_id, origin,
			rubrique, subtype, position, not_before, not_after,
			Resolve.plain_text(citation.quotation),
			text_column(citation.author),
			text_column(citation.resolved_author),
			String(citation.resolution),
			anchor_column(citation.author_antecedent),
			text_column(citation.reference),
			anchor_column(citation.reference_antecedent),
			String(citation.reference_resolution),
			citation.span.file, citation.span.start_byte, citation.span.end_byte,
		),
	)
	insert_segments!(writer, "citation", citation_id, citation.quotation)
	return nothing
end


# ===== nodes =====

function insert_constituent!(writer, node_id::AbstractString, constituent)
	insert_row!(
		writer,
		"insert into constituents values (?,?,?,?,?,?,?)",
		(
			node_id, constituent.name, constituent.text, column(constituent.value),
			constituent.span.file,
			constituent.span.start_byte,
			constituent.span.end_byte,
		),
	)
	return nothing
end

function insert_node!(
	writer,
	entry::Resolve.ResolvedEntry,
	node::Resolve.ResolvedNode,
	parent::Union{Nothing, String},
	position::Int;
	origin::AbstractString = "entry",
	rubrique_id = nothing,
	rubrique = nothing,
	citation_subtype = nothing,
)
	insert_row!(
		writer,
		"insert into nodes values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
		(
			node.node_id, entry.entry_id, column(parent), origin,
			column(rubrique_id), column(rubrique),
			node_type_column(node.node_type), position,
			column(node.number), column(node.form), column(node.separator),
			Resolve.plain_text(node.definition),
			node.span.file, node.span.start_byte, node.span.end_byte,
		),
	)
	insert_segments!(writer, "node", node.node_id, node.definition)
	for constituent in node.constituents
		insert_constituent!(writer, node.node_id, constituent)
	end
	for qualification in node.qualifications
		insert_qualification!(writer, qualification, entry.entry_id, node.node_id)
	end
	from_rubrique = origin == "rubrique"
	for (index, citation) in enumerate(node.citations)
		insert_citation!(
			writer, citation, entry, index;
			node_id = node.node_id,
			origin = from_rubrique ? "rubrique" : "sense",
			rubrique = from_rubrique ? column(rubrique) : missing,
			subtype = column(citation_subtype),
		)
	end
	for (index, child) in enumerate(node.children)
		insert_node!(
			writer, entry, child, node.node_id, index;
			origin, rubrique_id, rubrique, citation_subtype,
		)
	end
	return nothing
end


# ===== etymology =====

etymology_row(segment::Resolve.EtymCit) = (
	"cit", String(segment.cit_type),
	text_column(segment.language),
	isnothing(segment.cue) ?
		missing : string(segment.cue.printed, segment.cue.trailing),
	isnothing(segment.cue) ? missing : text_column(segment.cue.expand),
	segment.fictif ? 1 : 0, join(segment.forms, "|"),
	text_column(segment.gloss),
	segment.defaulted ? 1 : 0, missing, missing,
)

etymology_row(segment::Resolve.EtymComponent) = (
	"component", missing, text_column(segment.language),
	missing, missing, missing, join(segment.forms, "|"),
	missing, missing, missing, missing,
)

etymology_row(segment::Resolve.EtymLiteral) = (
	"literal", missing, missing, missing, missing, missing, missing, missing, missing,
	segment.printed, missing,
)

etymology_row(segment::Resolve.EtymConnector) = (
	"connector", missing, missing, missing, missing, missing, missing, missing, missing,
	segment.printed, missing,
)

etymology_row(segment::Resolve.EtymSuspect) = (
	"suspect", missing, missing, missing, missing, missing, missing, missing, missing,
	segment.token, missing,
)

etymology_row(segment::Resolve.EtymProse) = (
	"prose", missing, missing, missing, missing, missing, missing, missing, missing,
	segment.text, missing,
)

etymology_row(segment::Resolve.EtymCrossReference) = (
	"cross_reference", missing, missing,
	text_column(segment.label),
	missing, missing, missing, missing, missing, segment.printed, segment.target,
)

function insert_etymology!(writer, entry, anchored, position::Int)
	insert_row!(
		writer,
		"insert into etymology values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
		(
			entry.entry_id, position, etymology_row(anchored.segment)...,
			anchored.span.file, anchored.span.start_byte, anchored.span.end_byte,
		),
	)
	return nothing
end


# ===== rubriques =====

rubrique_node_text(node::Resolve.ResolvedNode)::String = join(
	filter(!isempty, String[
		[Resolve.form_value(form) for form in node.forms]...,
		Resolve.plain_text(node.definition),
		[Resolve.plain_text(citation.quotation) for citation in node.citations]...,
	]),
	" ",
)

rubrique_item_text(item::Resolve.RubriqueProse)::String =
	Resolve.plain_text(item.content)
rubrique_item_text(item::Resolve.RubriqueLabel)::String = item.text
rubrique_item_text(item::Resolve.RubriqueNode)::String = rubrique_node_text(item.node)
rubrique_item_text(item::Resolve.RubriqueCitation)::String =
	Resolve.plain_text(item.citation.quotation)

rubrique_text(rubrique::Resolve.ResolvedRubrique)::String =
	join((rubrique_item_text(item) for item in rubrique.items), "\n")

function insert_rubrique!(
	writer, entry, rubrique, position::Int, parent_rubrique_id,
)
	rubrique_id = anchor_id(rubrique.span)
	insert_row!(
		writer,
		"insert into rubriques values (?,?,?,?,?,?,?,?,?)",
		(
			rubrique_id, entry.entry_id, parent_rubrique_id,
			rubrique.name, position, rubrique_text(rubrique),
			rubrique.span.file, rubrique.span.start_byte, rubrique.span.end_byte,
		),
	)
	offset = 0
	for item in rubrique.items
		item isa Resolve.RubriqueProse || continue
		offset = insert_segments!(writer, "rubrique", rubrique_id, item.content, offset)
	end
	return nothing
end


# ===== one entry =====

function insert_header_notes!(writer, entry)
	for (index, note) in enumerate(entry.header)
		insert_row!(
			writer,
			"insert into header_notes values (?,?,?,?,?,?)",
			(
				entry.entry_id, index, Resolve.plain_text(note.content),
				note.span.file, note.span.start_byte, note.span.end_byte,
			),
		)
	end
	return nothing
end

function insert_rubrique_nodes!(writer, entry)
	for rubrique in entry.rubriques
		subtype = Resolve.conventions_for(rubrique.name).subtype
		for (index, item) in enumerate(rubrique.items)
			item isa Resolve.RubriqueNode || continue
			insert_node!(
				writer, entry, item.node, nothing, index;
				origin = "rubrique",
				rubrique_id = anchor_id(rubrique.span),
				rubrique = rubrique.name,
				citation_subtype = subtype,
			)
		end
	end
	return nothing
end

function insert_entry_etymology!(writer, entry)
	position = 0
	for rubrique in entry.rubriques, anchored in rubrique.etymology
		position += 1
		insert_etymology!(writer, entry, anchored, position)
	end
	return nothing
end

function insert_rubrique_citations!(writer, entry)
	for rubrique in entry.rubriques
		for (index, item) in enumerate(rubrique.items)
			item isa Resolve.RubriqueCitation || continue
			insert_citation!(
				writer, item.citation, entry, index;
				origin = "rubrique",
				rubrique = rubrique.name,
				subtype = item.subtype,
				not_before = column(item.not_before),
				not_after = column(item.not_after),
			)
		end
	end
	return nothing
end

function insert_entry_rubriques!(writer, entry)
	rubrique_ids = Set(anchor_id(rubrique.span) for rubrique in entry.rubriques)
	ordered = sort(entry.rubriques; by = rubrique -> rubrique.span.start_byte)
	for (index, rubrique) in enumerate(ordered)
		nested = !isnothing(rubrique.parent_id) && rubrique.parent_id in rubrique_ids
		insert_rubrique!(
			writer, entry, rubrique, index, nested ? rubrique.parent_id : missing,
		)
	end
	return nothing
end

function insert_entry!(writer, entry::Resolve.ResolvedEntry)
	insert_row!(
		writer,
		"insert into entries values (?,?,?,?,?,?,?)",
		(
			entry.entry_id, entry.headword, column(entry.homograph),
			entry.span.file, entry.span.start_byte, entry.span.end_byte,
			column(entry.pronunciation),
		),
	)
	for qualification in entry.grammar
		insert_qualification!(writer, qualification, entry.entry_id, missing)
	end
	insert_header_notes!(writer, entry)
	for (index, node) in enumerate(entry.nodes)
		insert_node!(writer, entry, node, nothing, index)
	end
	insert_rubrique_nodes!(writer, entry)
	insert_entry_etymology!(writer, entry)
	insert_rubrique_citations!(writer, entry)
	insert_entry_rubriques!(writer, entry)
	return nothing
end

# ===== the database =====

function insert_coverage!(writer, coverage)
	for record in coverage
		insert_row!(
			writer,
			"insert into coverage values (?,?,?,?,?,?,?,?,?,?,?)",
			(
				record.pass, record.pass_version, record.population,
				record.population_version, record.population_size,
				record.population_hash, record.examined,
				record.positive, record.negative, record.unresolved, record.stale,
			),
		)
	end
	return nothing
end

function insert_review!(writer, review)
	for finding in review
		insert_row!(
			writer,
			"insert into review values (?,?,?,?,?)",
			(
				finding.category, finding.detail,
				finding.span.file, finding.span.start_byte, finding.span.end_byte,
			),
		)
	end
	return nothing
end

function create_schema(database::SQLite.DB)
	for statement in filter(!isempty, strip.(split(schema, ";")))
		DBInterface.execute(database, statement)
	end
	return nothing
end

function render_sqlite(
	corpus::Resolve.ResolvedCorpus, path::AbstractString; progress = nothing,
)
	isfile(path) && rm(path)
	database = SQLite.DB(path)
	create_schema(database)
	writer = SqliteWriter(database, Dict{String, SQLite.Stmt}())

	total_entries = length(corpus.entries)
	report_step = max(cld(total_entries, 20), 1)
	started = time_ns()
	SQLite.transaction(database) do
		for (entry_index, entry) in enumerate(corpus.entries)
			insert_entry!(writer, entry)
			due = entry_index % report_step == 0 || entry_index == total_entries
			if !isnothing(progress) && due
				elapsed = (time_ns() - started) / 1e9
				progress(entry_index, total_entries, entry.span.file, elapsed)
			end
		end
		insert_coverage!(writer, corpus.coverage)
		insert_review!(writer, corpus.review)
	end
	close(database)
	return path
end
