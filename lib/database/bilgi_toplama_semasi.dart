import 'package:sqflite/sqflite.dart';

/// v20: rehberlik atamasından bağımsız form ve onay kuyruğu.
/// Kimlik cevapları yalnız yanıtta tutulur; öğrenciye yazılmaz.
class BilgiToplamaSemasi {
  static const ogrenciAlanlari = [
    'AnneAdi',
    'BabaAdi',
    'AnneTelefon',
    'BabaTelefon',
    'Telefon',
  ];
  // Bağımlılık sırası: yedek uyarlaması ve ters sırada sıfırlama için.
  static const tablolar = [
    'BilgiToplamaForm',
    'BilgiToplamaSoru',
    'BilgiToplamaHedef',
    'BilgiToplamaYanit',
    'BilgiToplamaEsleme',
    'OgrenciEkBilgiDeger',
  ];

  static Future<void> hazirla(DatabaseExecutor db) async {
    final mevcut = (await db.rawQuery(
      'PRAGMA table_info(Ogrenci)',
    )).map((r) => r['name']).toSet();
    for (final alan in ogrenciAlanlari) {
      if (!mevcut.contains(alan)) {
        await db.execute('ALTER TABLE Ogrenci ADD COLUMN $alan TEXT');
      }
    }
    await db.execute('''CREATE TABLE BilgiToplamaForm (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      OkulId TEXT NOT NULL REFERENCES OkulProfil(OkulId) ON DELETE RESTRICT,
      OgretmenProfilId INTEGER NOT NULL REFERENCES OgretmenProfil(OgretmenProfilId) ON DELETE RESTRICT,
      EgitimOgretimYili TEXT NOT NULL CHECK(length(trim(EgitimOgretimYili)) > 0),
      Baslik TEXT NOT NULL CHECK(length(trim(Baslik)) BETWEEN 1 AND 300),
      GoogleFormId TEXT UNIQUE,
      HedefTuru TEXT NOT NULL CHECK(HedefTuru IN ('TumOkul','Siniflarim','SinifSec','OgrenciSec')),
      Durum TEXT NOT NULL DEFAULT 'Taslak' CHECK(Durum IN ('Taslak','Aktif','Kapali')),
      Surum INTEGER NOT NULL DEFAULT 1 CHECK(Surum > 0),
      OlusturmaTarihi TEXT NOT NULL, GuncellemeTarihi TEXT
    )''');
    await db.execute('''CREATE TABLE BilgiToplamaSoru (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      FormId INTEGER NOT NULL REFERENCES BilgiToplamaForm(Id) ON DELETE RESTRICT,
      AlanAnahtari TEXT NOT NULL CHECK(length(trim(AlanAnahtari)) > 0),
      Baslik TEXT NOT NULL CHECK(length(trim(Baslik)) BETWEEN 1 AND 300),
      VeriTuru TEXT NOT NULL CHECK(VeriTuru IN ('Metin','Sayi','Tarih','EvetHayir','Secenek','Telefon')),
      HedefAlan TEXT CHECK(HedefAlan IS NULL OR HedefAlan IN ('AnneAdi','BabaAdi','AnneTelefon','BabaTelefon','Telefon')),
      Secenekler TEXT NOT NULL DEFAULT '[]',
      Zorunlu INTEGER NOT NULL DEFAULT 0 CHECK(Zorunlu IN (0,1)),
      Sira INTEGER NOT NULL CHECK(Sira > 0), GoogleSoruId TEXT,
      UNIQUE(FormId, AlanAnahtari), UNIQUE(FormId, Sira),
      UNIQUE(FormId, GoogleSoruId), UNIQUE(Id, FormId)
    )''');
    await db.execute('''CREATE TABLE BilgiToplamaHedef (
      FormId INTEGER NOT NULL REFERENCES BilgiToplamaForm(Id) ON DELETE RESTRICT,
      OgrenciId INTEGER NOT NULL REFERENCES Ogrenci(OgrenciId) ON DELETE RESTRICT,
      PRIMARY KEY(FormId, OgrenciId)
    )''');
    await db.execute('''CREATE TABLE BilgiToplamaYanit (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      FormId INTEGER NOT NULL REFERENCES BilgiToplamaForm(Id) ON DELETE RESTRICT,
      GoogleYanitId TEXT NOT NULL CHECK(length(trim(GoogleYanitId)) > 0),
      KaynakSurum TEXT NOT NULL CHECK(length(trim(KaynakSurum)) > 0),
      FormSurum INTEGER NOT NULL CHECK(FormSurum > 0),
      GirilenOkulNo TEXT NOT NULL, GirilenAdSoyad TEXT NOT NULL, GirilenSinif TEXT NOT NULL,
      HamYanit TEXT NOT NULL, SoruAnlikGoruntusu TEXT NOT NULL,
      OgrenciId INTEGER REFERENCES Ogrenci(OgrenciId) ON DELETE RESTRICT,
      Durum TEXT NOT NULL DEFAULT 'Bekliyor' CHECK(Durum IN ('Bekliyor','Kontrol','Reddedildi','Onaylandi')),
      OnaylayanProfilId INTEGER REFERENCES OgretmenProfil(OgretmenProfilId) ON DELETE RESTRICT,
      OnayTarihi TEXT, OlusturmaTarihi TEXT NOT NULL,
      UNIQUE(FormId, GoogleYanitId, KaynakSurum), UNIQUE(Id, FormId),
      UNIQUE(Id, FormId, OgrenciId),
      CHECK(Durum != 'Onaylandi' OR (OgrenciId IS NOT NULL AND OnaylayanProfilId IS NOT NULL AND OnayTarihi IS NOT NULL)),
      FOREIGN KEY(FormId, OgrenciId) REFERENCES BilgiToplamaHedef(FormId, OgrenciId) ON DELETE RESTRICT
    )''');
    // Her yönetici düzeltmesi ayrı satırdır; özgün cevaplar değiştirilmez.
    await db.execute('''CREATE TABLE BilgiToplamaEsleme (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      YanitId INTEGER NOT NULL, FormId INTEGER NOT NULL,
      OncekiOgrenciId INTEGER REFERENCES Ogrenci(OgrenciId) ON DELETE RESTRICT,
      YeniOgrenciId INTEGER NOT NULL,
      KontrolEdenProfilId INTEGER NOT NULL REFERENCES OgretmenProfil(OgretmenProfilId) ON DELETE RESTRICT,
      Aciklama TEXT NOT NULL CHECK(length(trim(Aciklama)) > 0), Tarih TEXT NOT NULL,
      FOREIGN KEY(YanitId, FormId) REFERENCES BilgiToplamaYanit(Id, FormId) ON DELETE RESTRICT,
      FOREIGN KEY(FormId, YeniOgrenciId) REFERENCES BilgiToplamaHedef(FormId, OgrenciId) ON DELETE RESTRICT
    )''');
    await db.execute('''CREATE TABLE OgrenciEkBilgiDeger (
      YanitId INTEGER NOT NULL, FormId INTEGER NOT NULL, SoruId INTEGER NOT NULL,
      OgrenciId INTEGER NOT NULL, Deger TEXT NOT NULL CHECK(length(trim(Deger)) > 0),
      PRIMARY KEY(YanitId, SoruId),
      FOREIGN KEY(YanitId, FormId, OgrenciId) REFERENCES BilgiToplamaYanit(Id, FormId, OgrenciId) ON DELETE RESTRICT,
      FOREIGN KEY(SoruId, FormId) REFERENCES BilgiToplamaSoru(Id, FormId) ON DELETE RESTRICT
    )''');
    await db.execute(
      'CREATE INDEX IX_BilgiToplamaForm_Kapsam ON BilgiToplamaForm(OkulId, OgretmenProfilId, EgitimOgretimYili)',
    );
    await db.execute(
      'CREATE INDEX IX_BilgiToplamaYanit_Durum ON BilgiToplamaYanit(FormId, Durum)',
    );
    await db.execute(
      'CREATE INDEX IX_OgrenciEkBilgi_Ogrenci ON OgrenciEkBilgiDeger(OgrenciId, SoruId)',
    );
  }
}
