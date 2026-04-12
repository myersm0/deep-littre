# Deep-Littré SQLite schema guide

This guide summarizes the SQLite schema emitted by the Deep-Littré pipeline and gives ready-to-run SQL examples for common extraction tasks.

Source references: project README and `emit_sqlite.jl`. The README describes the intended database contents and purpose of each table, while the emitter shows the exact column names and the actual values written into fields like `sense_type`, `role`, and `rubrique_type`.

## Overview

The database is a flattened but still hierarchical representation of Littré:

- `entries` stores one row per dictionary entry
- `senses` stores numbered senses, indents, labels, locutions, proverbs, cross-references, and transition-group containers
- `citations` stores examples and quotations attached to a `sense_id`
- `locutions` stores extracted canonical locution forms for locution rows
- `rubriques` stores entry-level sections such as etymology and historical notes
- `review_queue` stores pipeline flags for human review
- `senses_fts` and `citations_fts` provide FTS5 full-text search over plain text

The most important design fact is that `senses` is recursive: ordinary senses and child indents live in the same table, linked by `parent_sense_id`.

## Table reference

### `entries`

One row per dictionary entry.

Columns:

- `entry_id TEXT PRIMARY KEY`
- `headword TEXT NOT NULL`
- `homograph_index INTEGER`
- `pronunciation TEXT`
- `pos TEXT`
- `is_supplement INTEGER DEFAULT 0`
- `source_letter TEXT`

Typical uses:

- look up entries by headword
- filter supplement material
- join outward to senses and rubriques

### `senses`

Stores all sense-like structural units.

Columns:

- `sense_id INTEGER PRIMARY KEY AUTOINCREMENT`
- `entry_id TEXT NOT NULL REFERENCES entries(entry_id)`
- `parent_sense_id INTEGER REFERENCES senses(sense_id)`
- `num INTEGER`
- `indent_id TEXT`
- `xml_id TEXT`
- `sense_type TEXT NOT NULL DEFAULT 'sense'`
- `role TEXT`
- `content_plain TEXT`
- `content_markup TEXT`
- `is_supplement INTEGER DEFAULT 0`
- `transition_type TEXT`
- `transition_form TEXT`
- `transition_pos TEXT`
- `depth INTEGER NOT NULL DEFAULT 0`

Interpretation:

- top-level numbered senses usually have `sense_type = 'sense'` and `parent_sense_id IS NULL`
- child indents also live here, with `parent_sense_id` pointing upward
- special semantic categories are mainly captured by `sense_type`
- `role` records the classifier label for indents and related items
- `depth` reflects nesting depth
- transition containers use `transition_type`, `transition_form`, and `transition_pos`

Actual `sense_type` values present in this database:

- `annotation`
- `cross_reference`
- `domain`
- `figurative`
- `grammatical_variant`
- `locution`
- `proverb`
- `register`
- `sense`
- `transition_group`
- `usage_group`

Actual `role` values present in this database:

- `Continuation`
- `CrossReference`
- `DomainLabel`
- `Elaboration`
- `Figurative`
- `Locution`
- `NatureLabel`
- `Proverb`
- `RegisterLabel`
- `VoiceTransition`

Use `sense_type` for most filtering. It is the cleaner public-facing category. Use `role` when you want classifier-specific distinctions such as `Continuation` vs `Elaboration`.

### `citations`

Stores quotations and examples attached to a sense.

Columns:

- `citation_id INTEGER PRIMARY KEY AUTOINCREMENT`
- `sense_id INTEGER NOT NULL REFERENCES senses(sense_id)`
- `text_plain TEXT`
- `text_markup TEXT`
- `author TEXT`
- `resolved_author TEXT`
- `reference TEXT`
- `is_hidden INTEGER DEFAULT 0`

Notes:

- `resolved_author` contains the resolved author when idem resolution succeeded; otherwise it falls back to `author`
- `is_hidden = 1` marks suppressed citations

