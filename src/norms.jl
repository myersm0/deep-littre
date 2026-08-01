const data_directory = joinpath(@__DIR__, "..", "data")

struct GramElement
	kind::String
	norm::String
	printed::String
end

struct UsgTarget
	kind::String
	norm::String
end

const AtomTarget = Union{Vector{GramElement}, UsgTarget}

struct NormRule
	pattern::Regex
	target::UsgTarget
end

struct NormTables
	exact::Dict{String, UsgTarget}
	prefix::Vector{NormRule}
	lemma::Vector{NormRule}
	domain_prefix::Vector{NormRule}
	construction::Dict{String, String}
	agreement::Dict{String, Tuple{String, String}}
	pos_heads::Dict{String, Tuple{String, String}}
	pos_modifiers::Dict{String, Tuple{String, String}}
	pos_head_sensitive::Dict{String, Tuple{String, String}}
	pos_head_sensitive_tokens::Set{String}
	connectors::Set{String}
end

function pair_table(section)::Dict{String, Tuple{String, String}}
	Dict{String, Tuple{String, String}}(
		key => (value[1], value[2]) for (key, value) in section
	)
end

function ordered_rules(rows, anchored::Bool)::Vector{NormRule}
	NormRule[
		NormRule(
			Regex(anchored ? "^(?:" * row["pattern"] * ")" : row["pattern"]),
			UsgTarget(row["type"], row["norm"]),
		)
		for row in rows
	]
end

function load_norm_tables(directory::AbstractString = data_directory)::NormTables
	register = TOML.parsefile(joinpath(directory, "usg_register_norms.toml"))
	gram = TOML.parsefile(joinpath(directory, "usg_gram_norms.toml"))
	pos = TOML.parsefile(joinpath(directory, "pos_abbreviations.toml"))

	head_sensitive = pair_table(pos["head_sensitive"])
	sensitive_tokens = Set{String}(
		String(first(split(key, '|'))) for key in keys(head_sensitive)
	)

	NormTables(
		Dict{String, UsgTarget}(
			key => UsgTarget(value[1], value[2]) for (key, value) in register["exact"]
		),
		ordered_rules(get(register, "prefix", []), true),
		ordered_rules(get(register, "lemma", []), false),
		ordered_rules(get(register, "domain_prefix", []), true),
		Dict{String, String}(gram["construction"]),
		pair_table(gram["agreement"]),
		pair_table(pos["heads"]),
		pair_table(pos["modifiers"]),
		head_sensitive,
		sensitive_tokens,
		Set{String}(pos["connectors"]["tokens"]),
	)
end

const norm_tables = load_norm_tables()

# ── Locution adjudications ───────────────────────────────────────
# The hand-adjudicated labels in test/sampling/locutions_labeled.tsv drive the
# <re> retirement's structural branch: rows labeled metonymic_subsense emit as
# nested <sense> rather than relatedEntry, in both TEI and SQLite. Ground
# truth by adjudication; the emitter-side heuristic only flags for review.
const locution_adjudication_path =
	joinpath(@__DIR__, "..", "test", "sampling", "locutions_labeled.tsv")

function load_locution_adjudications(path::AbstractString = locution_adjudication_path)::Dict{String, String}
	adjudications = Dict{String, String}()
	if !isfile(path)
		@warn "Locution adjudication table not found; all locutions migrate uniformly" path
		return adjudications
	end
	for (i, line) in enumerate(eachline(path))
		i == 1 && continue
		fields = split(line, '\t')
		length(fields) == 4 && (adjudications[fields[1]] = fields[4])
	end
	adjudications
end

const locution_adjudications = load_locution_adjudications()

is_adjudicated_metonymic(sense_id::AbstractString)::Bool =
	get(locution_adjudications, sense_id, "") == "metonymic_subsense"

# ── Atom normalization ───────────────────────────────────────────
# Must stay bit-compatible with scripts/sampling/build_sampling_artifacts.py:
# lowercase, collapse whitespace, strip trailing .,;: — per atom, after the
# " et " split, not before it.

