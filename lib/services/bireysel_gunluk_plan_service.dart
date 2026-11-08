import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';

import '../core/calisma_modu.dart';
import '../database/gunluk_plan_semasi.dart';
import '../database/local_database.dart';
import '../models/bireysel_gunluk_plan.dart';
import '../models/dbf_belgesi.dart';
import 'dbf_gunluk_plan_taslagi.dart';
import 'gunluk_plan_hafta_taslagi.dart';
import 'bireysel_yillik_plan_service.dart';
import 'calisma_modu_service.dart';

class BireyselGunlukPlanService {
  BireyselGunlukPlanService._();

  static const azamiAlanUzunlugu = 20000;

  static void _icerigiDogrula(BireyselGunlukPlan plan) {
    for (final alan in plan.icerikAlanlari.entries) {
      if ((alan.value as String).length > azamiAlanUzunlugu) {
        throw FormatException(
          'Günlük plan alanı en fazla $azamiAlanUzunlugu karakter olabilir: ${alan.key}.',
        );
      }
    }
  }

  static String _yil(String value) =>
      BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(value);

  static String _tarih(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static Future<void> _modKontrol() async {
    if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError(
        'Günlük plan yalnız bireysel öğretmen modunda kullanılabilir.',
      );
    }
  }

  static Future<({Map<String, Object?> ogretmen, Map<String, Object?> okul})>
  _oturumuGetir(DatabaseExecutor db, int profilId, String yil) async {
    await _modKontrol();
    final teachers = await db.query(
      'OgretmenProfil',
      where: 'Aktif = 1',
      orderBy: 'OgretmenProfilId DESC',
      limit: 1,
    );
    final schools = await db.query(
      'OkulProfil',
      where: 'Id = 1 AND AktifMi = 1',
    );
    if (teachers.isEmpty || schools.length != 1) {
      throw StateError('Önce bireysel öğretmen ve okul kurulumunu tamamlayın.');
    }
    final teacher = teachers.single, school = schools.single;
    if (profilId <= 0 ||
        teacher['OgretmenProfilId'] != profilId ||
        yil.isEmpty ||
        _yil(teacher['EgitimOgretimYili'].toString()) != yil ||
        _yil(school['EgitimYili'].toString()) != yil ||
        (school['OkulId'] ?? '').toString().trim().isEmpty ||
        (teacher['AdSoyad'] ?? '').toString().trim().isEmpty ||
        (school['OkulAdi'] ?? '').toString().trim().isEmpty ||
        school['OkulAdi'] != teacher['OkulAdi']) {
      throw StateError(
        'Okul, öğretmen veya eğitim yılı değişti. Ekranı yeniden açın.',
      );
    }
    return (ogretmen: teacher, okul: school);
  }

