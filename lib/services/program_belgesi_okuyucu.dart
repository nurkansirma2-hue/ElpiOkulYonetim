import 'dart:convert';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:office_oxide_ffi/office_oxide_ffi.dart';
import '../models/ortak_import.dart';
import '../models/import_ilerleme.dart';
import 'belge_analiz_service.dart';
import 'ortak_import_service.dart';
import 'ogretmen_programi_pdf_okuyucu.dart';

/// Dosya adı yerine başlık ve tablo yapısını tanır. Belirsiz dosyayı kaydetmez.
class ProgramBelgesiOkuyucu {
  static const uzantilar = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv'};
  static Future<List<ImportKaynakSatiri>> oku(
    ImportDosya dosya, {
    void Function(ImportIlerleme)? ilerleme,
  }) async {
    if (!uzantilar.contains(dosya.uzanti)) {
      throw const FormatException('PDF, Word veya Excel programı seçin.');
    }
    ilerleme?.call(
      const ImportIlerleme('Belge biçimi ve boyutu kontrol ediliyor…'),
    );
    await BelgeAnalizService.bicimiDogrulaAsync(dosya);
    if (dosya.uzanti == 'pdf') {
      return OgretmenProgramiPdfOkuyucu.oku(dosya, ilerleme: ilerleme);
    }
    ilerleme?.call(
      const ImportIlerleme(
        'Word / Excel tabloları okunuyor; program türü belirleniyor…',
      ),
    );
    return _officeOku(dosya);
  }

