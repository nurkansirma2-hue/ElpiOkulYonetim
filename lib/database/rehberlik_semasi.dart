import 'package:sqflite/sqflite.dart';

class RehberlikSemasi {
  static const atamaTablosu = 'RehberlikAtama';
  static const modulTablolari = [
    'RehberlikKayit',
    'RehberlikBag',
    'RehberlikForm',
    'MesajForm',
    'MesajFormCevap',
  ];

  static const googleTablolari = [
    'RehberlikGoogleForm',
    'RehberlikFormDavet',
    'RehberlikGoogleYanit',
  ];

  static Future<void> moduluHazirla(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE RehberlikKayit (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      AtamaId INTEGER NOT NULL REFERENCES RehberlikAtama(RehberlikAtamaId) ON DELETE RESTRICT,
      Tur TEXT NOT NULL CHECK(Tur IN ('Toplanti','Gorusme','Gorev','Plan','Etkinlik','GorusTalebi')),
      Baslik TEXT NOT NULL CHECK(length(trim(Baslik)) BETWEEN 1 AND 300),
      Tarih TEXT, Durum TEXT NOT NULL DEFAULT 'Planlandi'
        CHECK(Durum IN ('Planlandi','Suruyor','Tamamlandi','Iptal')),
      OgrenciId INTEGER REFERENCES Ogrenci(OgrenciId) ON DELETE RESTRICT,
      Icerik TEXT NOT NULL DEFAULT '{}', Hassas INTEGER NOT NULL DEFAULT 0 CHECK(Hassas IN (0,1)),
      KaynakAnahtar TEXT, BelgeId TEXT,
      OlusturmaTarihi TEXT NOT NULL, GuncellemeTarihi TEXT,
      UNIQUE(AtamaId, KaynakAnahtar)
    )''');
    await db.execute(
      'CREATE INDEX IX_RehberlikKayit_Atama ON RehberlikKayit(AtamaId, Tur, Tarih)',
    );
    await db.execute('''CREATE TABLE RehberlikBag (
      KayitId INTEGER NOT NULL REFERENCES RehberlikKayit(Id) ON DELETE RESTRICT,
      IlgiliId INTEGER NOT NULL REFERENCES RehberlikKayit(Id) ON DELETE RESTRICT,
      PRIMARY KEY(KayitId, IlgiliId), CHECK(KayitId != IlgiliId)
    )''');
    await db.execute('''CREATE TABLE RehberlikForm (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      AtamaId INTEGER NOT NULL REFERENCES RehberlikAtama(RehberlikAtamaId) ON DELETE RESTRICT,
      OgrenciId INTEGER NOT NULL REFERENCES Ogrenci(OgrenciId) ON DELETE RESTRICT,
      Sorular TEXT NOT NULL, Cevaplar TEXT NOT NULL, OlusturmaTarihi TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IX_RehberlikForm_Ogrenci ON RehberlikForm(AtamaId,OgrenciId,Id)',
    );
    // Ortak mesajlaşmanın yapılandırılmış talepleri; rehberliğe bağımlı değildir.
    await db.execute('''CREATE TABLE MesajForm (
      Id TEXT PRIMARY KEY, OkulId TEXT NOT NULL, OgretmenProfilId INTEGER NOT NULL,
      EgitimOgretimYili TEXT NOT NULL, KaynakModul TEXT NOT NULL, KaynakKayit TEXT NOT NULL,
      Baslik TEXT NOT NULL, AliciTuru TEXT NOT NULL CHECK(AliciTuru IN ('Ogretmen','Ogrenci','Veli')),
      Ogrenciler TEXT NOT NULL, SinifGeneli INTEGER NOT NULL CHECK(SinifGeneli IN (0,1)),
      Soru TEXT NOT NULL, OlusturmaTarihi TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE MesajFormCevap (
      Id TEXT PRIMARY KEY, FormId TEXT NOT NULL REFERENCES MesajForm(Id) ON DELETE RESTRICT,
      Yanitlayan TEXT NOT NULL, SinifGorusu TEXT NOT NULL, OgrenciGorusleri TEXT NOT NULL,
      OlusturmaTarihi TEXT NOT NULL
    )''');
  }

