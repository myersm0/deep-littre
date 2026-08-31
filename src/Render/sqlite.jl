"""
SQLite is a queryable mirror of the same resolved semantic model and provenance, never an
independent interpretation. `node_type` is null exactly where the semantic type is
underdetermined, so the coarse/derived distinction survives into the database rather than being
flattened into a generic sense.
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

scope_columns(qualification::Resolve.Qualification) =
	qualification.scope isa Resolve.AssertedScope ?
		(
			Resolve.scope_name(qualification.scope),
			qualification.scope.target.file,
			qualification.scope.target.start_byte,
			qualification.scope.target.end_byte,
		) :
		(Resolve.scope_name(qualification.scope), missing, missing, missing)

node_type_column(::Nothing) = missing
node_type_column(value::Adjudication.NodeType) = Adjudication.node_type_name(value)

# A cross-reference keeps what the source printed and, where the resolver could establish it, the
# anchor it names. Unresolved stays null rather than guessing, which is the same contract the TEI
# renderer applies when it declines to emit @target.
resolved_columns(::Nothing) = (missing, missing, missing, missing)
resolved_columns(span::RawSpan) =
	(anchor_id(span), span.file, span.start_byte, span.end_byte)

struct SqliteWriter
	database::SQLite.DB
	prepared::Dict{String, SQLite.Stmt}
end

insert_row!(writer::SqliteWriter, statement::AbstractString, values::Tuple) = DBInterface.execute(
	get!(() -> DBInterface.prepare(writer.database, statement), writer.prepared, statement), values,
)

"""
	insert_segments!(writer, owner_kind, owner_id, items)

