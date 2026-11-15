import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

class ProjeOdevRaporService {
  static Future<Uint8List> olustur(
    String uzanti,
    String baslik,
    String kapsam,
    List<List<String>> rows,
  ) async {
    if (rows.isEmpty) throw const FormatException('Rapor başlıkları gerekli.');
    if (uzanti == 'xlsx') {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.appendRow([baslik]);
      sheet.appendRow([kapsam]);
      for (final row in rows) {
        sheet.appendRow(row);
      }
      return Uint8List.fromList(excel.encode()!);
    }
    if (uzanti == 'docx') {
      String x(String s) => XmlText(
        s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''),
      ).toXmlString();
      String p(String s) =>
          '<w:p><w:r><w:t xml:space="preserve">${x(s)}</w:t></w:r></w:p>';
      final body =
          '${p(baslik)}${p(kapsam)}<w:tbl><w:tblPr><w:tblBorders>'
          '${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((e) => '<w:$e w:val="single" w:sz="4" w:color="BBBBBB"/>').join()}'
          '</w:tblBorders></w:tblPr>${rows.map((r) => '<w:tr>${r.map((c) => '<w:tc>${p(c)}</w:tc>').join()}</w:tr>').join()}</w:tbl>'
          '<w:p/><w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>'
          '<w:pgMar w:top="720" w:bottom="720" w:left="720" w:right="720"/></w:sectPr>';
      final files = {
        '[Content_Types].xml':
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        '_rels/.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
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
    if (uzanti != 'pdf') {
      throw const FormatException('Desteklenmeyen rapor biçimi.');
    }
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        maxPages: 200,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        footer: (c) => pw.Text('${c.pageNumber}/${c.pagesCount}'),
        build: (_) => [
          pw.Text(baslik, style: pw.TextStyle(font: bold, fontSize: 16)),
          pw.SizedBox(height: 6),
          pw.Text(kapsam),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: rows.first,
            data: rows.skip(1).toList(),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(font: bold, fontSize: 8),
          ),
        ],
      ),
    );
    return pdf.save();
  }
}
