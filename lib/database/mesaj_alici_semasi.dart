import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// v23: alıcı kimliği kaynak modül adından bağımsızdır.
class MesajAliciSemasi {
  static const tablolar = [
    'MesajOgretmenKisi',
    'MesajOgretmenSinif',
    'MesajAliciBag',
  ];

  static Future<void> hazirla(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE MesajOgretmenKisi (
      KisiId TEXT PRIMARY KEY NOT NULL CHECK(length(KisiId)=32 AND KisiId NOT GLOB '*[^a-f0-9]*'),
      OkulId TEXT NOT NULL REFERENCES OkulProfil(OkulId) ON DELETE RESTRICT,
      SahipProfilId INTEGER NOT NULL REFERENCES OgretmenProfil(OgretmenProfilId) ON DELETE RESTRICT,
      AdSoyad TEXT NOT NULL CHECK(length(trim(AdSoyad)) BETWEEN 1 AND 200),
      Telefon TEXT NOT NULL DEFAULT '' CHECK(length(Telefon)<=50),
      Aktif INTEGER NOT NULL DEFAULT 1 CHECK(Aktif IN (0,1)),
      OlusturmaTarihi TEXT NOT NULL, GuncellemeTarihi TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE MesajOgretmenSinif (
      KisiId TEXT NOT NULL REFERENCES MesajOgretmenKisi(KisiId) ON DELETE RESTRICT,
      SinifSubeId INTEGER NOT NULL REFERENCES SinifSube(SinifSubeId) ON DELETE RESTRICT,
      EgitimOgretimYili TEXT NOT NULL,
      Kaynak TEXT NOT NULL CHECK(Kaynak IN ('ElleDogrulandi','DersProgrami')),
      OlusturmaTarihi TEXT NOT NULL,
      PRIMARY KEY(KisiId,SinifSubeId,EgitimOgretimYili)
    )''');
    // Geçmiş bağları canlı kişilere FK ile bağlanmaz: sıfırlama veya yeni bir
    // öğrenci kimliğinin tekrar kullanılması geçmiş alıcıyı devralamaz.
    await db.execute('''CREATE TABLE MesajAliciBag (
      AliciId INTEGER NOT NULL REFERENCES MesajAlici(AliciId) ON DELETE RESTRICT,
      Tur TEXT NOT NULL CHECK(Tur IN ('Ogrenci','Veli','Ogretmen')),
      KisiId TEXT NOT NULL CHECK(length(trim(KisiId))>0),
      SinifSubeId INTEGER NOT NULL CHECK(SinifSubeId>0),
      AnlikGoruntu TEXT NOT NULL,
      EskiKayit INTEGER NOT NULL DEFAULT 0 CHECK(EskiKayit IN (0,1)),
      PRIMARY KEY(AliciId,Tur,KisiId,SinifSubeId)
    )''');
    await db.execute(
      'CREATE INDEX IX_MesajOgretmen_Sahip ON MesajOgretmenKisi(OkulId,SahipProfilId,Aktif)',
    );
    for (final r in eskiBaglar(
      await db.query('MesajKuyrugu'),
      await db.query('MesajAlici'),
    )) {
      await db.insert('MesajAliciBag', r);
    }
  }

  /// Yalnız eski kayıtların sürüm geçişinde bilinen tarihsel varsayımlar kullanılır.
  /// Ham alıcı/metin/durum/SMS kayıtları değiştirilmez.
  static List<Map<String, Object?>> eskiBaglar(
    List<Map<String, Object?>> kuyruklar,
    List<Map<String, Object?>> alicilar,
  ) {
    final kaynaklar = {
      for (final q in kuyruklar) q['KuyrukId']: q['KaynakModul'],
    };
    final sonuc = <String, Map<String, Object?>>{};
    for (final a in alicilar) {
      final kaynak = kaynaklar[a['KuyrukId']];
      if (kaynak == null) {
        throw const FormatException('Eski mesaj kuyruğu ilişkisi eksik.');
      }
      final tur =
          {
            'BilgiFormDuzeltmeOgrenci',
            'BilgiFormPaylasimOgrenci',
          }.contains(kaynak)
          ? 'Ogrenci'
          : 'Veli';
      final rows = jsonDecode(a['Ogrenciler'] as String) as List;
      if (rows.isEmpty) {
        throw const FormatException(
          'Eski mesaj alıcısının öğrenci ilişkisi eksik.',
        );
      }
      for (final raw in rows) {
        if (raw is! Map ||
            raw['id'] is! int ||
            (raw['id'] as int) <= 0 ||
            raw['sinifId'] is! int ||
            (raw['sinifId'] as int) <= 0 ||
            raw['aciklama'] is! String) {
          throw const FormatException('Eski mesaj alıcı ilişkisi geçersiz.');
        }
        final row = <String, Object?>{
          'AliciId': a['AliciId'],
          'Tur': tur,
          'KisiId': '${raw['id']}',
          'SinifSubeId': raw['sinifId'],
          'EskiKayit': 1,
          'AnlikGoruntu': jsonEncode({'aciklama': raw['aciklama']}),
        };
        sonuc['${a['AliciId']}:$tur:${raw['id']}:${raw['sinifId']}'] = row;
      }
    }
    return sonuc.values.toList();
  }
}