The ordered inline pieces of a definition, a rubrique's prose, or a citation's quotation, each with
its own anchor. The flattened text column beside it stays for reading and search; this is where the
structure the resolver recovered remains queryable — a cross-reference keeps its target, a source
wrapper keeps which element it was and what language it declared.
"""
function insert_segments!(
	writer, owner_kind::AbstractString, owner_id::AbstractString,
	items::Vector{Resolve.Inline}, offset::Int = 0,
)::Int
	for (index, item) in enumerate(items)
		(kind, target, source_element, editorial_origin, language) = if item isa Resolve.CrossReference
			("cross_reference", item.target, missing, missing, missing)
		elseif item isa Resolve.Emphasis
			("emphasis", missing, item.source_element,
				item.source_element == "exemple" ? "gannaz" : missing,
				item.language === nothing ? missing : item.language)
		else
			("text", missing, missing, missing, missing)
		end
		resolved = item isa Resolve.CrossReference ? item.resolved : nothing
		insert_row!(
			writer,
			"insert into content_segments values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
			(
				owner_kind, owner_id, offset + index, kind, Resolve.inline_text(item),
				target, resolved_columns(resolved)..., source_element, editorial_origin, language,
				item.span.file, item.span.start_byte, item.span.end_byte,
			),
		)
	end
	offset + length(items)
end

function insert_node!(
	writer, entry::Resolve.ResolvedEntry, node::Resolve.ResolvedNode,
	parent::Union{Nothing, String}, position::Int; origin::AbstractString = "entry",
	rubrique_id = nothing, rubrique = nothing, citation_subtype = nothing,
)
	insert_row!(
		writer,
		"insert into nodes values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
		(
			node.node_id, entry.entry_id, parent === nothing ? missing : parent, origin,
			rubrique_id === nothing ? missing : rubrique_id,
			rubrique === nothing ? missing : rubrique,
			node_type_column(node.node_type), position,
			node.number === nothing ? missing : node.number,
			node.form === nothing ? missing : node.form,
			node.separator === nothing ? missing : node.separator,
			Resolve.plain_text(node.definition),
			node.span.file, node.span.start_byte, node.span.end_byte,
		),
	)
	insert_segments!(writer, "node", node.node_id, node.definition)
	for constituent in node.constituents
		insert_row!(
			writer,
			"insert into constituents values (?,?,?,?,?,?,?)",
			(
				node.node_id, constituent.name, constituent.text,
				constituent.value === nothing ? missing : constituent.value,
				constituent.span.file, constituent.span.start_byte, constituent.span.end_byte,
			),
		)
	end
	for qualification in node.qualifications
		insert_row!(
			writer,
			"insert into qualifications values (?,?,?,?,?,?,?,?,?,?,?,?,?)",
			(
				node.node_id, entry.entry_id, String(qualification.channel), qualification.type,
				isempty(qualification.norm) ? missing : qualification.norm, qualification.printed,
				scope_columns(qualification)...,
				qualification.span.file, qualification.span.start_byte, qualification.span.end_byte,
			),
		)
	end
	for (index, citation) in enumerate(node.citations)
		citation_origin = origin == "rubrique" ? "rubrique" : "sense"
		citation_rubrique = origin == "rubrique" ? rubrique : missing
		citation_subtype_value = citation_subtype === nothing ? missing : citation_subtype
		insert_row!(
			writer,
			"insert into citations values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
			(
				anchor_id(citation.span), node.node_id, entry.entry_id, citation_origin,
				citation_rubrique, citation_subtype_value, index, missing, missing,
				Resolve.plain_text(citation.quotation),
				isempty(citation.author) ? missing : citation.author,
				isempty(citation.resolved_author) ? missing : citation.resolved_author,
				String(citation.resolution),
				citation.author_antecedent === nothing ? missing : anchor_id(citation.author_antecedent),
				isempty(citation.reference) ? missing : citation.reference,
				citation.reference_antecedent === nothing ? missing :
					anchor_id(citation.reference_antecedent),
				String(citation.reference_resolution),
				citation.span.file, citation.span.start_byte, citation.span.end_byte,
			),
		)
		insert_segments!(writer, "citation", anchor_id(citation.span), citation.quotation)
	end
	for (index, child) in enumerate(node.children)
		insert_node!(
			writer, entry, child, node.node_id, index; origin, rubrique_id, rubrique, citation_subtype,
		)
	end
	nothing
end

etymology_row(segment::Resolve.EtymCit) = (
	"cit", String(segment.cit_type),
	isempty(segment.language) ? missing : segment.language,
	segment.cue === nothing ? missing : string(segment.cue.printed, segment.cue.trailing),
	segment.cue === nothing || isempty(segment.cue.expand) ? missing : segment.cue.expand,
	segment.fictif ? 1 : 0, join(segment.forms, "|"),
	isempty(segment.gloss) ? missing : segment.gloss,
	segment.defaulted ? 1 : 0, missing, missing,
)


etymology_row(segment::Resolve.EtymComponent) = (
	"component", missing,
	isempty(segment.language) ? missing : segment.language,
	missing, missing, missing, join(segment.forms, "|"), missing, missing, missing, missing,
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
	isempty(segment.label) ? missing : segment.label,
	missing, missing, missing, missing, missing, segment.printed, segment.target,
)

function insert_etymology!(writer, entry, anchored, position::Int)
	insert_row!(
		writer,
		"insert into etymology values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
		(entry.entry_id, position, etymology_row(anchored.segment)...,
			anchored.span.file, anchored.span.start_byte, anchored.span.end_byte),
	)
	nothing
end

rubrique_node_text(node::Resolve.ResolvedNode)::String = join(
	filter(!isempty, String[
		[Resolve.form_value(form) for form in node.forms]...,
		Resolve.plain_text(node.definition),
		[Resolve.plain_text(citation.quotation) for citation in node.citations]...,
	]),
	" ",
)

rubrique_text(rubrique::Resolve.ResolvedRubrique)::String = join(
	(
		item isa Resolve.RubriqueProse ? Resolve.plain_text(item.content) :
			item isa Resolve.RubriqueLabel ? item.text :
			item isa Resolve.RubriqueNode ? rubrique_node_text(item.node) :
			Resolve.plain_text(item.citation.quotation)
		for item in rubrique.items
	),
	"\n",
)

function insert_rubrique_citation!(writer, entry, rubrique, item, position::Int)
	citation = item.citation
	insert_row!(
		writer,
		"insert into citations values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
		(
			anchor_id(citation.span), missing, entry.entry_id, "rubrique", rubrique.name, item.subtype,
			position,
			item.not_before === nothing ? missing : item.not_before,
			item.not_after === nothing ? missing : item.not_after,
			Resolve.plain_text(citation.quotation),
			isempty(citation.author) ? missing : citation.author,
			isempty(citation.resolved_author) ? missing : citation.resolved_author,
			String(citation.resolution),
			citation.author_antecedent === nothing ? missing : anchor_id(citation.author_antecedent),
			isempty(citation.reference) ? missing : citation.reference,
			citation.reference_antecedent === nothing ? missing :
				anchor_id(citation.reference_antecedent),
			String(citation.reference_resolution),
			citation.span.file, citation.span.start_byte, citation.span.end_byte,
		),
	)
	insert_segments!(writer, "citation", anchor_id(citation.span), citation.quotation)
	nothing
end

function render_sqlite(
	corpus::Resolve.ResolvedCorpus, path::AbstractString; progress = nothing,
)
	isfile(path) && rm(path)
	database = SQLite.DB(path)
	foreach(statement -> DBInterface.execute(database, statement),
		filter(!isempty, strip.(split(schema, ";"))))
	writer = SqliteWriter(database, Dict{String, SQLite.Stmt}())

	total_entries = length(corpus.entries)
	report_step = max(cld(total_entries, 20), 1)
	started = time_ns()
	SQLite.transaction(database) do
		for (entry_index, entry) in enumerate(corpus.entries)
			insert_row!(
				writer,
				"insert into entries values (?,?,?,?,?,?,?)",
				(
					entry.entry_id, entry.headword,
					entry.homograph === nothing ? missing : entry.homograph,
					entry.span.file, entry.span.start_byte, entry.span.end_byte,
					entry.pronunciation === nothing ? missing : entry.pronunciation,
				),
			)
			for qualification in entry.grammar
				insert_row!(
					writer,
					"insert into qualifications values (?,?,?,?,?,?,?,?,?,?,?,?,?)",
					(
						missing, entry.entry_id, String(qualification.channel), qualification.type,
						isempty(qualification.norm) ? missing : qualification.norm,
						qualification.printed, scope_columns(qualification)...,
						qualification.span.file,
						qualification.span.start_byte, qualification.span.end_byte,
					),
				)
			end
			for (index, node) in enumerate(entry.nodes)
				insert_node!(writer, entry, node, nothing, index)
			end
			for rubrique in entry.rubriques
				rubrique_id = anchor_id(rubrique.span)
				for (index, item) in enumerate(rubrique.items)
					item isa Resolve.RubriqueNode || continue
					insert_node!(
						writer, entry, item.node, nothing, index; origin = "rubrique",
						rubrique_id, rubrique = rubrique.name,
						citation_subtype = Resolve.conventions_for(rubrique.name).subtype,
					)
				end
			end
			position = 0
			for rubrique in entry.rubriques
				for anchored in rubrique.etymology
					position += 1
					insert_etymology!(writer, entry, anchored, position)
				end
			end
			for rubrique in entry.rubriques
				for (index, item) in enumerate(rubrique.items)
					item isa Resolve.RubriqueCitation || continue
					insert_rubrique_citation!(writer, entry, rubrique, item, index)
				end
			end
			rubrique_ids = Set(anchor_id(rubrique.span) for rubrique in entry.rubriques)
			ordered_rubriques = sort(entry.rubriques; by = rubrique -> rubrique.span.start_byte)
			for (index, rubrique) in enumerate(ordered_rubriques)
				parent_rubrique_id = rubrique.parent_id !== nothing && rubrique.parent_id in rubrique_ids ?
					rubrique.parent_id : missing
				insert_row!(
					writer,
					"insert into rubriques values (?,?,?,?,?,?,?,?,?)",
					(
						anchor_id(rubrique.span), entry.entry_id, parent_rubrique_id,
						rubrique.name, index, rubrique_text(rubrique),
						rubrique.span.file, rubrique.span.start_byte, rubrique.span.end_byte,
					),
				)
				position = 0
				for item in rubrique.items
					item isa Resolve.RubriqueProse || continue
					position = insert_segments!(
						writer, "rubrique", anchor_id(rubrique.span), item.content, position,
					)
				end
			end
			if progress !== nothing && (entry_index % report_step == 0 || entry_index == total_entries)
				progress(
					entry_index, total_entries, entry.span.file,
					(time_ns() - started) / 1e9,
				)
			end
		end
		for record in corpus.coverage
			insert_row!(
				writer,
				"insert into coverage values (?,?,?,?,?,?,?,?,?,?,?)",
				(
					record.pass, record.pass_version, record.population, record.population_version,
					record.population_size, record.population_hash, record.examined,
					record.positive, record.negative, record.unresolved, record.stale,
				),
			)
		end
		for finding in corpus.review
			insert_row!(
				writer,
				"insert into review values (?,?,?,?,?)",
				(
					finding.category, finding.detail,
					finding.span.file, finding.span.start_byte, finding.span.end_byte,
				),
			)
		end
	end
	close(database)
	path
end
