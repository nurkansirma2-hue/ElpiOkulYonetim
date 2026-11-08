import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'bireysel_belge_service.dart';
import 'bireysel_rehberlik_service.dart';

class RehberlikBelgeService {
  static Future<Uint8List> pdfOlustur(
    BireyselRehberlikBaglami b,
    String sinif,
    Map<String, Object?> kayit,
  ) async {
    if (kayit['Hassas'] == 1) {
      throw StateError('Hassas kayıtlar genel belge çıktısına eklenmez.');
    }
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final pdf = pw.Document();
    final veri = Map<String, Object?>.from(
      jsonDecode(kayit['Icerik'] as String) as Map,
    );
    const adlar = {
      'toplantiTuru': 'Toplantı türü',
      'yer': 'Yer',
      'saat': 'Saat',
      'gundem': 'Gündem',
      'katilim': 'Katılım',
      'tutanak': 'Tutanak',
      'kararlar': 'Kararlar',
      'takip': 'Takip',
      'aciklama': 'Açıklama',
      'sorumlu': 'Sorumlu',
      'sonuc': 'Sonuç',
      'hafta': 'Hafta',
      'tarih': 'Plan tarihi',
      'konu': 'Konu',
    };
    final satirlar = <String>[
      '${b.okulAdi}\n${b.egitimOgretimYili} • $sinif',
      '${rehberlikTurleri[kayit['Tur']]} • ${kayit['Baslik']}',
      'Tarih: ${kayit['Tarih'] ?? 'Belirtilmedi'}',
      for (final e in adlar.entries)
        if ((veri[e.key] ?? '').toString().trim().isNotEmpty)
          '${e.value}\n${veri[e.key]}',
      'Sınıf rehber öğretmeni: ${b.ogretmenAdi}\nİmza: __________________',
    ];
    // Uzun tutanaklar küçük paragraflara ayrılır; tek blok sayfayı aşmaz.
    final paragraflar = <String>[];
    for (final s in satirlar) {
      for (final line in s.split('\n')) {
        for (var i = 0; i < line.length; i += 300) {
          paragraflar.add(
            line.substring(i, i + 300 > line.length ? line.length : i + 300),
          );
        }
      }
    }
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 200,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        footer: (c) => pw.Text(
          'Sınıf Rehberliğim • ${c.pageNumber}/${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        build: (_) => [
          for (final s in paragraflar)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(s, style: const pw.TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<String> arsiveKaydet(
    BireyselRehberlikService service,
    BireyselRehberlikBaglami b,
    int atamaId,
    String sinif,
    Map<String, Object?> kayit, {
    BireyselBelgeService? belgeService,
  }) async {
    final belgeler = belgeService ?? BireyselBelgeService.instance;
    // Güncel sahiplik ve değiştirilmemiş içerik kontrolü PDF üretiminden önce.
    final rows = await service.kayitlar(b, atamaId);
    final asil = rows.singleWhere((r) => r['Id'] == kayit['Id']);
    if (asil['Hassas'] == 1 ||
        asil['Icerik'] != kayit['Icerik'] ||
        asil['Baslik'] != kayit['Baslik']) {
      throw StateError('Kayıt değişti veya hassas. Ekranı yenileyin.');
    }
    final bytes = await pdfOlustur(b, sinif, asil);
    final arsiv = await belgeler.arsivleriGetir();
    if (arsiv.aktif.okulId != b.okulId ||
        arsiv.aktif.ogretmenProfilId != b.ogretmenProfilId) {
      throw StateError('Belge arşivi değişti.');
    }
    final sonuc = await belgeler.ekle(
      arsivId: arsiv.aktif.id,
      dosya: PlatformFile(
        name: 'Rehberlik_${kayit['Id']}.pdf',
        size: bytes.length,
        bytes: bytes,
      ),
    );
    await service.belgeBagla(b, atamaId, kayit['Id'] as int, sonuc.belge.id);
    return sonuc.belge.id;
  }
}
