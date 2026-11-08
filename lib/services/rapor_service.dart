import 'dart:io';
import '../models/rapor_sablonu.dart';
import '../raporlama/rapor_pdf_service.dart';
import 'ogrenci_rapor_uyarlayici.dart';

import 'package:elpi_okul_yonetim/models/ogrenci.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:elpi_okul_yonetim/models/okul_bilgi.dart';

class RaporService {
  static Future<Uint8List> dinamikSinifListesi({
    required RaporSablonu sablon,
    required List<Map<String, Object?>> ogrenciler,
    required Map<String, String> bilgiler,
  }) async {
    sablon.dogrula();
    if (ogrenciler.isEmpty) throw StateError('Bu sınıfta yazdırılacak öğrenci bulunamadı.');
    return RaporPdfService.olustur(
      tanim: OgrenciRaporUyarlayici.tanim(sablon),
      tasarim: OgrenciRaporUyarlayici.tasarim(sablon),
      veri: OgrenciRaporUyarlayici.veri(sablon, ogrenciler, bilgiler),
      normalFont: await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      kalinFont: await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
  }


  static Future<void> pdfSinifListesiOlustur({
    required List<Ogrenci> ogrenciler,
    required String baslik,
    required String raporTuru,
    required String sinifAdi,
    required bool okulAdiGoster,
    required bool tarihGoster,
    required bool satirNoGoster,
    required bool okulNoGoster,
    required bool adSoyadGoster,
    required bool alanGoster,
    required bool fotografGoster,
    required bool cinsiyetGoster,
    required bool telefonGoster,
    required bool mailGoster,
    required bool adresGoster,
    required bool veliAdiGoster,
    required bool veliTelefonGoster,
    required bool imzaSutunuGoster,
    required bool yolTarifiGoster,
    String? ogretmenAdi,
    String? dersAdi,
    OkulBilgi? okulBilgi,
  }) async {
    final pdf = pw.Document();

    final fontRegular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );

    final fontBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );

    final now = DateTime.now();
    final tarihYazi = DateFormat('dd.MM.yyyy HH:mm').format(now);

    final temizBaslik = baslik.trim();

    final temizSinifAdi = sinifAdi
        .trim()
        .isEmpty ? '-' : sinifAdi.trim();
    final temizOgretmenAdi =
    (ogretmenAdi ?? '')
        .trim()
        .isEmpty ? null : ogretmenAdi!.trim();
    final temizDersAdi =
    (dersAdi ?? '')
        .trim()
        .isEmpty ? null : dersAdi!.trim();

    final sutunlar = _sutunlariHazirla(
      satirNoGoster: satirNoGoster,
      okulNoGoster: okulNoGoster,
      adSoyadGoster: adSoyadGoster,
      alanGoster: alanGoster,
      fotografGoster: fotografGoster,
      cinsiyetGoster: cinsiyetGoster,
      telefonGoster: telefonGoster,
      mailGoster: mailGoster,
      adresGoster: adresGoster,
      veliAdiGoster: veliAdiGoster,
      veliTelefonGoster: veliTelefonGoster,
      imzaSutunuGoster: imzaSutunuGoster,
      yolTarifiGoster: yolTarifiGoster,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        theme: pw.ThemeData.withFont(
          base: fontRegular,
          bold: fontBold,
        ),
        build: (context) =>
        [
          _buildUstBilgi(
            baslik: temizBaslik,
            sinifAdi: temizSinifAdi,
            okulAdiGoster: okulAdiGoster,
            tarihGoster: tarihGoster,
            tarihYazi: tarihYazi,
            ogretmenAdi: temizOgretmenAdi,
            dersAdi: temizDersAdi,
            okulBilgi: okulBilgi,
          ),
          pw.SizedBox(height: 12),
          raporTuru == 'bos'
              ? _buildBosCizelge(
            ogrenciler: ogrenciler,
            sutunlar: sutunlar,
          )
              : _buildTabloluRapor(
            ogrenciler: ogrenciler,
            sutunlar: sutunlar,
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final dosyaAdi =
        'rapor_${_dosyaAdiTemizle(temizSinifAdi)}_${DateFormat(
        'yyyyMMdd_HHmmss').format(now)}.pdf';
    final file = File('${dir.path}/$dosyaAdi');

    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(file.path);
  }

