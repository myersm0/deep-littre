module DeepLittre

using DBInterface
using JSON
using Random
using SQLite
using TOML
using Unicode
using XML

include("model.jl")
export IndentRole,
	Figurative, DomainLabel, NatureLabel, CrossReference,
	RegisterLabel, Proverb, VoiceTransition, Locution,
	Unclassified,
	RubriqueKind,
	Historique, Etymologie, Remarque, Synonyme, Proverbes, Supplement,
	ClassificationMethod, Deterministic, Heuristic, LlmAssisted, Manual,
	Classification, SourceLocation,
	Citation, Indent, Rubrique,
	BodyElement, Sense, TransitionGroup,
	Entry, ReviewFlag

include("parse.jl")
export parse_all, parse_file, strip_tags

include("enrich.jl")
export enrich!, resolve_all_authors!, classify_all!, extract_all_locutions!,
	extract_all_proverb_forms!, load_verdicts, VerdictDict

include("scope.jl")
export scope_all!

include("norms.jl")
export GramElement, UsgTarget, NormTables, load_norm_tables,
	parse_pos, route_atom, route_content, route_spans, route_usg_atom,
	split_atoms, split_atom_spans, normalize_atom, gram_markup, usg_markup,
	century_range, century_date_markup

include("etym.jl")
export segment_etymology, EtymSegment,
	EtymCit, EtymConnector, EtymCrossReference, EtymProse, EtymSuspect,
	EtymCue, EtymLanguageTable, load_etym_language_table

include("emit_tei.jl")
export emit_tei

include("flags.jl")
export collect_flags

include("emit_sqlite.jl")
export emit_sqlite

end
