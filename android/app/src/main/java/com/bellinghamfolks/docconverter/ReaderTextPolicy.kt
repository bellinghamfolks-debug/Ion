package com.bellinghamfolks.docconverter

import java.util.Locale

/** Pure, deterministic narration decisions shared by online and offline paths. */
object ReaderTextPolicy {
    fun normalize(text: String): String =
        text.replace(Regex("[\\u064B-\\u0652\\u0640]"), "")
            .replace(Regex("\\s+"), " ").trim().lowercase()

    fun similarity(a: String, b: String): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        val left = a.split(' ').filter { it.isNotBlank() }.toHashSet()
        val right = b.split(' ').filter { it.isNotBlank() }.toHashSet()
        if (left.isEmpty() || right.isEmpty()) return 0.0
        val intersection = left.count { it in right }
        val union = left.size + right.size - intersection
        return if (union == 0) 0.0 else intersection.toDouble() / union
    }

    fun isNearDuplicate(text: String, previous: String): Boolean {
        val current = normalize(text)
        val old = normalize(previous)
        if (current == old) return true
        if (old.length >= 8 && (current.contains(old) || old.contains(current))) return true
        return similarity(current, old) >= 0.6
    }

    fun dominantLocale(text: String): Locale {
        var arabic = 0
        var otherLetters = 0
        for (character in text) when {
            character.code in 0x0600..0x06FF && character.isLetter() -> arabic++
            character.isLetter() -> otherLetters++
        }
        return if (arabic >= otherLetters) Locale("ar") else Locale.ENGLISH
    }
}
