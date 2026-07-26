package com.bellinghamfolks.docconverter

import android.graphics.Bitmap
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/**
 * Global camera-motion estimation by PHASE CORRELATION (FFT-based image
 * registration).
 *
 * Given two grayscale frames it recovers the dominant translation (dx,dy)
 * between them from the single sharp peak of the inverse-transformed
 * cross-power spectrum, then measures the residual difference after
 * compensating that shift. This cleanly separates:
 *   - a slight glasses movement on the SAME content -> small/consistent shift,
 *     sharp peak, LOW aligned residual, and
 *   - a NEW screen -> no consistent shift (flat peak) / HIGH residual.
 *
 * It runs on the raw frame BEFORE any OCR, so the same decision serves the
 * online (Gemini) and offline (Tesseract/PaddleOCR) engines identically.
 * Pure Kotlin (a small radix-2 FFT) — no OpenCV dependency.
 */
object MotionEstimator {

    const val N = 128                  // power-of-two grid side for the FFT

    /** dx,dy in grid units; residual = mean |luma| diff after alignment (0..255);
     *  valid = a consistent translation was found within bounds. */
    data class Motion(val dx: Int, val dy: Int, val residual: Double, val valid: Boolean)

    // A consistent peak must stand out from the mean of the correlation surface.
    private const val PEAK_SHARP = 3.0
    // Max plausible inter-frame shift (guards against circular-FFT wraparound
    // matches). Beyond this the views are treated as unrelated.
    private val MAX_SHIFT = (N * 0.35).toInt()
    // Aligned mean-luma difference at or below this = same content (tune on device).
    const val SAME_RESIDUAL = 16.0

    /** Downscale a frame to an N×N grayscale grid for motion estimation. */
    fun grayGrid(bmp: Bitmap): FloatArray {
        val small = Bitmap.createScaledBitmap(bmp, N, N, true)
        val px = IntArray(N * N)
        small.getPixels(px, 0, N, 0, 0, N, N)
        if (small !== bmp) small.recycle()
        val g = FloatArray(N * N)
        for (i in px.indices) {
            val c = px[i]
            g[i] = 0.299f * ((c shr 16) and 0xFF) +
                0.587f * ((c shr 8) and 0xFF) +
                0.114f * (c and 0xFF)
        }
        return g
    }

    // Hann window (cached) — tapers frame edges so the big edge discontinuity
    // doesn't smear the correlation peak (spectral leakage).
    private val hann = FloatArray(N).also { w ->
        for (i in 0 until N) w[i] = (0.5 * (1.0 - cos(2.0 * Math.PI * i / (N - 1)))).toFloat()
    }

    /**
     * Phase-correlate `a` (the frame being read) with `b` (the current frame)
     * and return the shift mapping b onto a plus the aligned residual.
     */
    fun estimate(a: FloatArray, b: FloatArray): Motion {
        val re1 = FloatArray(N * N); val im1 = FloatArray(N * N)
        val re2 = FloatArray(N * N); val im2 = FloatArray(N * N)
        for (y in 0 until N) {
            val wy = hann[y]
            val row = y * N
            for (x in 0 until N) {
                val w = wy * hann[x]
                val idx = row + x
                re1[idx] = a[idx] * w
                re2[idx] = b[idx] * w
            }
        }
        fft2d(re1, im1, false)
        fft2d(re2, im2, false)
        // Cross-power spectrum R = F1 · conj(F2) / |F1 · conj(F2)|
        val cr = FloatArray(N * N); val ci = FloatArray(N * N)
        for (i in re1.indices) {
            val r = re1[i] * re2[i] + im1[i] * im2[i]     // Re(F1·conj(F2))
            val im = im1[i] * re2[i] - re1[i] * im2[i]     // Im(F1·conj(F2))
            val mag = hypot(r.toDouble(), im.toDouble()).toFloat()
            if (mag > 1e-6f) { cr[i] = r / mag; ci[i] = im / mag }
        }
        fft2d(cr, ci, true)     // inverse -> correlation surface (real part in cr)
        // Locate the peak and the mean magnitude (for sharpness).
        var peakIdx = 0; var peakVal = cr[0]; var sum = 0.0
        for (i in cr.indices) {
            val v = cr[i]
            sum += abs(v)
            if (v > peakVal) { peakVal = v; peakIdx = i }
        }
        val py = peakIdx / N; val px = peakIdx % N
        val dx = if (px > N / 2) px - N else px       // circular index -> signed shift
        val dy = if (py > N / 2) py - N else py
        val mean = sum / (N * N)
        val sharp = if (mean > 1e-9) peakVal / mean else 0.0
        if (abs(dx) > MAX_SHIFT || abs(dy) > MAX_SHIFT || sharp < PEAK_SHARP) {
            return Motion(dx, dy, 255.0, false)
        }
        return Motion(dx, dy, alignedResidual(a, b, dx, dy), true)
    }

