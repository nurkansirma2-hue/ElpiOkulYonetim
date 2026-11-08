import 'package:sqflite/sqflite.dart';

/// V30: mevcut ödev tablolarını yeniden kurmadan rutin kontrolün yeni alt türü.
class DersUygulamaSemasi {
  static const tablolar = ['OdevUygulama', 'OdevUygulamaSonuc'];
  static Future<void> hazirla(DatabaseExecutor db) async {
    if (!(await db.rawQuery(
      'PRAGMA table_info(OdevTanim)',
    )).any((r) => r['name'] == 'DersUygulamalari')) {
      await db.execute('''ALTER TABLE OdevTanim ADD COLUMN DersUygulamalari
        INTEGER NOT NULL DEFAULT 0 CHECK(DersUygulamalari IN (0,1)
        AND (DersUygulamalari=0 OR GorevTuru='RutinKontrol'))''');
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS OdevUygulama (
      UygulamaId INTEGER PRIMARY KEY AUTOINCREMENT,
      OdevId INTEGER NOT NULL REFERENCES OdevTanim(OdevId) ON DELETE RESTRICT,
      Sira INTEGER NOT NULL CHECK(Sira>0),
      Ad TEXT NOT NULL CHECK(length(trim(Ad)) BETWEEN 1 AND 150),
      AdAnahtari TEXT NOT NULL CHECK(length(trim(AdAnahtari))>0),
      Adet INTEGER NOT NULL DEFAULT 1 CHECK(Adet > 0),
      Aktif INTEGER NOT NULL DEFAULT 1 CHECK(Aktif IN (0,1)),
      UNIQUE(OdevId,AdAnahtari), UNIQUE(OdevId,Sira), UNIQUE(UygulamaId,OdevId)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS OdevUygulamaSonuc (
      OdevId INTEGER NOT NULL, UygulamaId INTEGER NOT NULL,
      OdevKontrolId INTEGER NOT NULL, OgrenciId INTEGER NOT NULL,
      Durum TEXT NOT NULL CHECK(Durum IN ('Yapti','Kismen','Yapmadi',
        'Gelmedi','Mazeretli','KontrolEdilmedi','Manuel')),
      NotDegeri INTEGER CHECK(NotDegeri IS NULL OR
        (typeof(NotDegeri)='integer' AND NotDegeri BETWEEN 0 AND 10)),
      Aciklama TEXT, GuncellemeTarihi TEXT NOT NULL,
      Adet INTEGER CHECK(Adet > 0),
      Yapilan INTEGER CHECK(Yapilan >= 0 AND Yapilan <= Adet),
      PRIMARY KEY(OdevKontrolId,OgrenciId,UygulamaId),
      FOREIGN KEY(UygulamaId,OdevId) REFERENCES OdevUygulama(UygulamaId,OdevId) ON DELETE RESTRICT,
      FOREIGN KEY(OdevKontrolId,OdevId) REFERENCES OdevKontrol(OdevKontrolId,OdevId) ON DELETE RESTRICT,
      FOREIGN KEY(OdevId,OgrenciId) REFERENCES OdevOgrenci(OdevId,OgrenciId) ON DELETE RESTRICT
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS IX_OdevUygulamaSonuc_Ogrenci
      ON OdevUygulamaSonuc(OdevId,OgrenciId,UygulamaId)''');
    for (final table in tablolar) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((c) => c['name'] == 'Adet')) {
        await db.execute(
          "ALTER TABLE $table ADD COLUMN Adet INTEGER ${table == 'OdevUygulama' ? 'NOT NULL DEFAULT 1' : ''} CHECK(Adet > 0)",
        );
      }
      if (table == 'OdevUygulamaSonuc' &&
          !columns.any((c) => c['name'] == 'Yapilan')) {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN Yapilan INTEGER CHECK(Yapilan >= 0 AND Yapilan <= Adet)',
        );
      }
    }
  }
}
