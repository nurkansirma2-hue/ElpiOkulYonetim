import 'dart:isolate';
import 'dart:typed_data';
import '../models/import_ilerleme.dart';
import '../models/ortak_import.dart';
import 'dbf_pdf_okuyucu.dart';

/// aSc öğretmen programlarındaki öğretmen-sınıf bağlarını okur.
/// Gün/saatleri kişisel ders programına aktarmaz; sınıf öğretmenliği etiketini
/// ders ilişkisi saymaz. Aynı sayfadaki programlar Sayın başlıklarıyla ayrılır.
class OgretmenProgramiPdfOkuyucu {
  static Future<List<ImportKaynakSatiri>> oku(
    ImportDosya dosya, {
    void Function(ImportIlerleme)? ilerleme,
  }) async {
    if (dosya.uzanti != 'pdf' ||
        dosya.bytes.length < 5 ||
        dosya.bytes.length > 50 * 1024 * 1024 ||
        String.fromCharCodes(dosya.bytes.take(5)) != '%PDF-') {
      throw const FormatException(
        'En fazla 50 MB boyutunda gerçek bir PDF seçin.',
      );
    }
    final bytes = dosya.bytes;
    final port = ReceivePort();
    final send = port.sendPort;
    final subscription = port.listen((m) {
      final sayilar = m as List<int>;
      ilerleme?.call(
        ImportIlerleme(
          'PDF sayfaları okunuyor…',
          tamamlanan: sayilar[0],
          toplam: sayilar[1],
        ),
      );
    });
    try {
      final rows = await _arkaPlandaOku(bytes, send);
      return rows;
    } finally {
      await subscription.cancel();
      port.close();
    }
  }

  // Ayrı kapsam: UI callback'i ve ReceivePort worker'a yakalanmamalı.
  static Future<List<ImportKaynakSatiri>> _arkaPlandaOku(
    Uint8List bytes,
    SendPort send,
  ) => Isolate.run(() {
    final dersler = <int, List<String>>{};
    final pages = DbfPdfOkuyucu.oku(
      bytes,
      programDersleri: dersler,
      sayfaOkundu: (n, toplam) => send.send([n, toplam]),
    );
    return metindenOku(pages, programDersleri: dersler);
  });