    /** Mean absolute luma difference over the region where b, shifted by
     *  (dx,dy), overlaps a. 0 = identical content, up to 255. */
    private fun alignedResidual(a: FloatArray, b: FloatArray, dx: Int, dy: Int): Double {
        var sum = 0.0; var cnt = 0
        for (y in 0 until N) {
            val by = y + dy
            if (by < 0 || by >= N) continue
            val ar = y * N; val br = by * N
            for (x in 0 until N) {
                val bx = x + dx
                if (bx < 0 || bx >= N) continue
                sum += abs(a[ar + x] - b[br + bx])
                cnt++
            }
        }
        return if (cnt == 0) 255.0 else sum / cnt
    }

    // ---- Radix-2 FFT: rows then columns, in place -------------------------
    private fun fft2d(re: FloatArray, im: FloatArray, inverse: Boolean) {
        val lineRe = FloatArray(N); val lineIm = FloatArray(N)
        for (y in 0 until N) {                 // rows
            val off = y * N
            System.arraycopy(re, off, lineRe, 0, N)
            System.arraycopy(im, off, lineIm, 0, N)
            fft1d(lineRe, lineIm, inverse)
            System.arraycopy(lineRe, 0, re, off, N)
            System.arraycopy(lineIm, 0, im, off, N)
        }
        for (x in 0 until N) {                 // columns
            for (y in 0 until N) { lineRe[y] = re[y * N + x]; lineIm[y] = im[y * N + x] }
            fft1d(lineRe, lineIm, inverse)
            for (y in 0 until N) { re[y * N + x] = lineRe[y]; im[y * N + x] = lineIm[y] }
        }
        if (inverse) {
            val s = 1f / (N * N)
            for (i in re.indices) { re[i] *= s; im[i] *= s }
        }
    }

    private fun fft1d(re: FloatArray, im: FloatArray, inverse: Boolean) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {                 // bit-reversal permutation
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j or bit
            if (i < j) {
                val tr = re[i]; re[i] = re[j]; re[j] = tr
                val ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var len = 2
        while (len <= n) {
            val ang = (if (inverse) 2.0 else -2.0) * Math.PI / len
            val wr = cos(ang).toFloat(); val wi = sin(ang).toFloat()
            var i = 0
            while (i < n) {
                var curR = 1f; var curI = 0f
                val half = len / 2
                for (k in 0 until half) {
                    val ia = i + k; val ib = ia + half
                    val vr = re[ib] * curR - im[ib] * curI
                    val vi = re[ib] * curI + im[ib] * curR
                    re[ib] = re[ia] - vr; im[ib] = im[ia] - vi
                    re[ia] += vr; im[ia] += vi
                    val ncR = curR * wr - curI * wi
                    curI = curR * wi + curI * wr
                    curR = ncR
                }
                i += len
            }
            len = len shl 1
        }
    }
}
