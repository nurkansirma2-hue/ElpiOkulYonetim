import 'dart:convert';
import 'dart:isolate';

import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:sqflite/sqflite.dart';

import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../models/ortak_import.dart';
import 'calisma_modu_service.dart';
import 'xls_import_okuyucu.dart';

class ImportTablosu {
  ImportTablosu(this.ad, List<List<String>> rows)
    : satirlar = List.unmodifiable(
        rows.map((r) => List<String>.unmodifiable(r)),
      );
  final String ad;
  final List<List<String>> satirlar;

  int baslikBul(ImportTanimi definition) {
    var best = -1, score = 0;
    for (var r = 0; r < satirlar.length && r < 100; r++) {
      final mapping = otomatikEsle(definition, r);
      final current = mapping.keys.fold<int>(
        0,
        (sum, key) =>
            sum +
            (definition.alanlar.firstWhere((f) => f.anahtar == key).zorunlu
                ? 3
                : 1),
      );
      if (current > score) {
        best = r;
        score = current;
      }
    }
    return best;
  }

  Map<String, int> otomatikEsle(ImportTanimi definition, int header) {
    if (header < 0 || header >= satirlar.length) return {};
    final result = <String, int>{};
    for (final field in definition.alanlar) {
      if (!field.kolondan) continue;
      final candidates = <int>[
        for (var c = 0; c < satirlar[header].length; c++)
          if (field.baslikEslesir(satirlar[header][c])) c,
      ];
      if (candidates.length == 1) result[field.anahtar] = candidates.single;
    }
    // Bir kolon birden çok alana aday ise manuel karar gerekir.
    final repeated = result.values
        .where((c) => result.values.where((v) => v == c).length > 1)
        .toSet();
    result.removeWhere((_, c) => repeated.contains(c));
    return result;
  }

  List<String> eslemeHatalari(
    ImportTanimi definition,
    int header,
    Map<String, int> mapping,
  ) {
    if (header < 0 || header >= satirlar.length) {
      return ['Başlık satırını seçin.'];
    }
    return [
      for (final field in definition.alanlar)
        if (field.zorunlu &&
            field.kolonDisiKapsam == null &&
            !mapping.containsKey(field.anahtar))
          '${field.ad} alanını eşleştirin.',
      if (mapping.values.toSet().length != mapping.length)
        'Aynı kolon birden fazla alana atanamaz.',
      if (mapping.keys.any(
            (k) => !definition.alanlar.any((f) => f.anahtar == k),
          ) ||
          mapping.values.any((c) => c < 0 || c >= satirlar[header].length))
        'Kolon eşleştirmesi geçersiz.',
    ];
  }

  List<ImportKaynakSatiri> esle(int header, Map<String, int> mapping) => [
    for (var r = header + 1; r < satirlar.length; r++)
      if (satirlar[r].any((v) => v.trim().isNotEmpty) &&
          !_tekrarBaslik(satirlar[r], satirlar[header], mapping))
        ImportKaynakSatiri('$ad:$r', '$ad, satır ${r + 1}', {
          for (final entry in mapping.entries)
            entry.key: entry.value < satirlar[r].length
                ? satirlar[r][entry.value].trim()
                : '',
        }),
  ];

  bool _tekrarBaslik(
    List<String> row,
    List<String> header,
    Map<String, int> mapping,
  ) =>
      mapping.isNotEmpty &&
      mapping.values.every(
        (c) =>
            c < row.length &&
            importNormalize(row[c]) == importNormalize(header[c]),
      );
}

class ImportProfili {
  ImportProfili({
    required this.ad,
    required this.modul,
    required this.surum,
    required this.basliklar,
    required this.esleme,
  });
  final String ad, modul;
  final int surum;
  final List<String> basliklar;
  final Map<String, String> esleme;

  Map<String, int>? uygula(
    ImportTanimi definition,
    List<String> headers, {
    bool benzer = false,
  }) {
    if (modul != definition.id || surum != definition.surum) return null;
    final normalized = headers.map(importNormalize).toList();
    final old = basliklar.toSet();
    final current = normalized.toSet();
    if (!benzer &&
        (old.length != current.length || !old.containsAll(current))) {
      return null;
    }
    if (benzer &&
        old.intersection(current).length / old.union(current).length < .6) {
      return null;
    }
    final result = <String, int>{};
    for (final entry in esleme.entries) {
      if (!definition.alanlar.any((f) => f.anahtar == entry.key)) return null;
      final candidates = <int>[
        for (var c = 0; c < normalized.length; c++)
          if (normalized[c] == entry.value) c,
      ];
      if (candidates.length != 1) return null;
      result[entry.key] = candidates.single;
    }
    if (result.values.toSet().length != result.length ||
        definition.alanlar.any(
          (f) =>
              f.zorunlu &&
              f.kolonDisiKapsam == null &&
              !result.containsKey(f.anahtar),
        )) {
      return null;
    }
    return result;
  }