### `locutions`

Side table for extracted canonical locution forms.

Columns:

- `sense_id INTEGER PRIMARY KEY REFERENCES senses(sense_id)`
- `canonical_form TEXT NOT NULL`

Notes:

- only senses classified as locutions get rows here
- the row points back to the corresponding row in `senses`

### `rubriques`

Entry-level sections such as etymology and historical notes.

Columns:

- `rubrique_id INTEGER PRIMARY KEY AUTOINCREMENT`
- `entry_id TEXT NOT NULL REFERENCES entries(entry_id)`
- `rubrique_type TEXT NOT NULL`
- `content_plain TEXT`
- `content_markup TEXT`

Actual `rubrique_type` values present in this database:

- `Etymologie`
- `Historique`
- `Proverbes`
- `Remarque`
- `Supplement`
- `Synonyme`

### `review_queue`

Human review queue for pipeline flags.

Columns:

- `review_id INTEGER PRIMARY KEY AUTOINCREMENT`
- `entry_id TEXT NOT NULL`
- `headword TEXT NOT NULL`
- `phase TEXT NOT NULL`
- `flag_type TEXT NOT NULL`
- `reason TEXT`
- `context TEXT`
- `resolution TEXT`
- `resolved_by TEXT`

Notes:

- unresolved items usually have `resolution IS NULL` or `resolution = ''`
- `context` is JSON stored as text

### Full-text tables

#### `senses_fts`

FTS5 virtual table over `senses.content_plain`.

- `rowid` matches `senses.sense_id`

#### `citations_fts`

FTS5 virtual table over `citations.text_plain`.

- `rowid` matches `citations.citation_id`

## Join map

The usual join paths are:

```sql
entries.entry_id -> senses.entry_id
senses.sense_id -> citations.sense_id
senses.sense_id -> locutions.sense_id
entries.entry_id -> rubriques.entry_id
```

The recursive link inside `senses` is:

```sql
senses.parent_sense_id -> senses.sense_id
```

## Common query patterns

### 1. Inspect structural vocabularies

```sql
SELECT DISTINCT sense_type FROM senses ORDER BY sense_type;
SELECT DISTINCT role FROM senses WHERE role IS NOT NULL ORDER BY role;
SELECT DISTINCT rubrique_type FROM rubriques ORDER BY rubrique_type;
```

### 2. Look up an entry

```sql
SELECT entry_id, headword, homograph_index, pronunciation, pos, is_supplement, source_letter
FROM entries
WHERE headword = 'ENVIE';
```

### 3. Get all top-level senses for a headword

```sql
SELECT s.sense_id, s.num, s.sense_type, s.role, s.content_plain
FROM senses s
JOIN entries e ON e.entry_id = s.entry_id
WHERE e.headword = 'ENVIE'
  AND s.parent_sense_id IS NULL
ORDER BY COALESCE(s.num, 999999), s.sense_id;
```

### 4. Get the full sense tree for a headword

```sql
SELECT s.sense_id, s.parent_sense_id, s.depth, s.num,
       s.indent_id, s.xml_id, s.sense_type, s.role,
       s.transition_type, s.transition_form, s.transition_pos,
       s.content_plain
FROM senses s
JOIN entries e ON e.entry_id = s.entry_id
WHERE e.headword = 'ENVIE'
ORDER BY s.sense_id;
```

### 5. Get the direct children of a sense

```sql
SELECT child.sense_id, child.parent_sense_id, child.depth, child.num,
       child.sense_type, child.role, child.content_plain
FROM senses child
WHERE child.parent_sense_id = 12345
ORDER BY child.sense_id;
```

### 6. Find all figurative senses

```sql
SELECT e.headword, s.sense_id, s.indent_id, s.content_plain
FROM senses s
JOIN entries e ON e.entry_id = s.entry_id
WHERE s.sense_type = 'figurative'
ORDER BY e.headword, s.sense_id;
```

