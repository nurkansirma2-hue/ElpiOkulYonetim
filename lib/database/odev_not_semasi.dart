import 'package:sqflite/sqflite.dart';

/// V28: eski durumlar aynen kalır; yeni sonuç tek bir değerle temsil edilir.
/// NotDegeri: 0..10 puan; null durum bilgisinden değerlendirilir.
class OdevNotSemasi {
  static const tablolar = [
    'PerformansTanim',
    'PerformansOdev',
    'PerformansSonuc',
    'OdevEk',
  ];
  static Future<void> hazirla(DatabaseExecutor db) async {
    final sonucKolonlari = await db.rawQuery(
      'PRAGMA table_info(OdevKontrolSonuc)',
    );
    if (!sonucKolonlari.any((r) => r['name'] == 'NotDegeri')) {
      await db.execute(
        'ALTER TABLE OdevKontrolSonuc ADD COLUMN NotDegeri INTEGER CHECK(NotDegeri IS NULL OR (typeof(NotDegeri)=\'integer\' AND NotDegeri BETWEEN 0 AND 10))',
      );
    }
    final gorevKolonlari = await db.rawQuery('PRAGMA table_info(OdevTanim)');
    if (!gorevKolonlari.any((r) => r['name'] == 'Tamamlandi')) {
      await db.execute(
        'ALTER TABLE OdevTanim ADD COLUMN Tamamlandi INTEGER NOT NULL DEFAULT 0 CHECK(Tamamlandi IN (0,1))',
      );
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS PerformansTanim (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      OgretmenProfilId INTEGER NOT NULL REFERENCES OgretmenProfil(OgretmenProfilId) ON DELETE RESTRICT,
      EgitimOgretimYili TEXT NOT NULL, Donem INTEGER NOT NULL CHECK(Donem IN (1,2)),
      DersId INTEGER NOT NULL REFERENCES Ders(DersId) ON DELETE RESTRICT,
      SinifSubeId INTEGER NOT NULL REFERENCES SinifSube(SinifSubeId) ON DELETE RESTRICT,
      Grup INTEGER NOT NULL CHECK(Grup IN (1,2)), Kriterler TEXT NOT NULL,
      OdevAgirligi INTEGER CHECK(OdevAgirligi IS NULL OR OdevAgirligi BETWEEN 0 AND 100),
      Surum INTEGER NOT NULL DEFAULT 0,
      UNIQUE(OgretmenProfilId,EgitimOgretimYili,Donem,DersId,SinifSubeId,Grup)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS PerformansOdev (
      PerformansId INTEGER NOT NULL REFERENCES PerformansTanim(Id) ON DELETE CASCADE,
      OdevId INTEGER NOT NULL REFERENCES OdevTanim(OdevId) ON DELETE CASCADE,
      PRIMARY KEY(PerformansId,OdevId)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS PerformansSonuc (
      PerformansId INTEGER NOT NULL REFERENCES PerformansTanim(Id) ON DELETE CASCADE,
      OgrenciId INTEGER NOT NULL REFERENCES Ogrenci(OgrenciId) ON DELETE RESTRICT,
      KriterPuanlari TEXT NOT NULL DEFAULT '{}',
      OdevPuani REAL, KriterPuani INTEGER, OneriPuani INTEGER,
      NihaiPuan INTEGER CHECK(NihaiPuan IS NULL OR NihaiPuan BETWEEN 0 AND 100),
      KaynakImza TEXT, GuncellemeTarihi TEXT NOT NULL,
      PRIMARY KEY(PerformansId,OgrenciId)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS OdevEk (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      OdevId INTEGER NOT NULL REFERENCES OdevTanim(OdevId) ON DELETE CASCADE,
      OdevKontrolSonucId INTEGER REFERENCES OdevKontrolSonuc(OdevKontrolSonucId) ON DELETE CASCADE,
      DosyaAdi TEXT NOT NULL, Veri BLOB NOT NULL,
      CHECK(length(Veri) BETWEEN 1 AND 10485760)
    )''');
  }
}