  Map<String, Object> toJson() => {
    'ad': ad,
    'modul': modul,
    'surum': surum,
    'basliklar': basliklar,
    'esleme': esleme,
  };
  factory ImportProfili.fromJson(Map<String, dynamic> json) => ImportProfili(
    ad: json['ad'] as String,
    modul: json['modul'] as String,
    surum: json['surum'] as int,
    basliklar: List<String>.from(json['basliklar'] as List),
    esleme: Map<String, String>.from(json['esleme'] as Map),
  );
}

class OrtakImportService {
  /// Aynı dosyada kolon, ortak etiket ve çoklu blok/kart kaynaklarını birleştirir.
  /// Eksik zorunlu değerler kayıt olarak korunur; modülün doğrulamasına gider.
  static List<ImportKaynakSatiri> kaynaklariOku(
    ImportTanimi definition,
    List<ImportTablosu> tables, {
    int? baslik,
    int tablo = 0,
    Map<String, int>? esleme,
  }) {
    final result = <ImportKaynakSatiri>[];
    final fileValues = <String, String>{};
    final keys = definition.alanlar.map((f) => f.anahtar).toSet();
    for (var t = 0; t < tables.length; t++) {
      final table = tables[t];
      final pageValues = <String, String>{}, blockValues = <String, String>{};
      var mapping = <String, int>{};
      for (var r = 0; r < table.satirlar.length; r++) {
        final row = table.satirlar[r];
        if (row.every((v) => v.trim().isEmpty)) continue;
        final block = definition.blokBaslangici?.call(row);
        if (block != null) {
          if (block.keys.any((k) => !keys.contains(k))) {
            throw StateError('Blok tanımında bilinmeyen alan var.');
          }
          blockValues
            ..clear()
            ..addAll(block);
          mapping = {};
          continue;
        }
        final automatic = table.otomatikEsle(definition, r);
        final requiredColumns = definition.alanlar.where(
          (f) => f.zorunlu && f.kolondan && f.kolonDisiKapsam == null,
        );
        if ((t == tablo && baslik != null && r == baslik) ||
            (automatic.isNotEmpty &&
                requiredColumns.isNotEmpty &&
                requiredColumns.every(
                  (f) => automatic.containsKey(f.anahtar),
                ))) {
          mapping = t == tablo && baslik != null && r == baslik
              ? (esleme ?? automatic)
              : automatic;
          if (mapping.keys.any((k) => !keys.contains(k)) ||
              mapping.values.any((c) => c < 0 || c >= row.length) ||
              mapping.values.toSet().length != mapping.length) {
            throw StateError('Kolon eşleştirmesi geçersiz.');
          }
          continue;
        }
        var metadata = false;
        for (final field in definition.alanlar.where(
          (f) => f.kolonDisiKapsam != null,
        )) {
          for (var c = 0; c < row.length; c++) {
            final split = row[c].indexOf(':');
            final label = split >= 0 ? row[c].substring(0, split) : row[c];
            if (!field.baslikEslesir(label)) continue;
            metadata = true;
            var value = split >= 0 ? row[c].substring(split + 1).trim() : '';
            if (value.isEmpty && c + 1 < row.length) value = row[c + 1].trim();
            final target = switch (field.kolonDisiKapsam!) {
              ImportBilgiKapsami.dosya => fileValues,
              ImportBilgiKapsami.sayfa => pageValues,
              ImportBilgiKapsami.blok => blockValues,
            };
            if (target.containsKey(field.anahtar) &&
                target[field.anahtar] != value) {
              throw FormatException(
                '${table.ad}, satır ${r + 1}: ${field.ad} ortak bilgisi çelişiyor.',
              );
            }
            target[field.anahtar] = value;
          }
        }
        if (metadata) continue;
        final cards = definition.kartKayitlariniOku?.call(row);
        final records =
            cards ??
            (mapping.isEmpty
                ? <Map<String, String>>[]
                : [
                    {
                      for (final e in mapping.entries)
                        e.key: e.value >= 0 && e.value < row.length
                            ? row[e.value].trim()
                            : '',
                    },
                  ]);
        for (var n = 0; n < records.length; n++) {
          if (records[n].keys.any((k) => !keys.contains(k))) {
            throw StateError('Kayıt tanımında bilinmeyen alan var.');
          }
          final values = <String, String>{
            ...fileValues,
            ...pageValues,
            ...blockValues,
          };
          for (final e in records[n].entries) {
            if (e.value.isNotEmpty || !values.containsKey(e.key)) {
              values[e.key] = e.value;
            }
          }
          result.add(
            ImportKaynakSatiri(
              '$t:$r:$n',
              '${table.ad}, satır ${r + 1}',
              values,
            ),
          );
        }
      }
    }
    return result;
  }

