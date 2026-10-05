"""Avoid equivalent meanings among the options of vocabulary checks.

This conservative filter supplements the hand-authored lesson assessments.
Arabic gloss overlap is intentionally conservative: a different distractor is
preferable to a potentially defensible second answer.
"""
import re
import unicodedata

FAMILIES = [
    {'hello', 'hi', 'hey'}, {'bye', 'goodbye', 'see you'},
    {'thanks', 'thank you'}, {'near', 'nearby', 'close', 'close to'},
    {'deadline', 'due date'}, {'grade', 'mark', 'score'},
    {'begin', 'start'}, {'end', 'finish'}, {'big', 'large'},
    {'small', 'little'}, {'quick', 'fast', 'rapid'},
    {'happy', 'glad', 'pleased'}, {'job', 'work'},
    {'house', 'home'}, {'ill', 'sick', 'unwell'},
    {'buy', 'purchase'}, {'cost', 'price'}, {'choose', 'select'},
    {'speak', 'talk'}, {'reply', 'respond', 'answer'},
    {'allow', 'permit'}, {'repair', 'fix'}, {'help', 'assist'},
    {'claim', 'assert', 'contend'}, {'show', 'demonstrate'},
    {'proof', 'evidence'}, {'substantiate', 'corroborate', 'verify'},
    {'disadvantage', 'drawback', 'downside'}, {'benefit', 'advantage'},
]
STOP = {'في','من','على','عن','الى','إلى','مع','هو','هي','لا','ان','أن','و','او','أو','ما','غير','شيء','شخص'}


def gloss_tokens(value):
    value = ''.join(c for c in unicodedata.normalize('NFD', value) if unicodedata.category(c) != 'Mn')
    value = value.replace('أ','ا').replace('إ','ا').replace('آ','ا')
    return {t.removeprefix('ال') for t in re.findall(r'[\u0621-\u064a]+', value) if t not in STOP and len(t) > 1}


def equivalent_words(word, words):
    english = word['english'].casefold()
    family = {english}
    for group in FAMILIES:
        if english in group:
            family |= group
    tokens = gloss_tokens(word['arabic'])
    return {w['english'] for w in words if w['english'].casefold() in family or tokens & gloss_tokens(w['arabic'])}


def meaning_distractors(rng, word, words):
    excluded = equivalent_words(word, words)
    candidates = list(dict.fromkeys(w['arabic'] for w in words if w['english'] not in excluded and w['arabic'] != word['arabic']))
    rng.shuffle(candidates)
    if len(candidates) < 2:
        raise ValueError(f"Not enough unambiguous meaning choices for {word['id']}")
    return candidates[:2]