function collapse_content(text::AbstractString)::String
	strip(replace(lowercase(replace(text, r"<[^>]+>" => "")), r"\s+" => " "))
end

function normalize_atom(text::AbstractString)::String
	strip(replace(collapse_content(text), r"[.,;:]+$" => ""))
end

# The connector is coordination syntax rather than label content, so splitting
# on it drops it from both spans. The normalized side is always derived from
# the collapsed string, so it is unaffected by anything below; the printed span
# prefers the source piece, which keeps inline markup that collapsing would
# discard, and falls back to the collapsed piece if tag removal moved a
# boundary and the two splits disagree.
const atom_separator = r"\s+et\s+"

function split_atom_spans(text::AbstractString)::Vector{Tuple{String, String}}
	collapsed = split(collapse_content(text), atom_separator)
	source = split(text, atom_separator)
	printed_pieces = length(source) == length(collapsed) ? source : collapsed
	spans = Tuple{String, String}[]
	for (index, piece) in enumerate(collapsed)
		normalized = normalize_atom(piece)
		isempty(normalized) || push!(spans, (normalized, String(strip(printed_pieces[index]))))
	end
	spans
end

split_atoms(text::AbstractString)::Vector{String} = first.(split_atom_spans(text))

# ── POS parser ───────────────────────────────────────────────────

function resolve_token(tables::NormTables, token::AbstractString)::String
	known(candidate) =
		haskey(tables.pos_heads, candidate) ||
		haskey(tables.pos_modifiers, candidate) ||
		candidate in tables.pos_head_sensitive_tokens
	known(token) && return String(token)
	bare = rstrip(token, '.')
	for candidate in (bare, bare * ".")
		known(candidate) && return String(candidate)
	end
	String(token)
end

function parse_pos(text::AbstractString, tables::NormTables = norm_tables)::Union{Nothing, Vector{GramElement}}
	cleaned = strip(replace(text, r"\s+" => " "))
	cleaned = replace(cleaned, r"[,;:]+$" => "")
	cleaned = replace(cleaned, r"\.\.+$" => ".")
	(isempty(cleaned) || occursin('<', cleaned)) && return nothing

	elements = GramElement[]
	head = ""
	for printed in split(cleaned, ' ')
		token = resolve_token(tables, lowercase(printed))
		token in tables.connectors && continue
		if haskey(tables.pos_heads, token)
			kind, norm = tables.pos_heads[token]
			head = token
			push!(elements, GramElement(kind, norm, String(printed)))
		elseif token in tables.pos_head_sensitive_tokens
			mapped = get(tables.pos_head_sensitive, "$(token)|$(head)", nothing)
			mapped === nothing && (mapped = get(tables.pos_head_sensitive, "$(token)|", nothing))
			mapped === nothing && return nothing
			push!(elements, GramElement(mapped[1], mapped[2], String(printed)))
		elseif haskey(tables.pos_modifiers, token)
			kind, norm = tables.pos_modifiers[token]
			push!(elements, GramElement(kind, norm, String(printed)))
		else
			return nothing
		end
	end
	isempty(elements) ? nothing : elements
end

# ── Routing ──────────────────────────────────────────────────────

function route_usg_atom(atom::AbstractString, tables::NormTables = norm_tables)::UsgTarget
	haskey(tables.exact, atom) && return tables.exact[atom]
	for rule in tables.prefix
		occursin(rule.pattern, atom) && return rule.target
	end
	for rule in tables.lemma
		occursin(rule.pattern, atom) && return rule.target
	end
	for rule in tables.domain_prefix
		occursin(rule.pattern, atom) && return rule.target
	end
	UsgTarget("hint", "")
end

# Trailing discourse adverbials ("populairement encore", "absolument aussi")
# are deixis rather than label content, the same species as the dropped "et"
# connector. They are stripped only as a retry after every tier has missed,
# so no previously routed atom can change target. A usg caller still places
# the full printed span; a gram element reached through the retry prints the
# stripped atom, consistent with gram content being normalized text already. Contentful interposers (au singulier, au pluriel)
# are deliberately absent: if the tables miss them the atom stays hint and
# shows up in the residue counts.
const discourse_tail = r"(?:\s+(?:encore|aussi|aujourd['’]hui|en ce sens|dans le même sens))+$"