  static Future<void> bireyselModuDogrula() async {
    if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError(
        'Bu import yalnız bireysel öğretmen modunda kullanılabilir.',
      );
    }
  }

  static Future<List<ImportTablosu>> oku(ImportDosya file) async {
    if (file.bytes.isEmpty || file.bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('Dosya boş veya 50 MB sınırından büyük.');
    }
    return Isolate.run(() => tablolariOku(file));
  }

  static List<ImportTablosu> tablolariOku(ImportDosya file) {
    String cell(dynamic v) => v is num && v.isFinite && v == v.roundToDouble()
        ? v.toInt().toString()
        : (v ?? '').toString().trim();
    if (file.uzanti == 'csv') {
      final text = utf8.decode(file.bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
      return [ImportTablosu('CSV', csvOku(text))];
    }
    if (file.uzanti == 'xlsx') {
      final decoder = SpreadsheetDecoder.decodeBytes(file.bytes);
      return [
        for (final table in decoder.tables.entries)
          ImportTablosu(
            table.key,
            table.value.rows.map((r) => r.map(cell).toList()).toList(),
          ),
      ];
    }
    if (file.uzanti == 'xls') {
      return [
        for (final sheet in XlsImportOkuyucu.oku(file.bytes))
          ImportTablosu(
            sheet.ad,
            sheet.satirlar.map((r) => r.map(cell).toList()).toList(),
          ),
      ];
    }
    throw const FormatException('XLS, XLSX veya UTF-8 CSV dosyası seçin.');
  }

  /// Tırnaklı ayraçlar, çift tırnak kaçışı ve çok satırlı hücreler desteklenir.
  static List<List<String>> csvOku(String text) {
    var delimiter = ',', best = -1;
    for (final candidate in [',', ';', '\t']) {
      var count = 0, quoted = false;
      for (var i = 0; i < text.length; i++) {
        final ch = text[i];
        if (ch == '"') {
          if (quoted && i + 1 < text.length && text[i + 1] == '"') {
            i++;
          } else {
            quoted = !quoted;
          }
        } else if (!quoted && (ch == '\r' || ch == '\n')) {
          break;
        } else if (!quoted && ch == candidate) {
          count++;
        }
      }
      if (count > best) {
        delimiter = candidate;
        best = count;
      }
    }
    final rows = <List<String>>[], row = <String>[];
    var buffer = StringBuffer(), quoted = false, closed = false;
    void cell() {
      row.add(buffer.toString());
      buffer = StringBuffer();
      closed = false;
    }

    void line() {
      cell();
      rows.add(List.of(row));
      row.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          buffer.write(ch);
        }
      } else if (ch == delimiter) {
        cell();
      } else if (ch == '\r' || ch == '\n') {
        line();
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      } else if (ch == '"' && buffer.isEmpty && !closed) {
        quoted = true;
      } else if (closed) {
        if (ch.trim().isNotEmpty) {
          throw const FormatException(
            'CSV: Kapanan tırnaktan sonra geçersiz karakter.',
          );
        }
      } else if (ch == '"') {
        throw const FormatException('CSV: Hücre içinde kaçışsız tırnak.');
      } else {
        buffer.write(ch);
      }
    }
    if (quoted) throw const FormatException('CSV: Kapatılmamış tırnak.');
    if (buffer.isNotEmpty || row.isNotEmpty || closed) line();
    return rows;
  }

  static String _key(ImportTanimi definition) =>
      'ortak_import_profilleri:${definition.id}';

  static Future<List<ImportProfili>> profilleriGetir(
    ImportTanimi definition,
  ) async {
    await bireyselModuDogrula();
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'UygulamaAyarlari',
      columns: ['Deger'],
      where: 'Anahtar = ?',
      whereArgs: [_key(definition)],
    );
    if (rows.isEmpty) return [];
    return (jsonDecode(rows.single['Deger'] as String) as List)
        .map((p) => ImportProfili.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
  }

  static Future<void> profilKaydet(
    ImportTanimi definition,
    ImportTablosu table,
    int header,
    Map<String, int> mapping,
    String name,
  ) async {
    await bireyselModuDogrula();
    if (name.trim().isEmpty) throw StateError('Profil adı boş bırakılamaz.');
    final errors = table.eslemeHatalari(definition, header, mapping);
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    final headers = table.satirlar[header].map(importNormalize).toList();
    if (mapping.values.any(
      (c) =>
          headers[c].isEmpty ||
          headers.where((h) => h == headers[c]).length != 1,
    )) {
      throw StateError(
        'Profil için eşleştirilen kolon başlıkları dolu ve benzersiz olmalıdır.',
      );
    }
    final profile = ImportProfili(
      ad: name.trim(),
      modul: definition.id,
      surum: definition.surum,
      basliklar: headers,
      esleme: {for (final e in mapping.entries) e.key: headers[e.value]},
    );
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'UygulamaAyarlari',
        where: 'Anahtar = ?',
        whereArgs: [_key(definition)],
      );
      final profiles = rows.isEmpty
          ? <ImportProfili>[]
          : (jsonDecode(rows.single['Deger'] as String) as List)
                .map(
                  (p) => ImportProfili.fromJson(
                    Map<String, dynamic>.from(p as Map),
                  ),
                )
                .toList();
      profiles.removeWhere((p) => p.ad == profile.ad);
      profiles.add(profile);
      await txn.insert('UygulamaAyarlari', {
        'Anahtar': _key(definition),
        'Deger': jsonEncode(profiles.map((p) => p.toJson()).toList()),
        'GuncellemeTarihi': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
