# Decomposition: adjudication guidance

Guidance version 1, 2026-09-27. Consolidates what was settled while authoring `decomposition_development_001` and `decomposition_development_002`. Records authored under this text should name it in `decision_procedure`, for instance `human/decomposition-guidance@1`; the records in those two samples carry `human/pilot` and were authored while it was being worked out.

A revision that would change an answer bumps the guidance version, not the pass version. See *Experiment provenance* in [`benchmark-regime.md`](benchmark-regime.md).

## The question

> Which stretches are cited forms, and which text, if any, glosses each?

A **form** is any stretch illustrating usage of the headword: a full sentence, a multiword expression, a collocation, a bare pronominal like *Se défendre*. A **gloss** is text defining a form.

A gloss glosses the form, not the headword. In BANQUE, `maison qui s'occupe principalement des opérations de banque` defines `Maison de banque`, so it is a gloss. In DISTINGUÉ, `Qui porte le caractère de la distinction, de l'éminence` defines the headword, and the trailing examples `Un personnage distingué.` and `Des savants distingués.` are not glossed by it, so the item is two form-only nodes with the definition as residual. The TEI carrier enforces the same line independently: `<gloss>` is admitted inside `cit` and `<def>` is not.

Roughly a third of nodes have no gloss.

Decomposition asserts that a span is cited material and that a span glosses it. It asserts nothing about what kind of thing the pair is — sub-lemma, voice variant, example, proverb, translation equivalent. That is a later stage; see [`decomposition-notes.md`](decomposition-notes.md).

## Nodes

One node per unglossed form. Several forms share a node only when they share a gloss, as in RENVERSÉ: `Un esprit renversé, une cervelle renversée, une tête renversée, un esprit, une cervelle, une tête troublée, jetée hors du sens.` is one node with three form constituents and one gloss. With no gloss, nothing binds forms together.

Elliptical coordination is one form. LIVRE's `chanter, accompagner, lire la musique à livre ouvert` expresses three locutions with only the last written out in full; the others would need discontiguous spans, which the harness can't express. Record the whole coordinated phrase as a single form, which captures the text verbatim without asserting how it distributes. This is not the RENVERSÉ shape, where each form is written out and is its own span.

A form that recurs inside commentary as a back-reference to one just cited is not marked again. In TIRER, `tirer le canon` reappears in the discussion of the construction; a further node would assert an independent attestation that is not being made.

Material belonging to another pass may sit between a form and its gloss, or between nodes. That's fine: siblings under `<sense>` carry order without requiring contiguity.

## Where a gloss ends

A gloss ends where the form is fully defined. If striking the remainder still leaves the form completely defined, the gloss was already over. In COUFIQUE, `caractères dont se servaient les Arabes avant le IVe siècle de l'hégire` fully defines `Caractères coufiques`, so the following `L'écriture coufique n'a pas de points diacritiques.` is not part of it.

The operative signal is binding, not punctuation. MORELLE's `autre variété de pomme à cidre, précoce, ronde et douceâtre` is bound to `Douce morelle d'Aumale` by apposition; the following `Ces deux pommes sont une variété de première saison` shifts subject and is bound to nothing in the block. Littré tends to begin a new sentence when the subject changes, so the sentence boundary is a correlate. The strike-the-remainder test is a proxy for binding and will fail where binding is ambiguous rather than where punctuation is.

Littré's glosses are appositive noun phrases and his unattributed examples bare fragments. An independent declarative with a finite verb doesn't fit either shape.

A gloss span includes its introducing formula: `c'est-à-dire`, `pour dire`, etc.

Trailing editorial remarks are not gloss. LAINE's `Ces deux locutions ont vieilli.` is Littré's comment and is residual.

## Residual

When uncertain whether trailing material is a form or residual, take residual. Residual under-claims and stays recoverable.

A residual may be a non-constituent fragment, including one that opens mid-sentence. DISPUTER, `1. Disputer quelqu'un, pour dire lui faire querelle, n'est pas dans le Dictionnaire de l'Académie ; mais…`, leaves `, n'est pas dans le Dictionnaire de l'Académie ; mais…` once its subject is extracted. This is expected.

A residual may also refer outside its block. MORELLE's `Ces deux pommes` has no antecedent in the block, and AMBITION's `voy. les exemples` points elsewhere in the entry. Residual is still correct.

Framing formulas and definitions share surface vocabulary. They're both residual. A _frame_ is syntactically incomplete until a form arrives and its colon is load-bearing: 
- CHEVROTER's `Il est actif aussi :`
- LIVRE's `On dit aussi en parlant de la musique :`
- TIRER's `on emploie toujours le régime direct :`

A _definition_ is a complete predication about the headword and doesn't require a form: 
- ENLEVER's `Il se dit aussi pour accaparer.`
- TIQUEUR's `Il se dit des animaux domestiques qui ont contracté un tic.` 

The test of a definition is whether the sentence says what the word means without any form following it. Nothing hinges on this while authoring, but it matters at render, and matching on `se dit` or `aussi` collapses the two. ENLEVER's `pour accaparer` has the shape of DISPUTER's `pour dire lui faire querelle` while attaching to the headword rather than to a form, so it's not a gloss.

## Negative by rule

Metalinguistic examples, and in particular forms the text reports as rejected, remain prose. Encoding attestation status is out of scope, so a block of this kind is negative, with the reason in the note. Surface cues: `on ne dit pas`, `il ne faut pas dire`, a construction reported from a named authority. Consider this indent from AMBITION:

```
Suivant Laveaux, ce mot ne régit pas les noms : on ne dit pas, l'ambition de la gloire ; mais il régit les verbes et l'on dit, l'ambition d'acquérir de la gloire. Cette règle n'est pas bonne (voy. les exemples).
```

Here, `l'ambition de la gloire` is cited as prohibited by Laveaux and `l'ambition d'acquérir de la gloire` as licensed. Then Littré overturns the prohibition; marking only the licensed form would encode the judgment Littré rejects, and the omission of the other would be unrecoverable.

A grammatical remark that cites constructions without rejecting any is positive. TIRER is two form-only nodes, as is CHEVROTER; the commentary concerns which construction is preferred where, and the forms illustrate usage of the headword.

## Selection mechanics

Selections are token ranges against the displayed target (`2-5`, `5-end`) or literal substrings. Ranges use a hyphen; a comma falls through to substring matching. Token ranges are trimmed of trailing `,;:` and whitespace, so a form does not swallow the separator after it. Terminal periods are not trimmed: a phrase ending a sentence is recorded with its period, as CHEVROTER's `chevroter un trille.` and TIRER's `tirer des bombes, des obus.` are. That is not a claim, just an artifact of selection granularity; see *Terminal punctuation* in [`decomposition-notes.md`](decomposition-notes.md).

Answer `p` only when about to enter at least one form. A positive with no forms records nothing.
