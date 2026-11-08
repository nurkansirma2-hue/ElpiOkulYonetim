import '../database/local_database.dart';
import 'bireysel_profil_service.dart';

/// Yalnız gerçek ders kayıtlarını aynı geçerli program sürümünde taşır.
/// Görevler ve çoklu kayıtlı hücreler bilinçli olarak bu işlemden hariçtir.
class BireyselDersTasimaService {
  BireyselDersTasimaService._();

  static Future<void> tasi({
    required int kaynakId,
    required String hedefGun,
    required int hedefSaatNo,
  }) async {
    if (kaynakId <= 0 || hedefSaatNo <= 0 ||
        !const ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma']
            .contains(hedefGun)) {
      throw ArgumentError('Geçersiz kaynak veya hedef saat.');
    }
    final profil = await BireyselProfilService.getir();
    final profilId = profil?['OgretmenProfilId'] as int?;
    final yil = (profil?['EgitimOgretimYili'] ?? '').toString();
    if (profilId == null || yil.isEmpty) {
      throw StateError('Aktif öğretmen profili bulunamadı.');
    }
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final kaynaklar = await txn.query('DersProgrami',
        where: 'DersProgramiId = ? AND OgretmenProfilId = ? '
            'AND EgitimOgretimYili = ? AND Aktif = 1',
        whereArgs: [kaynakId, profilId, yil]);
      if (kaynaklar.length != 1) throw StateError('Kaynak ders güncel değil.');
      final kaynak = kaynaklar.single;
      final surum = kaynak['ProgramSurumId'] as int?;
      if (surum == null) throw StateError('Sürümü bilinmeyen ders taşınamaz.');
      final surumler = await txn.rawQuery('''
        SELECT ProgramSurumId FROM DersProgramiSurum
        WHERE ProgramSurumId = ? AND OgretmenProfilId = ?
          AND EgitimOgretimYili = ? AND Aktif = 1
          AND (BaslangicTarihi IS NULL OR BaslangicTarihi <= date('now','localtime'))
          AND (BitisTarihi IS NULL OR BitisTarihi >= date('now','localtime'))
      ''', [surum, profilId, yil]);
      if (surumler.length != 1) {
        throw StateError('Ders programı değişmiş. Ekranı yenileyin.');
      }
      final hedefSaatler = await txn.query('DersSaati',
        where: 'SiraNo = ? AND Aktif = 1', whereArgs: [hedefSaatNo]);
      if (hedefSaatler.length != 1) {
        throw StateError('Hedef ders saati tanımlı değil.');
      }
      final hedefSaatId = hedefSaatler.single['DersSaatiId'] as int;
      final kaynakGun = kaynak['Gun'] as String;
      final kaynakSaatId = kaynak['DersSaatiId'] as int;
      if (kaynakGun == hedefGun && kaynakSaatId == hedefSaatId) return;

      final ayniSaat = await txn.rawQuery('''
        SELECT DersProgramiId FROM DersProgrami
        WHERE ProgramSurumId = ? AND Gun = ? AND DersSaatiId = ?
          AND OgretmenProfilId = ? AND Aktif = 1
      ''', [surum, kaynakGun, kaynakSaatId, profilId]);
      if (ayniSaat.length != 1) {
        throw StateError('Birden fazla ders bulunan kaynak hücre taşınamaz.');
      }
      final hedefler = await txn.rawQuery('''
        SELECT * FROM DersProgrami
        WHERE ProgramSurumId = ? AND Gun = ? AND DersSaatiId = ?
          AND OgretmenProfilId = ? AND Aktif = 1
      ''', [surum, hedefGun, hedefSaatId, profilId]);
      if (hedefler.length > 1) {
        throw StateError('Birden fazla ders bulunan hedef hücre değiştirilemez.');
      }
      final gorev = await txn.rawQuery('''
        SELECT 1 FROM DersProgramiGorev WHERE ProgramSurumId = ?
          AND ((Gun = ? AND DersSaatiNo = ?) OR (Gun = ? AND DersSaatiNo = ?))
        LIMIT 1
      ''', [surum, kaynakGun, await _saatNo(txn, kaynakSaatId), hedefGun, hedefSaatNo]);
      if (gorev.isNotEmpty) throw StateError('Görev içeren hücreler taşınamaz.');
      final seflik = await txn.rawQuery('''
        SELECT 1 FROM SeflikProgramSaati WHERE OgretmenProfilId = ?
          AND EgitimOgretimYili = ? AND Aktif = 1
          AND BaslangicTarihi <= date('now','localtime')
          AND (BitisTarihi IS NULL OR BitisTarihi >= date('now','localtime'))
          AND ((Gun = ? AND DersSaatiNo = ?) OR (Gun = ? AND DersSaatiNo = ?))
        LIMIT 1
      ''', [profilId, yil, kaynakGun, await _saatNo(txn, kaynakSaatId), hedefGun, hedefSaatNo]);
      if (seflik.isNotEmpty) throw StateError('Şeflik hücresi değiştirilemez.');

      final hedefId = hedefler.isEmpty ? null : hedefler.single['DersProgramiId'] as int;
      final simdi = DateTime.now().toIso8601String();
      // Dersin kendi sınıf/derslik ilişkisi korunur; yalnız zaman alanları takas edilir.
      if (hedefId != null) {
        await txn.update('DersProgrami', {
          'Gun': kaynakGun, 'DersSaatiId': kaynakSaatId,
          'Baslangic': kaynak['Baslangic'], 'Bitis': kaynak['Bitis'],
          'GuncellemeTarihi': simdi,
        }, where: 'DersProgramiId = ?', whereArgs: [hedefId]);
      }
      final hedefZaman = hedefler.isNotEmpty ? hedefler.single : null;
      final referans = hedefZaman ?? (await txn.rawQuery('''
        SELECT Baslangic, Bitis FROM DersProgrami
        WHERE ProgramSurumId = ? AND DersSaatiId = ? AND Aktif = 1
        LIMIT 1
      ''', [surum, hedefSaatId])).firstOrNull;
      if (referans == null || referans['Baslangic'] == null ||
          referans['Bitis'] == null) {
        throw StateError('Hedef ders saatinin zaman bilgisi bulunamadı.');
      }
      await txn.update('DersProgrami', {
        'Gun': hedefGun, 'DersSaatiId': hedefSaatId,
        'Baslangic': referans['Baslangic'], 'Bitis': referans['Bitis'],
        'GuncellemeTarihi': simdi,
      }, where: 'DersProgramiId = ?', whereArgs: [kaynakId]);
    });
  }

  static Future<int> _saatNo(dynamic txn, int id) async {
    final r = await txn.query('DersSaati',
        columns: ['SiraNo'], where: 'DersSaatiId = ?', whereArgs: [id]);
    if (r.length != 1) throw StateError('Ders saati bulunamadı.');
    return r.single['SiraNo'] as int;
  }
}
