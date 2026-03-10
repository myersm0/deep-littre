"""Decomposition-based locution detection.

Instead of asking "is this a locution?", asks the model to decompose
the text into form + gloss. Validation of the decomposition then
determines whether the item is a locution.

Usage:
	python scripts/decompose.py data/littre.db --model qwen2.5:72b --limit 100
	python scripts/decompose.py data/littre.db --model qwen2.5:72b --fallback --limit 100
	python scripts/decompose.py data/littre.db --model qwen2.5:72b --fallback --all
	python scripts/decompose.py data/littre.db --model qwen2.5:72b --fallback --all \
		--exclude decompose_fallback_qwen2.5_72b.jsonl
"""

import argparse
import json
import sqlite3
import sys
from pathlib import Path

import requests

ollama_url = "http://localhost:11434/api/chat"

system_prompt = """\
You are processing items from a 19th-century French dictionary.

Each item has a HEADWORD and TEXT. Your job is to split the text into two parts:

- "form": the phrase or expression being defined (before the definitional boundary)
- "gloss": the definition or explanation (after the definitional boundary)

The boundary is usually a comma, but could also be a colon or semicolon.

If the text begins with an introductory remark ("On dit aussi...", \
"On dit dans le même sens...", "Invariablement.", or similar) followed by a \
separate phrase-comma-gloss definition, skip that remark and extract from the \
text that follows it.

Always give it your best attempt, even if the split feels awkward or forced. \
Do not refuse. Do not explain. Just return the JSON.

Respond with ONLY a JSON object: {"form": "...", "gloss": "..."}

Examples:

HEADWORD: DÉFAUT
TEXT: Le défaut de la cuirasse, l'intervalle entre les deux pièces d'une cuirasse.
{"form": "Le défaut de la cuirasse", "gloss": "l'intervalle entre les deux pièces d'une cuirasse"}

HEADWORD: ABOYER
TEXT: Aboyer à la lune, crier inutilement.
{"form": "Aboyer à la lune", "gloss": "crier inutilement"}

HEADWORD: INDUSIE
TEXT: On dit aussi induse. Calcaire à induses, calcaire qui contient de ces étuis.
{"form": "Calcaire à induses", "gloss": "calcaire qui contient de ces étuis"}

HEADWORD: TISSU
TEXT: En botanique, tissu se dit aussi en parlant des différentes parties qui constituent les végétaux.
{"form": "En botanique", "gloss": "tissu se dit aussi en parlant des différentes parties qui constituent les végétaux"}

HEADWORD: ABUSER
TEXT: Abuser, v. n., se conjugue avec l'auxiliaire avoir.
{"form": "Abuser", "gloss": "v. n., se conjugue avec l'auxiliaire avoir"}"""

french_articles = frozenset([
	"un", "une", "le", "la", "les", "l'", "des", "du", "de", "d'",
])


def build_prompt(row):
	return f"HEADWORD: {row['headword']}\nTEXT: {row['content_plain'][:300]}"


