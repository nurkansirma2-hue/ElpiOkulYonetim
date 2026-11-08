import 'package:sqflite/sqflite.dart';

class GunlukPlanSemasi {
  GunlukPlanSemasi._();

  static const tablo = 'BireyselGunlukPlan';

  static Future<void> hazirla(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE BireyselGunlukPlan (
        GunlukPlanId INTEGER PRIMARY KEY AUTOINCREMENT,
        Surum INTEGER NOT NULL DEFAULT 1 CHECK (Surum > 0),
        OkulId TEXT NOT NULL CHECK (length(trim(OkulId)) > 0),
        OgretmenProfilId INTEGER NOT NULL,
        EgitimOgretimYili TEXT NOT NULL CHECK (
          EgitimOgretimYili GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
        ),
        DersId INTEGER NOT NULL,
        SinifSubeId INTEGER NOT NULL,
        SinifSeviyesi INTEGER NOT NULL CHECK (SinifSeviyesi > 0),
        OgretmenAdi TEXT NOT NULL,
        OkulAdi TEXT NOT NULL,
        DersAdi TEXT NOT NULL,
        SinifKodu TEXT NOT NULL,
        Tarih TEXT NOT NULL CHECK (
          length(Tarih) = 10 AND date(Tarih, '+0 days') IS NOT NULL
          AND date(Tarih, '+0 days') = Tarih
        ),
        Konu TEXT NOT NULL DEFAULT '',
        Kazanim TEXT NOT NULL DEFAULT '',
        OgrenmeCiktisi TEXT NOT NULL DEFAULT '',
        YontemTeknik TEXT NOT NULL DEFAULT '',
        AracGerec TEXT NOT NULL DEFAULT '',
        Degerlendirme TEXT NOT NULL DEFAULT '',
        DersinIslenisi TEXT NOT NULL DEFAULT '',
        Etkinlikler TEXT NOT NULL DEFAULT '',
        BelgeId TEXT,
        OlusturmaTarihi TEXT NOT NULL,
        GuncellemeTarihi TEXT,
        UNIQUE (OkulId, OgretmenProfilId, EgitimOgretimYili,
                DersId, SinifSubeId, Tarih),
        FOREIGN KEY (OkulId) REFERENCES OkulProfil (OkulId) ON DELETE RESTRICT,
        FOREIGN KEY (OgretmenProfilId) REFERENCES OgretmenProfil (OgretmenProfilId)
          ON DELETE RESTRICT,
        FOREIGN KEY (DersId) REFERENCES Ders (DersId) ON DELETE RESTRICT,
        FOREIGN KEY (SinifSubeId) REFERENCES SinifSube (SinifSubeId) ON DELETE RESTRICT,
        FOREIGN KEY (BelgeId) REFERENCES BireyselBelge (BelgeId) ON DELETE SET NULL
      )
    ''');
  }
}
