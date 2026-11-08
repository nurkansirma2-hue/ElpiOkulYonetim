import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

/// PDFium çağrıları aynı isolate üzerinde sıralı yapılır; belge ve sayfa
/// tutamaçları ile ayrılan bellek hata halinde de kapatılır.
class DbfPdfOkuyucu {
  static bool _hazir = false;
  static List<String> oku(
    Uint8List bytes, {
    void Function(int, int)? sayfaOkundu,
    Map<int, List<String>>? programDersleri,
  }) {
    final pdf = pdfiumBindings;
    if (!_hazir) {
      pdf.FPDF_InitLibrary();
      _hazir = true;
    }
    final data = calloc<Uint8>(bytes.length);
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      final doc = pdf.FPDF_LoadMemDocument64(
        data.cast(),
        bytes.length,
        nullptr,
      );
      if (doc == nullptr) {
        throw const FormatException(
          'PDF açılamadı; bozuk veya şifreli olabilir.',
        );
      }
      try {
        final count = pdf.FPDF_GetPageCount(doc);
        if (count < 1 ||
            count > 100 ||
            pdf.FPDF_GetSecurityHandlerRevision(doc) >= 0) {
          throw const FormatException(
            'Şifresiz, en fazla 100 sayfalık DBF gerekli.',
          );
        }
        final pages = <String>[];
        var total = 0;
        for (var i = 0; i < count; i++) {
          final page = pdf.FPDF_LoadPage(doc, i);
          if (page == nullptr) {
            throw FormatException('Sayfa ${i + 1} açılamadı.');
          }
          try {
            final text = pdf.FPDFText_LoadPage(page);
            if (text == nullptr) {
              throw FormatException('Sayfa ${i + 1} okunamadı.');
            }
            try {
              final chars = pdf.FPDFText_CountChars(text);
              if (chars < 0 || total + chars > 1000000) {
                throw const FormatException('DBF metni boyut sınırını aşıyor.');
              }
              total += chars;
              final buffer = calloc<UnsignedShort>(chars + 1);
              try {
                final read = pdf.FPDFText_GetText(text, 0, chars, buffer);
                if (read <= 0 || read > chars + 1) {
                  throw FormatException('Sayfa ${i + 1} metin içermiyor.');
                }
                pages.add(
                  String.fromCharCodes(
                    buffer.cast<Uint16>().asTypedList(read - 1),
                  ),
                );
                if (programDersleri != null) {
                  final metin = pages.last;
                  final h = metin.indexOf('Öğretmenin Adı');
                  final hds = metin.indexOf('HDS');
                  if (h >= 0 && hds >= 0 && metin.contains('Sınıfın Adı')) {
                    final box = calloc<Double>(4);
                    try {
                      if (pdf.FPDFText_GetCharBox(
                            text,
                            hds,
                            box,
                            box + 1,
                            box + 2,
                            box + 3,
                          ) ==
                          0) {
                        throw const FormatException(
                          'Ders tablosunun sütun konumu okunamadı.',
                        );
                      }
                      final dersSag = box.value - 1;
                      final karakterler = <(int, double, double, double)>[];
                      for (var c = 0; c < chars; c++) {
                        final kod = pdf.FPDFText_GetUnicode(text, c);
                        if (kod <= 32) continue;
                        if (pdf.FPDFText_GetCharBox(
                                  text,
                                  c,
                                  box,
                                  box + 1,
                                  box + 2,
                                  box + 3,
                                ) !=
                                0 &&
                            box.value >= 0 &&
                            box[1] < dersSag) {
                          karakterler.add((
                            c,
                            box.value,
                            box[1],
                            (box[2] + box[3]) / 2,
                          ));
                        }
                      }
                      final dersler = <String>[];
                      var offset = h + 'Öğretmenin Adı'.length;
                      for (final line
                          in metin
                              .substring(offset)
                              .split('\n')
                              .map((l) => l.trim())
                              .where((l) => l.isNotEmpty)) {
                        if (RegExp(r'^\d+\.$|^Toplam\s+Saat').hasMatch(line)) {
                          break;
                        }
                        final index = metin.indexOf(line, offset);
                        if (index < 0 ||
                            pdf.FPDFText_GetCharBox(
                                  text,
                                  index,
                                  box,
                                  box + 1,
                                  box + 2,
                                  box + 3,
                                ) ==
                                0) {
                          throw const FormatException(
                            'Öğretmen satırının ders konumu okunamadı.',
                          );
                        }
                        offset = index + line.length;
                        final merkez = (box[2] + box[3]) / 2;
                        final secilen =
                            karakterler
                                .where((c) => (c.$4 - merkez).abs() < 3)
                                .toList()
                              ..sort((a, b) => a.$1.compareTo(b.$1));
                        dersler.add(
                          secilen.isEmpty
                              ? ''
                              : metin
                                    .substring(
                                      secilen.first.$1,
                                      secilen.last.$1 + 1,
                                    )
                                    .replaceAll(RegExp(r'\s+'), ' ')
                                    .trim(),
                        );
                      }
                      programDersleri[i] = dersler;
                    } finally {
                      calloc.free(box);
                    }
                  }
                }
                sayfaOkundu?.call(i + 1, count);
              } finally {
                calloc.free(buffer);
              }
            } finally {
              pdf.FPDFText_ClosePage(text);
            }
          } finally {
            pdf.FPDF_ClosePage(page);
          }
        }
        return pages;
      } finally {
        pdf.FPDF_CloseDocument(doc);
      }
    } finally {
      calloc.free(data);
    }
  }
}
