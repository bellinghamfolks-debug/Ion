package com.bellinghamfolks.docconverter

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

/** Serial, session-aware bilingual TTS. Language is changed only after the
 * previous segment finishes, which is reliable across Android TTS engines. */
class TtsController(
    context: Context,
    private val rate: () -> Float,
    private val onReady: (Boolean) -> Unit,
) {
    private data class Segment(val text: String, val locale: Locale)
    private data class Pending(val text: String, val generation: Long, val announce: Boolean)

    private var tts: TextToSpeech? = null
    private var ready = false
    private var pending: Pending? = null
    private val segments = ArrayDeque<Segment>()
    private val session = AtomicLong()
    @Volatile var speaking = false
        private set

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (ready) {
                val arabic = tts?.isLanguageAvailable(Locale("ar")) ?: TextToSpeech.LANG_NOT_SUPPORTED
                ready = arabic >= TextToSpeech.LANG_AVAILABLE
            }
            onReady(ready)
            if (ready) pending?.also { pending = null; submit(it) }
        }
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) { speaking = true }
            override fun onDone(id: String?) { playNext(id) }
            @Deprecated("Deprecated in Java")
            override fun onError(id: String?) { playNext(id) }
        })
    }

    fun narrate(text: String, generation: Long) = enqueue(Pending(text, generation, false))
    @Synchronized fun appendNarration(text: String, generation: Long) {
        if (!ready) { pending = Pending(text, generation, false); return }
        if (session.get() != generation) {
            session.set(generation); segments.clear(); tts?.stop(); speaking = false
        }
        segments.addAll(split(text))
        if (!speaking) { speaking = true; speakHead(generation) }
    }
    fun announce(text: String) = enqueue(Pending(text, session.incrementAndGet(), true))

    private fun enqueue(item: Pending) {
        if (item.text.isBlank()) return
        if (!ready) { pending = item; return }
        submit(item)
    }

    @Synchronized private fun submit(item: Pending) {
        session.set(item.generation)
        segments.clear()
        segments.addAll(split(item.text))
        tts?.stop()
        speaking = segments.isNotEmpty()
        speakHead(item.generation)
    }

    @Synchronized private fun playNext(id: String?) {
        val idGeneration = id?.substringBefore(':')?.toLongOrNull() ?: return
        if (idGeneration != session.get()) return
        if (segments.isNotEmpty()) segments.removeFirst()
        if (segments.isEmpty()) { speaking = false; return }
        speakHead(idGeneration)
    }

    private fun speakHead(generation: Long) {
        val segment = segments.peekFirst() ?: return
        tts?.language = segment.locale
        tts?.setSpeechRate(rate())
        val result = tts?.speak(segment.text, TextToSpeech.QUEUE_FLUSH, null, "$generation:${segments.size}")
        if (result == TextToSpeech.ERROR) { segments.clear(); speaking = false }
    }

    fun cancel() {
        session.incrementAndGet(); pending = null; segments.clear(); speaking = false; tts?.stop()
    }

    fun shutdown() { cancel(); ready = false; tts?.shutdown(); tts = null }

    private fun split(text: String): List<Segment> {
        val out = ArrayList<Segment>(); val chunk = StringBuilder(); var arabic: Boolean? = null
        fun flush() {
            val value = chunk.toString().trim()
            if (value.isNotEmpty()) out += Segment(value, if (arabic != false) Locale("ar") else Locale.ENGLISH)
            chunk.setLength(0)
        }
        for (character in text) {
            val script = when {
                character.code in 0x0600..0x06FF && character.isLetter() -> true
                character.isLetter() -> false
                else -> null
            }
            if (script != null && arabic != null && script != arabic) flush()
            if (script != null) arabic = script
            chunk.append(character)
        }
        flush()
        return out.ifEmpty { listOf(Segment(text, Locale("ar"))) }
    }
}