### 7. Find all domain-labeled material

```sql
SELECT e.headword, s.sense_id, s.content_plain
FROM senses s
JOIN entries e ON e.entry_id = s.entry_id
WHERE s.sense_type = 'domain'
ORDER BY e.headword, s.sense_id;
```

### 8. Find all register-labeled material

```sql
SELECT e.headword, s.sense_id, s.content_plain
FROM senses s
JOIN entries e ON e.entry_id = s.entry_id
WHERE s.sense_type = 'register'
ORDER BY e.headword, s.sense_id;
```

### 9. Find all proverbs

```sql
SELECT e.headword, s.sense_id, s.content_plain
FROM senses s
JOIN entries e ON e.entry_id = s.entry_id
WHERE s.sense_type = 'proverb'
ORDER BY e.headword, s.sense_id;
```

### 10. Find all cross-references

```sql
SELECT e.headword, s.sense_id, s.content_plain
FROM senses s
JOIN entries e ON e.entry_id = s.entry_id
WHERE s.sense_type = 'cross_reference'
ORDER BY e.headword, s.sense_id;
```

### 11. Browse extracted locutions

```sql
SELECT e.headword, l.canonical_form, s.sense_id, s.content_plain
FROM locutions l
JOIN senses s ON s.sense_id = l.sense_id
JOIN entries e ON e.entry_id = s.entry_id
ORDER BY l.canonical_form;
```

### 12. Look up a locution by canonical form

```sql
SELECT e.headword, l.canonical_form, s.content_plain
FROM locutions l
JOIN senses s ON s.sense_id = l.sense_id
JOIN entries e ON e.entry_id = s.entry_id
WHERE l.canonical_form LIKE '%avoir envie%'
ORDER BY e.headword;
```

### 13. Find transition groups and grammatical variants

```sql
SELECT e.headword,
       s.sense_id,
       s.parent_sense_id,
       s.depth,
       s.sense_type,
       s.transition_type,
       s.transition_form,
       s.transition_pos,
       s.content_plain
FROM senses s
JOIN entries e ON e.entry_id = s.entry_id
WHERE s.sense_type IN ('transition_group', 'grammatical_variant', 'usage_group')
ORDER BY e.headword, s.sense_id;
```

### 14. Get all citations for a headword

```sql
SELECT e.headword, s.sense_id, c.citation_id,
       c.author, c.resolved_author, c.reference, c.text_plain
FROM citations c
JOIN senses s ON s.sense_id = c.sense_id
JOIN entries e ON e.entry_id = s.entry_id
WHERE e.headword = 'ENVIE'
ORDER BY s.sense_id, c.citation_id;
```

### 15. Find citations by author

```sql
SELECT e.headword, s.sense_id, c.reference, c.text_plain
FROM citations c
JOIN senses s ON s.sense_id = c.sense_id
JOIN entries e ON e.entry_id = s.entry_id
WHERE c.resolved_author = 'MOLIÈRE'
ORDER BY e.headword, s.sense_id, c.citation_id;
```

### 16. Hidden citations only

```sql
SELECT e.headword, s.sense_id, c.reference, c.text_plain
FROM citations c
JOIN senses s ON s.sense_id = c.sense_id
JOIN entries e ON e.entry_id = s.entry_id
WHERE c.is_hidden = 1
ORDER BY e.headword, s.sense_id;
```

### 17. Get rubriques for an entry

```sql
SELECT e.headword, r.rubrique_type, r.content_plain
FROM rubriques r
JOIN entries e ON e.entry_id = r.entry_id
WHERE e.headword = 'ENVIE'
ORDER BY r.rubrique_id;
```

### 18. Find all entries with an `Historique` rubrique

```sql
SELECT e.headword, r.content_plain
FROM rubriques r
JOIN entries e ON e.entry_id = r.entry_id
WHERE r.rubrique_type = 'Historique'
ORDER BY e.headword;
```

