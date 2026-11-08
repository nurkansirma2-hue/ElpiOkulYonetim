import 'package:sqflite/sqflite.dart';

class MesajlasmaSemasi {
  static const tablolar = ['MesajKuyrugu', 'MesajAlici', 'MesajSms'];
  static const tekliGecmisTablosu = 'MesajTekliGecmis';
  static Future<void> tekliGecmisHazirla(DatabaseExecutor db) async {
    // Tarihsel görüntü; öğrenci silinince başka bir öğrenciye bağlanmaz.
    await db.execute('''CREATE TABLE IF NOT EXISTS MesajTekliGecmis (
      KayitId TEXT NOT NULL PRIMARY KEY, IslemId TEXT NOT NULL,
      OkulId TEXT NOT NULL, OgretmenProfilId INTEGER NOT NULL,
      OgretmenAdi TEXT NOT NULL, EgitimOgretimYili TEXT NOT NULL,
      KaynakModul TEXT NOT NULL, KaynakKayit TEXT,
      OgrenciId INTEGER, OgrenciKimligi TEXT,
      Tur TEXT NOT NULL, KisiId TEXT NOT NULL, AliciAdi TEXT NOT NULL,
      Telefon TEXT NOT NULL, Aciklama TEXT NOT NULL, Metin TEXT NOT NULL,
      Kanal TEXT NOT NULL CHECK(Kanal IN ('SMS','WhatsApp')),
      Durum TEXT NOT NULL CHECK(Durum IN ('Belirsiz','Istendi','Acildi','Acilamadi')),
      Tarih TEXT NOT NULL, Hata TEXT
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS IX_MesajTekliGecmis_Sahip '
      'ON MesajTekliGecmis(OkulId,OgretmenProfilId,EgitimOgretimYili,OgrenciId,Tarih)',
    );
  }

  static const iletisimAlanlari = ['VeliAdi', 'VeliTelefonu'];

  // WhatsApp durumlarından bağımsız SMS kayıtları; eski kuyruklar korunur.
  // Belirsiz gönderimler otomatik tekrarlanmaz.
  static Future<void> smsHazirla(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS MesajSms (
      AliciId INTEGER NOT NULL PRIMARY KEY
        REFERENCES MesajAlici(AliciId) ON DELETE RESTRICT,
      Durum TEXT NOT NULL DEFAULT 'Bekliyor'
        CHECK(Durum IN ('Bekliyor','Belirsiz','Istendi','Basarisiz','Gonderildi')),
      IstekTarihi TEXT, SonucTarihi TEXT, Hata TEXT,
      ParcaSayisi INTEGER CHECK(ParcaSayisi IS NULL OR ParcaSayisi > 0)
    )''');
  }

  /// GitHub v22 iletişim kayıtlarının kayıpsız geçiş/yedek uyumluluğu.
  /// Yeni alıcılar VeliIliskisi üzerinden okunur. Buraya telefon kopyalanmaz;
  /// eski kayıtlar ve eski varsayılan seçimler tarihsel olarak korunur.
  static Future<void> ortakIletisimHazirla(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS OgrenciIletisim (
      IletisimId INTEGER PRIMARY KEY AUTOINCREMENT,
      OgrenciId INTEGER NOT NULL REFERENCES Ogrenci(OgrenciId) ON DELETE RESTRICT,
      Tur TEXT NOT NULL CHECK(Tur IN ('Anne','Baba','Veli')),
      Ad TEXT NOT NULL DEFAULT '',
      Telefon TEXT NOT NULL DEFAULT '',
      Varsayilan INTEGER NOT NULL DEFAULT 0 CHECK(Varsayilan IN (0,1)),
      GuncellemeTarihi TEXT,
      UNIQUE(OgrenciId, Tur)
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS IX_OgrenciIletisim_Ogrenci '
      'ON OgrenciIletisim(OgrenciId)',
    );
  }

  static Future<void> hazirla(DatabaseExecutor db) async {
    for (final alan in iletisimAlanlari) {
      await db.execute('ALTER TABLE Ogrenci ADD COLUMN $alan TEXT');
    }
    // Sahiplik ve alıcılar anlık görüntüdür. Profil/öğrenci sıfırlanınca
    // geçmiş silinmez ve yeniden kullanılan sayısal kimliklere bağlanmaz.
    await db.execute('''CREATE TABLE MesajKuyrugu (
      KuyrukId TEXT NOT NULL PRIMARY KEY,
      OkulId TEXT NOT NULL, OgretmenProfilId INTEGER NOT NULL,
      OgretmenAdi TEXT NOT NULL, OkulAdi TEXT NOT NULL,
      EgitimOgretimYili TEXT NOT NULL,
      KaynakModul TEXT NOT NULL, KaynakKayit TEXT,
      Metin TEXT NOT NULL CHECK(length(trim(Metin)) > 0),
      OlusturmaTarihi TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE MesajAlici (
      AliciId INTEGER PRIMARY KEY AUTOINCREMENT,
      KuyrukId TEXT NOT NULL REFERENCES MesajKuyrugu(KuyrukId) ON DELETE RESTRICT,
      Sira INTEGER NOT NULL CHECK(Sira > 0),
      Telefon TEXT NOT NULL CHECK(length(Telefon) BETWEEN 8 AND 15
        AND Telefon NOT GLOB '*[^0-9]*' AND substr(Telefon, 1, 1) != '0'),
      AliciAdi TEXT NOT NULL, Ogrenciler TEXT NOT NULL,
      Durum TEXT NOT NULL DEFAULT 'Bekliyor'
        CHECK(Durum IN ('Bekliyor','Acildi','Acilamadi','Onaylandi','Atlandi')),
      AcilmaTarihi TEXT, OnayTarihi TEXT, Hata TEXT,
      UNIQUE(KuyrukId, Telefon), UNIQUE(KuyrukId, Sira),
      CHECK((Durum = 'Onaylandi' AND OnayTarihi IS NOT NULL)
        OR (Durum != 'Onaylandi' AND OnayTarihi IS NULL))
    )''');
    await smsHazirla(db);
    await db.execute(
      'CREATE INDEX IX_MesajKuyrugu_Sahip '
      'ON MesajKuyrugu(OkulId, OgretmenProfilId, EgitimOgretimYili, OlusturmaTarihi)',
    );
  }
}
