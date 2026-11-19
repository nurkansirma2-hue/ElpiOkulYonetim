package com.example.elpi_okul_yonetim

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Yalnız bellek içi bitmapler. Görsel, sonuç ve öğrenci bilgileri dosyaya/loga yazılmaz. */
object RehberlikOcrChannel {
    fun register(engine: FlutterEngine) {
        val busy = AtomicBoolean(false)
        val main = Handler(Looper.getMainLooper())
        MethodChannel(engine.dartExecutor.binaryMessenger,
            "elpi_okul_yonetim/rehberlik_ocr").setMethodCallHandler { call, result ->
            if (call.method != "oku") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (!busy.compareAndSet(false, true)) {
                result.error("OCR_MESGUL", "Önceki görsel okuma işlemi sürüyor.", null)
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val corners = call.argument<List<Number>>("koseler")
            val regions = call.argument<List<Map<String, Any>>>("alanlar")
            Thread {
                var source: Bitmap? = null
                var flat: Bitmap? = null
                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                try {
                    require(bytes != null && bytes.isNotEmpty() && bytes.size <= 20 * 1024 * 1024) {
                        "Görsel boş veya 20 MB sınırından büyük."
                    }
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    require(bounds.outWidth > 0 && bounds.outHeight > 0 &&
                        bounds.outWidth.toLong() * bounds.outHeight <= 8_000_000) {
                        "Görsel boyutları geçersiz."
                    }
                    require(corners != null && corners.size == 8 && corners.all {
                        it.toDouble().isFinite() && it.toDouble() in 0.0..1.0
                    }) { "Formun dört köşesini seçin." }
                    val points = corners.map { it.toFloat() }
                    val cross = (0..3).map { i ->
                        val a = i * 2; val b = ((i + 1) % 4) * 2; val c = ((i + 2) % 4) * 2
                        (points[b] - points[a]) * (points[c+1] - points[b+1]) -
                            (points[b+1] - points[a+1]) * (points[c] - points[b])
                    }
                    require(cross.all { it > 0.015f }) { "Köşeler saat yönünde ve birbirinden ayrı olmalı." }
                    require(regions != null && regions.size in 1..50)
                    val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        ?: throw IllegalArgumentException("Görsel çözülemedi.")
                    source = decoded
                    val matrix = Matrix()
                    val from = FloatArray(8) { i -> points[i] * if (i % 2 == 0) decoded.width else decoded.height }
                    require(matrix.setPolyToPoly(from, 0,
                        floatArrayOf(0f, 360f, 1600f, 360f, 1600f, 2360f, 0f, 2360f), 0, 4))
                    // Tablonun üstündeki tarih için 360 px başlık payı.
                    val rectified = Bitmap.createBitmap(1600, 2360, Bitmap.Config.ARGB_8888)
                    flat = rectified
                    Canvas(rectified).apply {
                        drawColor(Color.WHITE)
                        drawBitmap(decoded, matrix, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
                    }
                    val output = mutableMapOf<String, String>()
                    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(120)
                    for (region in regions) {
                        check(System.nanoTime() < deadline) { "Görsel okuma zaman aşımına uğradı." }
                        val id = region["id"] as? String ?: error("Alan kimliği eksik.")
                        val box = (region["kutu"] as? List<*>)?.map { (it as Number).toFloat() }
                            ?: error("Alan sınırları eksik.")
                        require(box.size == 4 && box.all { it.isFinite() } &&
                            box[0] in 0f..1f && box[2] in 0f..1f &&
                            box[1] in -0.18f..1f && box[3] in -0.18f..1f &&
                            box[2] > box[0] && box[3] > box[1] && !output.containsKey(id))
                        val x = (box[0] * 1600).toInt(); val y = (360 + box[1] * 2000).toInt()
                        val w = ((box[2] - box[0]) * 1600).toInt().coerceAtLeast(1)
                        val h = ((box[3] - box[1]) * 2000).toInt().coerceAtLeast(1)
                        val cell = Bitmap.createBitmap(rectified, x, y, w.coerceAtMost(1600-x), h.coerceAtMost(2360-y))
                        try {
                            output[id] = Tasks.await(recognizer.process(InputImage.fromBitmap(cell, 0)),
                                10, TimeUnit.SECONDS).text
                        } finally { cell.recycle() }
                    }
                    main.post { result.success(output) }
                } catch (e: Exception) {
                    main.post { result.error("FORM_OKUNAMADI", "Öğrenci formu okunamadı.", e.toString()) }
                } finally {
                    recognizer.close()
                    flat?.recycle()
                    source?.recycle()
                    busy.set(false)
                }
            }.start()
        }
    }
}
