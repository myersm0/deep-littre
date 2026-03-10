"""Quality check on extracted locution canonical forms using a local LLM.

Checks whether the canonical form is a clean extraction from the definition,
NOT whether the item "should" be a locution.

Usage:
	python scripts/locution_check2.py data/littre.db --model qwen2.5:32b --limit 200
	python scripts/locution_check2.py data/littre.db --model qwen2.5:32b --all
"""

import argparse
import json
import sqlite3
import sys
from pathlib import Path

import requests

ollama_url = "http://localhost:11434/api/chat"

system_prompt = """\
You are auditing canonical forms extracted from a 19th-century French dictionary.

Each item has a DEFINITION that follows the pattern: phrase, then a comma, then a \
gloss. A CANONICAL FORM has been extracted — it should be the phrase portion \
(everything before the definitional comma).

Your job is to check whether the CANONICAL FORM was extracted correctly. \
You are NOT judging whether the item is a "real" locution or idiom — only whether \
the extraction is clean.

Flag as BAD if ANY of these apply:
- The canonical form is a contextual or domain framing phrase rather than the \
  locution itself. These are short phrases that set a context but do not contain \
  the headword. Common patterns: "En prose", "En droit", "En musique", \
  "En peinture", "En somme", "Au jeu de loto", "Aux loteries", \
  "Chez les anciens", "Dans le même sens", "En termes de", "En parlant des choses".
- The canonical form has a leaked prefix: "Loc.", "Fig.", or similar abbreviations \
  that are editorial markup, not part of the phrase.
- The canonical form contains a grammatical note: "se met après son substantif", \
  "se conjugue avec", "se dit aussi absolument", or similar.
- The canonical form contains definition text from after the comma \
  (the gloss leaked into the form).
- The canonical form is a fragment of commentary rather than the actual phrase \
  ("Mot qui", "Cette locution", "On dit aussi", "Bon mot", "Mot très bon").
- The canonical form is an illustrative sentence rather than a named phrase \
  (e.g. "Je ne l'aurais pas cru", "C'est un homme affreux"). These typically \
  read as natural sentences rather than dictionary-style phrase headings.
- The canonical form captures the wrong part of the definition entirely \
  (e.g. "S'éveiller" when the actual phrase is "se lever au chant de l'alouette").
- The definition after the comma is a grammatical rule ("veut le subjonctif", \
  "régit le datif", "prend un complément en de") rather than a definitional \
  gloss. The item is a construction note, not a locution.
- The canonical form is just the bare headword itself (possibly differing in \
  capitalization), with no additional words forming a phrase.

Flag as OK if:
- The canonical form matches the phrase portion of the definition, even if \
  the phrase is very simple (e.g. "Race féconde"), very long, or not idiomatic. \
  Simplicity is not a defect.
- The canonical form is a complete sentence-length expression like \
  "Cela ressemble à une gageure" — if the definition gives it form-comma-gloss \
  structure, it is a valid extraction regardless of length.

Respond with ONLY "ok" or "bad".
"""


def build_prompt(row):
	lines = [
		f"HEADWORD: {row['headword']}",
		f"CANONICAL FORM: {row['canonical_form']}",
		f"DEFINITION: {row['content_plain'][:300]}",
	]
	return "\n".join(lines)


def fetch_locutions(db_path, limit=None):
	conn = sqlite3.connect(db_path)
	conn.row_factory = sqlite3.Row
	cur = conn.cursor()
	query = """
		SELECT l.sense_id, l.canonical_form, s.content_plain,
			s.indent_id, e.headword
		FROM locutions l
		JOIN senses s ON l.sense_id = s.sense_id
		JOIN entries e ON s.entry_id = e.entry_id
		ORDER BY e.headword, s.sense_id
	"""
	if limit:
		query += f" LIMIT {limit}"
	cur.execute(query)
	items = [dict(row) for row in cur.fetchall()]
	conn.close()
	return items


def query_ollama(model, system, user):
	response = requests.post(ollama_url, json={
		"model": model,
		"messages": [
			{"role": "system", "content": system},
			{"role": "user", "content": user},
		],
		"stream": False,
		"options": {"num_predict": 10},
	})
	response.raise_for_status()
	return response.json()["message"]["content"].strip().lower()


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("db_path", nargs="?", default="data/littre.db")
	parser.add_argument("--model", default="qwen2.5:32b")
	parser.add_argument("--limit", type=int, default=200)
	parser.add_argument("--all", action="store_true")
	parser.add_argument("--output", default=None)
	args = parser.parse_args()

	model_tag = args.model.replace(":", "_").replace("/", "_")
	output_path = args.output or f"locution_check2_{model_tag}.json"

	limit = None if args.all else args.limit
	print(f"Fetching locutions from {args.db_path}...")
	items = fetch_locutions(args.db_path, limit)
	print(f"Got {len(items)} locutions to check")
	print(f"Model: {args.model}\n")

	results = []
	ok_count = 0
	bad_count = 0

	for i, item in enumerate(items):
		prompt = build_prompt(item)
		try:
			raw = query_ollama(args.model, system_prompt, prompt)
			is_bad = "bad" in raw and "ok" not in raw.split("bad")[0]
			label = "BAD" if is_bad else "OK"
			flag = f"  ← BAD" if is_bad else ""
			print(
				f"[{i + 1}/{len(items)}] {item['indent_id'] or '?':30} "
				f"{item['canonical_form'][:50]:50} {label}{flag}"
			)
			if is_bad:
				bad_count += 1
			else:
				ok_count += 1
			results.append({
				"sense_id": item["sense_id"],
				"indent_id": item["indent_id"],
				"headword": item["headword"],
				"canonical_form": item["canonical_form"],
				"content": item["content_plain"][:200],
				"label": label,
				"raw_answer": raw,
			})
		except Exception as exc:
			print(f"[{i + 1}] ERROR {item['headword']}: {exc}", file=sys.stderr)
			results.append({
				"sense_id": item["sense_id"],
				"indent_id": item["indent_id"],
				"headword": item["headword"],
				"canonical_form": item["canonical_form"],
				"label": f"ERROR:{exc}",
				"raw_answer": None,
			})

	total = ok_count + bad_count
	print(f"\n{'=' * 60}")
	print(f"Results ({total} items):")
	print(f"  OK:  {ok_count} ({100 * ok_count / total:.1f}%)")
	print(f"  BAD: {bad_count} ({100 * bad_count / total:.1f}%)")

	bad_items = [r for r in results if r["label"] == "BAD"]
	if bad_items:
		print(f"\nFlagged items ({len(bad_items)}):")
		for r in bad_items[:30]:
			print(f"  {r['headword']:20} | {r['canonical_form'][:40]:40} | {r['content'][:60]}")
		if len(bad_items) > 30:
			print(f"  ... and {len(bad_items) - 30} more")

	Path(output_path).write_text(
		json.dumps(results, indent=2, ensure_ascii=False)
	)
	print(f"\nResults written to {output_path}")


if __name__ == "__main__":
	main()
