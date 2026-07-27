package com.bellinghamfolks.docconverter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class ReaderTextPolicyTest {
    @Test fun arabicDiacriticsDoNotCauseARepeat() {
        assertTrue(ReaderTextPolicy.isNearDuplicate("مَرْحَبًا بالعالم", "مرحبا بالعالم"))
    }

    @Test fun reorderedOcrWithMostlySameWordsIsDuplicate() {
        assertTrue(ReaderTextPolicy.isNearDuplicate("one two three four", "four one two three"))
    }

    @Test fun genuinelyDifferentTextIsNotDuplicate() {
        assertFalse(ReaderTextPolicy.isNearDuplicate("الباب مغلق", "الحافلة وصلت الآن"))
    }

    @Test fun dominantScriptSelectsStableVoice() {
        assertEquals(Locale("ar"), ReaderTextPolicy.dominantLocale("هذا وصف عربي مع sign"))
        assertEquals(Locale.ENGLISH, ReaderTextPolicy.dominantLocale("This is English نص"))
    }
}
