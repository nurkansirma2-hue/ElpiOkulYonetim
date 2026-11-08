import 'dart:typed_data';
import 'package:excel2003/excel2003.dart';
// Paket OLE okuyucusunu dışa aktarmıyor; mevcut okuyucu tekrar kullanılır.
// ignore: implementation_imports
import 'package:excel2003/src/ole2/ole2_reader.dart';

class XlsImportSayfasi {
  XlsImportSayfasi(this.ad, this.satirlar);
  final String ad;
  final List<List<dynamic>> satirlar;
}

class XlsImportOkuyucu {
  static List<XlsImportSayfasi> oku(Uint8List bytes) {
    final ole = Ole2Reader()..openBytes(bytes);
    final entry = ole.findEntry('Workbook') ?? ole.findEntry('Book');
    if (entry == null) {
      throw const FormatException('XLS çalışma kitabı bulunamadı.');
    }
    final workbook = ole.readEntry(entry);
    final data = ByteData.sublistView(workbook);
    final offsets = <int>[];
    final segments = <Uint8List>[];
    var continuing = false;
    for (var p = 0; p + 4 <= workbook.length;) {
      final type = data.getUint16(p, Endian.little);
      final end = p + 4 + data.getUint16(p + 2, Endian.little);
      if (end > workbook.length) {
        throw const FormatException('Eksik XLS kaydı.');
      }
      if (type == 0x85) offsets.add(data.getUint32(p + 4, Endian.little));
      if (type == 0xfc || (type == 0x3c && continuing)) {
        segments.add(Uint8List.sublistView(workbook, p + 4, end));
        continuing = true;
      } else {
        continuing = false;
      }
      p = end;
      if (type == 0x0a) break;
    }
    final strings = segments.isEmpty ? <String>[] : metinleriOku(segments);
    final reader = XlsReader.fromBytes(bytes);
    final result = <XlsImportSayfasi>[];
    for (var s = 0; s < reader.sheetCount; s++) {
      final sheet = reader.sheet(s);
      final rows = [
        for (var r = 0; r < sheet.lastRow; r++)
          [for (var c = 0; c < sheet.lastCol; c++) sheet.cell(r, c)],
      ];
      for (var p = offsets[s]; p + 4 <= workbook.length;) {
        final type = data.getUint16(p, Endian.little);
        final size = data.getUint16(p + 2, Endian.little);
        final end = p + 4 + size;
        if (end > workbook.length) {
          throw const FormatException('Eksik XLS sayfa kaydı.');
        }
        if (type == 0xfd) {
          if (size < 10) {
            throw const FormatException('Eksik XLS metin hücresi.');
          }
          final r = data.getUint16(p + 4, Endian.little);
          final c = data.getUint16(p + 6, Endian.little);
          final index = data.getUint32(p + 10, Endian.little);
          if (index >= strings.length ||
              r >= rows.length ||
              c >= rows[r].length) {
            throw const FormatException(
              'Geçersiz XLS metin hücresi bağlantısı.',
            );
          }
          rows[r][c] = strings[index];
        }
        p = end;
        if (type == 0x0a) break;
      }
      result.add(XlsImportSayfasi(sheet.name, rows));
    }
    return result;
  }

  /// BIFF8 SST/CONTINUE: yalnız karakter devamında yeni kodlama baytı bulunur.
  static List<String> metinleriOku(List<Uint8List> segments) {
    final cursor = _SstCursor(segments);
    cursor.uint(4); // toplam başvuru sayısı
    final count = cursor.uint(4);
    if (count > segments.fold<int>(0, (n, s) => n + s.length) ~/ 3) {
      throw const FormatException('Geçersiz XLS metin sayısı.');
    }
    final strings = <String>[];
    for (var n = 0; n < count; n++) {
      final length = cursor.uint(2), flags = cursor.uint(1);
      final runs = flags & 8 != 0 ? cursor.uint(2) : 0;
      final extension = flags & 4 != 0 ? cursor.uint(4) : 0;
      var wide = flags & 1 != 0;
      final chars = <int>[];
      for (var c = 0; c < length; c++) {
        if (cursor.atEnd) {
          cursor.next();
          wide = cursor.uint(1) & 1 != 0;
        }
        if (wide && cursor.remaining < 2) {
          throw const FormatException('Eksik XLS Unicode karakteri.');
        }
        chars.add(cursor.uint(wide ? 2 : 1));
      }
      cursor.skip(runs * 4 + extension);
      strings.add(String.fromCharCodes(chars));
    }
    return strings;
  }
}

class _SstCursor {
  _SstCursor(this.segments);
  final List<Uint8List> segments;
  int segment = 0, offset = 0;
  int get remaining => segments[segment].length - offset;
  bool get atEnd => remaining == 0;
  void next() {
    segment++;
    offset = 0;
    if (segment >= segments.length || segments[segment].isEmpty) {
      throw const FormatException('Eksik XLS metin devam kaydı.');
    }
  }

  int uint(int size) {
    var value = 0;
    for (var i = 0; i < size; i++) {
      if (atEnd) next();
      value |= segments[segment][offset++] << (8 * i);
    }
    return value;
  }

  void skip(int count) {
    while (count > 0) {
      if (atEnd) next();
      final size = count < remaining ? count : remaining;
      offset += size;
      count -= size;
    }
  }
}