  static Future<List<GunlukPlanSinifSecenegi>> _siniflariGetir(
    DatabaseExecutor db,
    int profilId,
    String yil,
    int dersId,
    int seviye,
  ) async {
    if (dersId <= 0 || seviye <= 0) {
      throw ArgumentError('Geçerli bir ders ve sınıf seviyesi seçin.');
    }
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT s.SinifSubeId, s.SinifKodu, s.SinifSeviyesi,
        s.EgitimOgretimYili AS SinifYili, dp.EgitimOgretimYili AS ProgramYili
      FROM DersProgrami dp
      LEFT JOIN DersProgramiSurum ps ON ps.ProgramSurumId = dp.ProgramSurumId
      INNER JOIN Ders d ON d.DersId = dp.DersId
      INNER JOIN SinifSube s ON s.SinifSubeId = dp.SinifSubeId
      WHERE dp.OgretmenProfilId = ? AND dp.DersId = ?
        AND s.SinifSeviyesi = ? AND dp.Aktif = 1 AND d.Aktif = 1 AND s.Aktif = 1
        AND (dp.ProgramSurumId IS NULL OR ps.Aktif = 1)
      ORDER BY s.SinifKodu, s.SinifSubeId
    ''',
      [profilId, dersId, seviye],
    );
    final seen = <int>{};
    return List.unmodifiable([
      for (final row in rows)
        if (_yil(row['ProgramYili'].toString()) == yil &&
            _yil(row['SinifYili'].toString()) == yil &&
            seen.add(row['SinifSubeId'] as int))
          GunlukPlanSinifSecenegi(
            sinifSubeId: row['SinifSubeId'] as int,
            sinifKodu: row['SinifKodu'] as String,
            sinifSeviyesi: row['SinifSeviyesi'] as int,
          ),
    ]);
  }

  static Future<List<GunlukPlanSinifSecenegi>> siniflariGetir({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    required int dersId,
    required int sinifSeviyesi,
  }) async {
    final db = await LocalDatabase.instance.database;
    final yil = _yil(egitimOgretimYili);
    await _oturumuGetir(db, ogretmenProfilId, yil);
    final result = await _siniflariGetir(
      db,
      ogretmenProfilId,
      yil,
      dersId,
      sinifSeviyesi,
    );
    await _modKontrol();
    return result;
  }

  static Future<List<Map<String, Object?>>> _anahtarlaGetir(
    DatabaseExecutor db,
    String okulId,
    int profilId,
    String yil,
    int dersId,
    int sinifId,
    DateTime tarih, {
    DateTime? bitis,
  }) => db.query(
    GunlukPlanSemasi.tablo,
    where:
        'OkulId = ? AND OgretmenProfilId = ? AND EgitimOgretimYili = ? '
        'AND DersId = ? AND SinifSubeId = ? AND Tarih BETWEEN ? AND ?',
    whereArgs: [
      okulId,
      profilId,
      yil,
      dersId,
      sinifId,
      _tarih(tarih),
      _tarih(bitis ?? tarih),
    ],
    orderBy: 'GunlukPlanId DESC',
  );

  static String _birlestir(
    List<Map<String, Object?>> rows,
    String field, {
    String? bosIse,
  }) {
    final result = <String>{};
    for (final row in rows) {
      var value = (row[field] ?? '').toString().trim();
      if (value.isEmpty && bosIse != null) {
        value = (row[bosIse] ?? '').toString().trim();
      }
      result.addAll(
        value.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    }
    return result.join('\n');
  }

  static String _ozet(Object veri) =>
      sha256.convert(utf8.encode(jsonEncode(veri))).toString();

  static Future<BireyselGunlukPlan> _bilgisiyleOku(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final plan = BireyselGunlukPlan.fromMap(row);
    final ek = await db.query(
      'UygulamaAyarlari',
      where: 'Anahtar = ?',
      whereArgs: ['gunlukPlan.bilgi.v1.${plan.id}'],
    );
    return ek.isEmpty
        ? plan
        : plan.copyWith(
            planBilgisi:
                jsonDecode(ek.single['Deger'] as String)
                    as Map<String, dynamic>,
          );
  }

  static Future<void> _ayarYaz(
    DatabaseExecutor db,
    String key,
    Object veri,
  ) async {
    final rows = await db.query(
      'UygulamaAyarlari',
      where: 'Anahtar = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) {
      await db.insert('UygulamaAyarlari', {
        'Anahtar': key,
        'Deger': jsonEncode(veri),
        'GuncellemeTarihi': DateTime.now().toIso8601String(),
      });
    } else {
      await db.update(
        'UygulamaAyarlari',
        {
          'Deger': jsonEncode(veri),
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        },
        where: 'Anahtar = ?',
        whereArgs: [key],
      );
    }
  }

  static Future<DbfBelgesi> _dbfOku(
    DatabaseExecutor db,
    String okulId,
    int profil,
    String yil,
    int ders,
    int seviye,
  ) async {
    final key = 'dbf.v1.${jsonEncode([okulId, profil, yil, ders, seviye])}';
    final rows = await db.query(
      'UygulamaAyarlari',
      where: 'Anahtar = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) {
      throw StateError(
        'Ders bilgi formu eksik. Bu dersin mevcut DBF yükleme alanını kullanın.',
      );
    }
    return DbfBelgesi.fromJson(
      jsonDecode(rows.single['Deger'] as String) as Map<String, dynamic>,
    );
  }

  static Future<BireyselGunlukPlan?> kayitliHaftayiGetir({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    required int dersId,
    required int sinifSeviyesi,
    required String sinifKodu,
    required DateTime tarih,
  }) async {
    final db = await LocalDatabase.instance.database;
    final yil = _yil(egitimOgretimYili);
    final oturum = await _oturumuGetir(db, ogretmenProfilId, yil);
    final okulId = oturum.okul['OkulId'] as String;
    final siniflar = await _siniflariGetir(
      db,
      ogretmenProfilId,
      yil,
      dersId,
      sinifSeviyesi,
    );
    final eslesen = siniflar.where((s) => s.sinifKodu == sinifKodu.trim());
    if (eslesen.length != 1) return null;
    final sinifSubeId = eslesen.single.sinifSubeId;
    // Kayıtlı haftayı kaynak değişmiş/silinmiş olsa da kendi anlık görüntüsüyle aç.
    final kayitlar = await db.query(
      GunlukPlanSemasi.tablo,
      where:
          'OkulId = ? AND OgretmenProfilId = ? AND EgitimOgretimYili = ? AND DersId = ? AND SinifSubeId = ?',
      whereArgs: [okulId, ogretmenProfilId, yil, dersId, sinifSubeId],
      orderBy: 'GunlukPlanId DESC',
    );
    BireyselGunlukPlan? eski;
    for (final row in kayitlar) {
      final aday = await _bilgisiyleOku(db, row);
      final bas = DateTime.parse(
        aday.planBilgisi['baslangic'] as String? ?? _tarih(aday.tarih),
      );
      final bit = DateTime.parse(
        aday.planBilgisi['bitis'] as String? ?? _tarih(aday.tarih),
      );
      final gun = DateTime(tarih.year, tarih.month, tarih.day);
      if (!gun.isBefore(bas) && !gun.isAfter(bit)) {
        eski = aday;
        break;
      }
    }
    if (eski == null && kayitlar.isNotEmpty) {
      // Gün bazında kaydedilmiş eski planın haftası yalnız yıllık kaynaktan bulunur.
      final kaynak = await BireyselYillikPlanService.icerigiGetir(
        ogretmenProfilId: ogretmenProfilId,
        egitimOgretimYili: yil,
        dersId: dersId,
        sinifSeviyesi: sinifSeviyesi,
      );
      final rows = kaynak.tariheAitDetaylar(tarih);
      if (rows.isNotEmpty) {
        final hafta = GunlukPlanHaftaTaslagi.haftayiOku(rows);
        final mevcut = await _anahtarlaGetir(
          db,
          okulId,
          ogretmenProfilId,
          yil,
          dersId,
          sinifSubeId,
          hafta.bas,
          bitis: hafta.bit,
        );
        if (mevcut.isNotEmpty) {
          eski = await _bilgisiyleOku(db, mevcut.first);
        }
      }
    }
    return eski == null ? null : getir(eski.id!);
  }

  static Future<BireyselGunlukPlan> hazirla({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    required int dersId,
    required int sinifSeviyesi,
    required int sinifSubeId,
    required DateTime tarih,
    bool yenidenOlustur = false,
  }) async {
    final db = await LocalDatabase.instance.database;
    final yil = _yil(egitimOgretimYili);
    final oturum = await _oturumuGetir(db, ogretmenProfilId, yil);
    final okulId = oturum.okul['OkulId'] as String;
    final siniflar = await _siniflariGetir(
      db,
      ogretmenProfilId,
      yil,
      dersId,
      sinifSeviyesi,
    );
    final secili = siniflar.where((s) => s.sinifSubeId == sinifSubeId);
    if (secili.length != 1) {
      throw StateError('Seçilen şube öğretmenin bu dersine ait değil.');
    }
    // Kayıtlı haftayı kaynak değişmiş/silinmiş olsa da kendi anlık görüntüsüyle aç.
    final kayitlar = await db.query(
      GunlukPlanSemasi.tablo,
      where:
          'OkulId = ? AND OgretmenProfilId = ? AND EgitimOgretimYili = ? AND DersId = ? AND SinifSubeId = ?',
      whereArgs: [okulId, ogretmenProfilId, yil, dersId, sinifSubeId],
      orderBy: 'GunlukPlanId DESC',
    );
    BireyselGunlukPlan? eski;
    for (final row in kayitlar) {
      final aday = await _bilgisiyleOku(db, row);
      final bas = DateTime.parse(
        aday.planBilgisi['baslangic'] as String? ?? _tarih(aday.tarih),
      );
      final bit = DateTime.parse(
        aday.planBilgisi['bitis'] as String? ?? _tarih(aday.tarih),
      );
      final gun = DateTime(tarih.year, tarih.month, tarih.day);
      if (!gun.isBefore(bas) && !gun.isAfter(bit)) {
        eski = aday;
        break;
      }
    }
    if (eski != null && !yenidenOlustur) return getir(eski.id!);
    final yillik = await BireyselYillikPlanService.icerigiGetir(
      ogretmenProfilId: ogretmenProfilId,
      egitimOgretimYili: yil,
      dersId: dersId,
      sinifSeviyesi: sinifSeviyesi,
    );
    if (yillik.yillikPlanId == null || yillik.detaylar.isEmpty) {
      throw StateError(
        'Yıllık plan eksik. Bu dersin mevcut yıllık plan yükleme alanını kullanın.',
      );
    }
    final rows = yillik.tariheAitDetaylar(tarih);
    // Takvim yalnız bu yıllık plana bağlı kaynak dosyadan okunur.
    final yp = (await db.query(
      'YillikPlan',
      where: 'YillikPlanId = ?',
      whereArgs: [yillik.yillikPlanId],
    )).single;
    final kaynakKey =
        'yillikPlan.takvim.v1.${jsonEncode([okulId, ogretmenProfilId, yil, dersId, sinifSeviyesi, yillik.yillikPlanId])}';
    final kaynakKaydi = await db.query(
      'UygulamaAyarlari',
      where: 'Anahtar = ?',
      whereArgs: [kaynakKey],
    );
    Map<String, dynamic>? takvimKaynak;
    List<Map<String, Object?>> tumTakvim;
    if (kaynakKaydi.isNotEmpty) {
      takvimKaynak =
          jsonDecode(kaynakKaydi.single['Deger'] as String)
              as Map<String, dynamic>;
      tumTakvim = (takvimKaynak['kayitlar'] as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
    } else {
      // Eski importlarda ancak dosya adı VE import zamanı eşleşirse kaynak doğrulanır.
      tumTakvim = await db.rawQuery(
        """
        SELECT td.*, t.EgitimOgretimYili AS KaynakYili FROM CalismaTakvimiDetay td
        INNER JOIN CalismaTakvimi t ON t.CalismaTakvimiId = td.CalismaTakvimiId
        WHERE t.OgretmenProfilId = ? AND t.Aktif = 1 AND td.Aktif = 1
          AND t.KaynakDosyaAdi = ?
          AND COALESCE(t.GuncellemeTarihi,t.OlusturmaTarihi) = ?
      """,
        [
          ogretmenProfilId,
          (yp['Aciklama'] ?? '').toString().replaceFirst(
            RegExp(r'^Import dosyası:\s*'),
            '',
          ),
          yp['GuncellemeTarihi'] ?? yp['OlusturmaTarihi'],
        ],
      );
      tumTakvim = tumTakvim
          .where((t) => _yil(t['KaynakYili'].toString()) == yil)
          .toList();
    }
    final secimBas = rows.isEmpty
        ? _tarih(tarih)
        : rows.first['BaslangicTarihi'] as String;
    final secimBit = rows.isEmpty
        ? _tarih(tarih)
        : rows.first['BitisTarihi'] as String;
    final uygunTakvim = tumTakvim
        .where(
          (t) =>
              t['BaslangicTarihi'] is String &&
              t['BitisTarihi'] is String &&
              (t['BaslangicTarihi'] as String).compareTo(secimBit) <= 0 &&
              (t['BitisTarihi'] as String).compareTo(secimBas) >= 0,
        )
        .toList();
    final tatiller = uygunTakvim.where((t) => t['CalismaVarMi'] == 0).toList();
    if (tatiller.any(
      (t) =>
          (t['BaslangicTarihi'] as String).compareTo(_tarih(tarih)) <= 0 &&
          (t['BitisTarihi'] as String).compareTo(_tarih(tarih)) >= 0,
    )) {
      throw StateError(
        'Seçilen tarih tatil/çalışma olmayan gün: '
        '${GunlukPlanHaftaTaslagi.birlestir(tatiller, 'Aciklama')}. Normal ders planı oluşturulmadı.',
      );
    }
    final hafta = GunlukPlanHaftaTaslagi.haftayiOku(rows);
    // Eski gün bazlı kayıtlar da aynı kaynak haftasında ikinci kayıt oluşturmaz.
    final mevcut = await _anahtarlaGetir(
      db,
      okulId,
      ogretmenProfilId,
      yil,
      dersId,
      sinifSubeId,
      hafta.bas,
      bitis: hafta.bit,
    );
    if (eski == null && mevcut.isNotEmpty) {
      eski = await _bilgisiyleOku(db, mevcut.first);
    }
    if (eski != null && !yenidenOlustur) return getir(eski.id!);
    final dbf = await _dbfOku(
      db,
      okulId,
      ogretmenProfilId,
      yil,
      dersId,
      sinifSeviyesi,
    );
    final ders = (await db.query(
      'Ders',
      where: 'DersId = ? AND Aktif = 1',
      whereArgs: [dersId],
    )).single;
    var taslak = BireyselGunlukPlan(
      id: eski?.id,
      surum: eski?.surum ?? 0,
      okulId: okulId,
      ogretmenProfilId: ogretmenProfilId,
      egitimOgretimYili: yil,
      ogretmenAdi: oturum.ogretmen['AdSoyad'] as String,
      okulAdi: oturum.okul['OkulAdi'] as String,
      dersAdi: ders['DersAdi'] as String,
      sinifKodu: secili.single.sinifKodu,
      dersId: dersId,
      sinifSubeId: sinifSubeId,
      sinifSeviyesi: sinifSeviyesi,
      tarih: eski?.tarih ?? hafta.bas,
      planBilgisi: {'kazanimAciklamasi': _birlestir(rows, 'KazanimAciklamasi')},
      konu: _birlestir(rows, 'Konu', bosIse: 'IcerikCercevesi'),
      kazanim: _birlestir(rows, 'Kazanim'),
      ogrenmeCiktisi: _birlestir(rows, 'OgrenmeCiktisi'),
      yontemTeknik: _birlestir(rows, 'YontemTeknik'),
      aracGerec: _birlestir(rows, 'AracGerec'),
      degerlendirme: _birlestir(rows, 'Degerlendirme'),
    );
    taslak = DbfGunlukPlanTaslagi.tamamla(taslak, dbf);
    taslak = GunlukPlanHaftaTaslagi.tamamla(
      taslak,
      rows,
      {
        'yillikPlanId': yillik.yillikPlanId,
        'yillikPlanOzeti': _ozet(rows),
        'yillikPlanKaydi': yp,
        'yillikPlanSatirlari': rows,
        'dbfSurum': dbf.surum,
        'dbfOzeti': dbf.icerikOzeti,
        'dbfAnlikGoruntu': dbf.toJson(),
        'dbfKayitOzeti': _ozet(dbf.toJson()),
        'takvimSatirlari': uygunTakvim,
        'takvimKaynakSurumu': takvimKaynak?['surum'],
      },
      kaynakUyarisi: [
        if (uygunTakvim.isEmpty)
          'Bu yıllık plana ait tatil/etkinlik takvimi doğrulanamadı. Mevcut yükleme alanından yıllık planı yeniden yükleyin.',
        if (tatiller.isNotEmpty)
          'Bu haftada tatil/çalışma olmayan gün var. Yıllık plandaki ders saatini kontrol edin.',
      ].join('\n'),
      takvimNotu: [
        GunlukPlanHaftaTaslagi.birlestir(uygunTakvim, 'Aciklama'),
        GunlukPlanHaftaTaslagi.birlestir(uygunTakvim, 'OzelGunAciklamasi'),
      ].where((s) => s.isNotEmpty).join('\n'),
    );
    // Eski günlük kayıt kimliği/tarihi korunur; haftalık aralık ek bilgilerde saklanır.
    if (eski != null) taslak = taslak.copyWith(tarih: eski.tarih);
    _icerigiDogrula(taslak);
    final current = await _oturumuGetir(db, ogretmenProfilId, yil);
    _sahipligiDogrula(
      taslak,
      current.okul['OkulId'] as String,
      ogretmenProfilId,
      yil,
    );
    return taslak;
  }

  /// Önceki içerik, kaynaklar ve belge bağlantısı salt okunur sürüm kaydıdır.
  static Future<List<BireyselGunlukPlan>> gecmisiGetir(int id) async {
    final plan = await getir(id); // Sahiplik ve mod kontrolü.
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'UygulamaAyarlari',
      where: 'Anahtar LIKE ?',
      whereArgs: ['gunlukPlan.gecmis.v1.$id.%'],
    );
    final result = <BireyselGunlukPlan>[];
    for (final row in rows) {
      final veri = jsonDecode(row['Deger'] as String) as Map<String, dynamic>;
      final eski = BireyselGunlukPlan.fromMap(
        Map<String, Object?>.from(veri['kayit'] as Map),
      ).copyWith(planBilgisi: Map<String, dynamic>.from(veri['bilgi'] as Map));
      _sahipligiDogrula(
        eski,
        plan.okulId,
        plan.ogretmenProfilId,
        plan.egitimOgretimYili,
      );
      result.add(eski);
    }
    result.sort((a, b) => b.surum.compareTo(a.surum));
    return result;
  }

  static void _sahipligiDogrula(
    BireyselGunlukPlan plan,
    String okulId,
    int profilId,
    String yil,
  ) {
    if (plan.okulId != okulId ||
        plan.ogretmenProfilId != profilId ||
        plan.egitimOgretimYili != yil) {
      throw StateError(
        'Günlük plan farklı okul, öğretmen veya eğitim yılına ait.',
      );
    }
  }

  static Future<BireyselGunlukPlan> getir(int id) async {
    if (id <= 0) throw ArgumentError('Geçerli bir günlük plan seçin.');
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      GunlukPlanSemasi.tablo,
      where: 'GunlukPlanId = ?',
      whereArgs: [id],
    );
    if (rows.length != 1) throw StateError('Günlük plan kaydı bulunamadı.');
    final plan = await _bilgisiyleOku(db, rows.single);
    _icerigiDogrula(plan);
    final oturum = await _oturumuGetir(
      db,
      plan.ogretmenProfilId,
      plan.egitimOgretimYili,
    );
    _sahipligiDogrula(
      plan,
      oturum.okul['OkulId'] as String,
      oturum.ogretmen['OgretmenProfilId'] as int,
      _yil(oturum.okul['EgitimYili'].toString()),
    );
    await _modKontrol();
    return plan;
  }

  static Future<BireyselGunlukPlan> kaydet(BireyselGunlukPlan plan) async {
    _icerigiDogrula(plan);
    if (plan.dersId <= 0 ||
        plan.sinifSubeId <= 0 ||
        plan.sinifSeviyesi <= 0 ||
        plan.egitimOgretimYili != _yil(plan.egitimOgretimYili) ||
        (plan.id == null
            ? plan.surum != 0
            : plan.id! <= 0 || plan.surum <= 0)) {
      throw ArgumentError(
        'Günlük planın kimlik veya sürüm bilgileri geçersiz.',
      );
    }
    final db = await LocalDatabase.instance.database;
    await _modKontrol();
    return db.transaction((txn) async {
      final oturum = await _oturumuGetir(
        txn,
        plan.ogretmenProfilId,
        plan.egitimOgretimYili,
      );
      _sahipligiDogrula(
        plan,
        oturum.okul['OkulId'] as String,
        oturum.ogretmen['OgretmenProfilId'] as int,
        _yil(oturum.okul['EgitimYili'].toString()),
      );
      final simdi = DateTime.now().toIso8601String();
      for (final alan in [
        plan.unite,
        plan.kazanimAciklamasi,
        plan.aciklamalar,
      ]) {
        if (alan.length > azamiAlanUzunlugu) {
          throw const FormatException('Plan alanı 20.000 karakteri aşamaz.');
        }
      }
      late int id;
      if (plan.id == null) {
        if (plan.belgeId != null) {
          throw StateError(
            'Belge bağlantısı yalnız PDF oluşturma işleminde kaydedilebilir.',
          );
        }
        final mevcut = await _anahtarlaGetir(
          txn,
          plan.okulId,
          plan.ogretmenProfilId,
          plan.egitimOgretimYili,
          plan.dersId,
          plan.sinifSubeId,
          DateTime.parse(
            plan.planBilgisi['baslangic'] as String? ?? _tarih(plan.tarih),
          ),
          bitis: DateTime.parse(
            plan.planBilgisi['bitis'] as String? ?? _tarih(plan.tarih),
          ),
        );
        if (mevcut.isNotEmpty) {
          throw StateError(
            'Bu haftanın planı zaten kaydedildi. Mevcut planı yeniden açın.',
          );
        }
        final siniflar = await _siniflariGetir(
          txn,
          plan.ogretmenProfilId,
          plan.egitimOgretimYili,
          plan.dersId,
          plan.sinifSeviyesi,
        );
        final secili = siniflar.where((s) => s.sinifSubeId == plan.sinifSubeId);
        if (secili.length != 1) {
          throw StateError(
            'Ders ve şube kapsamı değişti. Ekranı yeniden açın.',
          );
        }
        final dersler = await txn.query(
          'Ders',
          where: 'DersId = ? AND Aktif = 1',
          whereArgs: [plan.dersId],
        );
        id = await txn.insert(GunlukPlanSemasi.tablo, {
          'Surum': 1,
          'OkulId': plan.okulId,
          'OgretmenProfilId': plan.ogretmenProfilId,
          'EgitimOgretimYili': plan.egitimOgretimYili,
          'DersId': plan.dersId,
          'SinifSubeId': plan.sinifSubeId,
          'SinifSeviyesi': plan.sinifSeviyesi,
          'OgretmenAdi': oturum.ogretmen['AdSoyad'],
          'OkulAdi': oturum.okul['OkulAdi'],
          'DersAdi': dersler.single['DersAdi'],
          'SinifKodu': secili.single.sinifKodu,
          'Tarih': _tarih(plan.tarih),
          ...plan.icerikAlanlari,
          'BelgeId': null,
          'OlusturmaTarihi': simdi,
        });
      } else {
        id = plan.id!;
        final rows = await _anahtarlaGetir(
          txn,
          plan.okulId,
          plan.ogretmenProfilId,
          plan.egitimOgretimYili,
          plan.dersId,
          plan.sinifSubeId,
          plan.tarih,
        );
        if (rows.length != 1 ||
            rows.single['GunlukPlanId'] != id ||
            rows.single['SinifSeviyesi'] != plan.sinifSeviyesi ||
            rows.single['Surum'] != plan.surum) {
          throw StateError(
            'Günlük plan başka bir işlemde değişti. Yeniden açın.',
          );
        }
        final row = rows.single;
        // PDF bağlantısını formdaki eski anlık görüntüyle değiştirmeyin.
        final onceki = await _bilgisiyleOku(txn, row);
        if (plan.icerikAlanlari.entries.any((e) => row[e.key] != e.value) ||
            jsonEncode(onceki.planBilgisi) != jsonEncode(plan.planBilgisi)) {
          await _ayarYaz(txn, 'gunlukPlan.gecmis.v1.$id.${plan.surum}', {
            'kayit': row,
            'bilgi': onceki.planBilgisi,
          });
          final changed = await txn.update(
            GunlukPlanSemasi.tablo,
            {
              ...plan.icerikAlanlari,
              'Surum': plan.surum + 1,
              'GuncellemeTarihi': simdi,
            },
            where: 'GunlukPlanId = ? AND Surum = ?',
            whereArgs: [id, plan.surum],
          );
          if (changed != 1) {
            throw StateError('Günlük plan değişti. Yeniden açın.');
          }
        }
      }
      await _ayarYaz(txn, 'gunlukPlan.bilgi.v1.$id', plan.planBilgisi);
      final current = await _oturumuGetir(
        txn,
        plan.ogretmenProfilId,
        plan.egitimOgretimYili,
      );
      _sahipligiDogrula(
        plan,
        current.okul['OkulId'] as String,
        current.ogretmen['OgretmenProfilId'] as int,
        _yil(current.okul['EgitimYili'].toString()),
      );
      final result = await txn.query(
        GunlukPlanSemasi.tablo,
        where: 'GunlukPlanId = ?',
        whereArgs: [id],
      );
      return _bilgisiyleOku(txn, result.single);
    });
  }
}
