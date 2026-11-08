import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'rapor_modeli.dart';

/// Verilen alan tanımı, tasarım, veri ve fontlardan PDF belleği üretir.
/// Veri toplama, dosyaya kaydetme ve yazdırma çağıran katmanın sorumluluğudur.
class RaporPdfService {
  static Future<Uint8List> olustur({
    required RaporTanimi tanim,
    required RaporTasarimi tasarim,
    required RaporVerisi veri,
    required ByteData normalFont,
    required ByteData kalinFont,
  }) async {
    tasarim.dogrula(tanim);
    if (veri.satirlar.isEmpty) throw StateError('Yazdırılacak kayıt bulunamadı.');
    final format = tasarim.yatay ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final sutunlar = tasarim.gorunenSutunlar;
    final alanlar = {for (final alan in tanim.sutunAlanlari) alan.id: alan};
    final toplam = sutunlar.fold<double>(0, (v, s) => v + s.genislik);
    final kullanilabilir = format.width - 48;
    if (sutunlar.any((s) => kullanilabilir * s.genislik / toplam < 28)) {
      throw StateError('Sütunlar sayfaya sığmıyor. Yatay sayfa seçin, sütun azaltın veya genişlikleri dengeleyin.');
    }
    final bilgiler = tasarim.bilgiler.where((b) => b.yazi(veri.bilgiler).isNotEmpty).toList();
    final resimVar = sutunlar.any((s) => alanlar[s.alanId]!.tur == RaporHucreTuru.resim);
    final enAzSatir = resimVar ? 40.0 : 16.0;
    final normalSatir = tasarim.satirYuksekligi < enAzSatir ? enAzSatir : tasarim.satirYuksekligi;
    final enAzYazi = tasarim.yaziBoyutu < 8 ? tasarim.yaziBoyutu : 8.0;

    // 1: Kullanıcının ölçüleri, 0: Okunabilir en küçük ölçüler.
    // MultiPage gerçek yazı ve hücre ölçüleriyle sayfaları oluşturur.
    pw.Document belgeOlustur(double oran) {
      final yaziBoyutu = enAzYazi + (tasarim.yaziBoyutu - enAzYazi) * oran;
      final yukseklik = enAzSatir + (normalSatir - enAzSatir) * oran;
      final dolgu = 2 + 2 * oran;
      final bosluk = 4 + 4 * oran;
      List<pw.Widget> bolgeIcerigi(String konum) {
        final hiza = konum.endsWith('Sol') ? pw.TextAlign.left
          : konum.endsWith('Sag') ? pw.TextAlign.right : pw.TextAlign.center;
        return [
          for (var i = 0; i < bilgiler.length; i++)
            if (bilgiler[i].konum == konum) pw.Padding(
              padding: pw.EdgeInsets.only(bottom: dolgu),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                pw.Text(bilgiler[i].yazi(veri.bilgiler), textAlign: hiza,
                  style: pw.TextStyle(fontSize: i < 2 ? yaziBoyutu + 2 : yaziBoyutu,
                    fontWeight: i < 2 ? pw.FontWeight.bold : pw.FontWeight.normal)),
                if (bilgiler[i].altMetin.trim().isNotEmpty)
                  pw.Text(bilgiler[i].altMetin.trim(), textAlign: hiza,
                    style: pw.TextStyle(fontSize: yaziBoyutu)),
              ])),
        ];
      }
      pw.Widget? bolgeler(String onEk) {
        final icerikler = [for (final sonEk in ['Sol', 'Orta', 'Sag']) bolgeIcerigi('$onEk$sonEk')];
        if (icerikler.every((alanlar) => alanlar.isEmpty)) return null;
        // Yalnız ortadaki bilgi alanları sayfanın tamamını kullanır.
        if (icerikler[0].isEmpty && icerikler[2].isEmpty) {
          return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: icerikler[1]);
        }
        return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (var i = 0; i < icerikler.length; i++) pw.Expanded(
            child: pw.Padding(padding: pw.EdgeInsets.only(left: i == 0 ? 0 : dolgu,
                right: i == 2 ? 0 : dolgu),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: icerikler[i]))),
        ]);
      }
      pw.Widget hucre(RaporTabloSutunu sutun, Map<String, Object?> satir, int index) {
        final tur = alanlar[sutun.alanId]!.tur;
        if (tur == RaporHucreTuru.resim) {
          final bytes = satir[sutun.alanId];
          pw.Widget resim = pw.Text('—');
          if (bytes is Uint8List && bytes.isNotEmpty) {
            try { resim = pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain); }
            catch (_) { resim = pw.Text('—'); }
          }
          return pw.Container(height: yukseklik - dolgu * 2,
            alignment: pw.Alignment.center, child: resim);
        }
        final metin = switch (tur) {
          RaporHucreTuru.sira => '${index + 1}',
          RaporHucreTuru.bos => '',
          _ => '${satir[sutun.alanId] ?? ''}',
        };
        return pw.Text(metin, style: pw.TextStyle(fontSize: yaziBoyutu));
      }
      final pdf = pw.Document();
      final ustBilgi = bolgeler('ust');
      final altBilgi = bolgeler('alt');
      pdf.addPage(pw.MultiPage(
        pageFormat: format, margin: const pw.EdgeInsets.all(24), maxPages: 200,
        theme: pw.ThemeData.withFont(base: pw.Font.ttf(normalFont), bold: pw.Font.ttf(kalinFont)),
        header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          if (ustBilgi != null) ustBilgi,
          pw.SizedBox(height: bosluk),
        ]),
        footer: (context) => pw.Padding(padding: pw.EdgeInsets.only(top: bosluk),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            if (altBilgi != null) ...[
              altBilgi, pw.SizedBox(height: bosluk),
            ],
            pw.Align(alignment: pw.Alignment.centerRight,
              child: pw.Text('${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8))),
          ])),
        build: (_) => [pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
          columnWidths: {for (var i = 0; i < sutunlar.length; i++) i: pw.FlexColumnWidth(sutunlar[i].genislik)},
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
              for (final s in sutunlar) pw.Padding(padding: pw.EdgeInsets.all(dolgu),
                child: pw.Text(s.baslik.trim(), textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: yaziBoyutu, fontWeight: pw.FontWeight.bold))),
            ]),
            for (var i = 0; i < veri.satirlar.length; i++) pw.TableRow(children: [
              for (final s in sutunlar) pw.Container(
                constraints: pw.BoxConstraints(minHeight: yukseklik),
                padding: pw.EdgeInsets.all(dolgu), alignment: pw.Alignment.centerLeft,
                child: hucre(s, veri.satirlar[i], i)),
            ]),
          ],
        )],
      ));
      return pdf;
    }

    final normal = belgeOlustur(1);
    if (!tasarim.tekSayfayaSigdir || normal.document.pdfPageList.pages.length == 1 ||
        veri.satirlar.length * enAzSatir > format.height - 48) {
      return normal.save();
    }
    var sigan = belgeOlustur(0);
    // Okunabilir taban ölçülerde de sığmıyorsa normal ölçülerle bütün
    // kayıtları sonraki sayfalara aktar; hiçbir satırı kesme veya gizleme.
    if (sigan.document.pdfPageList.pages.length != 1) return normal.save();
    var alt = 0.0;
    var ust = 1.0;
    for (var deneme = 0; deneme < 4; deneme++) {
      final oran = (alt + ust) / 2;
      final aday = belgeOlustur(oran);
      if (aday.document.pdfPageList.pages.length == 1) {
        alt = oran;
        sigan = aday;
      } else {
        ust = oran;
      }
    }
    return sigan.save();
  }
}