  static List<ImportKaynakSatiri> metindenOku(
    List<String> sayfalar, {
    Map<int, List<String>>? programDersleri,
  }) {
    if (sayfalar.isEmpty ||
        sayfalar.length > 100 ||
        sayfalar.fold<int>(0, (n, s) => n + s.length) > 1000000) {
      throw const FormatException(
        'PDF en fazla 100 sayfa ve 1 milyon metin karakteri içermeli.',
      );
    }
    final sonuc = <ImportKaynakSatiri>[];
    final baslik = RegExp(
      r'^\s*Say[ıiİI]n[ \t]+([^\r\n]+)',
      multiLine: true,
      caseSensitive: false,
    );
    final yil = RegExp(r'\b(20\d{2})\s*[-/]\s*(20\d{2})\b');
    final sinif = RegExp(
      r'^\s*((?:[1-9]|1[0-2])\s*[-/–—]\s*[A-ZÇĞİÖŞÜa-zçğıöşü][A-ZÇĞİÖŞÜa-zçğıöşü \t]{0,30})\s*$',
      multiLine: true,
    );
    for (var s = 0; s < sayfalar.length; s++) {
      final metin = sayfalar[s].replaceAll('\r', '');
      final sinifBasliklari = RegExp(
        r'S[ıiİI]n[ıiİI]f[ıiİI]n\s+Ad[ıiİI]\s*:?\s*([^\n]+)',
        caseSensitive: false,
      ).allMatches(metin).toList();
      if (sinifBasliklari.isNotEmpty) {
        if (sinifBasliklari.length != 1) {
          throw FormatException(
            'Sayfa ${s + 1}: birden çok sınıf tablosu ayrıştırılamadı. Ayrı sayfalı belge seçin.',
          );
        }
        final lines = metin
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        final header = lines.indexWhere(
          (l) => importNormalize(l) == 'ogretmenin adi',
        );
        if (header < 0) {
          throw FormatException(
            'Sayfa ${s + 1}: sınıf programı tanındı fakat öğretmen özet tablosu bulunamadı.',
          );
        }
        final yillar = yil
            .allMatches(metin)
            .map((y) => '${y[1]}-${y[2]}')
            .toSet();
        final adlar = <String, Set<String>>{};
        final dersBaslik = lines.indexWhere(
          (l) => importNormalize(l) == 'dersin adi',
        );
        final hds = lines.indexWhere((l) => importNormalize(l) == 'hds');
        final metinDersleri = dersBaslik >= 0 && hds > dersBaslik
            ? lines
                  .sublist(dersBaslik + 1, hds)
                  .where((l) => importNormalize(l) != 'toplam saat')
                  .toList()
            : <String>[];
        final ogretmenSatirlari = <String>[];
        for (final line in lines.skip(header + 1)) {
          if (RegExp(
            r'^\d+\.$|^Toplam\s+Saat',
            caseSensitive: false,
          ).hasMatch(line)) {
            break;
          }
          ogretmenSatirlari.add(line);
        }
        final dersler = programDersleri?[s] ?? metinDersleri;
        for (final entry in ogretmenSatirlari.indexed) {
          for (final ad in entry.$2.split(RegExp(r'[,;/]'))) {
            final temiz = ad.trim().replaceAll(RegExp(r'\s+'), ' ');
            if (temiz.isNotEmpty) {
              final set = adlar.putIfAbsent(temiz, () => <String>{});
              if (dersler.length == ogretmenSatirlari.length &&
                  dersler[entry.$1].isNotEmpty) {
                set.add(dersler[entry.$1]);
              }
            }
          }
        }
        if (adlar.isEmpty) {
          throw FormatException('Sayfa ${s + 1}: öğretmen listesi boş.');
        }
        final okul = lines
            .where((l) => importNormalize(l).contains('lisesi'))
            .join(' ');
        for (final entry in adlar.entries.indexed) {
          sonuc.add(
            ImportKaynakSatiri(
              'pdf:sinif:$s:${entry.$1}',
              'Sayfa ${s + 1}, öğretmen özeti',
              {
                'ogretmen': entry.$2.key,
                'dersler': entry.$2.value.join('\n'),
                'sinif': sinifBasliklari.single[1]!.trim(),
                'yil': yillar.length == 1 ? yillar.single : '',
                'okul': okul,
                'blok': 'sinif:${importNormalize(entry.$2.key)}',
                'tur': 'Sınıf programı',
              },
            ),
          );
        }
        continue;
      }
      if (!importNormalize(metin).contains('haftalik ders programi')) continue;
      final basliklar = baslik.allMatches(metin).toList();
      for (var b = 0; b < basliklar.length; b++) {
        final m = basliklar[b];
        final blok = metin.substring(
          m.end,
          b + 1 < basliklar.length ? basliklar[b + 1].start : metin.length,
        );
        final yillar = yil
            .allMatches(blok)
            .map((y) => '${y[1]}-${y[2]}')
            .toSet();
        final dipnot = RegExp(
          r'S[ıi]n[ıi]f\s+[Öö]ğretmenli[ğg]i|N[öo]bet\s+G[üu]n[üu]',
          caseSensitive: false,
        ).firstMatch(blok);
        final tablo = dipnot == null ? blok : blok.substring(0, dipnot.start);
        final sinifDersleri = <String, Set<String>>{};
        final onceki = <String>[];
        for (final line
            in tablo
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)) {
          if (sinif.hasMatch(line)) {
            if (onceki.isNotEmpty) {
              (sinifDersleri[line] ??= {}).add(onceki.join(' '));
            }
            onceki.clear();
          } else if (line.contains(':') ||
              line.contains(',') ||
              RegExp(
                r'LAB[- ]?\d|^\d+\.$',
                caseSensitive: false,
              ).hasMatch(line) ||
              const [
                'pazartesi',
                'sali',
                'carsamba',
                'persembe',
                'cuma',
              ].contains(importNormalize(line))) {
            onceki.clear();
          } else {
            onceki.add(line);
            if (onceki.length > 4) onceki.removeAt(0);
          }
        }
        final siniflar = sinif
            .allMatches(tablo)
            .map((c) => c[1]!.trim().replaceAll(RegExp(r'\s+'), ' '))
            .toSet();
        final kisa = '$s:$b';
        final okul = metin
            .split('\n')
            .where((l) => importNormalize(l).contains('lisesi'))
            .join(' ');
        for (final entry in (siniflar.isEmpty ? [''] : siniflar).indexed) {
          sonuc.add(
            ImportKaynakSatiri(
              'pdf:$kisa:${entry.$1}',
              'Sayfa ${s + 1}, program ${b + 1}',
              {
                'ogretmen': m[1]!.trim().replaceAll(RegExp(r'\s+'), ' '),
                'sinif': entry.$2,
                'dersler': (sinifDersleri[entry.$2] ?? {}).join('\n'),
                'yil': yillar.length == 1 ? yillar.single : '',
                'blok': kisa,
                'okul': okul,
                'tur': 'Öğretmen programı',
              },
            ),
          );
        }
      }
    }
    if (sonuc.isEmpty) {
      throw const FormatException(
        'Öğretmen veya sınıf ders programı tanınamadı. Metin içeren bir program seçin; tarama resimleri otomatik okunamaz.',
      );
    }
    return List.unmodifiable(sonuc);
  }
}
