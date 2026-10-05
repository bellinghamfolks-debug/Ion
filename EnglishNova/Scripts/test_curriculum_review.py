#!/usr/bin/env python3
"""Regression checks for reviewed guides, assessment options and localization."""
import json
import re
import unittest
from pathlib import Path
from random import Random
from expand_curriculum import sentence_answers
from assessment_choices import equivalent_words, meaning_distractors
from lesson_guides import ROOT, TRANSLATIONS, load_guides, polished_learning_copy

class ReviewedCurriculumTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / 'EnglishNova/Resources/Curriculum/curriculum.json').read_text())
        cls.guides = load_guides()
        cls.translations = json.loads(TRANSLATIONS.read_text())
        for path in sorted(TRANSLATIONS.parent.glob('interface_en_*.json')):
            cls.translations.update(json.loads(path.read_text()))
        cls.lessons = [ls for lv in cls.catalog['levels'] for u in lv['units'] for ls in u['lessons']]

    def test_all_authored_guides_reach_the_generated_resource(self):
        self.assertEqual(360, len(self.lessons))
        for lesson in self.lessons:
            with self.subTest(lesson=lesson['id']):
                guide = self.guides[lesson['id']]
                self.assertIn(guide['focusAr'], lesson['exercises'][0]['explanationAr'])
                self.assertIn(guide['taskAr'], lesson['exercises'][-1]['explanationAr'])
                checks = [e for e in lesson['exercises'] if e.get('promptEn') == guide['check']['promptEn']]
                self.assertEqual(1, len(checks))
                self.assertEqual(guide['check']['answer'], checks[0]['answer'])
                self.assertTrue(any(re.search(rf"\b{re.escape(w['english'])}\b", lesson['modelSentence']) for w in lesson['vocabulary']))

    def test_translations_cover_rendered_curriculum_after_runtime_polish(self):
        for lesson in self.lessons:
            for exercise in lesson['exercises']:
                for field in ('promptAr', 'explanationAr', 'accessibilityHint'):
                    text = polished_learning_copy(exercise[field])
                    if re.search(r'[\u0600-\u06ff]', text):
                        with self.subTest(exercise=exercise['id'], field=field):
                            self.assertIn(text, self.translations)
                            self.assertNotEqual(text, self.translations.get(text))
            guide = self.guides[lesson['id']]
            self.assertIn(guide['focusEn'], self.translations[polished_learning_copy(lesson['exercises'][0]['explanationAr'])])
            self.assertIn(guide['taskEn'], self.translations[polished_learning_copy(lesson['exercises'][-1]['explanationAr'])])

    def test_choices_have_one_declared_answer_and_three_distinct_options(self):
        for lesson in self.lessons:
            for exercise in lesson['exercises']:
                if exercise['type'] in ('multipleChoice', 'listenAndChoose'):
                    with self.subTest(exercise=exercise['id']):
                        self.assertEqual(3, len(set(exercise['choices'])))
                        self.assertEqual(1, exercise['choices'].count(exercise['answer']))

    def test_contractions_keep_negation_and_do_not_guess_ambiguous_forms(self):
        self.assertIn("I do not agree.", sentence_answers("I don't agree."))
        self.assertNotIn("I agree.", sentence_answers("I don't agree."))
        self.assertIn("I am ready.", sentence_answers("I'm ready."))
        self.assertNotIn("She is left.", sentence_answers("She's left."))

    def test_synonym_and_gloss_overlap_are_not_meaning_distractors(self):
        words = [{'id':str(i), 'english':en, 'arabic':ar} for i,(en,ar) in enumerate([
            ('hello','مرحبًا'), ('hi','أهلًا'), ('welcome','مرحباً بالضيف'), ('book','كتاب'), ('water','ماء')])]
        self.assertEqual({'hello','hi','welcome'}, equivalent_words(words[0],words))
        self.assertEqual({'كتاب','ماء'},set(meaning_distractors(Random(1),words[0],words)))

if __name__ == '__main__':
    unittest.main()
