import 'package:sqflite/sqflite.dart';
import '../database/local_database.dart';
import 'bireysel_profil_service.dart';

/// Sadece boş program hücrelerine manuel görev ekler.
/// Excel'den aktarılmış şeflik kayıtlarına müdahale etmez.
class BireyselProgramGorevAtamaService {
  BireyselProgramGorevAtamaService._();

  static Future<void> ata({
    required String gun,
    required int dersSaatiNo,
    required String gorev,
  }) async {
    if (!const ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma'].contains(gun) ||
        dersSaatiNo <= 0 || !const ['Şeflik', 'Koordinatörlük'].contains(gorev)) {
      throw ArgumentError('Görev veya ders saati geçersiz.');
    }
    final profil = await BireyselProfilService.getir();
    final id = profil?['OgretmenProfilId'] as int?;
    final yil = (profil?['EgitimOgretimYili'] ?? '').toString();
    if (id == null || yil.isEmpty) throw StateError('Aktif öğretmen bulunamadı.');
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final surumler = await txn.rawQuery('''
        SELECT * FROM DersProgramiSurum
        WHERE OgretmenProfilId = ? AND EgitimOgretimYili = ? AND Aktif = 1
          AND (BaslangicTarihi IS NULL OR BaslangicTarihi <= date('now','localtime'))
          AND (BitisTarihi IS NULL OR BitisTarihi >= date('now','localtime'))
        ORDER BY ProgramSurumId DESC LIMIT 1
      ''', [id, yil]);
      if (surumler.isEmpty) throw StateError('Önce ders programını yükleyin.');
      final surum = surumler.first['ProgramSurumId'] as int;
      final bas = surumler.first['BaslangicTarihi'] as String?;
      if (bas == null) throw StateError('Program başlangıç tarihi tanımsız.');
      final dersler = await txn.rawQuery('''
        SELECT dp.DersProgramiId FROM DersProgrami dp
        WHERE dp.ProgramSurumId = ? AND dp.Gun = ? AND dp.Aktif = 1
          AND dp.DersSaatiId IN
            (SELECT DersSaatiId FROM DersSaati WHERE SiraNo = ?)
      ''', [surum, gun, dersSaatiNo]);
      if (dersler.isNotEmpty) throw StateError('Dolu ders hücresine görev atanamaz.');
      final koord = await txn.query('DersProgramiGorev',
        where: 'ProgramSurumId = ? AND Gun = ? AND DersSaatiNo = ?',
        whereArgs: [surum, gun, dersSaatiNo]);
      final seflik = await txn.rawQuery('''
        SELECT * FROM SeflikProgramSaati WHERE OgretmenProfilId = ?
          AND EgitimOgretimYili = ? AND Gun = ? AND DersSaatiNo = ?
          AND Aktif = 1 AND BaslangicTarihi <= date('now','localtime')
          AND (BitisTarihi IS NULL OR BitisTarihi >= date('now','localtime'))
      ''', [id, yil, gun, dersSaatiNo]);
      if (koord.isNotEmpty || seflik.isNotEmpty) {
        throw StateError('Hücrede zaten görev var. Önce mevcut görevi kontrol edin.');
      }
      final ornek = await txn.rawQuery('''
        SELECT Baslangic, Bitis FROM DersProgrami
        WHERE OgretmenProfilId = ? AND EgitimOgretimYili = ?
          AND ProgramSurumId = ? AND DersSaatiId IN
            (SELECT DersSaatiId FROM DersSaati WHERE SiraNo = ?)
          AND Baslangic IS NOT NULL AND Bitis IS NOT NULL
        LIMIT 1
      ''', [id, yil, surum, dersSaatiNo]);
      final saatTanim = await txn.query('DersSaati',
        columns: ['Baslangic', 'Bitis'],
        where: 'SiraNo = ? AND Aktif = 1', whereArgs: [dersSaatiNo],
        limit: 1);
      final ilk = ornek.isNotEmpty
          ? ornek.first['Baslangic'].toString()
          : (saatTanim.isEmpty ? '' : (saatTanim.first['Baslangic'] ?? '').toString());
      final son = ornek.isNotEmpty
          ? ornek.first['Bitis'].toString()
          : (saatTanim.isEmpty ? '' : (saatTanim.first['Bitis'] ?? '').toString());
      if (ilk.isEmpty || son.isEmpty) {
        throw StateError('Ders saati başlangıç/bitişi bilinmiyor.');
      }
      if (gorev == 'Koordinatörlük') {
        await txn.insert('DersProgramiGorev', {
          'ProgramSurumId': surum, 'Gun': gun, 'DersSaatiNo': dersSaatiNo,
          'Baslangic': ilk, 'Bitis': son, 'GorevAdi': 'Koordinatörlük',
        });
      } else {
        final ayar = await txn.query('UygulamaAyarlari',
          where: 'Anahtar = ?', whereArgs: ['MeslekPaketiAktif'], limit: 1);
        if (ayar.isEmpty || ayar.first['Deger'] != '1') {
          throw StateError('Şeflik için meslek paketi etkin olmalıdır.');
        }
        await txn.insert('SeflikProgramSaati', {
          'OgretmenProfilId': id, 'EgitimOgretimYili': yil, 'SeflikId': null,
          'Gun': gun, 'DersSaatiNo': dersSaatiNo,
          'Baslangic': ilk, 'Bitis': son,
          'BaslangicTarihi': bas, 'BitisTarihi': null,
          'Kaynak': 'Manuel', 'HamMetin': 'Şeflik',
          'Aktif': 1, 'OlusturmaTarihi': DateTime.now().toIso8601String(),
        });
      }
    });
  }
}
