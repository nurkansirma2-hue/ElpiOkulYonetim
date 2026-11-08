import '../database/local_database.dart';
import '../database/ders_programi_surumu.dart';
import 'package:sqflite/sqflite.dart';
import '../core/calisma_modu.dart';
import '../models/bireysel_seflik.dart';
import 'calisma_modu_service.dart';
import 'bireysel_yillik_plan_service.dart';

class BireyselDersProgramiKayitGirdisi {
  const BireyselDersProgramiKayitGirdisi({
    required this.gun,
    required this.dersSaatiNo,
    required this.baslangic,
    required this.bitis,
    required this.dersAdi,
    required this.sinif,
    required this.derslik,
  });

  final String gun;
  final int dersSaatiNo;
  final String baslangic;
  final String bitis;
  final String dersAdi;
  final String sinif;
  final String derslik;
  bool get gorevMi => dersAdi == 'Koordinatörlük' && sinif.isEmpty;
}

class BireyselGunlukDers {
  const BireyselGunlukDers({
    required this.dersId,
    required this.dersSaatiNo,
    required this.baslangic,
    required this.bitis,
    required this.dersAdi,
    required this.sinif,
    required this.sinifSeviyesi,
    required this.derslik,
    required this.konu,
    this.seflikMi = false,
    this.dersProgramiId,
    this.sinifSubeId,
    this.dersSaatiId,
    this.programSurumId,
  });

  final int dersId;
  final int dersSaatiNo;
  final int? dersProgramiId, sinifSubeId, dersSaatiId, programSurumId;
  final String baslangic;
  final String bitis;
  final String dersAdi;
  final String sinif;
  final int? sinifSeviyesi;
  final String derslik;
  final bool seflikMi;
  bool get gorevMi => seflikMi || (dersAdi == 'Koordinatörlük' && sinif.isEmpty);
  final String konu;
}

class BireyselHaftalikDers {
  const BireyselHaftalikDers({
    required this.gun,
    required this.gunNo,
    required this.dersId,
    required this.dersSaatiNo,
    required this.baslangic,
    required this.bitis,
    required this.dersAdi,
    required this.sinif,
    required this.derslik,
    this.seflikMi = false,
    this.dersProgramiId,
    this.programSurumId,
  });

  final String gun;
  final int gunNo;
  final int dersId;
  final int? dersProgramiId, programSurumId;
  final int dersSaatiNo;
  final String baslangic;
  final String bitis;
  final String dersAdi;
  final String sinif;
  final String derslik;
  final bool seflikMi;
  bool get gorevMi => seflikMi || (dersAdi == 'Koordinatörlük' && sinif.isEmpty);
}

class BireyselBugunDersDurumu {
  const BireyselBugunDersDurumu({
    required this.tarih,
    required this.gunAdi,
    required this.haftaSonu,
    required this.calismaTakvimiVarMi,
    required this.tarihTakvimdeVarMi,
    required this.calismaVarMi,
    required this.takvimAciklamasi,
    required this.ozelGunAciklamasi,
    required this.dersler,
  });

  final DateTime tarih;
  final String gunAdi;
  final bool haftaSonu;
  final bool calismaTakvimiVarMi;
  final bool tarihTakvimdeVarMi;
  final bool calismaVarMi;
  final String takvimAciklamasi;
  final String ozelGunAciklamasi;
  final List<BireyselGunlukDers> dersler;
}

class BireyselDersProgramiService {
  BireyselDersProgramiService._();

