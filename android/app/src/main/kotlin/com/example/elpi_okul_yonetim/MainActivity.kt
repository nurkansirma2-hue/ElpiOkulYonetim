package com.example.elpi_okul_yonetim

import android.Manifest
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.ContactsContract
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var driveBelgeChannel: DriveBelgeChannel? = null

    companion object {
        private const val SMS_IZIN_KODU = 7104
        // Drive yetkilendirmesi 7105 kullanır; sonuçlar birbirine yönlenmemeli.
        private const val REHBER_TELEFON_KODU = 7106
        private const val CHANNEL = "elpi_okul_yonetim/dosya_secici"
        private const val KLASOR_SEC_REQUEST_CODE = 7001
        private const val IMPORT_DOSYA_SEC_REQUEST_CODE = 7002
        private const val YEDEK_KAYDET_REQUEST_CODE = 7003

        private const val PREFS_NAME = "elpi_dosya_secici"
        private const val PREF_KOK_KLASOR_URI = "kok_klasor_uri"
    }

    private var bekleyenRehberSonucu: MethodChannel.Result? = null
    private var bekleyenSmsIzni: MethodChannel.Result? = null
    private var bekleyenKlasorSecimSonucu: MethodChannel.Result? = null
    private var bekleyenDosyaSecimSonucu: MethodChannel.Result? = null
    private var bekleyenYedekSonucu: MethodChannel.Result? = null
    private var bekleyenYedekDosyasi: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DbfKaynakChannel.register(this, flutterEngine)
        RehberlikOcrChannel.register(flutterEngine)
        driveBelgeChannel = DriveBelgeChannel(this, flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "elpi_okul_yonetim/google_form").setMethodCallHandler { call, result ->
            if (call.method != "ac") {
                result.notImplemented()
            } else {
                try {
                    val uri = Uri.parse(call.argument<String>("adres") ?: "")
                    require(uri.scheme == "https" && uri.host == "docs.google.com"
                        && uri.path.orEmpty().startsWith("/forms/"))
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("FORM_ACILAMADI", "Google Form açılamadı.", e.toString())
                }
            }
        }

        okulYonetimImportKlasorunuHazirla()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "elpi_okul_yonetim/mesajlasma").setMethodCallHandler { call, result ->
            when (call.method) {
                "rehberTelefonSec" -> rehberTelefonSec(result)
                "whatsappAc" -> whatsappAc(call, result)
                "smsIzni" -> smsIzni(result)
                "smsGonder" -> smsGonder(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "kokKlasorSec" -> kokKlasorSec(result)
                "kayitliKokKlasoruGetir" -> kayitliKokKlasoruGetir(result)
                "klasorListele" -> klasorListele(call, result)
                "dosyaOku" -> dosyaOku(call, result)
                "importDosyasiSec" -> importDosyasiSec(result)
                "belgePaylas" -> belgePaylas(call, result)
                "bakimYedegiKaydet" -> bakimYedegiKaydet(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun rehberTelefonSec(result: MethodChannel.Result) {
        if (bekleyenRehberSonucu != null) {
            result.error("REHBER_BEKLIYOR", "Rehber seçimi devam ediyor.", null)
            return
        }
        try {
            bekleyenRehberSonucu = result
            // Kullanıcı tek bir telefon satırı seçer; tüm rehberi okuma izni istenmez.
            startActivityForResult(
                Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI),
                REHBER_TELEFON_KODU
            )
        } catch (e: Exception) {
            bekleyenRehberSonucu = null
            result.error("REHBER_ACILAMADI", "Telefon rehberi açılamadı.", e.javaClass.simpleName)
        }
    }

    override fun onDestroy() {
        bekleyenRehberSonucu?.error("REHBER_KAPANDI", "Rehber seçimi tamamlanamadı; yeniden deneyin.", null)
        bekleyenRehberSonucu = null
        super.onDestroy()
    }

    private fun smsIzinleriTamam(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED &&
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED

    private fun smsIzni(result: MethodChannel.Result) {
        if (smsIzinleriTamam()) {
            result.success(true)
            return
        }
        if (bekleyenSmsIzni != null) {
            result.error("SMS_IZIN_BEKLIYOR", "SMS izni isteği devam ediyor.", null)
            return
        }
        val eksikler = listOf(Manifest.permission.SEND_SMS, Manifest.permission.READ_PHONE_STATE)
            .filter {
                ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
            }
        bekleyenSmsIzni = result
        ActivityCompat.requestPermissions(this, eksikler.toTypedArray(), SMS_IZIN_KODU)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_IZIN_KODU) {
            // Android yanıtında izinlerin sırasına dayanma; gerçek durumu denetle.
            bekleyenSmsIzni?.success(smsIzinleriTamam())
            bekleyenSmsIzni = null
        }
    }

    private fun smsGonder(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (!smsIzinleriTamam()) {
                result.error("SMS_IZIN_YOK",
                    "SMS ve Telefon izinlerini uygulama ayarlarından etkinleştirin.", null)
                return
            }
            if (!packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)) {
                result.error("SMS_DESTEKLENMIYOR",
                    "Bu cihaz SIM üzerinden SMS göndermeyi desteklemiyor.", null)
                return
            }
            val telefon = call.argument<String>("telefon") ?: ""
            val metin = call.argument<String>("metin") ?: ""
            require(Regex("^[1-9][0-9]{7,14}$").matches(telefon) &&
                metin.isNotBlank() && metin.length <= 4000) { "SMS alıcısı veya metni geçersiz." }
            // Kullanıcının Android ayarlarında belirlediği varsayılan SMS SIM'ini kullan.
            val subscriptionId = SubscriptionManager.getDefaultSmsSubscriptionId()
            if (subscriptionId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                result.error("SMS_SIM_SECIMI",
                    "Telefon ayarlarından varsayılan SMS SIM hattını seçin.", null)
                return
            }
            val sms = if (Build.VERSION.SDK_INT >= 31)
                getSystemService(SmsManager::class.java).createForSubscriptionId(subscriptionId)
            else @Suppress("DEPRECATION") SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
            val parts = sms.divideMessage(metin)
            // İşlemin istenmesi teslim kanıtı değildir; hatada otomatik yeniden gönderme yok.
            if (parts.size == 1) sms.sendTextMessage(telefon, null, metin, null, null)
            else sms.sendMultipartTextMessage(telefon, null, parts, null, null)
            result.success(mapOf("durum" to "Istendi", "parca" to parts.size))
        } catch (e: SecurityException) {
            // Bazı cihazlarda SIM altyapısı ek korumalı telefon kimliği sorgulayabilir.
            // İleti kısmen iletilmiş olabileceğinden otomatik yeniden gönderme yapma.
            result.error("SMS_TELEFON_YETKISI",
                "Android SIM bilgisine erişimi engelledi. SMS sonucunu telefondan kontrol edin.",
                e.toString())
        } catch (e: Exception) {
            result.error("SMS_GONDERIM_HATASI", "SMS gönderim isteği başarısız.", e.toString())
        }
    }

    private fun whatsappAc(call: MethodCall, result: MethodChannel.Result) {
        try {
            val telefon = call.argument<String>("telefon") ?: ""
            val metin = call.argument<String>("metin") ?: ""
            require(Regex("^[1-9][0-9]{7,14}$").matches(telefon) &&
                metin.isNotBlank() && metin.length <= 4000) { "Alıcı veya mesaj geçersiz." }
            val uri = Uri.Builder().scheme("https").authority("wa.me")
                .appendPath(telefon).appendQueryParameter("text", metin).build()
            // Tarayıcıya sessizce düşülmez. İki WhatsApp da varsa kullanıcı seçer.
            val intents = listOf("com.whatsapp", "com.whatsapp.w4b").mapNotNull { paket ->
                val intent = Intent(Intent.ACTION_VIEW, uri).setPackage(paket)
                if (intent.resolveActivity(packageManager) != null) intent else null
            }
            if (intents.isEmpty()) throw ActivityNotFoundException("WhatsApp veya WhatsApp Business kurulu değil.")
            if (intents.size == 1) startActivity(intents.first())
            else startActivity(Intent.createChooser(intents.first(), "WhatsApp seçin")
                .putExtra(Intent.EXTRA_INITIAL_INTENTS, intents.drop(1).toTypedArray()))
            // Yalnız açma sonucu; mesajın gönderildiği anlamına gelmez.
            result.success(null)
        } catch (e: Exception) {
            result.error("WHATSAPP_ACILAMADI", "WhatsApp açılamadı.", e.toString())
        }
    }

    private fun bakimYedegiKaydet(call: MethodCall, result: MethodChannel.Result) {
        if (bekleyenYedekSonucu != null) {
            result.error("YEDEK_SURUYOR", "Yedek kaydetme işlemi sürüyor.", null)
            return
        }
        try {
            val kaynak = File(call.argument<String>("yol") ?: "").canonicalFile
            require(kaynak.parentFile == File(filesDir, "bakim_yedekleri").canonicalFile &&
                kaynak.isFile && kaynak.extension == "zip") { "Yedek dosyası geçersiz." }
            bekleyenYedekSonucu = result
            bekleyenYedekDosyasi = kaynak
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(Intent.EXTRA_TITLE, kaynak.name)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            startActivityForResult(intent, YEDEK_KAYDET_REQUEST_CODE)
        } catch (e: Exception) {
            bekleyenYedekSonucu = null
            bekleyenYedekDosyasi = null
            result.error("YEDEK_SECIM_HATASI", "Yedek konumu açılamadı.", e.toString())
        }
    }

    private fun belgePaylas(call: MethodCall, result: MethodChannel.Result) {
        try {
            val kaynak = File(call.argument<String>("yol") ?: "").canonicalFile
            val izinli = File(cacheDir, "belge_goruntuleme").canonicalFile
            require(kaynak.parentFile == izinli && kaynak.isFile) {
                "Yalnız hazırlanmış belge kopyası paylaşılabilir."
            }
            val ad = call.argument<String>("ad") ?: kaynak.name
            require(ad.isNotBlank() && ad.length <= 240 && !ad.contains('/') &&
                !ad.contains('\\') && ad.none { it.code < 32 }) { "Dosya adı geçersiz." }
            val klasor = File(cacheDir, "belge_paylasim")
            require(klasor.mkdirs() || klasor.isDirectory)
            // Paylaşım alıcısı asıl arşive erişemez. Önceki kopyalar bir gün
            // korunur; alıcı dosyayı okurken hemen silinmez.
            klasor.listFiles()?.filter { it.isFile &&
                System.currentTimeMillis() - it.lastModified() > 86400000L }
                ?.forEach { it.delete() }
            val hedef = File(klasor, ad)
            kaynak.copyTo(hedef, overwrite = true)
            val uri = FileProvider.getUriForFile(this,
                "$packageName.fileProvider.com.crazecoder.openfile", hedef)
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(
                hedef.extension.lowercase()) ?: "application/octet-stream"
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TITLE, ad)
                clipData = ClipData.newRawUri(ad, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Belgeyi paylaş"))
            result.success(null)
        } catch (e: Exception) {
            result.error("BELGE_PAYLASIM_HATASI", "Belge paylaşılamadı.", e.toString())
        }
    }

    private fun okulYonetimImportKlasorunuHazirla() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return
        }

        try {
            val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/OkulYonetim/"
            val dosyaAdi = "README.txt"
            val collection = MediaStore.Downloads.getContentUri(
                MediaStore.VOLUME_EXTERNAL_PRIMARY
            )

            val mevcutVar = contentResolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
                    "${MediaStore.MediaColumns.DISPLAY_NAME} = ?",
                arrayOf(relativePath, dosyaAdi),
                null
            )?.use { cursor ->
                cursor.moveToFirst()
            } ?: false

            if (mevcutVar) {
                return
            }

            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, dosyaAdi)
                put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val uri = contentResolver.insert(collection, values)
                ?: throw Exception(
                    "Download/OkulYonetim klasörü için README.txt oluşturulamadı."
                )

            try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    output.write(
                        (
                            "Elpi Okul Yönetim import klasörü.\n" +
                                "Öğrenci, fotoğraf, ders programı ve yıllık plan " +
                                "dosyalarınızı bu klasörde tutabilirsiniz.\n"
                            ).toByteArray(Charsets.UTF_8)
                    )
                } ?: throw Exception("README.txt dosyasına yazılamadı.")

                val tamamlandi = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }

                contentResolver.update(
                    uri,
                    tamamlandi,
                    null,
                    null
                )
            } catch (e: Exception) {
                contentResolver.delete(uri, null, null)
                throw e
            }
        } catch (e: Exception) {
            Log.w(
                "ElpiOkulYonetim",
                "Download/OkulYonetim klasörü hazırlanamadı. Orijinal hata: $e",
                e
            )
        }
    }

    private fun kokKlasorSec(result: MethodChannel.Result) {
        if (bekleyenKlasorSecimSonucu != null) {
            result.error(
                "KLASOR_SECIMI_DEVAM_EDIYOR",
                "Başka bir klasör seçme işlemi halen devam ediyor.",
                null
            )
            return
        }

        try {
            bekleyenKlasorSecimSonucu = result

            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }

            startActivityForResult(intent, KLASOR_SEC_REQUEST_CODE)
        } catch (e: Exception) {
            bekleyenKlasorSecimSonucu = null

            result.error(
                "KLASOR_SECIM_HATASI",
                "Ana klasör seçilirken hata oluştu.",
                e.toString()
            )
        }
    }

    private fun importDosyasiSec(result: MethodChannel.Result) {
        if (bekleyenDosyaSecimSonucu != null) {
            result.error(
                "DOSYA_SECIMI_DEVAM_EDIYOR",
                "Başka bir dosya seçme işlemi halen devam ediyor.",
                null
            )
            return
        }

        try {
            bekleyenDosyaSecimSonucu = result

            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"

                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "application/msword",
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                        "application/vnd.ms-excel",
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                    )
                )

                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            startActivityForResult(
                intent,
                IMPORT_DOSYA_SEC_REQUEST_CODE
            )
        } catch (e: Exception) {
            bekleyenDosyaSecimSonucu = null

            result.error(
                "DOSYA_SECIM_HATASI",
                "Import dosyası seçilirken hata oluştu.",
                e.toString()
            )
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (driveBelgeChannel?.sonucuAl(requestCode, resultCode, data) == true) return

        when (requestCode) {
            REHBER_TELEFON_KODU -> {
                val sonuc = bekleyenRehberSonucu ?: return
                bekleyenRehberSonucu = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    sonuc.success(null)
                    return
                }
                try {
                    require(uri.scheme == "content")
                    val kolon = ContactsContract.CommonDataKinds.Phone.NUMBER
                    val telefon = contentResolver.query(uri, arrayOf(kolon), null, null, null)?.use { c ->
                        if (c.moveToFirst()) c.getString(c.getColumnIndexOrThrow(kolon)) else null
                    }
                    require(!telefon.isNullOrBlank() && telefon.length <= 50)
                    sonuc.success(telefon)
                } catch (e: Exception) {
                    sonuc.error("REHBER_OKUNAMADI", "Seçilen telefon numarası okunamadı.", e.javaClass.simpleName)
                }
            }
            YEDEK_KAYDET_REQUEST_CODE -> {
                val sonuc = bekleyenYedekSonucu ?: return
                val kaynak = bekleyenYedekDosyasi
                bekleyenYedekSonucu = null
                bekleyenYedekDosyasi = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    sonuc.success(null)
                    return
                }
                // Büyük yedekleri byte[] olarak kanaldan taşımadan akışla yaz.
                Thread {
                    try {
                        require(kaynak != null && kaynak.isFile)
                        val output = contentResolver.openOutputStream(uri, "w")
                            ?: throw Exception("Hedef dosya yazılamadı.")
                        output.use { target -> kaynak.inputStream().use { it.copyTo(target) } }
                        runOnUiThread { sonuc.success(uri.toString()) }
                    } catch (e: Exception) {
                        runOnUiThread { sonuc.error("YEDEK_YAZMA_HATASI",
                            "Yedek kaydedilemedi; yerel kopya korunuyor.", e.toString()) }
                    }
                }.start()
            }


            KLASOR_SEC_REQUEST_CODE -> {
                val flutterResult = bekleyenKlasorSecimSonucu
                bekleyenKlasorSecimSonucu = null

                if (flutterResult == null) {
                    return
                }

                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    flutterResult.success(null)
                    return
                }

                try {
                    val uri = data.data!!
                    val readFlag =
                        data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION

                    if (readFlag != 0) {
                        contentResolver.takePersistableUriPermission(
                            uri,
                            readFlag
                        )
                    }

                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                        .edit()
                        .putString(PREF_KOK_KLASOR_URI, uri.toString())
                        .apply()

                    flutterResult.success(
                        klasorBilgisiOlustur(uri)
                    )
                } catch (e: Exception) {
                    flutterResult.error(
                        "KLASOR_KAYIT_HATASI",
                        "Seçilen klasör erişimi kaydedilirken hata oluştu.",
                        e.toString()
                    )
                }
            }

            IMPORT_DOSYA_SEC_REQUEST_CODE -> {
                val flutterResult = bekleyenDosyaSecimSonucu
                bekleyenDosyaSecimSonucu = null

                if (flutterResult == null) {
                    return
                }

                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    flutterResult.success(null)
                    return
                }

                try {
                    val uri = data.data!!

                    var dosyaAdi = "Seçilen Dosya"
                    var dosyaBoyutu = 0L

                    contentResolver.query(
                        uri,
                        arrayOf(
                            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                            DocumentsContract.Document.COLUMN_SIZE
                        ),
                        null,
                        null,
                        null
                    )?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val adIndex = cursor.getColumnIndex(
                                DocumentsContract.Document.COLUMN_DISPLAY_NAME
                            )

                            val boyutIndex = cursor.getColumnIndex(
                                DocumentsContract.Document.COLUMN_SIZE
                            )

                            if (adIndex >= 0 && !cursor.isNull(adIndex)) {
                                dosyaAdi =
                                    cursor.getString(adIndex) ?: dosyaAdi
                            }

                            if (boyutIndex >= 0 &&
                                !cursor.isNull(boyutIndex)
                            ) {
                                dosyaBoyutu =
                                    cursor.getLong(boyutIndex)
                            }
                        }
                    }

                    val bytes =
                        contentResolver.openInputStream(uri)?.use { input ->
                            input.readBytes()
                        }

                    if (bytes == null || bytes.isEmpty()) {
                        flutterResult.error(
                            "DOSYA_OKUNAMADI",
                            "Seçilen import dosyasının içeriği okunamadı.",
                            null
                        )
                        return
                    }

                    flutterResult.success(
                        mapOf(
                            "ad" to dosyaAdi,
                            "boyut" to dosyaBoyutu,
                            "bytes" to bytes
                        )
                    )
                } catch (e: Exception) {
                    flutterResult.error(
                        "DOSYA_OKUMA_HATASI",
                        "Seçilen import dosyası okunurken hata oluştu.",
                        e.toString()
                    )
                }
            }
        }
    }

    private fun kayitliKokKlasoruGetir(result: MethodChannel.Result) {
        try {
            val uriMetni = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getString(PREF_KOK_KLASOR_URI, null)

            if (uriMetni.isNullOrBlank()) {
                result.success(null)
                return
            }

            val uri = Uri.parse(uriMetni)

            val izinVar = contentResolver.persistedUriPermissions.any { izin ->
                izin.uri == uri && izin.isReadPermission
            }

            if (!izinVar) {
                getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    .edit()
                    .remove(PREF_KOK_KLASOR_URI)
                    .apply()

                result.success(null)
                return
            }

            result.success(klasorBilgisiOlustur(uri))
        } catch (e: Exception) {
            result.error(
                "KOK_KLASOR_OKUMA_HATASI",
                "Kayıtlı ana klasör bilgisi okunurken hata oluştu.",
                e.toString()
            )
        }
    }

    private fun klasorListele(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            val uriMetni = call.argument<String>("uri")
                ?: getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    .getString(PREF_KOK_KLASOR_URI, null)

            if (uriMetni.isNullOrBlank()) {
                result.error(
                    "KOK_KLASOR_YOK",
                    "Önce bir ana klasör seçilmelidir.",
                    null
                )
                return
            }

            val klasorUri = Uri.parse(uriMetni)
            val documentId = klasorDocumentIdGetir(klasorUri)

            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                klasorUri,
                documentId
            )

            val kolonlar = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
            )

            val liste = mutableListOf<Map<String, Any?>>()

            contentResolver.query(
                childrenUri,
                kolonlar,
                null,
                null,
                null
            )?.use { cursor ->
                val documentIdIndex = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID
                )
                val displayNameIndex = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME
                )
                val mimeTypeIndex = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_MIME_TYPE
                )
                val sizeIndex = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_SIZE
                )
                val lastModifiedIndex = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED
                )

                while (cursor.moveToNext()) {
                    if (documentIdIndex < 0) {
                        continue
                    }

                    val childDocumentId = cursor.getString(documentIdIndex)
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(
                        klasorUri,
                        childDocumentId
                    )

                    val ad = if (displayNameIndex >= 0 && !cursor.isNull(displayNameIndex)) {
                        cursor.getString(displayNameIndex) ?: "Adsız"
                    } else {
                        "Adsız"
                    }

                    val mimeType = if (mimeTypeIndex >= 0 && !cursor.isNull(mimeTypeIndex)) {
                        cursor.getString(mimeTypeIndex) ?: ""
                    } else {
                        ""
                    }

                    val klasorMu = mimeType == DocumentsContract.Document.MIME_TYPE_DIR

                    val boyut = if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        cursor.getLong(sizeIndex)
                    } else {
                        0L
                    }

                    val degistirilme = if (
                        lastModifiedIndex >= 0 &&
                        !cursor.isNull(lastModifiedIndex)
                    ) {
                        cursor.getLong(lastModifiedIndex)
                    } else {
                        0L
                    }

                    liste.add(
                        mapOf(
                            "ad" to ad,
                            "uri" to childUri.toString(),
                            "klasorMu" to klasorMu,
                            "mimeType" to mimeType,
                            "boyut" to boyut,
                            "degistirilmeZamani" to degistirilme
                        )
                    )
                }
            }

            val siraliListe = liste.sortedWith(
                compareBy<Map<String, Any?>> {
                    !(it["klasorMu"] as? Boolean ?: false)
                }.thenBy {
                    (it["ad"] ?: "").toString().lowercase()
                }
            )

            result.success(siraliListe)
        } catch (e: Exception) {
            result.error(
                "KLASOR_LISTELEME_HATASI",
                "Klasör içeriği listelenirken hata oluştu.",
                e.toString()
            )
        }
    }

    private fun dosyaOku(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            val uriMetni = call.argument<String>("uri")

            if (uriMetni.isNullOrBlank()) {
                result.error(
                    "DOSYA_URI_YOK",
                    "Okunacak dosyanın URI bilgisi bulunamadı.",
                    null
                )
                return
            }

            val uri = Uri.parse(uriMetni)
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                input.readBytes()
            }

            if (bytes == null || bytes.isEmpty()) {
                result.error(
                    "DOSYA_OKUNAMADI",
                    "Seçilen dosyanın içeriği okunamadı.",
                    null
                )
                return
            }

            result.success(bytes)
        } catch (e: Exception) {
            result.error(
                "DOSYA_OKUMA_HATASI",
                "Seçilen dosya okunurken hata oluştu.",
                e.toString()
            )
        }
    }

    private fun klasorDocumentIdGetir(uri: Uri): String {
        return try {
            DocumentsContract.getDocumentId(uri)
        } catch (_: IllegalArgumentException) {
            DocumentsContract.getTreeDocumentId(uri)
        }
    }

    private fun klasorBilgisiOlustur(uri: Uri): Map<String, Any?> {
        var ad = "Seçili Klasör"

        try {
            val documentId = klasorDocumentIdGetir(uri)
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                uri,
                documentId
            )

            contentResolver.query(
                documentUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME
                    )

                    if (index >= 0 && !cursor.isNull(index)) {
                        ad = cursor.getString(index) ?: ad
                    }
                }
            }
        } catch (_: Exception) {
            // URI geçerli olduğu sürece klasör adının okunamaması
            // klasör erişimini engellemez.
        }

        return mapOf(
            "ad" to ad,
            "uri" to uri.toString()
        )
    }
}