### 19. Unresolved review items

```sql
SELECT review_id, entry_id, headword, phase, flag_type, reason, context
FROM review_queue
WHERE resolution IS NULL OR resolution = ''
ORDER BY phase, flag_type, headword;
```

### 20. Count unresolved review items by type

```sql
SELECT phase, flag_type, COUNT(*) AS n
FROM review_queue
WHERE resolution IS NULL OR resolution = ''
GROUP BY phase, flag_type
ORDER BY n DESC, phase, flag_type;
```

### 21. Count major object types per entry

```sql
SELECT 
    e.headword,
    COUNT(DISTINCT s.sense_id) AS n_senses,
    COUNT(DISTINCT c.citation_id) AS n_citations,
    COUNT(DISTINCT l.sense_id) AS n_locutions,
    COUNT(DISTINCT r.rubrique_id) AS n_rubriques
FROM entries e
LEFT JOIN senses s ON s.entry_id = e.entry_id
LEFT JOIN citations c ON c.sense_id = s.sense_id
LEFT JOIN locutions l ON l.sense_id = s.sense_id
LEFT JOIN rubriques r ON r.entry_id = e.entry_id
GROUP BY e.entry_id, e.headword
ORDER BY n_senses DESC, e.headword;
```

### 22. Full-text search in definitions and sense content

```sql
SELECT s.sense_id, e.headword, s.sense_type, s.content_plain
FROM senses_fts f
JOIN senses s ON s.sense_id = f.rowid
JOIN entries e ON e.entry_id = s.entry_id
WHERE senses_fts MATCH 'envie'
ORDER BY bm25(senses_fts);
```

### 23. Full-text search in citations

```sql
SELECT c.citation_id, e.headword, c.resolved_author, c.reference, c.text_plain
FROM citations_fts f
JOIN citations c ON c.citation_id = f.rowid
JOIN senses s ON s.sense_id = c.sense_id
JOIN entries e ON e.entry_id = s.entry_id
WHERE citations_fts MATCH 'vertu'
ORDER BY bm25(citations_fts);
```

### 24. Supplements only

```sql
SELECT entry_id, headword, pos
FROM entries
WHERE is_supplement = 1
ORDER BY headword;
```

### 25. Frequency of sense types

```sql
SELECT sense_type, COUNT(*) AS n
FROM senses
GROUP BY sense_type
ORDER BY n DESC, sense_type;
```

### 26. Frequency of classifier roles

```sql
SELECT role, COUNT(*) AS n
FROM senses
WHERE role IS NOT NULL
GROUP BY role
ORDER BY n DESC, role;
```

## Notes on query strategy

1. Prefer `sense_type` over `role` when your goal is a user-facing semantic class such as figurative, locution, proverb, or cross-reference.
2. Prefer `role` when you care about internal classifier distinctions such as `Continuation` versus `Elaboration`.
3. For locutions, use the `locutions` table rather than filtering only on `senses.sense_type = 'locution'`, unless you explicitly want all locution-classified rows whether or not canonical extraction succeeded.
4. When reconstructing local hierarchy, `parent_sense_id` and `depth` are the key fields.
5. FTS is best for content discovery; exact joins and filters are better for structural extraction.

## Minimal starter workflow

A good way to begin exploring a fresh build is:

```sql
SELECT DISTINCT sense_type FROM senses ORDER BY sense_type;
SELECT DISTINCT role FROM senses WHERE role IS NOT NULL ORDER BY role;
SELECT DISTINCT rubrique_type FROM rubriques ORDER BY rubrique_type;

SELECT headword, pos
FROM entries
ORDER BY headword
LIMIT 20;

SELECT e.headword, s.sense_type, s.role, s.content_plain
FROM senses s
JOIN entries e ON e.entry_id = s.entry_id
WHERE e.headword = 'ENVIE'
ORDER BY s.sense_id;
```