  static Future<List<BireyselHaftalikDers>> haftalikProgramiGetir({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    DateTime? tarih,
  }) async {
    if (ogretmenProfilId <= 0) {
      throw Exception('Geçerli bir öğretmen profil kimliği bulunamadı.');
    }

    final yil = egitimOgretimYili.trim();

    if (yil.isEmpty) {
      throw Exception('Eğitim öğretim yılı boş bırakılamaz.');
    }

    try {
      final db = await LocalDatabase.instance.database;

      final tarihIso = _tarihIso(tarih ?? DateTime.now());
      final sonuc = await db.rawQuery(
        '''
        SELECT
          dp.DersProgramiId,
          dp.ProgramSurumId,
          dp.Gun,
          d.DersId,
          ds.SiraNo,
          dp.Baslangic,
          dp.Bitis,
          dp.Derslik,
          d.DersAdi,
          s.SinifKodu
        FROM DersProgrami dp
        LEFT JOIN DersProgramiSurum ps ON ps.ProgramSurumId = dp.ProgramSurumId
        INNER JOIN Ders d
          ON d.DersId = dp.DersId
        INNER JOIN SinifSube s
          ON s.SinifSubeId = dp.SinifSubeId
        INNER JOIN DersSaati ds
          ON ds.DersSaatiId = dp.DersSaatiId
        WHERE dp.OgretmenProfilId = ?
          AND dp.EgitimOgretimYili = ?
          AND dp.Aktif = 1
          AND (dp.ProgramSurumId IS NULL OR (ps.Aktif = 1
            AND (ps.BaslangicTarihi IS NULL OR ps.BaslangicTarihi <= ?)
            AND (ps.BitisTarihi IS NULL OR ps.BitisTarihi >= ?)))
          AND d.Aktif = 1
          AND s.Aktif = 1
          AND ds.Aktif = 1
        ORDER BY
          CASE dp.Gun
            WHEN 'Pazartesi' THEN 1
            WHEN 'Salı' THEN 2
            WHEN 'Çarşamba' THEN 3
            WHEN 'Perşembe' THEN 4
            WHEN 'Cuma' THEN 5
            ELSE 99
          END,
          ds.SiraNo ASC,
          d.DersAdi ASC
        ''',
        [ogretmenProfilId, yil, tarihIso, tarihIso],
      );

      final gorevler = await _gorevleriGetir(db, ogretmenProfilId, yil, tarihIso);
      final haftalik = <BireyselHaftalikDers>[
        ...gorevler.map((g) => BireyselHaftalikDers(
          gun: g['Gun'].toString(), gunNo: _gunNo(g['Gun'].toString()), dersId: 0,
          dersSaatiNo: g['DersSaatiNo'] as int, baslangic: g['Baslangic'].toString(),
          bitis: g['Bitis'].toString(), dersAdi: g['GorevAdi'].toString(), sinif: '', derslik: '',
          seflikMi: g['SeflikMi'] == 1,
        )),
        ...sonuc.map(
          (satir) {
            final gun = (satir['Gun'] ?? '').toString().trim();

            return BireyselHaftalikDers(
              gun: gun,
              gunNo: _gunNo(gun),
              dersProgramiId: satir['DersProgramiId'] as int?,
              programSurumId: satir['ProgramSurumId'] as int?,
              dersId: (satir['DersId'] as int?) ?? 0,
              dersSaatiNo: (satir['SiraNo'] as int?) ?? 0,
              baslangic: (satir['Baslangic'] ?? '').toString().trim(),
              bitis: (satir['Bitis'] ?? '').toString().trim(),
              dersAdi: (satir['DersAdi'] ?? '').toString().trim(),
              sinif: (satir['SinifKodu'] ?? '').toString().trim(),
              derslik: (satir['Derslik'] ?? '').toString().trim(),
            );
          },
        ),
      ];
      haftalik.sort((a,b) => a.gunNo == b.gunNo ? a.dersSaatiNo.compareTo(b.dersSaatiNo) : a.gunNo.compareTo(b.gunNo));
      return List.unmodifiable(haftalik);
    } catch (e) {
      throw Exception(
        'Bireysel öğretmenin haftalık ders programı okunurken '
        'hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<BireyselBugunDersDurumu> bugununDurumunuGetir({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    DateTime? tarih,
  }) async {
    if (ogretmenProfilId <= 0) {
      throw Exception('Geçerli bir öğretmen profil kimliği bulunamadı.');
    }

    final yil = egitimOgretimYili.trim();

    if (yil.isEmpty) {
      throw Exception('Eğitim öğretim yılı boş bırakılamaz.');
    }

    final simdi = tarih ?? DateTime.now();
    final gun = DateTime(simdi.year, simdi.month, simdi.day);
    final gunAdi = _gunAdi(gun.weekday);
    final tarihIso = _tarihIso(gun);
    final haftaSonu = gun.weekday == DateTime.saturday ||
        gun.weekday == DateTime.sunday;

    try {
      final db = await LocalDatabase.instance.database;

      final takvimAdaylari = await db.query(
        'CalismaTakvimi',
        columns: ['CalismaTakvimiId', 'EgitimOgretimYili'],
        where: 'OgretmenProfilId = ? AND Aktif = 1',
        whereArgs: [ogretmenProfilId],
        orderBy: 'CalismaTakvimiId DESC',
      );
      final planYili = BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
        yil,
      );
      final takvimKaydi = takvimAdaylari.where(
        (satir) =>
            BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
              satir['EgitimOgretimYili'].toString(),
            ) ==
            planYili,
      ).toList(growable: false);

      final calismaTakvimiVarMi = takvimKaydi.isNotEmpty;
      var tarihTakvimdeVarMi = false;
      var calismaVarMi = false;
      var takvimAciklamasi = '';
      var ozelGunAciklamasi = '';

      if (calismaTakvimiVarMi) {
        final calismaTakvimiId =
            takvimKaydi.first['CalismaTakvimiId'] as int;

        final takvimDetayi = await db.rawQuery(
          '''
          SELECT
            CalismaVarMi,
            KayitTuru,
            Aciklama,
            OzelGunAciklamasi
          FROM CalismaTakvimiDetay
          WHERE CalismaTakvimiId = ?
            AND Aktif = 1
            AND BaslangicTarihi IS NOT NULL
            AND BitisTarihi IS NOT NULL
            AND ? BETWEEN BaslangicTarihi AND BitisTarihi
          ORDER BY CalismaVarMi ASC, CalismaTakvimiDetayId DESC
          LIMIT 1
          ''',
          [calismaTakvimiId, tarihIso],
        );

        if (takvimDetayi.isNotEmpty) {
          final satir = takvimDetayi.first;
          tarihTakvimdeVarMi = true;
          calismaVarMi = (satir['CalismaVarMi'] as int? ?? 0) == 1;
          takvimAciklamasi =
              (satir['Aciklama'] ?? satir['KayitTuru'] ?? '')
                  .toString()
                  .trim();
          ozelGunAciklamasi =
              (satir['OzelGunAciklamasi'] ?? '').toString().trim();
        }
      }

      final dersSonucu = await db.rawQuery(
        '''
        SELECT
          dp.DersProgramiId,
          dp.ProgramSurumId,
          dp.SinifSubeId,
          dp.DersSaatiId,
          d.DersId,
          ds.SiraNo,
          dp.Baslangic,
          dp.Bitis,
          dp.Derslik,
          d.DersAdi,
          s.SinifKodu,
          s.SinifSeviyesi
        FROM DersProgrami dp
        LEFT JOIN DersProgramiSurum ps ON ps.ProgramSurumId = dp.ProgramSurumId
        INNER JOIN Ders d
          ON d.DersId = dp.DersId
        INNER JOIN SinifSube s
          ON s.SinifSubeId = dp.SinifSubeId
        INNER JOIN DersSaati ds
          ON ds.DersSaatiId = dp.DersSaatiId
        WHERE dp.OgretmenProfilId = ?
          AND dp.EgitimOgretimYili = ?
          AND dp.Gun = ?
          AND dp.Aktif = 1
          AND (dp.ProgramSurumId IS NULL OR (ps.Aktif = 1
            AND (ps.BaslangicTarihi IS NULL OR ps.BaslangicTarihi <= ?)
            AND (ps.BitisTarihi IS NULL OR ps.BitisTarihi >= ?)))
          AND d.Aktif = 1
          AND s.Aktif = 1
          AND ds.Aktif = 1
        ORDER BY ds.SiraNo ASC
        ''',
        [ogretmenProfilId, yil, gunAdi, tarihIso, tarihIso],
      );

      final planlar = <(int, int), BireyselYillikPlanIcerigi>{};
      final dersler = <BireyselGunlukDers>[];
      for (final satir in dersSonucu) {
        final dersId = (satir['DersId'] as int?) ?? 0;
        final seviye = satir['SinifSeviyesi'] as int?;
        final konular = <String>{};
        if (dersId > 0 && seviye != null && seviye > 0) {
          final anahtar = (dersId, seviye);
          final plan = planlar[anahtar] ??=
              await BireyselYillikPlanService.icerigiGetir(
                ogretmenProfilId: ogretmenProfilId,
                egitimOgretimYili: yil,
                dersId: dersId,
                sinifSeviyesi: seviye,
              );
          for (final detay in plan.tariheAitDetaylar(gun)) {
            final konu = (detay['Konu'] ?? '').toString().trim();
            final metin = konu.isNotEmpty
                ? konu
                : (detay['IcerikCercevesi'] ?? '').toString().trim();
            konular.addAll(
              metin.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty),
            );
          }
        }
        dersler.add(BireyselGunlukDers(
          dersId: dersId,
          dersProgramiId: satir['DersProgramiId'] as int?,
          programSurumId: satir['ProgramSurumId'] as int?,
          sinifSubeId: satir['SinifSubeId'] as int?,
          dersSaatiId: satir['DersSaatiId'] as int?,
          dersSaatiNo: (satir['SiraNo'] as int?) ?? 0,
          baslangic: (satir['Baslangic'] ?? '').toString().trim(),
          bitis: (satir['Bitis'] ?? '').toString().trim(),
          dersAdi: (satir['DersAdi'] ?? '').toString().trim(),
          sinif: (satir['SinifKodu'] ?? '').toString().trim(),
          sinifSeviyesi: seviye,
          derslik: (satir['Derslik'] ?? '').toString().trim(),
          konu: konular.join('\n'),
        ));
      }

