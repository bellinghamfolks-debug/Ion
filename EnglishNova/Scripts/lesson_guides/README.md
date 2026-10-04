# Reviewed lesson guides

Each level JSON maps stable lesson ids to authored bilingual teaching material:

- `focusAr` / `focusEn`: a specific usage explanation, including a useful contrast or a common learner error.
- `taskAr` / `taskEn`: a short transfer task; the learner changes the context instead of merely repeating a definition.
- `exampleEn` / `exampleAr`: one possible response to that task, not the only accepted wording.
- `check`: a contextual or grammatical question, three distinct choices, one unambiguous answer, and a bilingual explanation of why it fits.
- Optional `lessonUpdates`: durable corrections to legacy lesson metadata/model sentences. Vocabulary corrections stay in their original sources or `curriculum_quality_fixes.json`.

`expand_curriculum.py` inserts the explanation into the lesson introduction,
uses the authored question in place of the generic model-sentence gap, and adds
the transfer task and its model response to the recap. This preserves the
lesson length and uses the existing accessible exercise components. The guide
text is registered in the translation dictionary for English mode.

The review ledger is in `Docs/CurriculumReview/`. A guide is not a substitute
for reviewing all the vocabulary, translations, model and extra examples in
the associated lesson. Keep the ledger honest about completed review batches.
