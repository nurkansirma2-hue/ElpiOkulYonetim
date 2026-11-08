import 'package:sqflite/sqflite.dart';

class BelgeArsiviSemasi {
  BelgeArsiviSemasi._();

  static Future<void> hazirla(DatabaseExecutor db) async {
    // Sahiplik anlık görüntüsü sıfırlamada da korunur. Silinen profillere
    // foreign key kurulmaz; belgeler yalnız kalıcı arşiv kaydına bağlıdır.
    await db.execute('''
      CREATE TABLE BelgeArsivi (
        ArsivId TEXT NOT NULL PRIMARY KEY,
        OkulId TEXT NOT NULL CHECK (length(trim(OkulId)) > 0),
        OgretmenProfilId INTEGER NOT NULL CHECK (OgretmenProfilId > 0),
        OkulAdi TEXT NOT NULL,
        OgretmenAdi TEXT NOT NULL,
        OlusturmaTarihi TEXT NOT NULL,
        UNIQUE (OkulId, OgretmenProfilId)
      )
    ''');
    await db.execute('''
      CREATE TABLE BireyselBelge (
        BelgeId TEXT NOT NULL PRIMARY KEY,
        ArsivId TEXT NOT NULL,
        DosyaAdi TEXT NOT NULL CHECK (length(trim(DosyaAdi)) > 0),
        AramaAdi TEXT NOT NULL,
        GoreliYol TEXT NOT NULL UNIQUE,
        Uzanti TEXT NOT NULL,
        Boyut INTEGER NOT NULL CHECK (Boyut > 0),
        IcerikOzeti TEXT,
        EgitimOgretimYili TEXT NOT NULL,
        EklenmeTarihi TEXT NOT NULL,
        Durum TEXT NOT NULL CHECK (Durum IN ('Hazirlaniyor', 'Hazir', 'Eksik')),
        FOREIGN KEY (ArsivId) REFERENCES BelgeArsivi (ArsivId)
          ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IX_BireyselBelge_ArsivTarih '
      'ON BireyselBelge (ArsivId, EklenmeTarihi, BelgeId)',
    );
    await db.execute(
      'CREATE INDEX IX_BireyselBelge_Icerik '
      'ON BireyselBelge (ArsivId, Boyut, IcerikOzeti)',
    );
  }

  static Future<void> yonetimiHazirla(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE BelgeSilmeBekleyen (
      BelgeId TEXT NOT NULL PRIMARY KEY, ArsivId TEXT NOT NULL,
      Uzanti TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE BelgeKlasoru (
      KlasorId TEXT NOT NULL PRIMARY KEY,
      ArsivId TEXT NOT NULL REFERENCES BelgeArsivi(ArsivId),
      Ad TEXT NOT NULL CHECK(length(trim(Ad)) > 0),
      AramaAdi TEXT NOT NULL,
      UNIQUE(ArsivId, AramaAdi)
    )''');
    await db.execute(
      "ALTER TABLE BireyselBelge ADD COLUMN KlasorId TEXT REFERENCES BelgeKlasoru(KlasorId)",
    );
    await db.execute(
      "ALTER TABLE BireyselBelge ADD COLUMN BelgeTuru TEXT NOT NULL DEFAULT 'Genel belge'",
    );
    await db.execute('ALTER TABLE BireyselBelge ADD COLUMN Analiz TEXT');
    await db.execute(
      'ALTER TABLE BireyselBelge ADD COLUMN TurElleSecildi INTEGER NOT NULL DEFAULT 0 CHECK(TurElleSecildi IN (0, 1))',
    );
    await db.execute('ALTER TABLE BireyselBelge ADD COLUMN SilinmeTarihi TEXT');
    await db.execute('''CREATE TABLE BelgeImportGecmisi (
      IslemId TEXT NOT NULL PRIMARY KEY,
      BelgeId TEXT NOT NULL REFERENCES BireyselBelge(BelgeId),
      Modul TEXT NOT NULL,
      EgitimOgretimYili TEXT NOT NULL,
      Tarih TEXT NOT NULL,
      Eklenen INTEGER NOT NULL CHECK(Eklenen >= 0),
      Guncellenen INTEGER NOT NULL CHECK(Guncellenen >= 0),
      Mesaj TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IX_BelgeImportGecmisi ON BelgeImportGecmisi(BelgeId, Tarih)',
    );
    await db.execute(
      'CREATE INDEX IX_BelgeKlasorFiltre ON BireyselBelge(ArsivId, KlasorId, SilinmeTarihi)',
    );
  }
}