      final gorevler = await _gorevleriGetir(db, ogretmenProfilId, yil, tarihIso);
      final gunluk = <BireyselGunlukDers>[
        ...dersler,
        ...gorevler.where((g) => g['Gun'] == gunAdi).map((g) => BireyselGunlukDers(
          dersId: 0, dersSaatiNo: g['DersSaatiNo'] as int,
          baslangic: g['Baslangic'].toString(), bitis: g['Bitis'].toString(),
          dersAdi: g['GorevAdi'].toString(), sinif: '', sinifSeviyesi: null, derslik: '', konu: '',
          seflikMi: g['SeflikMi'] == 1,
        )),
      ]..sort((a,b) => a.dersSaatiNo.compareTo(b.dersSaatiNo));
      return BireyselBugunDersDurumu(
        tarih: gun,
        gunAdi: gunAdi,
        haftaSonu: haftaSonu,
        calismaTakvimiVarMi: calismaTakvimiVarMi,
        tarihTakvimdeVarMi: tarihTakvimdeVarMi,
        calismaVarMi: calismaVarMi,
        takvimAciklamasi: takvimAciklamasi,
        ozelGunAciklamasi: ozelGunAciklamasi,
        dersler: List<BireyselGunlukDers>.unmodifiable(gunluk),
      );
    } catch (e) {
      throw Exception(
        'Seçilen günün ders ve çalışma takvimi durumu okunurken '
        'hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<List<Map<String, Object?>>> _gorevleriGetir(
      DatabaseExecutor db, int profil, String yil, String tarih) async {
    final gorevler = await db.rawQuery('''
    SELECT g.* FROM DersProgramiGorev g
    INNER JOIN DersProgramiSurum ps ON ps.ProgramSurumId = g.ProgramSurumId
    WHERE ps.OgretmenProfilId = ? AND ps.EgitimOgretimYili = ? AND ps.Aktif = 1
      AND (ps.BaslangicTarihi IS NULL OR ps.BaslangicTarihi <= ?)
      AND (ps.BitisTarihi IS NULL OR ps.BitisTarihi >= ?)
  ''', [profil, yil, tarih, tarih]);

    final meslekPaketi = await db.query(
      'UygulamaAyarlari',
      columns: ['Deger'],
      where: 'Anahtar = ?',
      whereArgs: ['MeslekPaketiAktif'],
      limit: 1,
    );
    if (meslekPaketi.isEmpty || meslekPaketi.single['Deger'] != '1') {
      return gorevler;
    }

    final seflikler = await db.rawQuery('''
      SELECT sp.Gun, sp.DersSaatiNo, sp.Baslangic, sp.Bitis,
        COALESCE(NULLIF(TRIM(sp.HamMetin), ''),
          CASE st.SeflikTuru
            WHEN 'Alan' THEN 'Alan Şefliği'
            WHEN 'AtolyeLaboratuvar' THEN 'Atölye/Laboratuvar Şefliği'
            ELSE 'Şeflik'
          END) AS GorevAdi,
        1 AS SeflikMi
      FROM SeflikProgramSaati sp
      LEFT JOIN SeflikTanim st ON st.SeflikId = sp.SeflikId
        AND st.OgretmenProfilId = sp.OgretmenProfilId
        AND st.EgitimOgretimYili = sp.EgitimOgretimYili
      WHERE sp.OgretmenProfilId = ? AND sp.EgitimOgretimYili = ?
        AND sp.Aktif = 1 AND sp.BaslangicTarihi <= ?
        AND (sp.BitisTarihi IS NULL OR sp.BitisTarihi >= ?)
        AND (sp.SeflikId IS NULL OR (st.Aktif = 1
          AND st.BaslangicTarihi <= ?
          AND (st.BitisTarihi IS NULL OR st.BitisTarihi >= ?)))
    ''', [profil, yil, tarih, tarih, tarih, tarih]);
    return [...gorevler, ...seflikler];
  }

  static Future<int> kaydet({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    required List<BireyselDersProgramiKayitGirdisi> kayitlar,
    required DateTime baslangicTarihi,
    SeflikProgramiImportu? seflikImportu,
  }) async {
    kayitlar = List.unmodifiable(kayitlar);
    final temizEgitimOgretimYili = egitimOgretimYili.trim();

    if (ogretmenProfilId <= 0) {
      throw Exception('Geçerli bir öğretmen profil kimliği bulunamadı.');
    }

    if (temizEgitimOgretimYili.isEmpty) {
      throw Exception('Eğitim öğretim yılı boş bırakılamaz.');
    }

    if (kayitlar.isEmpty && seflikImportu == null) {
      throw Exception('Kaydedilecek ders programı kaydı bulunamadı.');
    }

    try {
      final db = await LocalDatabase.instance.database;
      final simdi = DateTime.now().toIso8601String();

      return await db.transaction<int>((txn) async {
        await _importOturumunuDogrula(
          txn, ogretmenProfilId, temizEgitimOgretimYili, seflikImportu != null,
        );
        final profil = await txn.query(
          'OgretmenProfil',
          columns: ['OgretmenProfilId'],
          where: 'OgretmenProfilId = ? AND Aktif = ?',
          whereArgs: [ogretmenProfilId, 1],
          limit: 1,
        );

        if (profil.isEmpty) {
          throw Exception(
            'Ders programı kaydedilemedi çünkü aktif öğretmen profili '
            'bulunamadı. ÖğretmenProfilId: $ogretmenProfilId',
          );
        }

        final programSurumId = await DersProgramiSurumu.yeniSurum(
          txn, ogretmenProfilId, temizEgitimOgretimYili, baslangicTarihi, simdi,
        );
        await _seflikSaatleriniKaydet(
          txn, ogretmenProfilId, temizEgitimOgretimYili,
          kayitlar, seflikImportu, simdi, baslangicTarihi,
        );

        var eklenenKayitSayisi = 0;

        for (var i = 0; i < kayitlar.length; i++) {
          final kayit = kayitlar[i];

          final gun = kayit.gun.trim();
          final dersAdi = kayit.dersAdi.trim();
          final sinif = kayit.sinif.trim();
          final baslangic = _saatNormalizeEt(kayit.baslangic);
          final bitis = _saatNormalizeEt(kayit.bitis);
          final derslik = kayit.derslik.trim();

          if (gun.isEmpty) {
            throw Exception(
              '${i + 1}. ders kaydında gün bilgisi boş.',
            );
          }

          if (kayit.dersSaatiNo <= 0) {
            throw Exception(
              '${i + 1}. ders kaydında ders saati numarası geçersiz: '
              '${kayit.dersSaatiNo}',
            );
          }

          if (dersAdi.isEmpty) {
            throw Exception(
              '${i + 1}. ders kaydında ders adı boş.',
            );
          }

          if (sinif.isEmpty && !kayit.gorevMi) {
            throw Exception(
              '${i + 1}. ders kaydında sınıf/şube bilgisi boş.',
            );
          }

          if (baslangic == null || bitis == null ||
              baslangic.compareTo(bitis) >= 0) {
            throw Exception(
              '${i + 1}. ders kaydında başlangıç/bitiş saati geçersiz. '
              'Gelen değer: ${kayit.baslangic} - ${kayit.bitis}',
            );
          }

          if (kayit.gorevMi) {
            await txn.insert('DersProgramiGorev', {
              'ProgramSurumId': programSurumId, 'Gun': gun,
              'DersSaatiNo': kayit.dersSaatiNo, 'Baslangic': baslangic,
              'Bitis': bitis, 'GorevAdi': 'Koordinatörlük',
            });
            eklenenKayitSayisi++;
            continue;
          }

          final sinifSubeId = await _sinifSubeGetirVeyaOlustur(
            txn: txn,
            sinifKodu: sinif,
            egitimOgretimYili: temizEgitimOgretimYili,
            simdi: simdi,
          );

          final dersId = await _dersGetirVeyaOlustur(
            txn: txn,
            dersAdi: dersAdi,
            simdi: simdi,
          );

          await _dersSinifBaglantisiniOlustur(
            txn: txn,
            dersId: dersId,
            sinifSubeId: sinifSubeId,
            egitimOgretimYili: temizEgitimOgretimYili,
            simdi: simdi,
          );

          final dersSaatiId = await _dersSaatiGetirVeyaOlustur(
            txn: txn,
            siraNo: kayit.dersSaatiNo,
          );

          await txn.insert(
            'DersProgrami',
            {
              'ProgramSurumId': programSurumId,
              'SinifSubeId': sinifSubeId,
              'DersId': dersId,
              'DersSaatiId': dersSaatiId,
              'Gun': gun,
              'Baslangic': baslangic,
              'Bitis': bitis,
              'Derslik': derslik.isEmpty ? null : derslik,
              'OgretmenProfilId': ogretmenProfilId,
              'EgitimOgretimYili': temizEgitimOgretimYili,
              'Aktif': 1,
              'OlusturmaTarihi': simdi,
              'GuncellemeTarihi': null,
            },
          );

          eklenenKayitSayisi++;
        }

        await _importOturumunuDogrula(
          txn, ogretmenProfilId, temizEgitimOgretimYili, seflikImportu != null,
        );
        return eklenenKayitSayisi;
      });
    } catch (e) {
      throw Exception(
        'Bireysel öğretmen ders programı SQLite veritabanına '
        'kaydedilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<void> _importOturumunuDogrula(
    DatabaseExecutor txn, int ogretmenId, String yil, bool seflikVar,
  ) async {
    if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError('Ders programı importu yalnız bireysel modda kullanılabilir.');
    }
    final profiller = await txn.query('OgretmenProfil',
        where: 'Aktif = 1', orderBy: 'OgretmenProfilId DESC', limit: 1);
    if (profiller.isEmpty || profiller.single['OgretmenProfilId'] != ogretmenId ||
        profiller.single['EgitimOgretimYili'].toString().trim() != yil) {
      throw StateError('Öğretmen veya eğitim yılı değişti. Ön izlemeyi yenileyin.');
    }
    if (seflikVar) {
      final tercih = await txn.query('UygulamaAyarlari',
          where: 'Anahtar = ?', whereArgs: ['MeslekPaketiAktif'], limit: 1);
      if (tercih.isEmpty || tercih.single['Deger'] != '1') {
        throw StateError('Şeflik saatleri için meslek paketini etkinleştirin.');
      }
    }
  }

  static Future<void> _seflikSaatleriniKaydet(
    DatabaseExecutor txn, int ogretmenId, String yil,
    List<BireyselDersProgramiKayitGirdisi> dersler,
    SeflikProgramiImportu? aktarim, String simdi, DateTime baslangicTarihi,
  ) async {
    final bas = seflikTarihYaz(baslangicTarihi);
    final oncekiBitis = seflikTarihYaz(await DersProgramiSurumu.oncekiDersGunu(txn, ogretmenId, yil, baslangicTarihi));
    if (aktarim != null && (seflikTarihYaz(aktarim.baslangicTarihi) != bas || aktarim.bitisTarihi != null)) {
      throw ArgumentError('Şeflik ve ders programı aynı başlangıç tarihini kullanmalıdır; bitiş otomatik belirlenir.');
    }
    final mevcut = await txn.query('SeflikProgramSaati',
      where: 'OgretmenProfilId = ? AND EgitimOgretimYili = ? AND Aktif = 1', whereArgs: [ogretmenId, yil]);
    final kalan = <Map<String, Object?>>[];
    for (final eski in mevcut) {
      final eskiBas = eski['BaslangicTarihi'] as String;
      final eskiSon = eski['BitisTarihi'] as String?;
      if (eski['Kaynak'] == 'Import') {
        if (eskiBas.compareTo(bas) > 0) {
          throw StateError('Başlangıç tarihi daha önce yüklenen şeflik programından önce olamaz.');
        }
        if (eskiBas == bas) {
          await txn.update('SeflikProgramSaati', {'Aktif': 0, 'GuncellemeTarihi': simdi},
            where: 'SeflikProgramSaatiId = ?', whereArgs: [eski['SeflikProgramSaatiId']]);
          continue;
        }
        if (eskiSon == null || eskiSon.compareTo(bas) >= 0) {
          if (eskiBas.compareTo(oncekiBitis) > 0) {
            throw StateError('Önceki şeflik programı için geçerli bir ders günü bulunamadı.');
          }
          await txn.update('SeflikProgramSaati', {'BitisTarihi': oncekiBitis, 'GuncellemeTarihi': simdi},
            where: 'SeflikProgramSaatiId = ?', whereArgs: [eski['SeflikProgramSaatiId']]);
        }
        continue;
      }
      // Yalnız yeni programla tarih aralığı kesişen manuel saatler denetlenir.
      if (eskiSon == null || eskiSon.compareTo(bas) >= 0) kalan.add(Map.from(eski));
    }
    // İçe aktarılan metinden şeflik türü tahmin edilmez. Yalnızca bu
    // öğretmen/yıl/tarih için tek bir geçerli tanım varsa güvenle eşleştirilir.
    final tanimlar = await txn.query(
      'SeflikTanim',
      columns: ['SeflikId'],
      where: 'OgretmenProfilId = ? AND EgitimOgretimYili = ? '
          'AND Aktif = 1 AND BaslangicTarihi <= ? '
          'AND (BitisTarihi IS NULL OR BitisTarihi >= ?)',
      whereArgs: [ogretmenId, yil, bas, bas],
    );
    final eslesenSeflikId =
        tanimlar.length == 1 ? tanimlar.single['SeflikId'] as int : null;

    final yeni = <Map<String, Object?>>[];
    for (final saat in aktarim?.saatler ?? <SeflikProgramSaatiGirdisi>[]) {
      final ilk = _saatNormalizeEt(saat.baslangic), son = _saatNormalizeEt(saat.bitis);
      if (_gunNo(saat.gun) == 0 || saat.dersSaatiNo <= 0 || saat.hamMetin.trim().isEmpty ||
          ilk == null || son == null || ilk.compareTo(son) >= 0) {
        throw ArgumentError('${saat.gun} ${saat.dersSaatiNo}. şeflik saati geçersiz.');
      }
      final veri = <String, Object?>{
        'OgretmenProfilId': ogretmenId, 'EgitimOgretimYili': yil, 'SeflikId': eslesenSeflikId,
        'Gun': _gunAdi(_gunNo(saat.gun)), 'DersSaatiNo': saat.dersSaatiNo,
        'Baslangic': ilk, 'Bitis': son, 'BaslangicTarihi': bas, 'BitisTarihi': null,
        'Kaynak': 'Import', 'HamMetin': saat.hamMetin.trim(), 'Aktif': 1,
        'OlusturmaTarihi': simdi, 'GuncellemeTarihi': null,
      };
      if (kalan.any((e) => _programSaatiCakisiyor(veri, e))) {
        throw StateError('${saat.gun} ${saat.dersSaatiNo}. şeflik saati başka bir görevle çakışıyor.');
      }
      kalan.add(veri);
      yeni.add(veri);
    }
    final kontrol = <Map<String, Object?>>[];
    for (final ders in dersler) {
      final ilk = _saatNormalizeEt(ders.baslangic), son = _saatNormalizeEt(ders.bitis);
      if (_gunNo(ders.gun) == 0 || ilk == null || son == null || ilk.compareTo(son) >= 0) {
        throw ArgumentError('${ders.gun} ${ders.dersSaatiNo}. saatin bilgileri geçersiz.');
      }
      final veri = <String, Object?>{
        'Gun': _gunAdi(_gunNo(ders.gun)), 'DersSaatiNo': ders.dersSaatiNo,
        'Baslangic': ilk, 'Bitis': son,
      };
      if ([...kalan, ...kontrol].any((e) => _programSaatiCakisiyor(veri, e))) {
        throw StateError('${ders.gun} ${ders.dersSaatiNo}. ders/görev başka bir saatle çakışıyor. Kayıt yapılmadı.');
      }
      kontrol.add(veri);
    }
    for (final veri in yeni) {
      await txn.insert('SeflikProgramSaati', veri);
    }
  }

  static bool _programSaatiCakisiyor(
    Map<String, Object?> a, Map<String, Object?> b,
  ) => a['Gun'] == b['Gun'] &&
      (a['DersSaatiNo'] == b['DersSaatiNo'] ||
          ((a['Baslangic'] as String).compareTo(b['Bitis'] as String) < 0 &&
              (b['Baslangic'] as String).compareTo(a['Bitis'] as String) < 0));

  static Future<int> _sinifSubeGetirVeyaOlustur({
    required dynamic txn,
    required String sinifKodu,
    required String egitimOgretimYili,
    required String simdi,
  }) async {
    final mevcut = await txn.query(
      'SinifSube',
      where: 'SinifKodu = ? AND EgitimOgretimYili = ?',
      whereArgs: [sinifKodu, egitimOgretimYili],
      limit: 1,
    );

    if (mevcut.isNotEmpty) {
      final id = mevcut.first['SinifSubeId'] as int;

      await txn.update(
        'SinifSube',
        {
          'Aktif': 1,
          'GuncellemeTarihi': simdi,
        },
        where: 'SinifSubeId = ?',
        whereArgs: [id],
      );

      return id;
    }

    return await txn.insert(
      'SinifSube',
      {
        'SinifKodu': sinifKodu,
        'SinifSeviyesi': _sinifSeviyesiGetir(sinifKodu),
        'Sube': _subeGetir(sinifKodu),
        'Alan': null,
        'RehberOgretmen': null,
        'EgitimOgretimYili': egitimOgretimYili,
        'Aktif': 1,
        'OlusturmaTarihi': simdi,
        'GuncellemeTarihi': null,
      },
    );
  }

  static Future<int> _dersGetirVeyaOlustur({
    required dynamic txn,
    required String dersAdi,
    required String simdi,
  }) async {
    final mevcut = await txn.query(
      'Ders',
      where: 'DersAdi = ? AND Aktif = ?',
      whereArgs: [dersAdi, 1],
      orderBy: 'DersId ASC',
      limit: 1,
    );

    if (mevcut.isNotEmpty) {
      return mevcut.first['DersId'] as int;
    }

    return await txn.insert(
      'Ders',
      {
        'DersAdi': dersAdi,
        'DersKodu': null,
        'Aktif': 1,
        'OlusturmaTarihi': simdi,
        'GuncellemeTarihi': null,
      },
    );
  }

  static Future<void> _dersSinifBaglantisiniOlustur({
    required dynamic txn,
    required int dersId,
    required int sinifSubeId,
    required String egitimOgretimYili,
    required String simdi,
  }) async {
    final mevcut = await txn.query(
      'DersSinif',
      where: 'DersId = ? AND SinifSubeId = ? AND EgitimOgretimYili = ?',
      whereArgs: [
        dersId,
        sinifSubeId,
        egitimOgretimYili,
      ],
      limit: 1,
    );

    if (mevcut.isNotEmpty) {
      final id = mevcut.first['DersSinifId'] as int;

      await txn.update(
        'DersSinif',
        {
          'Aktif': 1,
        },
        where: 'DersSinifId = ?',
        whereArgs: [id],
      );

      return;
    }

    await txn.insert(
      'DersSinif',
      {
        'DersId': dersId,
        'SinifSubeId': sinifSubeId,
        'EgitimOgretimYili': egitimOgretimYili,
        'Aktif': 1,
        'OlusturmaTarihi': simdi,
      },
    );
  }

  static Future<int> _dersSaatiGetirVeyaOlustur({
    required dynamic txn,
    required int siraNo,
  }) async {
    final mevcut = await txn.query(
      'DersSaati',
      where: 'SiraNo = ?',
      whereArgs: [siraNo],
      limit: 1,
    );

    if (mevcut.isNotEmpty) {
      final id = mevcut.first['DersSaatiId'] as int;

      await txn.update(
        'DersSaati',
        {
          'Aktif': 1,
        },
        where: 'DersSaatiId = ?',
        whereArgs: [id],
      );

      return id;
    }

    return await txn.insert(
      'DersSaati',
      {
        'SiraNo': siraNo,
        'Baslangic': null,
        'Bitis': null,
        'Aktif': 1,
      },
    );
  }

  static int? _sinifSeviyesiGetir(String sinifKodu) {
    final eslesme = RegExp(r'^\s*(\d{1,2})').firstMatch(sinifKodu);
    return int.tryParse(eslesme?.group(1) ?? '');
  }

  static String? _subeGetir(String sinifKodu) {
    final eslesme = RegExp(
      r'^\s*\d{1,2}\s*-\s*([A-ZÇĞİÖŞÜ0-9]+)',
      caseSensitive: false,
    ).firstMatch(sinifKodu);

    final sube = eslesme?.group(1)?.trim();

    if (sube == null || sube.isEmpty) {
      return null;
    }

    return sube;
  }

  static String? _saatNormalizeEt(String deger) {
    final eslesme = RegExp(
      r'^\s*(\d{1,2}):(\d{2})\s*$',
    ).firstMatch(deger);

    if (eslesme == null) {
      return null;
    }

    final saat = int.tryParse(eslesme.group(1) ?? '');
    final dakika = int.tryParse(eslesme.group(2) ?? '');

    if (saat == null ||
        dakika == null ||
        saat < 0 ||
        saat > 23 ||
        dakika < 0 ||
        dakika > 59) {
      return null;
    }

    return '${saat.toString().padLeft(2, '0')}:'
        '${dakika.toString().padLeft(2, '0')}';
  }

  static int _gunNo(String gun) {
    switch (gun.trim().toLowerCase()) {
      case 'pazartesi':
        return DateTime.monday;
      case 'salı':
      case 'sali':
        return DateTime.tuesday;
      case 'çarşamba':
      case 'carsamba':
        return DateTime.wednesday;
      case 'perşembe':
      case 'persembe':
        return DateTime.thursday;
      case 'cuma':
        return DateTime.friday;
      case 'cumartesi':
        return DateTime.saturday;
      case 'pazar':
        return DateTime.sunday;
      default:
        return 0;
    }
  }

  static String _gunAdi(int haftaGunu) {
    switch (haftaGunu) {
      case DateTime.monday:
        return 'Pazartesi';
      case DateTime.tuesday:
        return 'Salı';
      case DateTime.wednesday:
        return 'Çarşamba';
      case DateTime.thursday:
        return 'Perşembe';
      case DateTime.friday:
        return 'Cuma';
      case DateTime.saturday:
        return 'Cumartesi';
      case DateTime.sunday:
        return 'Pazar';
      default:
        return '';
    }
  }

  static String _tarihIso(DateTime tarih) {
    return '${tarih.year.toString().padLeft(4, '0')}-'
        '${tarih.month.toString().padLeft(2, '0')}-'
        '${tarih.day.toString().padLeft(2, '0')}';
  }
}
