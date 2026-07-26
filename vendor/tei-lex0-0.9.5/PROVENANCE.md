# Vendored TEI Lex-0 schema — v0.9.5

Source project: BCDH/tei-lex-0 (current official home; supersedes the older
DARIAH-ERIC/lexicalresources repo, which stops at v0.9.4).

- Release tag: v0.9.5
- ODD source: odd/lex-0.odd @ tag v0.9.5 (commit 8c2c50bd80d998e4218cb9adf26f8ae1d4995b70)
- Generated schema vendored from: gh-pages releases/v0.9.5/schema/ (commit a80b596ab258378088cee330361364a49875f16a)
  Also published at https://lex-0.org/schema/lex-0.rng
- RNG generation stamp (from file header): 2026-02-08T13:24:46Z
- Built against TEI P5 Version 4.10.2 (2025-09-04, revision bcfa98f42)

## Files
- lex-0.rng   RelaxNG, primary validation schema. Embeds 27 Schematron
              (sch:assert/sch:report) constraints.
- lex-0.rnc   RelaxNG compact syntax (same grammar).
- lex-0.xsd   W3C XML Schema (references xml.xsd).
- xml.xsd     XML namespace schema (xsd dependency).

## Schematron
No standalone .sch ships with v0.9.5; the Schematron constraints are embedded
in the RNG. RNG validators (jing, xmllint) do NOT execute them — extracting and
running them needs an ISO-Schematron XSLT pipeline on an XSLT2 engine (Saxon).

## Validator note
xmllint --relaxng is NOT sound against this schema: libxml2's RelaxNG engine
emits false positives on TEI's biblStruct/monogr content model. Use jing for
RNG validation. Verified 2026-07-18.