  static List<_RaporSutun> _sutunlariHazirla({
    required bool satirNoGoster,
    required bool okulNoGoster,
    required bool adSoyadGoster,
    required bool alanGoster,
    required bool fotografGoster,
    required bool cinsiyetGoster,
    required bool telefonGoster,
    required bool mailGoster,
    required bool adresGoster,
    required bool veliAdiGoster,
    required bool veliTelefonGoster,
    required bool imzaSutunuGoster,
    required bool yolTarifiGoster,
  }) {
    final sutunlar = <_RaporSutun>[];

    if (satirNoGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'No',
          flex: 1,
          degerGetir: (ogrenci, index) => '${index + 1}',
        ),
      );
    }

    if (okulNoGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Okul No',
          flex: 2,
          degerGetir: (ogrenci, index) => _metin(ogrenci.okulNo),
        ),
      );
    }

    if (adSoyadGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Ad Soyad',
          flex: 4,
          degerGetir: (ogrenci, index) =>
              '${_metin(ogrenci.ad)} ${_metin(ogrenci.soyad)}'.trim(),
        ),
      );
    }

    if (alanGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Alan',
          flex: 3,
          degerGetir: (ogrenci, index) => _metin(ogrenci.alan),
        ),
      );
    }

    if (fotografGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Fotoğraf',
          flex: 2,
          degerGetir: (ogrenci, index) {
            final foto = (ogrenci.fotoYolu ?? '').trim();
            return foto.isNotEmpty ? 'Var' : '-';
          },
        ),
      );
    }

    if (cinsiyetGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Cinsiyet',
          flex: 2,
          degerGetir: (ogrenci, index) => _metin(ogrenci.cinsiyet),
        ),
      );
    }

    if (telefonGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Telefon',
          flex: 3,
          degerGetir: (ogrenci, index) => _metin(ogrenci.telefon),
        ),
      );
    }

    if (mailGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Mail',
          flex: 4,
          degerGetir: (ogrenci, index) => _metin(ogrenci.mail),
        ),
      );
    }

    if (adresGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Adres',
          flex: 5,
          degerGetir: (ogrenci, index) => _metin(ogrenci.adres),
        ),
      );
    }

    if (veliAdiGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Veli Adı',
          flex: 3,
          degerGetir: (ogrenci, index) => _metin(ogrenci.veliAdi),
        ),
      );
    }

    if (veliTelefonGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Veli Tel.',
          flex: 3,
          degerGetir: (ogrenci, index) => _metin(ogrenci.veliTelefonu),
        ),
      );
    }

    if (imzaSutunuGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'İmza',
          flex: 3,
          degerGetir: (ogrenci, index) => '',
        ),
      );
    }

    if (yolTarifiGoster) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Yol Tarifi',
          flex: 4,
          degerGetir: (ogrenci, index) => _metin(ogrenci.yolTarifi),
        ),
      );
    }

    if (sutunlar.isEmpty) {
      sutunlar.add(
        _RaporSutun(
          baslik: 'Ad Soyad',
          flex: 4,
          degerGetir: (ogrenci, index) =>
              '${_metin(ogrenci.ad)} ${_metin(ogrenci.soyad)}'.trim(),
        ),
      );
    }

    return sutunlar;
  }

  static pw.Widget _buildUstBilgi({
    required String baslik,
    required String sinifAdi,
    required bool okulAdiGoster,
    required bool tarihGoster,
    required String tarihYazi,
    String? ogretmenAdi,
    String? dersAdi,
    OkulBilgi? okulBilgi,
  }) {
    final String okulAdi = (okulBilgi?.okulAdi ?? '').trim();

    final String gosterilecekBaslik =
    baslik.trim().isNotEmpty ? baslik.trim() : '';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // 🔥 T.C.
        if (okulAdiGoster && okulAdi.isNotEmpty) ...[
          pw.Center(
            child: pw.Text(
              'T.C.',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),

          pw.SizedBox(height: 4),

          // 🔥 OKUL ADI
          pw.Center(
            child: pw.Text(
              okulAdi,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),

          pw.SizedBox(height: 10),
        ],

        // 🔥 RAPOR BAŞLIĞI (varsa)
        if (gosterilecekBaslik.isNotEmpty) ...[
          pw.Center(
            child: pw.Text(
              gosterilecekBaslik,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
        ],

        // 🔥 SINIF
        pw.Text(
          'Sınıf: $sinifAdi',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),

        if (ogretmenAdi != null && ogretmenAdi.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Öğretmen: $ogretmenAdi',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],

        if (dersAdi != null && dersAdi.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Ders: $dersAdi',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],

        if (tarihGoster) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Tarih: $tarihYazi',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ],
    );
  }
  static pw.Widget _buildTabloluRapor({
    required List<Ogrenci> ogrenciler,
    required List<_RaporSutun> sutunlar,
  }) {
    final headers = sutunlar.map((e) => e.baslik).toList();

    final data = List<List<String>>.generate(ogrenciler.length, (index) {
      final ogrenci = ogrenciler[index];
      return sutunlar.map((sutun) => sutun.degerGetir(ogrenci, index)).toList();
    });

    final columnWidths = <int, pw.TableColumnWidth>{};
    for (int i = 0; i < sutunlar.length; i++) {
      columnWidths[i] = pw.FlexColumnWidth(sutunlar[i].flex.toDouble());
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      columnWidths: columnWidths,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.grey300,
      ),
      cellStyle: const pw.TextStyle(
        fontSize: 8,
      ),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.center,
      cellPadding: const pw.EdgeInsets.all(4),
      border: pw.TableBorder.all(
        color: PdfColors.grey600,
        width: 0.5,
      ),
      rowDecoration: const pw.BoxDecoration(
        color: PdfColors.white,
      ),
      oddRowDecoration: const pw.BoxDecoration(
        color: PdfColors.grey100,
      ),
    );
  }

  static pw.Widget _buildBosCizelge({
    required List<Ogrenci> ogrenciler,
    required List<_RaporSutun> sutunlar,
  }) {
    final bosSatirlar = List<List<String>>.generate(ogrenciler.length, (index) {
      final ogrenci = ogrenciler[index];
      return sutunlar.map((sutun) {
        if (sutun.baslik == 'İmza') {
          return '';
        }
        return sutun.degerGetir(ogrenci, index);
      }).toList();
    });

    final columnWidths = <int, pw.TableColumnWidth>{};
    for (int i = 0; i < sutunlar.length; i++) {
      columnWidths[i] = pw.FlexColumnWidth(sutunlar[i].flex.toDouble());
    }

    return pw.TableHelper.fromTextArray(
      headers: sutunlar.map((e) => e.baslik).toList(),
      data: bosSatirlar,
      columnWidths: columnWidths,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.grey300,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellHeight: 22,
      headerAlignment: pw.Alignment.center,
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.all(4),
      border: pw.TableBorder.all(
        color: PdfColors.grey700,
        width: 0.6,
      ),
    );
  }

  static String _metin(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    if (text.isEmpty) return '-';
    return text;
  }

  static String _dosyaAdiTemizle(String metin) {
    return metin
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(' ', '_')
        .replaceAll('ş', 's')
        .replaceAll('Ş', 'S')
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'I')
        .replaceAll('ğ', 'g')
        .replaceAll('Ğ', 'G')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U')
        .replaceAll('ö', 'o')
        .replaceAll('Ö', 'O')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'C');
  }
}

class _RaporSutun {
  final String baslik;
  final int flex;
  final String Function(Ogrenci ogrenci, int index) degerGetir;

  _RaporSutun({
    required this.baslik,
    required this.flex,
    required this.degerGetir,
  });
}
