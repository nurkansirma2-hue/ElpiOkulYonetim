import 'package:sqflite/sqflite.dart';

/// Program geçmişi sınıf/ders bağlantıları ve diğer modüllerden ayrı tutulur.
class DersProgramiSurumu {
  static String tarihYaz(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  static Future<void> hazirla(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE DersProgramiSurum (
      ProgramSurumId INTEGER PRIMARY KEY AUTOINCREMENT,
      OgretmenProfilId INTEGER NOT NULL REFERENCES OgretmenProfil(OgretmenProfilId),
      EgitimOgretimYili TEXT NOT NULL,
      BaslangicTarihi TEXT,
      BitisTarihi TEXT,
      Aktif INTEGER NOT NULL DEFAULT 1,
      OlusturmaTarihi TEXT NOT NULL,
      CHECK (BitisTarihi IS NULL OR BaslangicTarihi IS NULL OR BitisTarihi >= BaslangicTarihi)
    )''');
    await db.execute('ALTER TABLE DersProgrami ADD COLUMN ProgramSurumId INTEGER REFERENCES DersProgramiSurum(ProgramSurumId)');
    // Önceden yüklenen programın bilinmeyen başlangıç tarihi tahmin edilmez.
    await db.execute('''INSERT INTO DersProgramiSurum
      (OgretmenProfilId, EgitimOgretimYili, OlusturmaTarihi)
      SELECT OgretmenProfilId, EgitimOgretimYili, MIN(OlusturmaTarihi)
      FROM DersProgrami WHERE Aktif = 1 AND OgretmenProfilId IS NOT NULL
      GROUP BY OgretmenProfilId, EgitimOgretimYili''');
    await db.execute('''UPDATE DersProgrami SET ProgramSurumId = (
      SELECT ps.ProgramSurumId FROM DersProgramiSurum ps
      WHERE ps.OgretmenProfilId = DersProgrami.OgretmenProfilId
        AND ps.EgitimOgretimYili = DersProgrami.EgitimOgretimYili)
      WHERE Aktif = 1''');
    await db.execute('''CREATE TABLE DersProgramiGorev (
      GorevId INTEGER PRIMARY KEY AUTOINCREMENT,
      ProgramSurumId INTEGER NOT NULL REFERENCES DersProgramiSurum(ProgramSurumId),
      Gun TEXT NOT NULL,
      DersSaatiNo INTEGER NOT NULL,
      Baslangic TEXT NOT NULL,
      Bitis TEXT NOT NULL,
      GorevAdi TEXT NOT NULL CHECK (GorevAdi = 'Koordinatörlük'),
      CHECK (Bitis > Baslangic),
      UNIQUE(ProgramSurumId, Gun, DersSaatiNo)
    )''');
    await db.execute('''CREATE VIEW GecerliDersProgrami AS
      SELECT dp.* FROM DersProgrami dp
      LEFT JOIN DersProgramiSurum ps ON ps.ProgramSurumId = dp.ProgramSurumId
      WHERE dp.Aktif = 1 AND (dp.ProgramSurumId IS NULL OR (
        ps.Aktif = 1 AND (ps.BaslangicTarihi IS NULL OR ps.BaslangicTarihi <= date('now','localtime'))
        AND (ps.BitisTarihi IS NULL OR ps.BitisTarihi >= date('now','localtime'))))''');
    await db.execute('CREATE INDEX IX_ProgramSurum_ProfilYil ON DersProgramiSurum(OgretmenProfilId,EgitimOgretimYili,BaslangicTarihi)');
  }

  static Future<DateTime> oncekiDersGunu(DatabaseExecutor db, int profil, String yil, DateTime baslangic) async {
    final takvim = await db.rawQuery('''SELECT d.BaslangicTarihi, d.BitisTarihi, d.CalismaVarMi
      FROM CalismaTakvimiDetay d INNER JOIN CalismaTakvimi t ON t.CalismaTakvimiId = d.CalismaTakvimiId
      WHERE t.OgretmenProfilId = ? AND t.EgitimOgretimYili = ? AND t.Aktif = 1 AND d.Aktif = 1
      ORDER BY d.CalismaVarMi ASC, d.CalismaTakvimiDetayId DESC''', [profil, yil]);
    var gun = DateTime(baslangic.year, baslangic.month, baslangic.day);
    for (var i = 0; i < 370; i++) {
      gun = DateTime(gun.year, gun.month, gun.day - 1);
      if (gun.weekday > DateTime.friday) continue;
      final iso = tarihYaz(gun);
      final kayitlar = takvim.where((e) => e['BaslangicTarihi'] != null && e['BitisTarihi'] != null &&
          e['BaslangicTarihi'].toString().compareTo(iso) <= 0 && e['BitisTarihi'].toString().compareTo(iso) >= 0);
      if (kayitlar.isEmpty || kayitlar.first['CalismaVarMi'] == 1) return gun;
    }
    throw StateError('Çalışma takviminde önceki ders günü bulunamadı.');
  }

  static Future<int> yeniSurum(DatabaseExecutor db, int profil, String yil, DateTime tarih, String simdi) async {
    final bas = tarihYaz(tarih);
    final mevcut = await db.query('DersProgramiSurum',
      where: 'OgretmenProfilId = ? AND EgitimOgretimYili = ? AND Aktif = 1', whereArgs: [profil, yil]);
    if (mevcut.any((e) => e['BaslangicTarihi'] != null && e['BaslangicTarihi'].toString().compareTo(bas) > 0)) {
      throw StateError('Yeni başlangıç tarihi son yüklenen programdan önce olamaz. Önce tarihi kontrol edin.');
    }
    final bitis = tarihYaz(await oncekiDersGunu(db, profil, yil, tarih));
    for (final eski in mevcut) {
      if (eski['BaslangicTarihi'] == bas) {
        await db.update('DersProgramiSurum', {'Aktif': 0}, where: 'ProgramSurumId = ?', whereArgs: [eski['ProgramSurumId']]);
      } else if (eski['BitisTarihi'] == null || eski['BitisTarihi'].toString().compareTo(bas) >= 0) {
        if (eski['BaslangicTarihi'] != null && eski['BaslangicTarihi'].toString().compareTo(bitis) > 0) {
          throw StateError('İki program arasında önceki program için geçerli bir ders günü yok. Başlangıç tarihini kontrol edin.');
        }
        await db.update('DersProgramiSurum', {'BitisTarihi': bitis}, where: 'ProgramSurumId = ?', whereArgs: [eski['ProgramSurumId']]);
      }
    }
    return db.insert('DersProgramiSurum', {
      'OgretmenProfilId': profil, 'EgitimOgretimYili': yil, 'BaslangicTarihi': bas,
      'BitisTarihi': null, 'Aktif': 1, 'OlusturmaTarihi': simdi,
    });
  }
}