  static Future<List<ImportKaynakSatiri>> _officeOku(ImportDosya dosya) {
    return Isolate.run(() {
      if (const {'xls', 'xlsx', 'csv'}.contains(dosya.uzanti)) {
        return tablolardanOku(OrtakImportService.tablolariOku(dosya));
      }
      if (dosya.uzanti == 'doc') {
        final doc = OfficeDocument.fromBytes(dosya.bytes, OfficeFormat.doc);
        try {
          final lines = doc.toMarkdown().split('\n');
          return tablolardanOku([
            ImportTablosu('Word', [
              for (final l in lines)
                if (!RegExp(r'^\s*\|?[\s:|-]+\|\s*$').hasMatch(l))
                  l.contains('|')
                      ? l
                            .replaceAll(RegExp(r'^\s*\||\|\s*$'), '')
                            .split('|')
                            .map((c) => c.trim())
                            .toList()
                      : [l.replaceAll(RegExp(r'^#+\s*'), '').trim()],
            ]),
          ]);
        } finally {
          doc.dispose();
        }
      }
      final archive = ZipDecoder().decodeBytes(dosya.bytes);
      final file = archive.findFile('word/document.xml');
      if (file == null) throw const FormatException('Word içeriği bulunamadı.');
      final xml = XmlDocument.parse(utf8.decode(file.content as List<int>));
      final body = xml.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.name.local == 'body',
      );
      String text(XmlElement e) => e.descendants
          .whereType<XmlElement>()
          .where((n) => n.name.local == 't')
          .map((n) => n.innerText)
          .join();
      final rows = <List<String>>[];
      for (final e in body.childElements) {
        if (e.name.local == 'p') rows.add([text(e)]);
        if (e.name.local == 'tbl') {
          for (final tr in e.childElements.where((n) => n.name.local == 'tr')) {
            rows.add(
              tr.childElements
                  .where((n) => n.name.local == 'tc')
                  .map(text)
                  .toList(),
            );
          }
        }
      }
      return tablolardanOku([ImportTablosu('Word', rows)]);
    });
  }

  static List<ImportKaynakSatiri> tablolardanOku(List<ImportTablosu> tables) {
    if (tables.length > 100 ||
        tables.fold<int>(0, (n, t) => n + t.satirlar.length) > 20000 ||
        tables.fold<int>(
              0,
              (n, t) =>
                  n + t.satirlar.fold<int>(0, (n, r) => n + r.join().length),
            ) >
            1000000) {
      throw const FormatException('Belge tablo veya metin sınırını aşıyor.');
    }
    final sonuc = <ImportKaynakSatiri>[];
    final yilRe = RegExp(r'\b(20\d{2})\s*[-/]\s*(20\d{2})\b');
    final sinifRe = RegExp(
      r'^(?:[1-9]|1[0-2])\s*[-/]\s*[A-ZÇĞİÖŞÜa-zçğıöşü][A-ZÇĞİÖŞÜa-zçğıöşü ]*$',
    );
    for (final t in tables.indexed) {
      final baslangic = sonuc.length;
      final lines = t.$2.satirlar;
      final all = lines.expand((r) => r).join('\n');
      final yillar = yilRe
          .allMatches(all)
          .map((m) => '${m[1]}-${m[2]}')
          .toSet();
      var ortakYil = yillar.length == 1 ? yillar.single : '';
      var sinif = sinifRe.hasMatch(t.$2.ad.trim()) ? t.$2.ad.trim() : '';
      var ogretmen = '', okul = '';
      int? adKolon, sinifKolon, yilKolon, dersKolon;
      var tur = '';
      final gorulen = <String>{};
      for (final r in lines.indexed) {
        final row = r.$2, normalized = row.map(importNormalize).toList();
        if (row.isEmpty || row.every((c) => c.trim().isEmpty)) continue;
        final joined = row.join(' ').trim();
        final sinifLabel = RegExp(
          r'^S[ıiİI]n[ıiİI]f[ıiİI]n\s+Ad[ıiİI]\s*:?\s*(.*)$',
          caseSensitive: false,
        ).firstMatch(joined);
        if (sinifLabel != null) {
          sinif = sinifLabel[1]!.trim();
          adKolon = null;
          sinifKolon = null;
          yilKolon = null;
          dersKolon = null;
          continue;
        }
        final sayin = RegExp(
          r'^Say[ıiİI]n\s+(.+)$',
          caseSensitive: false,
        ).firstMatch(joined);
        if (sayin != null) {
          ogretmen = sayin[1]!.trim();
          adKolon = null;
          sinifKolon = null;
          yilKolon = null;
          dersKolon = null;
          continue;
        }
        if (normalized.any((c) => c.contains('lisesi'))) okul = joined;
        if (normalized.first == 'egitim yili' ||
            normalized.first == 'egitim ogretim yili') {
          final ys = yilRe
              .allMatches(joined)
              .map((m) => '${m[1]}-${m[2]}')
              .toSet();
          ortakYil = ys.length == 1 ? ys.single : '';
          continue;
        }
        int? column(Set<String> labels) {
          final matches = normalized.indexed
              .where((c) => labels.contains(c.$2))
              .toList();
          if (matches.length > 1) {
            throw FormatException(
              '${t.$2.ad}: aynı başlıktan birden fazla kolon var.',
            );
          }
          return matches.isEmpty ? null : matches.single.$1;
        }

        final ac = column({
          'ogretmen',
          'ogretmenin adi',
          'ogretmen adi',
          'ogretmen adi soyadi',
          'ogretmen ad soyad',
        });
        final sc = column({'sinif', 'sinif sube', 'sinif kodu'});
        if (ac != null || sc != null) {
          adKolon = ac;
          sinifKolon = sc;
          yilKolon = column({'yil', 'egitim yili', 'egitim ogretim yili'});
          dersKolon = column({'ders', 'dersin adi', 'ders adi', 'dersler'});
          tur = ac != null && sc != null
              ? 'Öğretmen-sınıf tablosu'
              : ac != null
              ? 'Sınıf programı'
              : 'Öğretmen programı';
          continue;
        }
        if (normalized.first.startsWith('toplam saat')) {
          adKolon = null;
          sinifKolon = null;
          continue;
        }
        String value(int? c) =>
            c != null && c < row.length ? row[c].trim() : '';
        final ad = adKolon == null ? ogretmen : value(adKolon);
        final kod = sinifKolon == null ? sinif : value(sinifKolon);
        if (adKolon == null && sinifKolon == null) continue;
        final yil = yilKolon == null ? ortakYil : value(yilKolon);
        final ys = yilRe.allMatches(yil).map((m) => '${m[1]}-${m[2]}').toSet();
        for (final name in ad.split(RegExp(r'[,;/]'))) {
          final temiz = name.trim().replaceAll(RegExp(r'\s+'), ' ');
          final key =
              '${importNormalize(temiz)}|${importNormalize(kod)}|$yil|${importNormalize(value(dersKolon))}';
          if (!gorulen.add(key)) continue;
          sonuc.add(
            ImportKaynakSatiri(
              'tablo:${t.$1}:${r.$1}:${gorulen.length}',
              '${t.$2.ad}, satır ${r.$1 + 1}',
              {
                'ogretmen': temiz,
                'dersler': value(dersKolon),
                'sinif': kod,
                'yil': ys.length == 1 ? ys.single : '',
                'tur': tur,
                'blok': 'tablo:${importNormalize(temiz)}',
                'okul': okul,
              },
            ),
          );
        }
      }
      if (sonuc.length == baslangic &&
          importNormalize(all).contains('haftalik ders programi')) {
        // Word/Excel öğretmen kartları: metin sırası korunabilen düzenler.
        sonuc.addAll(
          OgretmenProgramiPdfOkuyucu.metindenOku([all]).map(
            (r) => ImportKaynakSatiri(
              'tablo:${t.$1}:${r.id}',
              '${t.$2.ad}, ${r.konum}',
              r.degerler,
            ),
          ),
        );
      }
    }
    if (sonuc.isEmpty) {
      throw const FormatException(
        'Öğretmen veya sınıf programı tanınamadı. Öğretmen/sınıf başlıklarını ve eğitim yılını kontrol edin.',
      );
    }
    return List.unmodifiable(sonuc);
  }
}
