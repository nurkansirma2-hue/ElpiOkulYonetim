part of 'bireysel_rehberlik_service.dart';

extension RehberlikTopluFormKaydi on BireyselRehberlikService {
  /// Eşleştirme yalnız bugün yazılabilir atamanın aktif öğrencilerinde yapılır.
  Future<List<Map<String, Object?>>> formImportOgrencileri(
    BireyselRehberlikBaglami b,
    int atamaId, {
    required bool hassasOnay,
  }) async {
    if (!hassasOnay) throw StateError('Hassas form erişimini açın.');
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atamaId, yazma: true);
      final rows = await tx.rawQuery(
        '''SELECT o.OgrenciId, o.OkulNo, o.Ad, o.Soyad,
        s.SinifKodu,
        (SELECT MAX(f.Id) FROM RehberlikForm f WHERE f.AtamaId=? AND f.OgrenciId=o.OgrenciId) AS SonFormId
        FROM Ogrenci o JOIN OgrenciSinifKayit k ON k.OgrenciId=o.OgrenciId
        JOIN SinifSube s ON s.SinifSubeId=k.SinifSubeId
        WHERE o.Aktif=1 AND k.Aktif=1 AND s.Aktif=1
          AND k.SinifSubeId=? AND k.EgitimOgretimYili=? AND s.EgitimOgretimYili=?
        ORDER BY CAST(o.OkulNo AS INTEGER), o.Ad, o.Soyad''',
        [
          atamaId,
          a['SinifSubeId'],
          a['EgitimOgretimYili'],
          a['EgitimOgretimYili'],
        ],
      );
      await _kontrol(tx, b);
      return rows
          .map((r) => Map<String, Object?>.unmodifiable(r))
          .toList(growable: false);
    });
  }

  /// Tüm seçimi tek transaction'da kaydeder; bir öğrencide hata olursa hiçbiri yazılmaz.
  Future<ImportOzet> formlariTopluKaydet(
    BireyselRehberlikBaglami b,
    int atamaId,
    List<RehberlikFormAktarimi> kayitlar, {
    required bool hassasOnay,
  }) async {
    if (!hassasOnay) throw StateError('Hassas form erişimini açın.');
    final items = List<RehberlikFormAktarimi>.unmodifiable(kayitlar);
    if (items.isEmpty ||
        items.length > 50 ||
        items.map((r) => r.ogrenciId).toSet().length != items.length) {
      throw const FormatException('En fazla 50 farklı öğrenci formu seçin.');
    }
    final allowed = ogrenciBilgiFormuSorulari.toSet();
    for (final r in items) {
      if (r.ogrenciId <= 0 ||
          r.cevaplar.keys.any((k) => !allowed.contains(k)) ||
          r.cevaplar.values.any((v) => v.length > 5000) ||
          jsonEncode(r.cevaplar).length > 100000) {
        throw const FormatException(
          'Toplu form alanlarını ve cevap uzunluklarını kontrol edin.',
        );
      }
    }
    final db = await _db();
    return _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atamaId, yazma: true);
        final sinif = (await tx.query(
          'SinifSube',
          where: 'SinifSubeId=?',
          whereArgs: [a['SinifSubeId']],
        )).single;
        if (sinif['EgitimOgretimYili'] != a['EgitimOgretimYili']) {
          throw StateError(
            'Sınıfın eğitim yılı değişti; ön izlemeyi yenileyin.',
          );
        }
        var added = 0, updated = 0, skipped = 0;
        for (final r in items) {
          await _ogrenciKontrol(tx, a, r.ogrenciId, yazma: true);
          final student = (await tx.query(
            'Ogrenci',
            where: 'OgrenciId=? AND Aktif=1',
            whereArgs: [r.ogrenciId],
          )).single;
          final patch = Map<String, String>.from(r.cevaplar)
            ..removeWhere((_, v) => v.trim().isEmpty);
          String number(String v) =>
              v.trim().replaceFirst(RegExp(r'^0+(?=\d)'), '');
          if (importNormalize(patch['Adınız Soyadınız'] ?? '') !=
                  importNormalize('${student['Ad']} ${student['Soyad']}') ||
              number(patch['Okul numaranız'] ?? '') !=
                  number('${student['OkulNo']}')) {
            throw StateError(
              'Formdaki okul numarası ve ad soyad güncel öğrenci kaydıyla uyuşmuyor. Ön izlemeyi yenileyin.',
            );
          }
          if (patch['Sınıfınız']?.trim().isNotEmpty == true &&
              importNormalize(patch['Sınıfınız']!).replaceAll(' ', '') !=
                  importNormalize(
                    '${sinif['SinifKodu']}',
                  ).replaceAll(' ', '')) {
            throw StateError(
              'Formdaki sınıf seçili rehberlik sınıfıyla uyuşmuyor.',
            );
          }
          final last = await tx.query(
            'RehberlikForm',
            where: 'AtamaId=? AND OgrenciId=?',
            whereArgs: [atamaId, r.ogrenciId],
            orderBy: 'Id DESC',
            limit: 1,
          );
          if ((last.isEmpty ? null : last.single['Id']) !=
              r.beklenenSonFormId) {
            throw StateError(
              'Ön izlemeden sonra bir öğrenci formu değişti. Hiçbir form kaydedilmedi; ön izlemeyi yenileyin.',
            );
          }
          final questions = last.isEmpty
              ? ogrenciBilgiFormuSorulari
              : List<String>.from(
                  jsonDecode(last.single['Sorular'] as String) as List,
                );
          final previous = last.isEmpty
              ? <String, String>{}
              : Map<String, String>.from(
                  jsonDecode(last.single['Cevaplar'] as String) as Map,
                );
          final merged = {...previous, ...patch};
          final mergedQuestions = {...questions, ...patch.keys}.toList();
          if (mergedQuestions.length > 100 ||
              jsonEncode(merged).length > 100000) {
            throw const FormatException(
              'Birleştirilmiş form soru veya içerik sınırını aşıyor. Hiçbir form kaydedilmedi.',
            );
          }
          final same =
              last.isNotEmpty &&
              questions.length == mergedQuestions.length &&
              previous.keys.every(mergedQuestions.contains) &&
              mergedQuestions.every(
                (q) => (previous[q] ?? '') == (merged[q] ?? ''),
              );
          if (same) {
            skipped++;
            continue;
          }
          await tx.insert('RehberlikForm', {
            'AtamaId': atamaId,
            'OgrenciId': r.ogrenciId,
            'Sorular': jsonEncode(mergedQuestions),
            'Cevaplar': jsonEncode(merged),
            'OlusturmaTarihi': DateTime.now().toIso8601String(),
          });
          if (last.isEmpty) {
            added++;
          } else {
            updated++;
          }
        }
        await _kontrol(tx, b);
        return ImportOzet(
          eklenen: added,
          guncellenen: updated,
          atlanan: skipped,
          hatali: 0,
          mesaj:
              '${added + updated} öğrenci formu yeni sürüm olarak kaydedildi. Değişmeyen: $skipped. Önceki sürümler ve boş bırakılan cevaplar korundu.',
        );
      }),
    );
  }
}
