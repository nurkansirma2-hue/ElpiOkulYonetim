import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'ders_programi_surumu.dart';
import 'belge_arsivi_semasi.dart';
import 'mesajlasma_semasi.dart';
import 'rehberlik_semasi.dart';
import 'gunluk_plan_semasi.dart';
import 'kaldirilan_moduller.dart';
import 'bilgi_toplama_semasi.dart';
import 'veli_iliskisi.dart';
import 'mesaj_alici_semasi.dart';
import 'mesaj_ogretmen_ders_semasi.dart';
import 'odev_not_semasi.dart';
import 'ders_uygulama_semasi.dart';
import 'odev_durum_temizligi.dart';
import 'seflik_yillik_plan_semasi.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();

  static const String _databaseName = 'okul_yonetim_bireysel.db';
  static const int _databaseVersion = 31;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, _databaseName);

      _database = await openDatabase(
        path,
        version: _databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      return _database!;
    } catch (e) {
      throw Exception(
        'Bireysel öğretmen veritabanı açılırken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    try {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE UygulamaAyarlari (
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            Anahtar TEXT NOT NULL UNIQUE,
            Deger TEXT,
            GuncellemeTarihi TEXT NOT NULL
          )
        ''');

        await txn.execute('''
          CREATE TABLE OgretmenProfil (
            OgretmenProfilId INTEGER PRIMARY KEY AUTOINCREMENT,
            AdSoyad TEXT NOT NULL,
            ProgramdakiAd TEXT,
            Brans TEXT,
            OkulAdi TEXT,
            EgitimOgretimYili TEXT NOT NULL,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT
          )
        ''');

        await txn.execute('''
          CREATE TABLE SinifSube (
            SinifSubeId INTEGER PRIMARY KEY AUTOINCREMENT,
            SinifKodu TEXT NOT NULL,
            SinifSeviyesi INTEGER,
            Sube TEXT,
            Alan TEXT,
            RehberOgretmen TEXT,
            EgitimOgretimYili TEXT NOT NULL,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT,
            UNIQUE (SinifKodu, EgitimOgretimYili)
          )
        ''');

        await txn.execute('''
          CREATE TABLE Ogrenci (
            OgrenciId INTEGER PRIMARY KEY AUTOINCREMENT,
            OkulNo TEXT NOT NULL,
            Ad TEXT NOT NULL,
            Soyad TEXT NOT NULL,
            Cinsiyet TEXT,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT,
            UNIQUE (OkulNo)
          )
        ''');

        await txn.execute('''
          CREATE TABLE OgrenciSinifKayit (
            OgrenciSinifKayitId INTEGER PRIMARY KEY AUTOINCREMENT,
            OgrenciId INTEGER NOT NULL,
            SinifSubeId INTEGER NOT NULL,
            EgitimOgretimYili TEXT NOT NULL,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT,
            UNIQUE (OgrenciId, SinifSubeId, EgitimOgretimYili),
            FOREIGN KEY (OgrenciId)
              REFERENCES Ogrenci (OgrenciId)
              ON DELETE RESTRICT,
            FOREIGN KEY (SinifSubeId)
              REFERENCES SinifSube (SinifSubeId)
              ON DELETE RESTRICT
          )
        ''');

        await txn.execute('''
          CREATE TABLE Ders (
            DersId INTEGER PRIMARY KEY AUTOINCREMENT,
            DersAdi TEXT NOT NULL,
            DersKodu TEXT,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT
          )
        ''');

        await txn.execute('''
          CREATE TABLE DersSinif (
            DersSinifId INTEGER PRIMARY KEY AUTOINCREMENT,
            DersId INTEGER NOT NULL,
            SinifSubeId INTEGER NOT NULL,
            EgitimOgretimYili TEXT NOT NULL,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            UNIQUE (DersId, SinifSubeId, EgitimOgretimYili),
            FOREIGN KEY (DersId)
              REFERENCES Ders (DersId)
              ON DELETE RESTRICT,
            FOREIGN KEY (SinifSubeId)
              REFERENCES SinifSube (SinifSubeId)
              ON DELETE RESTRICT
          )
        ''');

        await txn.execute('''
          CREATE TABLE DersSaati (
            DersSaatiId INTEGER PRIMARY KEY AUTOINCREMENT,
            SiraNo INTEGER NOT NULL,
            Baslangic TEXT,
            Bitis TEXT,
            Aktif INTEGER NOT NULL DEFAULT 1,
            UNIQUE (SiraNo)
          )
        ''');

        await txn.execute('''
          CREATE TABLE DersProgrami (
            DersProgramiId INTEGER PRIMARY KEY AUTOINCREMENT,
            SinifSubeId INTEGER NOT NULL,
            DersId INTEGER NOT NULL,
            DersSaatiId INTEGER NOT NULL,
            Gun TEXT NOT NULL,
            Baslangic TEXT,
            Bitis TEXT,
            Derslik TEXT,
            OgretmenProfilId INTEGER,
            EgitimOgretimYili TEXT NOT NULL,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT,
            FOREIGN KEY (SinifSubeId)
              REFERENCES SinifSube (SinifSubeId)
              ON DELETE RESTRICT,
            FOREIGN KEY (DersId)
              REFERENCES Ders (DersId)
              ON DELETE RESTRICT,
            FOREIGN KEY (DersSaatiId)
              REFERENCES DersSaati (DersSaatiId)
              ON DELETE RESTRICT,
            FOREIGN KEY (OgretmenProfilId)
              REFERENCES OgretmenProfil (OgretmenProfilId)
              ON DELETE SET NULL
          )
        ''');

        await txn.execute('''
          CREATE TABLE YillikPlan (
            YillikPlanId INTEGER PRIMARY KEY AUTOINCREMENT,
            DersId INTEGER NOT NULL,
            SinifSubeId INTEGER,
            OgretmenProfilId INTEGER,
            SinifSeviyesi INTEGER,
            EgitimOgretimYili TEXT NOT NULL,
            Aciklama TEXT,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT,
            FOREIGN KEY (DersId)
              REFERENCES Ders (DersId)
              ON DELETE RESTRICT,
            FOREIGN KEY (SinifSubeId)
              REFERENCES SinifSube (SinifSubeId)
              ON DELETE SET NULL,
            FOREIGN KEY (OgretmenProfilId)
              REFERENCES OgretmenProfil (OgretmenProfilId)
              ON DELETE SET NULL
          )
        ''');

        await txn.execute('''
          CREATE TABLE YillikPlanDetay (
            YillikPlanDetayId INTEGER PRIMARY KEY AUTOINCREMENT,
            YillikPlanId INTEGER NOT NULL,
            HaftaNo INTEGER,
            Ay TEXT,
            TarihAraligi TEXT,
            BaslangicTarihi TEXT,
            BitisTarihi TEXT,
            Saat TEXT,
            Konu TEXT,
            Unite TEXT,
            Kazanim TEXT,
            KazanimAciklamasi TEXT,
            OgrenmeBirimi TEXT,
            IcerikCercevesi TEXT,
            OgrenmeCiktisi TEXT,
            SurecBilesenleri TEXT,
            YontemTeknik TEXT,
            AracGerec TEXT,
            Degerlendirme TEXT,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT,
            FOREIGN KEY (YillikPlanId)
              REFERENCES YillikPlan (YillikPlanId)
              ON DELETE CASCADE
          )
        ''');

        await txn.execute('''
          CREATE TABLE CalismaTakvimi (
            CalismaTakvimiId INTEGER PRIMARY KEY AUTOINCREMENT,
            OgretmenProfilId INTEGER,
            EgitimOgretimYili TEXT NOT NULL,
            KaynakDosyaAdi TEXT,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT,
            UNIQUE (OgretmenProfilId, EgitimOgretimYili),
            FOREIGN KEY (OgretmenProfilId)
              REFERENCES OgretmenProfil (OgretmenProfilId)
              ON DELETE SET NULL
          )
        ''');

        await txn.execute('''
          CREATE TABLE CalismaTakvimiDetay (
            CalismaTakvimiDetayId INTEGER PRIMARY KEY AUTOINCREMENT,
            CalismaTakvimiId INTEGER NOT NULL,
            HaftaNo INTEGER,
            Ay TEXT,
            TarihAraligi TEXT,
            BaslangicTarihi TEXT,
            BitisTarihi TEXT,
            KayitTuru TEXT NOT NULL,
            CalismaVarMi INTEGER NOT NULL DEFAULT 1,
            Aciklama TEXT,
            OzelGunAciklamasi TEXT,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT,
            FOREIGN KEY (CalismaTakvimiId)
              REFERENCES CalismaTakvimi (CalismaTakvimiId)
              ON DELETE CASCADE
          )
        ''');

        await txn.execute('''
          CREATE TABLE OgrenciFotograf (
            OgrenciFotografId INTEGER PRIMARY KEY AUTOINCREMENT,
            OgrenciId INTEGER NOT NULL,
            DosyaYolu TEXT NOT NULL,
            DosyaAdi TEXT,
            Aktif INTEGER NOT NULL DEFAULT 1,
            OlusturmaTarihi TEXT NOT NULL,
            GuncellemeTarihi TEXT,
            UNIQUE (OgrenciId),
            FOREIGN KEY (OgrenciId)
              REFERENCES Ogrenci (OgrenciId)
              ON DELETE CASCADE
          )
        ''');

        await _surum4TablolariniHazirla(txn);
        await _surum5TablolariniHazirla(txn);
        await _surum6TablolariniHazirla(txn);
        await _surum7TablolariniHazirla(txn);
        await _surum8TablolariniHazirla(txn);
        await SeflikYillikPlanSemasi.hazirla(txn);
        await _surum9AlanlariniHazirla(txn);
        await DersProgramiSurumu.hazirla(txn);
        await BelgeArsiviSemasi.hazirla(txn);
        await BelgeArsiviSemasi.yonetimiHazirla(txn);

        await MesajlasmaSemasi.hazirla(txn);
        await RehberlikSemasi.hazirla(txn);
        await RehberlikSemasi.moduluHazirla(txn);
        await RehberlikSemasi.googleFormHazirla(txn);
        await GunlukPlanSemasi.hazirla(txn);
        await BilgiToplamaSemasi.hazirla(txn);
        await _performansOlcutTablolariniHazirla(txn);
        await VeliIliskisi.hazirla(txn);
        await MesajAliciSemasi.hazirla(txn);
        await MesajOgretmenDersSemasi.hazirla(txn);
        await MesajlasmaSemasi.ortakIletisimHazirla(txn);
        await MesajlasmaSemasi.tekliGecmisHazirla(txn);
        await OdevNotSemasi.hazirla(txn);
        await DersUygulamaSemasi.hazirla(txn);
        await OdevDurumTemizligi.hazirla(txn);

        await txn.execute('CREATE INDEX IX_Ogrenci_OkulNo ON Ogrenci (OkulNo)');

        await txn.execute(
          'CREATE INDEX IX_SinifSube_SinifKodu '
          'ON SinifSube (SinifKodu)',
        );

        await txn.execute(
          'CREATE INDEX IX_DersProgrami_Gun '
          'ON DersProgrami (Gun)',
        );

        await txn.execute(
          'CREATE INDEX IX_DersProgrami_OgretmenProfilId '
          'ON DersProgrami (OgretmenProfilId)',
        );

        await txn.execute(
          'CREATE INDEX IX_OgrenciSinifKayit_OgrenciId '
          'ON OgrenciSinifKayit (OgrenciId)',
        );

        await txn.execute(
          'CREATE INDEX IX_OgrenciSinifKayit_SinifSubeId '
          'ON OgrenciSinifKayit (SinifSubeId)',
        );

        await txn.execute(
          'CREATE INDEX IX_CalismaTakvimiDetay_CalismaTakvimiId '
          'ON CalismaTakvimiDetay (CalismaTakvimiId)',
        );

        await txn.execute(
          'CREATE INDEX IX_CalismaTakvimiDetay_HaftaNo '
          'ON CalismaTakvimiDetay (HaftaNo)',
        );
      });
    } catch (e) {
      throw Exception(
        'Bireysel öğretmen SQLite tabloları oluşturulurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    try {
      if (oldVersion < 2) {
        await db.transaction((txn) async {
          await txn.execute(
            'ALTER TABLE DersProgrami ADD COLUMN Baslangic TEXT',
          );

          await txn.execute('ALTER TABLE DersProgrami ADD COLUMN Bitis TEXT');

          await txn.execute('ALTER TABLE DersProgrami ADD COLUMN Derslik TEXT');
        });
      }

      if (oldVersion < 3) {
        await db.transaction((txn) async {
          await txn.execute('ALTER TABLE YillikPlanDetay ADD COLUMN Saat TEXT');

          await txn.execute(
            'ALTER TABLE YillikPlanDetay ADD COLUMN OgrenmeBirimi TEXT',
          );

          await txn.execute(
            'ALTER TABLE YillikPlanDetay ADD COLUMN IcerikCercevesi TEXT',
          );

          await txn.execute(
            'ALTER TABLE YillikPlanDetay ADD COLUMN OgrenmeCiktisi TEXT',
          );

          await txn.execute(
            'ALTER TABLE YillikPlanDetay ADD COLUMN SurecBilesenleri TEXT',
          );

          await txn.execute(
            'ALTER TABLE YillikPlanDetay ADD COLUMN YontemTeknik TEXT',
          );

          await txn.execute(
            'ALTER TABLE YillikPlanDetay ADD COLUMN AracGerec TEXT',
          );

          await txn.execute(
            'ALTER TABLE YillikPlanDetay ADD COLUMN Degerlendirme TEXT',
          );

          await txn.execute('''
            CREATE TABLE CalismaTakvimi (
              CalismaTakvimiId INTEGER PRIMARY KEY AUTOINCREMENT,
              OgretmenProfilId INTEGER,
              EgitimOgretimYili TEXT NOT NULL,
              KaynakDosyaAdi TEXT,
              Aktif INTEGER NOT NULL DEFAULT 1,
              OlusturmaTarihi TEXT NOT NULL,
              GuncellemeTarihi TEXT,
              UNIQUE (OgretmenProfilId, EgitimOgretimYili),
              FOREIGN KEY (OgretmenProfilId)
                REFERENCES OgretmenProfil (OgretmenProfilId)
                ON DELETE SET NULL
            )
          ''');

          await txn.execute('''
            CREATE TABLE CalismaTakvimiDetay (
              CalismaTakvimiDetayId INTEGER PRIMARY KEY AUTOINCREMENT,
              CalismaTakvimiId INTEGER NOT NULL,
              HaftaNo INTEGER,
              Ay TEXT,
              TarihAraligi TEXT,
              BaslangicTarihi TEXT,
              BitisTarihi TEXT,
              KayitTuru TEXT NOT NULL,
              CalismaVarMi INTEGER NOT NULL DEFAULT 1,
              Aciklama TEXT,
              OzelGunAciklamasi TEXT,
              Aktif INTEGER NOT NULL DEFAULT 1,
              OlusturmaTarihi TEXT NOT NULL,
              GuncellemeTarihi TEXT,
              FOREIGN KEY (CalismaTakvimiId)
                REFERENCES CalismaTakvimi (CalismaTakvimiId)
                ON DELETE CASCADE
            )
          ''');

          await txn.execute(
            'CREATE INDEX IX_CalismaTakvimiDetay_CalismaTakvimiId '
            'ON CalismaTakvimiDetay (CalismaTakvimiId)',
          );

          await txn.execute(
            'CREATE INDEX IX_CalismaTakvimiDetay_HaftaNo '
            'ON CalismaTakvimiDetay (HaftaNo)',
          );
        });
      }
      if (oldVersion < 4) {
        await db.transaction((txn) async {
          await _surum4TablolariniHazirla(txn);
        });
      }
      if (oldVersion < 5) {
        await db.transaction((txn) async {
          await _surum5TablolariniHazirla(txn);
        });
      }
      if (oldVersion < 6) {
        await db.transaction((txn) async {
          await _surum6TablolariniHazirla(txn);
        });
      }
      if (oldVersion < 7) {
        await db.transaction((txn) async {
          await _surum7TablolariniHazirla(txn);
        });
      }
      if (oldVersion < 8) {
        await db.transaction((txn) async {
          await _surum8TablolariniHazirla(txn);
        });
      }
      if (oldVersion < 9) {
        await db.transaction((txn) async {
          await _surum9AlanlariniHazirla(txn);
        });
      }
      if (oldVersion < 10) {
        await db.transaction((txn) async {
          await DersProgramiSurumu.hazirla(txn);
        });
      }
      if (oldVersion < 11) {
        await db.transaction((txn) async {
          await BelgeArsiviSemasi.hazirla(txn);
        });
      }
      if (oldVersion < 12) {
        await db.transaction((txn) async {
          await BelgeArsiviSemasi.yonetimiHazirla(txn);
        });
      }
      if (oldVersion < 13) {
        await db.transaction((txn) => MesajlasmaSemasi.hazirla(txn));
      }
      if (oldVersion < 14) {
        await db.transaction((txn) => RehberlikSemasi.hazirla(txn));
      }
      if (oldVersion < 15) {
        await db.transaction((txn) => RehberlikSemasi.moduluHazirla(txn));
      }
      if (oldVersion < 16) {
        await db.transaction((txn) => GunlukPlanSemasi.hazirla(txn));
      }
      if (oldVersion < 18) {
        await db.transaction((txn) => MesajlasmaSemasi.smsHazirla(txn));
      }
      if (oldVersion < 19) {
        await db.transaction((txn) => RehberlikSemasi.googleFormHazirla(txn));
      }
      if (oldVersion < 20) {
        await db.transaction((txn) => BilgiToplamaSemasi.hazirla(txn));
      }
      if (oldVersion < 21) {
        await db.transaction((txn) => _performansOlcutTablolariniHazirla(txn));
      }
      if (oldVersion < 24) {
        await db.transaction((txn) async {
          await VeliIliskisi.hazirla(txn);
          if ((await txn.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='MesajAliciBag'",
          )).isEmpty) {
            await MesajAliciSemasi.hazirla(txn);
          }
          await MesajlasmaSemasi.ortakIletisimHazirla(txn);
        });
      }
      if (oldVersion < 25) {
        await db.transaction((txn) => MesajOgretmenDersSemasi.hazirla(txn));
      }
      if (oldVersion < 26) {
        await db.transaction((tx) => KaldirilanModuller.temizle(tx));
      }
      if (oldVersion < 27) {
        await db.transaction(MesajlasmaSemasi.tekliGecmisHazirla);
      }
      if (oldVersion < 28) {
        await db.transaction(OdevNotSemasi.hazirla);
      }
      if (oldVersion < 29) {
        await db.transaction(SeflikYillikPlanSemasi.hazirla);
      }
      if (oldVersion < 30) {
        await db.transaction(DersUygulamaSemasi.hazirla);
      }
      if (oldVersion < 31) {
        await db.transaction((tx) async {
          await DersUygulamaSemasi.hazirla(tx);
          await OdevDurumTemizligi.hazirla(tx);
        });
      }
    } catch (e) {
      throw Exception(
        'Bireysel öğretmen veritabanı güncellenirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  Future<void> _surum4TablolariniHazirla(Transaction txn) async {
    // Eski dosya yolları korunur; yeni fotoğraflar doğrudan SQLite'ta tutulur.
    await txn.execute('ALTER TABLE OgrenciFotograf ADD COLUMN FotoVerisi BLOB');
    await txn.execute('ALTER TABLE OgrenciFotograf ADD COLUMN MimeTuru TEXT');
  }

  Future<void> _performansOlcutTablolariniHazirla(Transaction txn) async {
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS OdevDegerlendirmeOlcutu (
        OlcutId INTEGER PRIMARY KEY AUTOINCREMENT,
        OdevId INTEGER NOT NULL,
        OdevKontrolId INTEGER NOT NULL,
        Sira INTEGER NOT NULL CHECK (Sira > 0),
        Baslik TEXT NOT NULL CHECK (length(trim(Baslik)) > 0),
        AzamiPuan INTEGER NOT NULL CHECK (AzamiPuan > 0 AND AzamiPuan <= 100),
        UNIQUE (OdevKontrolId, Sira),
        FOREIGN KEY (OdevKontrolId, OdevId)
          REFERENCES OdevKontrol (OdevKontrolId, OdevId) ON DELETE RESTRICT
      )
    ''');
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS OdevDegerlendirmePuani (
        OlcutId INTEGER NOT NULL,
        OdevKontrolSonucId INTEGER NOT NULL,
        Puan INTEGER NOT NULL CHECK (Puan >= 0 AND Puan <= 100),
        PRIMARY KEY (OlcutId, OdevKontrolSonucId),
        FOREIGN KEY (OlcutId) REFERENCES OdevDegerlendirmeOlcutu (OlcutId)
          ON DELETE RESTRICT,
        FOREIGN KEY (OdevKontrolSonucId)
          REFERENCES OdevKontrolSonuc (OdevKontrolSonucId) ON DELETE RESTRICT
      )
    ''');
  }

  Future<void> _surum5TablolariniHazirla(Transaction txn) async {
    // Ders programı yenilense de görevler ve öğrenci katılımları korunur.
    await txn.execute('''
      CREATE TABLE OdevTanim (
        OdevId INTEGER PRIMARY KEY AUTOINCREMENT,
        OgretmenProfilId INTEGER NOT NULL,
        EgitimOgretimYili TEXT NOT NULL,
        Donem INTEGER CHECK (Donem IN (1, 2)),
        DersId INTEGER NOT NULL,
        SinifSubeId INTEGER NOT NULL,
        GorevTuru TEXT NOT NULL CHECK (
          GorevTuru IN ('NormalOdev', 'RutinKontrol', 'Proje', 'Performans')
        ),
        Baslik TEXT NOT NULL CHECK (length(trim(Baslik)) > 0),
        Aciklama TEXT,
        BaslangicTarihi TEXT NOT NULL,
        TeslimTarihi TEXT,
        Aktif INTEGER NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
        OlusturmaTarihi TEXT NOT NULL,
        GuncellemeTarihi TEXT,
        FOREIGN KEY (OgretmenProfilId) REFERENCES OgretmenProfil (OgretmenProfilId)
          ON DELETE RESTRICT,
        FOREIGN KEY (DersId) REFERENCES Ders (DersId) ON DELETE RESTRICT,
        FOREIGN KEY (SinifSubeId) REFERENCES SinifSube (SinifSubeId)
          ON DELETE RESTRICT
      )
    ''');
    await txn.execute('''
      CREATE TABLE OdevOgrenci (
        OdevOgrenciId INTEGER PRIMARY KEY AUTOINCREMENT,
        OdevId INTEGER NOT NULL,
        OgrenciId INTEGER NOT NULL,
        Aktif INTEGER NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
        OlusturmaTarihi TEXT NOT NULL,
        GuncellemeTarihi TEXT,
        UNIQUE (OdevId, OgrenciId),
        FOREIGN KEY (OdevId) REFERENCES OdevTanim (OdevId) ON DELETE RESTRICT,
        FOREIGN KEY (OgrenciId) REFERENCES Ogrenci (OgrenciId) ON DELETE RESTRICT
      )
    ''');
    await txn.execute('''
      CREATE TABLE OdevKontrol (
        OdevKontrolId INTEGER PRIMARY KEY AUTOINCREMENT,
        OdevId INTEGER NOT NULL,
        KontrolTarihi TEXT NOT NULL,
        SiraNo INTEGER NOT NULL CHECK (SiraNo > 0),
        Aciklama TEXT,
        Aktif INTEGER NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
        OlusturmaTarihi TEXT NOT NULL,
        GuncellemeTarihi TEXT,
        UNIQUE (OdevId, SiraNo),
        UNIQUE (OdevKontrolId, OdevId),
        FOREIGN KEY (OdevId) REFERENCES OdevTanim (OdevId) ON DELETE RESTRICT
      )
    ''');
    await txn.execute('''
      CREATE TABLE OdevKontrolSonuc (
        OdevKontrolSonucId INTEGER PRIMARY KEY AUTOINCREMENT,
        OdevId INTEGER NOT NULL,
        OdevKontrolId INTEGER NOT NULL,
        OgrenciId INTEGER NOT NULL,
        Durum TEXT NOT NULL DEFAULT 'KontrolEdilmedi' CHECK (
          Durum IN ('Yapti', 'Kismen', 'Yapmadi',
                    'Gelmedi', 'Mazeretli', 'KontrolEdilmedi')
        ),
        Aciklama TEXT,
        OlusturmaTarihi TEXT NOT NULL,
        GuncellemeTarihi TEXT,
        UNIQUE (OdevKontrolId, OgrenciId),
        FOREIGN KEY (OdevKontrolId, OdevId)
          REFERENCES OdevKontrol (OdevKontrolId, OdevId) ON DELETE RESTRICT,
        FOREIGN KEY (OdevId, OgrenciId)
          REFERENCES OdevOgrenci (OdevId, OgrenciId) ON DELETE RESTRICT
      )
    ''');
    await txn.execute(
      'CREATE INDEX IX_OdevTanim_ProfilYilSinifDers '
      'ON OdevTanim (OgretmenProfilId, EgitimOgretimYili, SinifSubeId, DersId)',
    );
    await txn.execute('CREATE INDEX IX_OdevTanim_DersId ON OdevTanim (DersId)');
    await txn.execute(
      'CREATE INDEX IX_OdevTanim_SinifSubeId ON OdevTanim (SinifSubeId)',
    );
    await txn.execute(
      'CREATE INDEX IX_OdevOgrenci_OgrenciId ON OdevOgrenci (OgrenciId)',
    );
    await txn.execute(
      'CREATE INDEX IX_OdevKontrolSonuc_OdevOgrenci '
      'ON OdevKontrolSonuc (OdevId, OgrenciId)',
    );
  }

  Future<void> _surum6TablolariniHazirla(Transaction txn) async {
    await txn.execute('''
      CREATE TABLE OkulProfil (
        Id INTEGER NOT NULL PRIMARY KEY CHECK (Id = 1),
        OkulId TEXT NOT NULL UNIQUE CHECK (length(trim(OkulId)) > 0),
        OkulAdi TEXT NOT NULL CHECK (length(trim(OkulAdi)) > 0),
        OkulKisaAdi TEXT NOT NULL CHECK (length(trim(OkulKisaAdi)) > 0),
        EgitimYili TEXT NOT NULL CHECK (length(trim(EgitimYili)) > 0),
        Donem INTEGER NOT NULL CHECK (Donem IN (1, 2)),
        OlusturmaTarihi TEXT NOT NULL,
        AktifMi INTEGER NOT NULL DEFAULT 1 CHECK (AktifMi IN (0, 1))
      )
    ''');
    await txn.execute('''
      CREATE TABLE OgretmenAktivasyon (
        AktivasyonId TEXT NOT NULL PRIMARY KEY
          CHECK (length(trim(AktivasyonId)) > 0),
        OkulId TEXT NOT NULL,
        OgretmenProfilId INTEGER NOT NULL,
        Rol TEXT NOT NULL CHECK (Rol IN ('Admin', 'Ogretmen')),
        KodHash TEXT NOT NULL UNIQUE CHECK (length(trim(KodHash)) > 0),
        OlusturmaTarihi TEXT NOT NULL,
        AktifMi INTEGER NOT NULL DEFAULT 1 CHECK (AktifMi IN (0, 1)),
        FOREIGN KEY (OkulId) REFERENCES OkulProfil (OkulId)
          ON DELETE RESTRICT,
        FOREIGN KEY (OgretmenProfilId) REFERENCES OgretmenProfil (OgretmenProfilId)
          ON DELETE RESTRICT
      )
    ''');
    await txn.execute(
      'CREATE UNIQUE INDEX UX_OgretmenAktivasyon_AktifRol '
      'ON OgretmenAktivasyon (OkulId, OgretmenProfilId, Rol) '
      'WHERE AktifMi = 1',
    );
    await txn.execute(
      'CREATE INDEX IX_OgretmenAktivasyon_OgretmenProfilId '
      'ON OgretmenAktivasyon (OgretmenProfilId)',
    );
  }

  Future<void> _surum7TablolariniHazirla(Transaction txn) async {
    // Haftalık toplam saat şefliğe aittir; mekân sayısıyla çarpılmaz.
    await txn.execute('''
      CREATE TABLE SeflikTanim (
        SeflikId INTEGER PRIMARY KEY AUTOINCREMENT,
        OgretmenProfilId INTEGER NOT NULL,
        EgitimOgretimYili TEXT NOT NULL
          CHECK (length(trim(EgitimOgretimYili)) > 0),
        SeflikTuru TEXT NOT NULL
          CHECK (SeflikTuru IN ('Alan', 'AtolyeLaboratuvar')),
        HaftalikSaat INTEGER NOT NULL
          CHECK (typeof(HaftalikSaat) = 'integer' AND HaftalikSaat > 0),
        BaslangicTarihi TEXT NOT NULL CHECK (
          length(BaslangicTarihi) = 10 AND
          date(BaslangicTarihi, '+0 days') IS NOT NULL AND
          date(BaslangicTarihi, '+0 days') = BaslangicTarihi
        ),
        BitisTarihi TEXT CHECK (
          BitisTarihi IS NULL OR (
            length(BitisTarihi) = 10 AND
            date(BitisTarihi, '+0 days') IS NOT NULL AND
            date(BitisTarihi, '+0 days') = BitisTarihi AND
            BitisTarihi >= BaslangicTarihi
          )
        ),
        Aktif INTEGER NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
        OlusturmaTarihi TEXT NOT NULL,
        GuncellemeTarihi TEXT,
        UNIQUE (SeflikId, OgretmenProfilId),
        FOREIGN KEY (OgretmenProfilId) REFERENCES OgretmenProfil (OgretmenProfilId)
          ON DELETE RESTRICT
      )
    ''');
    await txn.execute('''
      CREATE TABLE SeflikMekan (
        MekanId INTEGER PRIMARY KEY AUTOINCREMENT,
        OgretmenProfilId INTEGER NOT NULL,
        MekanAdi TEXT NOT NULL CHECK (length(trim(MekanAdi)) > 0),
        MekanTuru TEXT NOT NULL CHECK (MekanTuru IN ('Atolye', 'Laboratuvar')),
        Aciklama TEXT,
        Aktif INTEGER NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
        OlusturmaTarihi TEXT NOT NULL,
        GuncellemeTarihi TEXT,
        UNIQUE (MekanId, OgretmenProfilId),
        FOREIGN KEY (OgretmenProfilId) REFERENCES OgretmenProfil (OgretmenProfilId)
          ON DELETE RESTRICT
      )
    ''');
    await txn.execute('''
      CREATE TABLE SeflikSorumluMekan (
        SeflikSorumluMekanId INTEGER PRIMARY KEY AUTOINCREMENT,
        SeflikId INTEGER NOT NULL,
        MekanId INTEGER NOT NULL,
        OgretmenProfilId INTEGER NOT NULL,
        Aktif INTEGER NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
        OlusturmaTarihi TEXT NOT NULL,
        GuncellemeTarihi TEXT,
        UNIQUE (SeflikId, MekanId),
        FOREIGN KEY (SeflikId, OgretmenProfilId)
          REFERENCES SeflikTanim (SeflikId, OgretmenProfilId) ON DELETE RESTRICT,
        FOREIGN KEY (MekanId, OgretmenProfilId)
          REFERENCES SeflikMekan (MekanId, OgretmenProfilId) ON DELETE RESTRICT
      )
    ''');
    await txn.execute(
      'CREATE INDEX IX_SeflikTanim_ProfilYil '
      'ON SeflikTanim (OgretmenProfilId, EgitimOgretimYili)',
    );
    await txn.execute(
      'CREATE INDEX IX_SeflikMekan_Profil ON SeflikMekan (OgretmenProfilId)',
    );
    await txn.execute(
      'CREATE INDEX IX_SeflikSorumluMekan_Mekan '
      'ON SeflikSorumluMekan (MekanId, OgretmenProfilId)',
    );
  }

  Future<void> _surum8TablolariniHazirla(Transaction txn) async {
    // Eşleştirme aynı öğretmen ve eğitim yılı içindeki şefliğe yapılır.
    await txn.execute(
      'CREATE UNIQUE INDEX UX_SeflikTanim_IdProfilYil '
      'ON SeflikTanim (SeflikId, OgretmenProfilId, EgitimOgretimYili)',
    );
    await txn.execute('''
      CREATE TABLE SeflikProgramSaati (
        SeflikProgramSaatiId INTEGER PRIMARY KEY AUTOINCREMENT,
        OgretmenProfilId INTEGER NOT NULL,
        EgitimOgretimYili TEXT NOT NULL
          CHECK (length(trim(EgitimOgretimYili)) > 0),
        SeflikId INTEGER,
        Gun TEXT NOT NULL CHECK (
          Gun IN ('Pazartesi', 'Salı', 'Çarşamba', 'Perşembe',
                  'Cuma', 'Cumartesi', 'Pazar')
        ),
        DersSaatiNo INTEGER NOT NULL CHECK (
          typeof(DersSaatiNo) = 'integer' AND DersSaatiNo > 0
        ),
        Baslangic TEXT NOT NULL CHECK (
          Baslangic GLOB '[0-2][0-9]:[0-5][0-9]' AND Baslangic < '24:00'
        ),
        Bitis TEXT NOT NULL CHECK (
          Bitis GLOB '[0-2][0-9]:[0-5][0-9]' AND Bitis < '24:00'
          AND Bitis > Baslangic
        ),
        BaslangicTarihi TEXT NOT NULL CHECK (
          length(BaslangicTarihi) = 10 AND
          date(BaslangicTarihi, '+0 days') IS NOT NULL AND
          date(BaslangicTarihi, '+0 days') = BaslangicTarihi
        ),
        BitisTarihi TEXT CHECK (
          BitisTarihi IS NULL OR (
            length(BitisTarihi) = 10 AND
            date(BitisTarihi, '+0 days') IS NOT NULL AND
            date(BitisTarihi, '+0 days') = BitisTarihi AND
            BitisTarihi >= BaslangicTarihi
          )
        ),
        Kaynak TEXT NOT NULL CHECK (Kaynak IN ('Import', 'Manuel')),
        HamMetin TEXT CHECK (
          Kaynak != 'Import' OR
          (HamMetin IS NOT NULL AND length(trim(HamMetin)) > 0)
        ),
        Aktif INTEGER NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
        OlusturmaTarihi TEXT NOT NULL,
        GuncellemeTarihi TEXT,
        FOREIGN KEY (OgretmenProfilId) REFERENCES OgretmenProfil (OgretmenProfilId)
          ON DELETE RESTRICT,
        FOREIGN KEY (SeflikId, OgretmenProfilId, EgitimOgretimYili)
          REFERENCES SeflikTanim (SeflikId, OgretmenProfilId, EgitimOgretimYili)
          ON DELETE RESTRICT
      )
    ''');
    // Aynı başlangıç tarihindeki aynı aktif haftalık saat iki kez kaydedilmez.
    await txn.execute(
      'CREATE UNIQUE INDEX UX_SeflikProgramSaati_AktifGunSaat '
      'ON SeflikProgramSaati (OgretmenProfilId, EgitimOgretimYili, '
      'Gun, DersSaatiNo, BaslangicTarihi) WHERE Aktif = 1',
    );
    await txn.execute(
      'CREATE INDEX IX_SeflikProgramSaati_Seflik '
      'ON SeflikProgramSaati (SeflikId, OgretmenProfilId, EgitimOgretimYili)',
    );
  }

  Future<void> _surum9AlanlariniHazirla(Transaction txn) async {
    await txn.execute('''
      ALTER TABLE OdevKontrol ADD COLUMN Baslik TEXT
        CHECK (Baslik IS NULL OR length(trim(Baslik)) > 0)
    ''');

    await txn.execute('''
      ALTER TABLE OdevKontrol ADD COLUMN HedefNot TEXT NOT NULL
        DEFAULT 'NotaEtkiEtmez'
        CHECK (
          HedefNot IN ('Sozlu1', 'Sozlu2', 'Performans', 'NotaEtkiEtmez')
        )
    ''');

    await txn.execute('''
      ALTER TABLE OdevKontrol ADD COLUMN KatkiOrani REAL NOT NULL
        DEFAULT 0
        CHECK (
          typeof(KatkiOrani) IN ('integer', 'real')
          AND KatkiOrani >= 0
          AND KatkiOrani <= 100
          AND (HedefNot != 'NotaEtkiEtmez' OR KatkiOrani = 0)
        )
    ''');

    await txn.execute('''
      ALTER TABLE OdevKontrol ADD COLUMN TamPuan REAL NOT NULL
        DEFAULT 10
        CHECK (
          typeof(TamPuan) IN ('integer', 'real')
          AND TamPuan > 0
          AND TamPuan <= 100
        )
    ''');

    await txn.execute('''
      ALTER TABLE OdevKontrol ADD COLUMN YaptiPuani REAL NOT NULL
        DEFAULT 10
        CHECK (
          typeof(YaptiPuani) IN ('integer', 'real')
          AND YaptiPuani >= 0
          AND YaptiPuani <= TamPuan
        )
    ''');

    await txn.execute('''
      ALTER TABLE OdevKontrol ADD COLUMN KismenPuani REAL NOT NULL
        DEFAULT 5
        CHECK (
          typeof(KismenPuani) IN ('integer', 'real')
          AND KismenPuani >= 0
          AND KismenPuani <= YaptiPuani
        )
    ''');

    await txn.execute('''
      ALTER TABLE OdevKontrol ADD COLUMN YapmadiPuani REAL NOT NULL
        DEFAULT 0
        CHECK (
          typeof(YapmadiPuani) IN ('integer', 'real')
          AND YapmadiPuani >= 0
          AND YapmadiPuani <= KismenPuani
        )
    ''');

    await txn.execute('''
      ALTER TABLE OdevKontrolSonuc ADD COLUMN GecTeslim INTEGER NOT NULL
        DEFAULT 0
        CHECK (GecTeslim IN (0, 1))
    ''');
  }

  Future<void> bireyselVerileriSifirla({required String onayMetni}) async {
    if (onayMetni != 'SIFIRLA') {
      throw Exception('Sıfırlama için SIFIRLA onayı gereklidir.');
    }

    try {
      final db = await database;
      await db.transaction((txn) async {
        // BelgeArsivi ve BireyselBelge korunur. Sahiplik bilgileri profil
        // tablolarından bağımsızdır; yeni kurulum eski belgeleri devralmaz.
        // Bağımlı kayıtlar önce silinir; hata olursa tüm işlem geri alınır.
        for (final tablo in const <String>[
          'OgrenciIletisim',
          MesajOgretmenDersSemasi.tablo,
          'MesajOgretmenSinif',
          'MesajOgretmenKisi',
          'OgrenciEkBilgiDeger',
          'BilgiToplamaEsleme',
          'BilgiToplamaYanit',
          'BilgiToplamaHedef',
          'BilgiToplamaSoru',
          'BilgiToplamaForm',
          GunlukPlanSemasi.tablo,
          'RehberlikBag',
          'RehberlikGoogleYanit',
          'RehberlikFormDavet',
          'RehberlikGoogleForm',
          'RehberlikForm',
          'RehberlikKayit',
          RehberlikSemasi.atamaTablosu,
          'SeflikProgramSaati',
          'DersProgramiGorev',
          'SeflikSorumluMekan',
          'SeflikMekan',
          'SeflikTanim',
          'OgretmenAktivasyon',
          'OdevEk',
          'PerformansSonuc',
          'PerformansOdev',
          'PerformansTanim',
          'OdevDegerlendirmePuani',
          'OdevDegerlendirmeOlcutu',
          'OdevKontrolSonuc',
          'OdevUygulamaSonuc',
          'OdevUygulama',
          'OdevKontrol',
          'OdevOgrenci',
          'OdevTanim',
          'OgrenciFotograf',
          'OgrenciSinifKayit',
          'YillikPlanDetay',
          'YillikPlan',
          'CalismaTakvimiDetay',
          'CalismaTakvimi',
          'DersProgrami',
          'DersProgramiSurum',
          'DersSinif',
          'DersSaati',
          'Ders',
          'Ogrenci',
          'SinifSube',
          'OgretmenProfil',
          'UygulamaAyarlari',
          'OkulProfil',
        ]) {
          await txn.delete(tablo);
        }
      });
    } catch (e) {
      throw Exception(
        'Bireysel veriler sıfırlanamadı. Silme işlemi geri alındı.\n'
        'Orijinal hata: $e',
      );
    }
  }

  Future<void> close() async {
    try {
      final db = _database;

      if (db != null && db.isOpen) {
        await db.close();
      }

      _database = null;
    } catch (e) {
      throw Exception(
        'Bireysel öğretmen veritabanı kapatılırken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }
}
