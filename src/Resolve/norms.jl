"""
Deterministic routing of printed Littré labels to normalized qualification targets. Nothing here is
an adjudication: it reconstructs, every build, what XMLittré already states.
"""
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

pair_table(section)::Dict{String, Tuple{String, String}} =
	Dict{String, Tuple{String, String}}(key => (value[1], value[2]) for (key, value) in section)

ordered_rules(rows, anchored::Bool)::Vector{NormRule} = NormRule[
	NormRule(
		Regex(anchored ? "^(?:" * row["pattern"] * ")" : row["pattern"]),
		UsgTarget(row["type"], row["norm"]),
	)
	for row in rows
]

const data_directory = normpath(joinpath(@__DIR__, "..", "..", "data"))

function load_norm_tables(directory::AbstractString = data_directory)::NormTables
	register = TOML.parsefile(joinpath(directory, "usg_register_norms.toml"))
	gram = TOML.parsefile(joinpath(directory, "usg_gram_norms.toml"))
	pos = TOML.parsefile(joinpath(directory, "pos_abbreviations.toml"))

	head_sensitive = pair_table(pos["head_sensitive"])

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
		Set{String}(String(first(split(key, '|'))) for key in keys(head_sensitive)),
		Set{String}(pos["connectors"]["tokens"]),
	)
end

# Without these declarations an edit to a committed table would not invalidate the precompile
# cache and the package would silently serve stale routing.
for name in ("usg_register_norms.toml", "usg_gram_norms.toml", "pos_abbreviations.toml")
	include_dependency(joinpath(data_directory, name))
end

const norm_tables = load_norm_tables()

collapse_content(text::AbstractString)::String =
	strip(replace(lowercase(replace(text, r"<[^>]+>" => "")), r"\s+" => " "))

normalize_atom(text::AbstractString)::String =
	strip(replace(collapse_content(text), r"[.,;:]+$" => ""))

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

function parse_pos(
	text::AbstractString, tables::NormTables = norm_tables,
)::Union{Nothing, Vector{GramElement}}
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
			(kind, norm) = tables.pos_heads[token]
			head = token
			push!(elements, GramElement(kind, norm, String(printed)))
		elseif token in tables.pos_head_sensitive_tokens
			mapped = get(tables.pos_head_sensitive, "$(token)|$(head)", nothing)
			mapped === nothing && (mapped = get(tables.pos_head_sensitive, "$(token)|", nothing))
			mapped === nothing && return nothing
			push!(elements, GramElement(mapped[1], mapped[2], String(printed)))
		elseif haskey(tables.pos_modifiers, token)
			(kind, norm) = tables.pos_modifiers[token]
			push!(elements, GramElement(kind, norm, String(printed)))
		else
			return nothing
		end
	end
	isempty(elements) ? nothing : elements
end

# Trailing discourse adverbials are deixis rather than label content. Stripped only as a retry
# after every tier has missed, so no previously routed atom can change target.
const discourse_tail =
	r"(?:\s+(?:encore|aussi|aujourd['’]hui|en ce sens|en cet emploi|dans le même sens))+$"

strip_discourse_tail(atom::AbstractString)::String =
	String(replace(atom, discourse_tail => ""))

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
	stripped = strip_discourse_tail(atom)
	stripped == atom ? UsgTarget("hint", "") : route_usg_atom(stripped, tables)
end

function route_atom(atom::AbstractString, tables::NormTables = norm_tables)::AtomTarget
	if haskey(tables.agreement, atom)
		(kind, norm) = tables.agreement[atom]
		return GramElement[GramElement(kind, norm, atom)]
	end
	haskey(tables.construction, atom) &&
		return GramElement[GramElement("construction", tables.construction[atom], atom)]
	elements = parse_pos(atom, tables)
	elements === nothing || return elements
	target = route_usg_atom(atom, tables)
	target.kind == "hint" || return target
	stripped = strip_discourse_tail(atom)
	stripped == atom ? target : route_atom(stripped, tables)
end

"""
	route_spans(content)

Whole-string POS parse first, so `s. m. et f.` stays one reading instead of splitting on the
connector. Each target travels with the printed span it was routed from.
"""
function route_spans(
	content::AbstractString, tables::NormTables = norm_tables,
)::Vector{Tuple{AtomTarget, String}}
	elements = parse_pos(content, tables)
	elements === nothing ||
		return Tuple{AtomTarget, String}[(elements, String(strip(content)))]
	Tuple{AtomTarget, String}[
		(route_atom(normalized, tables), printed) for (normalized, printed) in split_atom_spans(content)
	]
end
