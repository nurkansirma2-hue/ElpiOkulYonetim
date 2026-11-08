import '../database/local_database.dart';
import 'bireysel_profil_service.dart';

class BireyselDersHucresiEkleService {
  static Future<({List<String> dersler, List<String> siniflar, List<String> derslikler})> secenekler() async {
    final profil = await BireyselProfilService.getir();
    final yil = (profil?['EgitimOgretimYili'] ?? '').toString();
    final db = await LocalDatabase.instance.database;
    final ders = await db.query('Ders', columns: ['DersAdi'],
      where: 'Aktif = 1', orderBy: 'DersAdi');
    final sinif = await db.query('SinifSube', columns: ['SinifKodu'],
      where: 'Aktif = 1 AND EgitimOgretimYili = ?', whereArgs: [yil],
      orderBy: 'SinifKodu');
    final derslik = await db.rawQuery('''
      SELECT DISTINCT TRIM(Derslik) AS Ad FROM DersProgrami
      WHERE Derslik IS NOT NULL AND TRIM(Derslik) != ''
      ORDER BY Ad
    ''');
    return (
      dersler: ders.map((e) => e['DersAdi'].toString()).toSet().toList(),
      siniflar: sinif.map((e) => e['SinifKodu'].toString()).toSet().toList(),
      derslikler: derslik.map((e) => e['Ad'].toString()).toList(),
    );
  }

  static Future<void> kaydet({
    required String gun,
    required int saat,
    required String dersAdi,
    required String sinifKodu,
    required String derslik,
  }) async {
    final ad = dersAdi.trim(), sinif = sinifKodu.trim(), yer = derslik.trim();
    if (ad.isEmpty || sinif.isEmpty || ad.length > 150 || sinif.length > 30 ||
        yer.length > 100 || saat < 1 || saat > 20 ||
        !const ['Pazartesi','Salı','Çarşamba','Perşembe','Cuma'].contains(gun)) {
      throw const FormatException('Ders, sınıf veya saat bilgileri geçersiz.');
    }
    final profil = await BireyselProfilService.getir();
    final id = profil?['OgretmenProfilId'] as int?;
    final yil = (profil?['EgitimOgretimYili'] ?? '').toString();
    if (id == null || yil.isEmpty) throw StateError('Aktif öğretmen bulunamadı.');
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final surumler = await txn.rawQuery('''
        SELECT ProgramSurumId FROM DersProgramiSurum
        WHERE OgretmenProfilId = ? AND EgitimOgretimYili = ? AND Aktif = 1
        AND (BaslangicTarihi IS NULL OR BaslangicTarihi <= date('now','localtime'))
        AND (BitisTarihi IS NULL OR BitisTarihi >= date('now','localtime'))
      ''', [id, yil]);
      if (surumler.length != 1) throw StateError('Geçerli tek ders programı sürümü bulunamadı.');
      final surum = surumler.single['ProgramSurumId'] as int;
      final saatler = await txn.query('DersSaati',
        where: 'SiraNo = ? AND Aktif = 1', whereArgs: [saat]);
      if (saatler.length != 1) throw StateError('Ders saati tanımlı değil.');
      final saatId = saatler.single['DersSaatiId'] as int;
      final varOlan = await txn.query('DersProgrami',
        where: 'ProgramSurumId = ? AND Gun = ? AND DersSaatiId = ? AND Aktif = 1',
        whereArgs: [surum,gun,saatId], limit: 1);
      final gorev = await txn.query('DersProgramiGorev',
        where: 'ProgramSurumId = ? AND Gun = ? AND DersSaatiNo = ?',
        whereArgs: [surum,gun,saat], limit: 1);
      final seflik = await txn.rawQuery('''
        SELECT 1 FROM SeflikProgramSaati WHERE OgretmenProfilId = ?
        AND EgitimOgretimYili = ? AND Gun = ? AND DersSaatiNo = ?
        AND Aktif = 1 AND BaslangicTarihi <= date('now','localtime')
        AND (BitisTarihi IS NULL OR BitisTarihi >= date('now','localtime')) LIMIT 1
      ''', [id,yil,gun,saat]);
      if (varOlan.isNotEmpty || gorev.isNotEmpty || seflik.isNotEmpty) {
        throw StateError('Bu hücre artık boş değil. Programı yenileyin.');
      }
      final zaman = await txn.rawQuery('''
        SELECT Baslangic, Bitis FROM DersProgrami
        WHERE ProgramSurumId = ? AND DersSaatiId = ?
        AND Aktif = 1 AND Baslangic IS NOT NULL AND Bitis IS NOT NULL LIMIT 1
      ''', [surum,saatId]);
      final bas = (saatler.single['Baslangic'] ?? (zaman.isEmpty ? null : zaman.single['Baslangic']))?.toString() ?? '';
      final bit = (saatler.single['Bitis'] ?? (zaman.isEmpty ? null : zaman.single['Bitis']))?.toString() ?? '';
      if (bas.isEmpty || bit.isEmpty || bas.compareTo(bit) >= 0) {
        throw StateError('Önce ders saatinin başlangıç ve bitişini tanımlayın.');
      }
      final simdi = DateTime.now().toIso8601String();
      final dersler = await txn.query('Ders', where: 'DersAdi = ? AND Aktif = 1',
        whereArgs: [ad]);
      final dersId = dersler.isNotEmpty
        ? dersler.first['DersId'] as int
        : await txn.insert('Ders', {'DersAdi':ad,'Aktif':1,'OlusturmaTarihi':simdi});
      final siniflar = await txn.query('SinifSube',
        where: 'SinifKodu = ? AND EgitimOgretimYili = ?',
        whereArgs: [sinif,yil]);
      final sinifId = siniflar.isNotEmpty
        ? siniflar.first['SinifSubeId'] as int
        : await txn.insert('SinifSube', {
            'SinifKodu':sinif, 'EgitimOgretimYili':yil,
            'Aktif':1,'OlusturmaTarihi':simdi});
      if (siniflar.isNotEmpty && siniflar.first['Aktif'] != 1) {
        await txn.update('SinifSube', {'Aktif':1},
          where:'SinifSubeId = ?', whereArgs:[sinifId]);
      }
      final bag = await txn.query('DersSinif',
        where:'DersId = ? AND SinifSubeId = ? AND EgitimOgretimYili = ?',
        whereArgs:[dersId,sinifId,yil]);
      if (bag.isEmpty) {
        await txn.insert('DersSinif', {
          'DersId':dersId,'SinifSubeId':sinifId,
          'EgitimOgretimYili':yil,'Aktif':1,'OlusturmaTarihi':simdi});
      } else if (bag.first['Aktif'] != 1) {
        await txn.update('DersSinif', {'Aktif':1},
          where:'DersSinifId = ?', whereArgs:[bag.first['DersSinifId']]);
      }
      await txn.insert('DersProgrami', {
        'ProgramSurumId':surum,'SinifSubeId':sinifId,'DersId':dersId,
        'DersSaatiId':saatId,'Gun':gun,'Baslangic':bas,'Bitis':bit,
        'Derslik':yer.isEmpty?null:yer,'OgretmenProfilId':id,
        'EgitimOgretimYili':yil,'Aktif':1,'OlusturmaTarihi':simdi,
      });
    });
  }
}