  /// Google Forms ilişkileri mevcut tanıma fişlerinin içeriğinden ayrıdır.
  /// Gerçek davet kodu ve hassas yanıt metni burada tutulmaz.
  static Future<void> googleFormHazirla(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE RehberlikGoogleForm (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      AtamaId INTEGER NOT NULL REFERENCES RehberlikAtama(RehberlikAtamaId) ON DELETE RESTRICT,
      GoogleFormId TEXT NOT NULL UNIQUE CHECK(length(trim(GoogleFormId)) > 0),
      SoruEslemeleri TEXT NOT NULL DEFAULT '{}',
      Surum INTEGER NOT NULL DEFAULT 1 CHECK(Surum > 0),
      Durum TEXT NOT NULL DEFAULT 'Taslak' CHECK(Durum IN ('Taslak','Aktif','Kapali')),
      OlusturmaTarihi TEXT NOT NULL, GuncellemeTarihi TEXT,
      UNIQUE(AtamaId)
    )''');
    await db.execute('''CREATE TABLE RehberlikFormDavet (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      FormId INTEGER NOT NULL REFERENCES RehberlikGoogleForm(Id) ON DELETE RESTRICT,
      OgrenciId INTEGER NOT NULL REFERENCES Ogrenci(OgrenciId) ON DELETE RESTRICT,
      KodOzeti TEXT NOT NULL UNIQUE CHECK(length(trim(KodOzeti)) > 0),
      SonGecerlilikTarihi TEXT, IptalTarihi TEXT,
      OlusturmaTarihi TEXT NOT NULL,
      UNIQUE(FormId, OgrenciId)
    )''');
    await db.execute('''CREATE TABLE RehberlikGoogleYanit (
      Id INTEGER PRIMARY KEY AUTOINCREMENT,
      FormId INTEGER NOT NULL REFERENCES RehberlikGoogleForm(Id) ON DELETE RESTRICT,
      DavetId INTEGER REFERENCES RehberlikFormDavet(Id) ON DELETE RESTRICT,
      GoogleYanitId TEXT NOT NULL CHECK(length(trim(GoogleYanitId)) > 0),
      Durum TEXT NOT NULL DEFAULT 'Bekliyor'
        CHECK(Durum IN ('Bekliyor','Kontrol','Reddedildi','Onaylandi')),
      RehberlikFormId INTEGER REFERENCES RehberlikForm(Id) ON DELETE RESTRICT,
      OlusturmaTarihi TEXT NOT NULL, KontrolTarihi TEXT,
      UNIQUE(FormId, GoogleYanitId)
    )''');
    await db.execute(
      'CREATE INDEX IX_RehberlikGoogleYanit_Durum ON RehberlikGoogleYanit(FormId, Durum)',
    );
  }

  static Future<void> hazirla(DatabaseExecutor db) async {
    // Atamanın yılı sınıfın yılıyla aynı kalır; profilin güncel yılına bağlanmaz.
    await db.execute(
      'CREATE UNIQUE INDEX UX_SinifSube_IdYil '
      'ON SinifSube (SinifSubeId, EgitimOgretimYili)',
    );
    await db.execute('''CREATE TABLE RehberlikAtama (
      RehberlikAtamaId INTEGER PRIMARY KEY AUTOINCREMENT,
      OkulId TEXT NOT NULL,
      OgretmenProfilId INTEGER NOT NULL,
      SinifSubeId INTEGER NOT NULL,
      EgitimOgretimYili TEXT NOT NULL CHECK(length(trim(EgitimOgretimYili)) > 0),
      BaslangicTarihi TEXT NOT NULL CHECK (
        length(BaslangicTarihi) = 10 AND
        BaslangicTarihi GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND
        date(BaslangicTarihi, '+0 days') IS NOT NULL AND
        date(BaslangicTarihi, '+0 days') = BaslangicTarihi
      ),
      BitisTarihi TEXT CHECK (
        BitisTarihi IS NULL OR (
          length(BitisTarihi) = 10 AND
          BitisTarihi GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND
          date(BitisTarihi, '+0 days') IS NOT NULL AND
          date(BitisTarihi, '+0 days') = BitisTarihi AND
          BitisTarihi >= BaslangicTarihi
        )
      ),
      OlusturmaTarihi TEXT NOT NULL,
      GuncellemeTarihi TEXT,
      UNIQUE (OkulId, OgretmenProfilId, SinifSubeId, EgitimOgretimYili, BaslangicTarihi),
      FOREIGN KEY (OkulId) REFERENCES OkulProfil(OkulId) ON DELETE RESTRICT,
      FOREIGN KEY (OgretmenProfilId) REFERENCES OgretmenProfil(OgretmenProfilId)
        ON DELETE RESTRICT,
      FOREIGN KEY (SinifSubeId, EgitimOgretimYili)
        REFERENCES SinifSube(SinifSubeId, EgitimOgretimYili) ON DELETE RESTRICT
    )''');
    await db.execute(
      'CREATE INDEX IX_RehberlikAtama_ProfilYil '
      'ON RehberlikAtama (OkulId, OgretmenProfilId, EgitimOgretimYili)',
    );
    await db.execute(
      'CREATE INDEX IX_RehberlikAtama_SinifYil '
      'ON RehberlikAtama (SinifSubeId, EgitimOgretimYili)',
    );
  }
}
