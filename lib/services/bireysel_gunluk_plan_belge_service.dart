import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'package:flutter/services.dart' show rootBundle;

import '../models/bireysel_gunluk_plan.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'bireysel_belge_service.dart';
import 'bireysel_gunluk_plan_service.dart';

class BireyselGunlukPlanBelgeService {
  BireyselGunlukPlanBelgeService._();

  /// Kaynak örneğindeki gibi bilgiler tablo, uzun işleniş tam sayfa genişliğindedir.
  /// PDF belleği üretilir; arşiv ve günlük plan kaydı değişmez.
  static Future<Uint8List> pdfOlustur(
    BireyselGunlukPlan plan, {
    ByteData? normalFont,
    ByteData? kalinFont,
  }) async {
    final normal =
        normalFont ??
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final kalin =
        kalinFont ?? await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final pdf = pw.Document();
    final bilgiler = {
      'Ders': plan.dersAdi,
      'Sınıf / şube': plan.sinifKodu,
      'Hafta / tarih': plan.haftaTarih,
      'Ders saati': plan.dersSaati,
    };
    List<String> parcalar(String value) {
      final result = <String>[];
      for (var satir
          in (value.trim().isEmpty ? 'Belirtilmedi' : value)
              .replaceAll('\r', '')
              .split('\n')) {
        if (satir.isEmpty) continue;
        while (satir.length > 500) {
          var son = satir.lastIndexOf(' ', 500);
          if (son < 200) son = 500;
          result.add(satir.substring(0, son));
          satir = satir.substring(son).trimLeft();
        }
        if (satir.isNotEmpty) result.add(satir);
      }
      return result;
    }

    pw.Widget paragraf(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 11)),
    );
    final icerik = <pw.Widget>[
      pw.Text(
        plan.okulAdi,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        '${plan.egitimOgretimYili} Eğitim Öğretim Yılı',
        textAlign: pw.TextAlign.center,
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Text(
          'GÜNLÜK DERS PLANI',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(2),
          1: const pw.FlexColumnWidth(6),
        },
        children: [
          for (final e in bilgiler.entries)
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    e.key,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(e.value),
                ),
              ],
            ),
        ],
      ),
    ];
    for (final e in bolumler(plan).entries.where((e) => e.key != 'İmzalar')) {
      final lines = parcalar(e.value);
      if (lines.isEmpty) lines.add('Belirtilmedi');
      // Başlık ve ilk paragraf birlikte kalır. Kalan paragraflar sayfalara akar.
      icerik.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
              padding: const pw.EdgeInsets.all(4),
              color: PdfColors.grey200,
              child: pw.Text(
                e.key,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            paragraf(lines.first),
          ],
        ),
      );
      icerik.addAll(lines.skip(1).map(paragraf));
    }
    icerik.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              children: [
                pw.Text(plan.ogretmenAdi),
                pw.Text('Ders Öğretmeni'),
                pw.SizedBox(height: 30),
              ],
            ),
            pw.Column(
              children: [
                pw.Text('UYGUNDUR'),
                pw.SizedBox(height: 18),
                pw.Text('......................................'),
                pw.Text('Okul Müdürü'),
              ],
            ),
          ],
        ),
      ),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        maxPages: 200,
        theme: pw.ThemeData.withFont(
          base: pw.Font.ttf(normal),
          bold: pw.Font.ttf(kalin),
        ),
        header: (c) => c.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  '${plan.dersAdi} • ${plan.sinifKodu} • ${plan.haftaTarih}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
        footer: (c) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${c.pageNumber} / ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (_) => icerik,
      ),
    );
    return pdf.save();
  }

  static Map<String, String> bolumler(BireyselGunlukPlan plan) => {
    'Ünite / tema': plan.unite,
    'Konu': plan.konu,
    'Öğrenme çıktıları / kazanımlar': [
      plan.kazanim,
      plan.ogrenmeCiktisi,
    ].where((s) => s.isNotEmpty).toSet().join('\n'),
    'Kazanım açıklaması': plan.kazanimAciklamasi,
    'Yöntem ve teknikler': plan.yontemTeknik,
    'Araç gereçler': plan.aracGerec,
    'Ölçme değerlendirme': plan.degerlendirme,
    'Açıklamalar': plan.aciklamalar,
    'Yapılacak etkinlikler': plan.etkinlikler,
    'Özet / işleniş': plan.dersinIslenisi,
    'İmzalar':
        '${plan.ogretmenAdi}\nDers Öğretmeni\n\nUYGUNDUR\n......................................\nOkul Müdürü',
  };

  /// Makrosuz OOXML; kaynak metinleri yalnız kaçışlı XML metni olarak yazılır.
  static Uint8List docxOlustur(BireyselGunlukPlan plan) {
    String x(String value) => XmlText(
      value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''),
    ).toXmlString();
    String p(String text, {String? style, bool kalin = false}) =>
        '<w:p><w:pPr>${style == null ? '' : '<w:pStyle w:val="$style"/>'}'
        '<w:spacing w:after="60"/></w:pPr><w:r><w:rPr>${kalin ? '<w:b/>' : ''}'
        '</w:rPr><w:t xml:space="preserve">${x(text)}</w:t></w:r></w:p>';
    String paragraflar(String text) =>
        (text.trim().isEmpty ? 'Belirtilmedi' : text)
            .replaceAll('\r', '')
            .split('\n')
            .map(
              (s) => p(
                s,
                style: RegExp(r'^\d+(?:–\d+)?\. ders saati').hasMatch(s)
                    ? 'Heading2'
                    : null,
              ),
            )
            .join();
    final bilgiler = {
      'Okul': plan.okulAdi,
      'Eğitim öğretim yılı': plan.egitimOgretimYili,
      'Ders': plan.dersAdi,
      'Sınıf / şube': plan.sinifKodu,
      'Hafta / tarih': plan.haftaTarih,
      'Ders saati': plan.dersSaati,
    };
    final tablo =
        '<w:tbl><w:tblPr><w:tblW w:w="9638" w:type="dxa"/>'
        '<w:tblLayout w:type="fixed"/><w:tblBorders>'
        '${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((e) => '<w:$e w:val="single" w:sz="4" w:color="D9D9D9"/>').join()}'
        '</w:tblBorders><w:tblCellMar><w:top w:w="90" w:type="dxa"/><w:left w:w="100" w:type="dxa"/>'
        '<w:bottom w:w="90" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="2700"/><w:gridCol w:w="6938"/></w:tblGrid>'
        '${bilgiler.entries.map((e) => '<w:tr><w:tc><w:tcPr><w:tcW w:w="2700" w:type="dxa"/></w:tcPr>${p(e.key, kalin: true)}</w:tc>'
            '<w:tc><w:tcPr><w:tcW w:w="6938" w:type="dxa"/></w:tcPr>${p(e.value)}</w:tc></w:tr>').join()}</w:tbl>';
    final body =
        '${p('GÜNLÜK DERS PLANI', style: 'Title')}$tablo${p('')}'
        '${bolumler(plan).entries.where((e) => e.key != 'İmzalar').map((e) => '${p(e.key, style: 'Heading1')}${paragraflar(e.value)}').join()}'
        '${p("İmzalar", style: "Heading1")}'
        '<w:tbl><w:tblPr><w:tblW w:w="9638" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="4819"/><w:gridCol w:w="4819"/></w:tblGrid><w:tr><w:trPr><w:cantSplit/></w:trPr>'
        '<w:tc><w:tcPr><w:tcW w:w="4819" w:type="dxa"/></w:tcPr>${p(plan.ogretmenAdi)}${p("Ders Öğretmeni")}</w:tc>'
        '<w:tc><w:tcPr><w:tcW w:w="4819" w:type="dxa"/></w:tcPr>${p("UYGUNDUR")}${p("......................................")}${p("Okul Müdürü")}</w:tc></w:tr></w:tbl>'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>'
        '</w:sectPr>';
    final files = <String, String>{
      '[Content_Types].xml':
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>',
      '_rels/.rels':
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      'word/_rels/document.xml.rels':
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
      'word/styles.xml':
          '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial" w:eastAsia="Arial"/>'
          '<w:sz w:val="21"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault></w:docDefaults>'
          '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
          '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:pPr><w:keepNext/><w:jc w:val="center"/></w:pPr>'
          '<w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="000000"/></w:rPr></w:style>'
          '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>'
          '<w:pPr><w:keepNext/><w:spacing w:before="160"/></w:pPr><w:rPr><w:b/><w:color w:val="000000"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:pPr><w:keepNext/></w:pPr></w:style></w:styles>',
      'word/document.xml':
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$body</w:body></w:document>',
    };
    final archive = Archive();
    for (final e in files.entries) {
      final bytes = utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>${e.value}',
      );
      archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// Kaydedilmiş sürüm tekrar okunur; ön izleme belleği arşive kaynak olmaz.
  static Future<String> arsiveKaydet(
    BireyselGunlukPlan plan, {
    BireyselBelgeService? belgeService,
  }) async {
    final id = plan.id;
    if (id == null) throw StateError('Önce günlük planı kaydedin.');
    final guncel = await BireyselGunlukPlanService.getir(id);
    if (guncel.surum != plan.surum ||
        guncel.okulId != plan.okulId ||
        guncel.ogretmenProfilId != plan.ogretmenProfilId ||
        guncel.egitimOgretimYili != plan.egitimOgretimYili) {
      throw StateError('Günlük plan değişti. Güncel planı yeniden açın.');
    }
    final bytes = await pdfOlustur(guncel);
    final belge = await (belgeService ?? BireyselBelgeService.instance)
        .gunlukPlanPdfKaydet(
          gunlukPlanId: id,
          surum: guncel.surum,
          bytes: bytes,
        );
    return belge.id;
  }
}
