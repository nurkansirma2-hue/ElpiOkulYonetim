import '../database/local_database.dart';
import 'bireysel_ders_programi_service.dart';

/// Yalnız önizleme üretir; onay verilmeden SQLite kayıtlarını değiştirmez.
class SeflikYillikFaaliyet {
  const SeflikYillikFaaliyet({
    required this.tarih,
    required this.gun,
    required this.dersSaatiNo,
    required this.baslangic,
    required this.bitis,
    required this.faaliyet,
  });

  final DateTime tarih;
  final String gun;
  final int dersSaatiNo;
  final String baslangic;
  final String bitis;
  final String faaliyet;
}

class SeflikYillikPlanTaslagi {
  const SeflikYillikPlanTaslagi({
    required this.egitimOgretimYili,
    required this.faaliyetler,
    required this.uyarilar,
  });

  final String egitimOgretimYili;
  final List<SeflikYillikFaaliyet> faaliyetler;
  final List<String> uyarilar;
}

class BireyselSeflikYillikPlanService {
  BireyselSeflikYillikPlanService._();

  static const _konular = <String>[
    'Laboratuvarların kullanıma hazır olma durumunun kontrolü',
    'Bilgisayar ve çevre birimlerinin çalışırlık kontrolü',
    'Ağ, internet ve kablolama durumunun kontrolü',
    'İş sağlığı ve güvenliği kontrolleri',
    'Ders yazılımlarının çalışırlığının kontrolü',
    'Demirbaş ve ekipman durumunun kontrolü',
    'Arıza ve bakım ihtiyaçlarının kayıt altına alınması',
    'Ders öğretmenlerinden gelen teknik ihtiyaçların değerlendirilmesi',
    'Güncelleme ve güvenlik kontrolleri',
    'Laboratuvar düzeni ve kullanım koşullarının kontrolü',
    'Bakım-onarım kayıtlarının gözden geçirilmesi',
    'Eksik malzeme ve donanım ihtiyaçlarının belirlenmesi',
  ];

  /// Başlangıç/bitiş tarihleri okul takviminden onaylı biçimde sağlanmalıdır.
  /// Takvimde çalışılmayan veya tanımsız günlere faaliyet yazılmaz.
  static Future<SeflikYillikPlanTaslagi> taslakOlustur({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    required DateTime ilkGun,
    required DateTime sonGun,
  }) async {
    final yil = egitimOgretimYili.trim();
    if (ogretmenProfilId <= 0 || yil.isEmpty) {
      throw ArgumentError('Öğretmen ve eğitim öğretim yılı zorunludur.');
    }
    final bas = DateTime(ilkGun.year, ilkGun.month, ilkGun.day);
    final son = DateTime(sonGun.year, sonGun.month, sonGun.day);
    if (son.isBefore(bas) || son.difference(bas).inDays > 370) {
      throw ArgumentError('Yıllık plan tarih aralığı geçersiz.');
    }
    final db = await LocalDatabase.instance.database;
    final takvimler = await db.query(
      'CalismaTakvimi',
      columns: ['CalismaTakvimiId', 'EgitimOgretimYili'],
      where: 'OgretmenProfilId = ? AND Aktif = 1',
      whereArgs: [ogretmenProfilId],
      orderBy: 'CalismaTakvimiId DESC',
    );
    final eslesen = takvimler.where(
      (t) => _yilNormalize(t['EgitimOgretimYili'].toString()) ==
          _yilNormalize(yil),
    ).toList();
    if (eslesen.isEmpty) {
      throw StateError(
        'Çalışma takvimi bulunamadı. Yıllık şeflik planı üretmeden '
        'önce eğitim öğretim yılı takvimini yükleyin.',
      );
    }
    final detaylar = await db.query(
      'CalismaTakvimiDetay',
      columns: ['BaslangicTarihi', 'BitisTarihi', 'CalismaVarMi',
        'Aciklama', 'KayitTuru', 'CalismaTakvimiDetayId'],
      where: 'CalismaTakvimiId = ? AND Aktif = 1',
      whereArgs: [eslesen.first['CalismaTakvimiId']],
      orderBy: 'CalismaVarMi ASC, CalismaTakvimiDetayId DESC',
    );

    // Eğitim yılı takvimi ders haftalarının dışında (ör. 1 Eylül)
    // zorunlu olarak günlük kayıt içermez. Takvim kapsamı dışındaki
    // tarihler çalışma günü sayılmaz; yalnız iç boşluklar uyarılır.
    final kapsanan = detaylar.where((satir) =>
        satir['BaslangicTarihi'] != null &&
        satir['BitisTarihi'] != null).toList();
    if (kapsanan.isEmpty) {
      throw StateError('Çalışma takviminde tarih aralığı bulunamadı.');
    }
    final kapsamaBaslangici = kapsanan
        .map((s) => s['BaslangicTarihi'].toString())
        .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    final kapsamaBitisi = kapsanan
        .map((s) => s['BitisTarihi'].toString())
        .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    final faaliyetler = <SeflikYillikFaaliyet>[];
    final uyarilar = <String>[];
    var sira = 0;
    for (var tarih = bas;
        !tarih.isAfter(son);
        tarih = tarih.add(const Duration(days: 1))) {
      if (tarih.weekday > DateTime.friday) continue;
      final iso = _tarih(tarih);
      final gunKayitlari = detaylar.where((satir) =>
        satir['BaslangicTarihi'] != null &&
        satir['BitisTarihi'] != null &&
        satir['BaslangicTarihi'].toString().compareTo(iso) <= 0 &&
        satir['BitisTarihi'].toString().compareTo(iso) >= 0).toList();
      if (gunKayitlari.isEmpty) {
        if (iso.compareTo(kapsamaBaslangici) < 0 ||
            iso.compareTo(kapsamaBitisi) > 0) continue;
        uyarilar.add('$iso: Çalışma takviminde gün tanımlı değil.');
        continue;
      }
      // Çakışan takvim kayıtlarında çalışılmayan gün önceliklidir.
      if (gunKayitlari.any((g) => g['CalismaVarMi'] != 1)) continue;
      // Program sürümü hafta içinde değişebilir; her günün geçerli saatini oku.
      final program =
          await BireyselDersProgramiService.haftalikProgramiGetir(
            ogretmenProfilId: ogretmenProfilId,
            egitimOgretimYili: yil,
            tarih: tarih,
          );
      final saatler = program.where(
        (d) => d.seflikMi && d.gunNo == tarih.weekday,
      ).toList()
        ..sort((a, b) => a.dersSaatiNo.compareTo(b.dersSaatiNo));
      for (final saat in saatler) {
        faaliyetler.add(SeflikYillikFaaliyet(
          tarih: tarih,
          gun: saat.gun,
          dersSaatiNo: saat.dersSaatiNo,
          baslangic: saat.baslangic,
          bitis: saat.bitis,
          faaliyet: _konular[sira++ % _konular.length],
        ));
      }
    }
    if (faaliyetler.isEmpty) {
      uyarilar.add('Seçilen tarihlerde tanımlı şeflik saati bulunamadı.');
    }
    return SeflikYillikPlanTaslagi(
      egitimOgretimYili: yil,
      faaliyetler: List.unmodifiable(faaliyetler),
      uyarilar: List.unmodifiable(uyarilar),
    );
  }