def fetch_items(db_path, limit=None, role_filter=None, exclude_ids=None):
	conn = sqlite3.connect(db_path)
	conn.row_factory = sqlite3.Row
	cur = conn.cursor()

	if role_filter:
		query = """
			SELECT s.sense_id, s.indent_id, e.headword, s.content_plain, s.role
			FROM senses s
			JOIN entries e ON s.entry_id = e.entry_id
			WHERE s.role IN ('continuation', 'elaboration')
			ORDER BY (s.sense_id * 2654435761) % 4294967296
		"""
	else:
		query = """
			SELECT l.sense_id, s.indent_id, e.headword, s.content_plain, s.role,
				l.canonical_form
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

	if exclude_ids:
		items = [item for item in items if item["sense_id"] not in exclude_ids]

	return items


def query_ollama(model, system, user):
	response = requests.post(ollama_url, json={
		"model": model,
		"messages": [
			{"role": "system", "content": system},
			{"role": "user", "content": user},
		],
		"stream": False,
		"options": {"num_predict": 200},
	})
	response.raise_for_status()
	return response.json()["message"]["content"].strip()


def parse_json_response(raw):
	text = raw.strip()
	if text.startswith("```"):
		text = text.split("\n", 1)[1] if "\n" in text else text[3:]
		text = text.rsplit("```", 1)[0]
	try:
		return json.loads(text)
	except json.JSONDecodeError:
		return None


def strip_articles(text):
	words = text.strip().split()
	while words and words[0].lower() in french_articles:
		words = words[1:]
	return " ".join(words)


def headword_prefix(headword, min_length=4):
	head = headword.split(",")[0].strip().lower()
	return head[:max(min_length, len(head) // 2)]


def validate_decomposition(form, gloss, headword, content):
	checks = {}
	head = headword.split(",")[0].strip().lower()
	form_lower = form.lower()
	form_stripped = strip_articles(form).lower()
	prefix = headword_prefix(headword)

	checks["headword_in_form"] = (
		head in form_lower
		or prefix in form_lower
	)

	checks["not_bare_headword"] = (
		form_stripped != head
		and form_lower != head
	)

	checks["form_is_phrase"] = len(form) < len(content) * 0.7

	grammar_markers = [
		"se conjugue", "v. n.", "v. a.", "v. réfl.", "veut le",
		"régit", "se met après", "se met avant",
		"se dit aussi absolument",
	]
	checks["gloss_is_definitional"] = not any(
		m in gloss.lower() for m in grammar_markers
	)

	context_prefixes = [
		"en prose", "en droit", "en musique", "en peinture",
		"en jurisprudence", "en botanique", "en somme",
		"en mathématiques", "en physique", "en chimie",
		"en architecture", "en médecine", "en pharmacie",
		"au jeu de", "au jeu du", "aux loteries",
		"chez les", "chez quelques",
		"dans le même sens", "dans le sens",
		"en termes de", "en termes d'",
		"en parlant", "en ce sens", "en mauvaise part",
		"en bonne part", "en recevant",
	]
	checks["form_not_context"] = not any(
		form_lower.startswith(p) for p in context_prefixes
	)

	commentary_starts = [
		"mot qui", "cette locution", "on dit aussi",
		"on dit dans", "on dit de", "on dit quelquefois",
		"bon mot", "mot très", "loc.", "fig.",
		"cette expression", "cet adjectif",
		"il se dit", "il ne se dit", "on le dit",
		"on le fait", "on trouve aussi",
		"on l'a dit", "avec de et",
	]
	checks["form_not_commentary"] = not any(
		form_lower.startswith(p) for p in commentary_starts
	)

	reconstruction = form + ", " + gloss
	overlap = len(
		set(reconstruction.lower().split())
		& set(content.lower().split()[:30])
	)
	checks["reconstruction_plausible"] = overlap >= min(
		3, len(content.split()) // 2
	)

	return checks


def score_result(checks):
	passing = sum(1 for v in checks.values() if v)
	total = len(checks)
	if not checks.get("headword_in_form"):
		return "REVIEW" if passing >= total - 1 else "BAD"
	if passing == total:
		return "CLEAN"
	elif passing >= total - 1:
		return "LIKELY_OK"
	else:
		return "REVIEW"


def load_exclude_ids(path):
	ids = set()
	with open(path) as f:
		for line in f:
			line = line.strip()
			if not line:
				continue
			record = json.loads(line)
			if "sense_id" in record:
				ids.add(record["sense_id"])
	return ids


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("db_path", nargs="?", default="data/littre.db")
	parser.add_argument("--model", default="qwen2.5:72b")
	parser.add_argument("--limit", type=int, default=100)
	parser.add_argument("--all", action="store_true")
	parser.add_argument("--fallback", action="store_true",
		help="Check continuation/elaboration items instead of existing locutions")
	parser.add_argument("--output", default=None)
	parser.add_argument("--exclude", default=None,
		help="JSONL from a previous run to skip")
	args = parser.parse_args()

	model_tag = args.model.replace(":", "_").replace("/", "_")
	source = "fallback" if args.fallback else "locutions"
	output_path = args.output or f"decompose_{source}_{model_tag}.jsonl"

	exclude_ids = None
	if args.exclude:
		exclude_ids = load_exclude_ids(args.exclude)
		print(f"Excluding {len(exclude_ids)} items from {args.exclude}")

	limit = None if args.all else args.limit
	print(f"Fetching {source} from {args.db_path}...")
	items = fetch_items(
		args.db_path, limit=limit,
		role_filter=args.fallback, exclude_ids=exclude_ids,
	)
	print(f"Got {len(items)} items")
	print(f"Model: {args.model}")
	print(f"Output: {output_path}\n")

	score_counts = {}
	total_written = 0

	with open(output_path, "a", encoding="utf-8") as out:
		for i, item in enumerate(items):
			prompt = build_prompt(item)
			try:
				raw = query_ollama(args.model, system_prompt, prompt)
				parsed = parse_json_response(raw)

				if parsed and "form" in parsed and "gloss" in parsed:
					form = parsed["form"]
					gloss = parsed["gloss"]
					checks = validate_decomposition(
						form, gloss, item["headword"], item["content_plain"]
					)
					verdict = score_result(checks)
				else:
					form = ""
					gloss = ""
					checks = {}
					verdict = "PARSE_ERROR"

				score_counts[verdict] = score_counts.get(verdict, 0) + 1
				flag = "" if verdict == "CLEAN" else f"  ← {verdict}"
				print(
					f"[{i + 1}/{len(items)}] {item['indent_id'] or '?':30} "
					f"{verdict:12} {form[:45]}"
					f"{flag}"
				)

				record = {
					"sense_id": item["sense_id"],
					"indent_id": item["indent_id"],
					"headword": item["headword"],
					"content": item["content_plain"][:200],
					"form": form,
					"gloss": gloss,
					"checks": checks,
					"verdict": verdict,
				}
				out.write(json.dumps(record, ensure_ascii=False) + "\n")
				out.flush()
				total_written += 1

			except Exception as exc:
				print(f"[{i + 1}] ERROR {item['headword']}: {exc}", file=sys.stderr)
				record = {
					"sense_id": item["sense_id"],
					"indent_id": item["indent_id"],
					"headword": item["headword"],
					"content": item["content_plain"][:200],
					"form": "",
					"gloss": "",
					"checks": {},
					"verdict": f"ERROR:{exc}",
				}
				out.write(json.dumps(record, ensure_ascii=False) + "\n")
				out.flush()
				total_written += 1

	print(f"\n{'=' * 60}")
	print(f"Results ({total_written} items):")
	for verdict, count in sorted(score_counts.items(), key=lambda x: -x[1]):
		pct = 100 * count / total_written if total_written else 0
		print(f"  {verdict:15} {count:5} ({pct:.1f}%)")

	bad_items = []
	with open(output_path) as f:
		for line in f:
			r = json.loads(line)
			if r["verdict"] not in ("CLEAN", "LIKELY_OK"):
				bad_items.append(r)

	if bad_items:
		print(f"\nFlagged items ({len(bad_items)}):")
		for r in bad_items[:20]:
			failed = [k for k, v in r.get("checks", {}).items() if not v]
			print(f"  [{r['verdict']}] {r['headword']:20} form={r.get('form', '?')[:40]}")
			if failed:
				print(f"           failed: {', '.join(failed)}")
		if len(bad_items) > 20:
			print(f"  ... and {len(bad_items) - 20} more")

	print(f"\nWrote {total_written} results to {output_path}")


if __name__ == "__main__":
	main()
