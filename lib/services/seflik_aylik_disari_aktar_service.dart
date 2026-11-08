import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'bireysel_belge_service.dart';
import 'belge_disari_aktar_service.dart';
import 'bireysel_seflik_yillik_plan_service.dart';

/// Yıllık onaylı planı değiştirmeden seçilen ay için belge üretir.
class SeflikAylikDisariAktarService {
  SeflikAylikDisariAktarService._();

  static const aylar = <String>[
    '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  static String dosyaAdi(DateTime ay, String uzanti) =>
      'Seflik_Aylik_Form_${ay.year}_${ay.month.toString().padLeft(2, '0')}.$uzanti';

  static List<SeflikYillikFaaliyet> ayFaaliyetleri(
    List<SeflikYillikFaaliyet> plan, DateTime ay,
  ) => List.unmodifiable(
    plan.where((f) => f.tarih.year == ay.year && f.tarih.month == ay.month)
        .toList()
      ..sort((a, b) {
        final tarih = a.tarih.compareTo(b.tarih);
        return tarih != 0 ? tarih : a.dersSaatiNo.compareTo(b.dersSaatiNo);
      }),
  );

  static String _tarih(DateTime tarih) =>
      '${tarih.day.toString().padLeft(2, '0')}.'
      '${tarih.month.toString().padLeft(2, '0')}.${tarih.year}';

  static String _metin(String value) {
    // Excel hücrelerindeki kullanıcı kaynaklı formül komutlarını etkisizleştir.
    final temiz = value.replaceAll(RegExp(r'[\\x00-\\x1f]'), ' ').trim();
    return RegExp(r'^[=+@-]').hasMatch(temiz) ? "'$temiz" : temiz;
  }

  static Uint8List excelOlustur({
    required DateTime ay,
    required String yil,
    required String okul,
    required String ogretmen,
    required List<SeflikYillikFaaliyet> faaliyetler,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([_metin(okul), '$yil Eğitim Öğretim Yılı']);
    sheet.appendRow(['ATÖLYE ŞEFLİĞİ AYLIK ÇALIŞMA FORMU']);
    sheet.appendRow(['Ay', '${aylar[ay.month]} ${ay.year}']);
    sheet.appendRow(['Atölye Şefi', _metin(ogretmen)]);
    sheet.appendRow(['Tarih', 'Gün', 'Ders Saati', 'Saat Aralığı',
      'Planlanan Faaliyet', 'Ders Saati Sayısı']);
    for (final f in faaliyetler) {
      sheet.appendRow([
        _tarih(f.tarih), _metin(f.gun), f.dersSaatiNo.toString(),
        '${f.baslangic} - ${f.bitis}', _metin(f.faaliyet), '1',
      ]);
    }
    sheet.appendRow(['Toplam', '', '', '', '', '${faaliyetler.length}']);
    sheet.appendRow(['Atölye Şefi', _metin(ogretmen), 'Okul Müdürü', 'İmza']);
    sheet.appendRow(['Onaylı yıllık plandan üretilen planlanan faaliyetlerdir.']);
    return Uint8List.fromList(excel.encode()!);
  }

  static Future<Uint8List> pdfOlustur({
    required DateTime ay,
    required String yil,
    required String okul,
    required String ogretmen,
    required List<SeflikYillikFaaliyet> faaliyetler,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (context) => pw.Column(children: [
        pw.Text(okul.isEmpty ? 'Okul adı belirtilmemiş' : okul,
          style: pw.TextStyle(font: bold, fontSize: 11)),
        pw.Text('$yil EĞİTİM ÖĞRETİM YILI',
          style: const pw.TextStyle(fontSize: 9)),
        pw.Text('ATÖLYE ŞEFLİĞİ AYLIK ÇALIŞMA FORMU',
          style: pw.TextStyle(font: bold, fontSize: 12)),
        pw.SizedBox(height: 8),
        pw.Text('Ay: ${aylar[ay.month]} ${ay.year}    Atölye Şefi: $ogretmen',
          style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
      ]),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: ['Tarih', 'Gün', 'Saat', 'Zaman', 'Planlanan faaliyet'],
          data: [
            for (final f in faaliyetler)
              [_tarih(f.tarih), f.gun, '${f.dersSaatiNo}',
               '${f.baslangic}-${f.bitis}', f.faaliyet],
          ],
          cellStyle: const pw.TextStyle(fontSize: 7),
          headerStyle: pw.TextStyle(font: bold, fontSize: 7),
          cellPadding: const pw.EdgeInsets.all(4),
          columnWidths: {
            0: const pw.FixedColumnWidth(62),
            1: const pw.FixedColumnWidth(54),
            2: const pw.FixedColumnWidth(32),
            3: const pw.FixedColumnWidth(72),
            4: const pw.FlexColumnWidth(),
          },
        ),
        pw.SizedBox(height: 8),
        pw.Text('Planlanan toplam: ${faaliyetler.length} ders saati'),
        pw.SizedBox(height: 25),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(children: [pw.Text(ogretmen), pw.Text('Atölye Şefi'),
              pw.SizedBox(height: 30), pw.Text('İmza')]),
            pw.Column(children: [pw.Text('UYGUNDUR'), pw.Text('Okul Müdürü'),
              pw.SizedBox(height: 30), pw.Text('İmza')]),
          ]),
        pw.SizedBox(height: 15),
        pw.Text('Onaylı yıllık plandan üretilen taslaktır; gerçekleşme veya imza onayı değildir.',
          style: const pw.TextStyle(fontSize: 7)),
      ],
    ));
    return pdf.save();
  }

  static Future<String> belgelerimeKaydet({
    required DateTime ay,
    required String yil,
    required Uint8List bytes,
    required String uzanti,
  }) async {
    if (uzanti != 'pdf' && uzanti != 'xlsx') {
      throw ArgumentError('Desteklenmeyen belge türü.');
    }
    final arsiv = (await BireyselBelgeService.instance.arsivleriGetir()).aktif;
    final sonuc = await BireyselBelgeService.instance.ekle(
      arsivId: arsiv.id,
      dosya: PlatformFile(
        name: dosyaAdi(ay, uzanti), size: bytes.length, bytes: bytes,
      ),
    );
    return sonuc.belge.dosyaAdi;
  }

  static Future<String?> dosyayaAktar({
    required DateTime ay,
    required String uzanti,
    required Uint8List bytes,
  }) => BelgeDisariAktarService.kaydet(dosyaAdi(ay, uzanti), bytes);
}