  /// Onaylı planı atomik kaydeder. Mevcut onaylı planın üstüne yazılmaz.
  static Future<void> onaylaVeKaydet({
    required int ogretmenProfilId,
    required SeflikYillikPlanTaslagi taslak,
  }) async {
    if (ogretmenProfilId <= 0 || taslak.egitimOgretimYili.trim().isEmpty ||
        taslak.faaliyetler.isEmpty) {
      throw StateError('Kaydedilecek geçerli yıllık plan bulunamadı.');
    }
    if (taslak.uyarilar.isNotEmpty) {
      throw StateError('Takvim uyarıları giderilmeden yıllık plan onaylanamaz.');
    }
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final mevcut = await txn.rawQuery(
        'SELECT COUNT(*) AS Sayi FROM SeflikYillikFaaliyet '
        'WHERE OgretmenProfilId = ? AND EgitimOgretimYili = ?',
        [ogretmenProfilId, taslak.egitimOgretimYili],
      );
      if ((mevcut.first['Sayi'] as int) > 0) {
        throw StateError('Bu eğitim yılına ait onaylı şeflik planı zaten var.');
      }
      final gorulen = <String>{};
      final simdi = DateTime.now().toIso8601String();
      for (final f in taslak.faaliyetler) {
        final faaliyet = f.faaliyet.trim();
        final anahtar = '${_tarih(f.tarih)}:${f.dersSaatiNo}';
        if (faaliyet.isEmpty || !gorulen.add(anahtar) ||
            f.dersSaatiNo <= 0 || f.baslangic.compareTo(f.bitis) >= 0) {
          throw StateError('Boş, tekrarlanan veya geçersiz şeflik faaliyeti var.');
        }
        await txn.insert('SeflikYillikFaaliyet', {
          'OgretmenProfilId': ogretmenProfilId,
          'EgitimOgretimYili': taslak.egitimOgretimYili,
          'Tarih': _tarih(f.tarih),
          'Gun': f.gun,
          'DersSaatiNo': f.dersSaatiNo,
          'Baslangic': f.baslangic,
          'Bitis': f.bitis,
          'Faaliyet': faaliyet,
          'OnayTarihi': simdi,
        });
      }
    });
  }

  static Future<List<SeflikYillikFaaliyet>> onayliPlaniGetir({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
  }) async {
    final db = await LocalDatabase.instance.database;
    final satirlar = await db.query('SeflikYillikFaaliyet',
      where: 'OgretmenProfilId = ? AND EgitimOgretimYili = ?',
      whereArgs: [ogretmenProfilId, egitimOgretimYili],
      orderBy: 'Tarih, DersSaatiNo');
    return List.unmodifiable(satirlar.map((s) => SeflikYillikFaaliyet(
      tarih: DateTime.parse(s['Tarih'] as String),
      gun: s['Gun'] as String,
      dersSaatiNo: s['DersSaatiNo'] as int,
      baslangic: s['Baslangic'] as String,
      bitis: s['Bitis'] as String,
      faaliyet: s['Faaliyet'] as String,
    )));
  }

  static String _tarih(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  static String _yilNormalize(String yil) =>
      yil.replaceAll(RegExp(r'[^0-9]'), '');
}
