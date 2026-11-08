import 'package:sqflite/sqflite.dart';

class SeflikYillikPlanSemasi {
  SeflikYillikPlanSemasi._();

  static Future<void> hazirla(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SeflikYillikFaaliyet (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        OgretmenProfilId INTEGER NOT NULL,
        EgitimOgretimYili TEXT NOT NULL,
        Tarih TEXT NOT NULL,
        Gun TEXT NOT NULL,
        DersSaatiNo INTEGER NOT NULL,
        Baslangic TEXT NOT NULL,
        Bitis TEXT NOT NULL,
        Faaliyet TEXT NOT NULL CHECK(length(trim(Faaliyet)) > 0),
        OnayTarihi TEXT NOT NULL,
        UNIQUE(OgretmenProfilId, EgitimOgretimYili, Tarih, DersSaatiNo),
        FOREIGN KEY(OgretmenProfilId)
          REFERENCES OgretmenProfil(OgretmenProfilId) ON DELETE RESTRICT
      )
    ''');
  }
}