strip_discourse_tail(atom::AbstractString)::String =
	String(replace(atom, discourse_tail => ""))

function route_atom(atom::AbstractString, tables::NormTables = norm_tables)::AtomTarget
	if haskey(tables.agreement, atom)
		kind, norm = tables.agreement[atom]
		return GramElement[GramElement(kind, norm, atom)]
	end
	if haskey(tables.construction, atom)
		return GramElement[GramElement("construction", tables.construction[atom], atom)]
	end
	elements = parse_pos(atom, tables)
	elements === nothing || return elements
	target = route_usg_atom(atom, tables)
	target.kind == "hint" || return target
	stripped = strip_discourse_tail(atom)
	stripped == atom ? target : route_atom(stripped, tables)
end

# Whole-string POS parse first so "s. m. et f." stays one reading instead of
# splitting into two atoms on " et ". Each target travels with the span of the
# source label it was routed from, so a caller placing several elements can
# give each one text that its own type describes.
function route_spans(content::AbstractString, tables::NormTables = norm_tables)::Vector{Tuple{AtomTarget, String}}
	elements = parse_pos(content, tables)
	elements === nothing || return Tuple{AtomTarget, String}[(elements, String(strip(content)))]
	Tuple{AtomTarget, String}[
		(route_atom(normalized, tables), printed)
		for (normalized, printed) in split_atom_spans(content)
	]
end

route_content(content::AbstractString, tables::NormTables = norm_tables)::Vector{AtomTarget} =
	AtomTarget[first(span) for span in route_spans(content, tables)]

# ── Markup construction ──────────────────────────────────────────

function gram_markup(elements::Vector{GramElement})::String
	body = join(
		begin
			norm = isempty(element.norm) ? "" : " norm=\"$(element.norm)\""
			"<gram type=\"$(element.kind)\"$(norm)>$(escape_xml(element.printed))</gram>"
		end
		for element in elements
	)
	"<gramGrp>$(body)</gramGrp>"
end

function usg_markup(target::UsgTarget, printed::AbstractString)::String
	norm = isempty(target.norm) ? "" : " norm=\"$(target.norm)\""
	"<usg type=\"$(target.kind)\"$(norm)>$(printed)</usg>"
end

# Positions whose content model admits <usg> but not <gramGrp> (etym, and any
# residual mid-prose survivor) take a usg with a valid type; a gram reading
# degrades to hint rather than changing element type.
function usg_only_markup(target::AtomTarget, printed::AbstractString)::String
	target isa UsgTarget && return usg_markup(target, printed)
	usg_markup(UsgTarget("hint", ""), printed)
end

# ── Century dates ────────────────────────────────────────────────

const roman_centuries = Dict(
	"IX" => 9, "X" => 10, "XI" => 11, "XII" => 12, "XIII" => 13,
	"XIV" => 14, "XV" => 15, "XVI" => 16, "XVII" => 17, "XVIII" => 18,
	"XIX" => 19,
)

const century_pattern = r"^\s*([IVXivx]+)\s*e?\s*(?:s\.|siècle)"

function century_range(text::AbstractString)::Union{Nothing, Tuple{Int, Int}}
	matched = match(century_pattern, text)
	matched === nothing && return nothing
	century = get(roman_centuries, uppercase(matched.captures[1]), nothing)
	century === nothing && return nothing
	((century - 1) * 100 + 1, century * 100)
end

function century_date_markup(text::AbstractString)::Union{Nothing, String}
	range = century_range(text)
	range === nothing && return nothing
	not_before = lpad(range[1], 4, '0')
	not_after = lpad(range[2], 4, '0')
	"<date notBefore=\"$(not_before)\" notAfter=\"$(not_after)\">$(escape_xml(strip(text)))</date>"
end
