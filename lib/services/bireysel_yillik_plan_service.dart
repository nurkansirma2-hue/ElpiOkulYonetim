import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel2003/excel2003.dart';
import 'package:office_oxide_ffi/office_oxide_ffi.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:sqflite/sqflite.dart';
import 'package:xml/xml.dart';

import '../database/local_database.dart';
import '../core/calisma_modu.dart';
import 'calisma_modu_service.dart';

class BireyselYillikPlanIcerigi {
  BireyselYillikPlanIcerigi({
    required this.yillikPlanId,
    required List<Map<String, Object?>> detaylar,
  }) : detaylar = List.unmodifiable(
         detaylar.map((satir) => Map<String, Object?>.unmodifiable(satir)),
       );

  final int? yillikPlanId;
  final List<Map<String, Object?>> detaylar;

  List<Map<String, Object?>> tariheAitDetaylar(DateTime tarih) {
    final gun = DateTime.utc(tarih.year, tarih.month, tarih.day);
    return List.unmodifiable(
      detaylar.where((satir) {
        final aralik = _gecerliTarihAraligi(satir);
        return aralik != null &&
            !gun.isBefore(aralik.$1) &&
            !gun.isAfter(aralik.$2);
      }),
    );
  }

  bool get tarihsizDetayVar =>
      detaylar.any((satir) => _gecerliTarihAraligi(satir) == null);

  static (DateTime, DateTime)? _gecerliTarihAraligi(
    Map<String, Object?> satir,
  ) {
    final baslangic = _isoTarihiOku(satir['BaslangicTarihi']);
    final bitis = _isoTarihiOku(satir['BitisTarihi']);
    if (baslangic == null || bitis == null || bitis.isBefore(baslangic)) {
      return null;
    }
    return (baslangic, bitis);
  }

  static DateTime? _isoTarihiOku(Object? deger) {
    final metin = (deger ?? '').toString().trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(metin)) return null;
    final tarih = DateTime.tryParse('${metin}T00:00:00Z');
    if (tarih == null || tarih.toIso8601String().substring(0, 10) != metin) {
      return null;
    }
    return tarih;
  }
}

class BireyselYillikPlanDetayAdayi {
  const BireyselYillikPlanDetayAdayi({
    required this.satirNo,
    required this.haftaNo,
    required this.ay,
    required this.tarihAraligi,
    required this.baslangicTarihi,
    required this.bitisTarihi,
    required this.saat,
    required this.konu,
    required this.unite,
    required this.kazanim,
    required this.kazanimAciklamasi,
    required this.ogrenmeBirimi,
    required this.icerikCercevesi,
    required this.ogrenmeCiktisi,
    required this.surecBilesenleri,
    required this.yontemTeknik,
    required this.aracGerec,
    required this.degerlendirme,
    this.etkinlik = '',
  });

  final int satirNo;
  final int haftaNo;
  final String ay;
  final String tarihAraligi;
  final String? baslangicTarihi;
  final String? bitisTarihi;
  final String saat;
  final String konu;
  final String unite;
  final String kazanim;
  final String kazanimAciklamasi;
  final String ogrenmeBirimi;
  final String icerikCercevesi;
  final String ogrenmeCiktisi;
  final String surecBilesenleri;
  final String yontemTeknik;
  final String aracGerec;
  final String degerlendirme;
  final String etkinlik;
}

class BireyselCalismaTakvimiAdayi {
  const BireyselCalismaTakvimiAdayi({
    required this.haftaNo,
    required this.ay,
    required this.tarihAraligi,
    required this.baslangicTarihi,
    required this.bitisTarihi,
    required this.kayitTuru,
    required this.calismaVarMi,
    required this.aciklama,
    required this.ozelGunAciklamasi,
  });

  final int? haftaNo;
  final String ay;
  final String tarihAraligi;
  final String? baslangicTarihi;
  final String? bitisTarihi;
  final String kayitTuru;
  final bool calismaVarMi;
  final String aciklama;
  final String ozelGunAciklamasi;
}

class BireyselYillikPlanOnIzleme {
  const BireyselYillikPlanOnIzleme({
    required this.dosyaAdi,
    required this.dosyaTuru,
    required this.baslikSatiri,
    required this.tespitEdilenDersAdi,
    required this.tespitEdilenSinifSeviyesi,
    required this.kayitlar,
    required this.calismaTakvimi,
    required this.hatalar,
  });

  final String dosyaAdi;
  final String dosyaTuru;
  final int baslikSatiri;
  final String tespitEdilenDersAdi;
  final int? tespitEdilenSinifSeviyesi;
  final List<BireyselYillikPlanDetayAdayi> kayitlar;
  final List<BireyselCalismaTakvimiAdayi> calismaTakvimi;
  final List<String> hatalar;

  bool get basarili =>
      hatalar.isEmpty &&
      kayitlar.isNotEmpty &&
      calismaTakvimi.isNotEmpty;
}

class _OkunanDokuman {
  const _OkunanDokuman({
    required this.satirlar,
    required this.baslikMetinleri,
  });

  final List<List<dynamic>> satirlar;
  final List<String> baslikMetinleri;
}

class _BaslikBilgisi {
  const _BaslikBilgisi({
    required this.dersAdi,
    required this.sinifSeviyesi,
  });

  final String dersAdi;
  final int? sinifSeviyesi;
}

class BireyselYillikPlanService {
  BireyselYillikPlanService._();

  static String egitimOgretimYiliniNormalizeEt(String deger) =>
      _egitimOgretimYiliniNormalizeEt(deger);

  /// Mevcut planı okur; import, takvim veya plan kaydı oluşturmaz.
  static Future<BireyselYillikPlanIcerigi> icerigiGetir({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    required int dersId,
    required int sinifSeviyesi,
  }) async {
    if (ogretmenProfilId <= 0 || dersId <= 0 || sinifSeviyesi <= 0) {
      throw ArgumentError('Geçerli öğretmen, ders ve sınıf seviyesi seçin.');
    }
    final yil = _egitimOgretimYiliniNormalizeEt(egitimOgretimYili);
    if (yil.isEmpty) throw ArgumentError('Eğitim öğretim yılı boş bırakılamaz.');
    if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError('Yıllık plan kartı yalnız bireysel modda kullanılabilir.');
    }

    try {
      final db = await LocalDatabase.instance.database;
      final profiller = await db.query(
        'OgretmenProfil',
        columns: ['OgretmenProfilId', 'EgitimOgretimYili'],
        where: 'Aktif = 1',
        orderBy: 'OgretmenProfilId DESC',
        limit: 1,
      );
      if (profiller.isEmpty ||
          profiller.single['OgretmenProfilId'] != ogretmenProfilId ||
          _egitimOgretimYiliniNormalizeEt(
                profiller.single['EgitimOgretimYili'].toString(),
              ) !=
              yil) {
        throw StateError('Öğretmen veya eğitim yılı değişti. Ekranı yenileyin.');
      }

      // Tarihsel program dersleri de aynı öğretmenin kapsamındadır.
      final dersKapsami = await db.rawQuery('''
        SELECT DISTINCT dp.EgitimOgretimYili
        FROM DersProgrami dp
        LEFT JOIN DersProgramiSurum ps ON ps.ProgramSurumId = dp.ProgramSurumId
        INNER JOIN Ders d ON d.DersId = dp.DersId
        INNER JOIN SinifSube s ON s.SinifSubeId = dp.SinifSubeId
        WHERE dp.OgretmenProfilId = ? AND dp.DersId = ?
          AND s.SinifSeviyesi = ? AND dp.Aktif = 1
          AND d.Aktif = 1 AND s.Aktif = 1
          AND (dp.ProgramSurumId IS NULL OR ps.Aktif = 1)
      ''', [ogretmenProfilId, dersId, sinifSeviyesi]);
      if (!dersKapsami.any(
        (satir) =>
            _egitimOgretimYiliniNormalizeEt(
              satir['EgitimOgretimYili'].toString(),
            ) ==
            yil,
      )) {
        throw StateError('Seçilen ders ve sınıf öğretmenin programında bulunamadı.');
      }

      final planlar = await db.query(
        'YillikPlan',
        columns: ['YillikPlanId', 'EgitimOgretimYili'],
        where: 'OgretmenProfilId = ? AND DersId = ? '
            'AND SinifSeviyesi = ? AND Aktif = 1',
        whereArgs: [ogretmenProfilId, dersId, sinifSeviyesi],
        orderBy: 'YillikPlanId DESC',
      );
      final uygunPlanlar = planlar.where(
        (satir) =>
            _egitimOgretimYiliniNormalizeEt(
              satir['EgitimOgretimYili'].toString(),
            ) ==
            yil,
      );
      if (uygunPlanlar.isEmpty) {
        return BireyselYillikPlanIcerigi(yillikPlanId: null, detaylar: const []);
      }
      final planId = uygunPlanlar.first['YillikPlanId'] as int;
      final detaylar = await db.query(
        'YillikPlanDetay',
        where: 'YillikPlanId = ? AND Aktif = 1',
        whereArgs: [planId],
        orderBy: 'COALESCE(HaftaNo, 9999), BaslangicTarihi, YillikPlanDetayId',
      );
      return BireyselYillikPlanIcerigi(yillikPlanId: planId, detaylar: detaylar);
    } catch (e) {
      throw Exception(
        'Bireysel yıllık plan içeriği okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  /// Ortak import için Word tablosunu hafta birleştirmeden döndürür.
  static List<List<String>> hamWordTablosu(Uint8List bytes, String uzanti) {
    if (bytes.isEmpty || bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('Plan dosyası boş veya 50 MB sınırından büyük.');
    }
    final dokuman = switch (uzanti) {
      'doc' => _docOku(bytes),
      'docx' => _docxOku(bytes),
      _ => throw const FormatException('Word dosyası seçin.'),
    };
    return dokuman.satirlar.map((r) => r.map((v) => (v ?? '').toString().trim()).toList()).toList();
  }

  /// Ortak kolon eşleştirmesini mevcut plan/takvim kurallarıyla işler.
  static BireyselYillikPlanOnIzleme eslenmisSatirlariOku(
    List<Map<String, String>> rows, {required String egitimOgretimYili}) {
    const columns = <String, String>{
      'hafta': 'Hafta', 'ay': 'Ay', 'tarih': 'Tarih', 'saat': 'Saat',
      'konu': 'Konu', 'unite': 'Ünite', 'kazanim': 'Kazanım',
      'kazanimAciklamasi': 'Kazanım Açıklaması', 'ogrenmeBirimi': 'Öğrenme Birimi',
      'icerikCercevesi': 'İçerik Çerçevesi', 'ogrenmeCiktisi': 'Öğrenme Çıktısı',
      'surecBilesenleri': 'Süreç Bileşenleri', 'yontemTeknik': 'Yöntem Teknik',
      'aracGerec': 'Araç Gereç', 'degerlendirme': 'Değerlendirme', 'etkinlik': 'Belirli Gün ve Haftalar',
    };
    final table = <List<dynamic>>[
      columns.values.toList(),
      for (final row in rows) [for (final key in columns.keys)
        key == 'hafta' && int.tryParse(row[key] ?? '') != null
          ? '${row[key]}. Hafta' : row[key] ?? ''],
    ];
    return _satirlariAyristir(dokuman: _OkunanDokuman(satirlar: table, baslikMetinleri: const []),
      dosyaAdi: '', dosyaTuru: 'EŞLEŞTİRİLMİŞ', egitimOgretimYili: egitimOgretimYili,
      baslikBilgisi: const _BaslikBilgisi(dersAdi: '', sinifSeviyesi: null));
  }

  static Future<BireyselYillikPlanOnIzleme> onIzlemeHazirla({
    required Uint8List dosyaBytes,
    required String dosyaAdi,
    required String dosyaUzantisi,
    required String egitimOgretimYili,
    int? konuKolonu,
  }) async {
    final uzanti = dosyaUzantisi.trim().toLowerCase();

    if (dosyaBytes.isEmpty) {
      throw Exception(
        'Bireysel yıllık plan ön izlemesi hazırlanamadı. '
        'Seçilen dosya boş.',
      );
    }

    if (uzanti != 'xls' &&
        uzanti != 'xlsx' &&
        uzanti != 'doc' &&
        uzanti != 'docx') {
      throw Exception(
        'Bireysel yıllık plan ön izlemesi hazırlanamadı. '
        'Yalnız XLS, XLSX, DOC ve DOCX dosyaları destekleniyor.',
      );
    }

    try {
      late final _OkunanDokuman dokuman;

      switch (uzanti) {
        case 'xls':
          dokuman = _xlsOku(dosyaBytes);
          break;
        case 'xlsx':
          dokuman = _xlsxOku(dosyaBytes);
          break;
        case 'doc':
          dokuman = _docOku(dosyaBytes);
          break;
        case 'docx':
          dokuman = _docxOku(dosyaBytes);
          break;
        default:
          throw Exception('Desteklenmeyen dosya türü: $uzanti');
      }

      final baslikBilgisi = _baslikBilgisiBul(
        dokuman.baslikMetinleri,
      );

      return _satirlariAyristir(
        dokuman: dokuman,
        dosyaAdi: dosyaAdi,
        dosyaTuru: uzanti.toUpperCase(),
        egitimOgretimYili: egitimOgretimYili,
        baslikBilgisi: baslikBilgisi,
        konuKolonu: konuKolonu,
      );
    } catch (e) {
      throw Exception(
        'Bireysel yıllık plan dosyası okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<int> kaydet({
    required int dersId,
    required int sinifSeviyesi,
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    required BireyselYillikPlanOnIzleme onIzleme,
    bool mevcutKayitlariKoru = false,
  }) async {
    if (dersId <= 0) {
      throw Exception('Yıllık plan için geçerli bir ders seçilmedi.');
    }

    if (sinifSeviyesi <= 0) {
      throw Exception(
        'Yıllık plan için geçerli bir sınıf seviyesi seçilmedi.',
      );
    }

    if (ogretmenProfilId <= 0) {
      throw Exception('Geçerli öğretmen profil kimliği bulunamadı.');
    }

    final yil = _egitimOgretimYiliniNormalizeEt(
      egitimOgretimYili,
    );

    if (yil.isEmpty) {
      throw Exception('Eğitim öğretim yılı boş bırakılamaz.');
    }

    if (!onIzleme.basarili) {
      throw Exception(
        'Yıllık plan kaydedilemedi. Ön izlemede hata var veya '
        'kaydedilecek yıllık plan/çalışma takvimi kaydı bulunamadı.',
      );
    }

    if (mevcutKayitlariKoru && await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
      throw StateError('Yıllık plan importu yalnız bireysel modda kullanılabilir.');
    }

    try {
      final db = await LocalDatabase.instance.database;
      final simdi = DateTime.now().toIso8601String();

      return await db.transaction<int>((txn) async {
        if (mevcutKayitlariKoru) {
          final profil = await txn.query('OgretmenProfil', where: 'Aktif = 1',
            orderBy: 'OgretmenProfilId DESC', limit: 1);
          if (profil.isEmpty || profil.single['OgretmenProfilId'] != ogretmenProfilId ||
              _egitimOgretimYiliniNormalizeEt(profil.single['EgitimOgretimYili'].toString()) != yil) {
            throw StateError('Öğretmen veya eğitim yılı değişti. Ön izlemeyi yenileyin.');
          }
          final dersKapsami = await txn.rawQuery('''
            SELECT dp.DersId FROM GecerliDersProgrami dp
            INNER JOIN SinifSube s ON s.SinifSubeId = dp.SinifSubeId
            WHERE dp.OgretmenProfilId = ? AND dp.EgitimOgretimYili = ?
              AND dp.DersId = ? AND s.SinifSeviyesi = ? AND dp.Aktif = 1 AND s.Aktif = 1
            LIMIT 1
          ''', [ogretmenProfilId, profil.single['EgitimOgretimYili'], dersId, sinifSeviyesi]);
          if (dersKapsami.isEmpty) throw StateError('Ders programındaki ders/sınıf kapsamı değişti. Ön izlemeyi yenileyin.');
        }
        await _profilVeDersiDogrula(
          txn: txn,
          ogretmenProfilId: ogretmenProfilId,
          dersId: dersId,
        );

        final yillikPlanId = await _yillikPlanBulVeyaOlustur(
          txn: txn,
          dersId: dersId,
          sinifSeviyesi: sinifSeviyesi,
          ogretmenProfilId: ogretmenProfilId,
          egitimOgretimYili: yil,
          dosyaAdi: onIzleme.dosyaAdi,
          simdi: simdi,
        );

        if (!mevcutKayitlariKoru) {
          await txn.delete(
          'YillikPlanDetay',
          where: 'YillikPlanId = ?',
          whereArgs: [yillikPlanId],
        );
        }

        var eklenen = 0;

        for (final kayit in onIzleme.kayitlar) {
          if (mevcutKayitlariKoru) {
            // Önizleme haftalık birleşik kayıt üretir; sadece seçili haftayı yenile.
            await txn.delete('YillikPlanDetay',
              where: 'YillikPlanId = ? AND HaftaNo = ? AND COALESCE(TarihAraligi, \'\') = ?',
              whereArgs: [yillikPlanId, kayit.haftaNo, kayit.tarihAraligi]);
          }
          await txn.insert(
            'YillikPlanDetay',
            {
              'YillikPlanId': yillikPlanId,
              'HaftaNo': kayit.haftaNo <= 0 ? null : kayit.haftaNo,
              'Ay': _nullIfEmpty(kayit.ay),
              'TarihAraligi': _nullIfEmpty(kayit.tarihAraligi),
              'BaslangicTarihi': kayit.baslangicTarihi,
              'BitisTarihi': kayit.bitisTarihi,
              'Saat': _nullIfEmpty(kayit.saat),
              'Konu': _nullIfEmpty(kayit.konu),
              'Unite': _nullIfEmpty(kayit.unite),
              'Kazanim': _nullIfEmpty(kayit.kazanim),
              'KazanimAciklamasi':
                  _nullIfEmpty(kayit.kazanimAciklamasi),
              'OgrenmeBirimi': _nullIfEmpty(kayit.ogrenmeBirimi),
              'IcerikCercevesi':
                  _nullIfEmpty(kayit.icerikCercevesi),
              'OgrenmeCiktisi':
                  _nullIfEmpty(kayit.ogrenmeCiktisi),
              'SurecBilesenleri':
                  _nullIfEmpty(kayit.surecBilesenleri),
              'YontemTeknik': _nullIfEmpty(kayit.yontemTeknik),
              'AracGerec': _nullIfEmpty(kayit.aracGerec),
              'Degerlendirme':
                  _nullIfEmpty(kayit.degerlendirme),
              'Aktif': 1,
              'OlusturmaTarihi': simdi,
              'GuncellemeTarihi': null,
            },
          );

          eklenen++;
        }

        await txn.update(
          'YillikPlan',
          {
            'Aktif': 1,
            'Aciklama': onIzleme.dosyaAdi.trim().isEmpty
                ? null
                : 'Import dosyası: ${onIzleme.dosyaAdi.trim()}',
            'GuncellemeTarihi': simdi,
          },
          where: 'YillikPlanId = ?',
          whereArgs: [yillikPlanId],
        );

        await _calismaTakviminiKaydet(
          txn: txn,
          ogretmenProfilId: ogretmenProfilId,
          egitimOgretimYili: yil,
          dosyaAdi: onIzleme.dosyaAdi,
          kayitlar: onIzleme.calismaTakvimi,
          simdi: simdi,
          mevcutKayitlariKoru: mevcutKayitlariKoru,
        );

        // Günlük plan takvimi başka bir ders importuyla değişmemelidir.
        // Ortak takvim akışı korunur; bu kaynağın kendi anlık görüntüsü de tutulur.
        final okullar = await txn.query('OkulProfil', where: 'Id = 1 AND AktifMi = 1');
        if (okullar.length == 1) {
          final key = 'yillikPlan.takvim.v1.${jsonEncode([
            okullar.single['OkulId'], ogretmenProfilId, yil, dersId, sinifSeviyesi, yillikPlanId])}';
          final once = await txn.query('UygulamaAyarlari', where: 'Anahtar = ?', whereArgs: [key]);
          final eski = once.isEmpty ? <String, dynamic>{} :
            jsonDecode(once.single['Deger'] as String) as Map<String, dynamic>;
          final yeni = [for (final k in onIzleme.calismaTakvimi) <String, Object?>{
            'HaftaNo': k.haftaNo, 'TarihAraligi': k.tarihAraligi,
            'BaslangicTarihi': k.baslangicTarihi, 'BitisTarihi': k.bitisTarihi,
            'KayitTuru': k.kayitTuru, 'CalismaVarMi': k.calismaVarMi ? 1 : 0,
            'Aciklama': k.aciklama, 'OzelGunAciklamasi': k.ozelGunAciklamasi,
          }];
          String anahtar(Map row) => jsonEncode([row['KayitTuru'], row['TarihAraligi'], row['HaftaNo']]);
          final yenilenen = yeni.map(anahtar).toSet();
          final veri = jsonEncode({
            'surum': (eski['surum'] as int? ?? 0) + 1,
            'dosyaAdi': onIzleme.dosyaAdi, 'kayitTarihi': simdi,
            'kayitlar': [
              if (mevcutKayitlariKoru) for (final row in eski['kayitlar'] as List? ?? const [])
                if (!yenilenen.contains(anahtar(row as Map))) row,
              ...yeni,
            ],
          });
          if (once.isEmpty) {
            await txn.insert('UygulamaAyarlari', {'Anahtar': key, 'Deger': veri, 'GuncellemeTarihi': simdi});
          } else {
            await txn.update('UygulamaAyarlari', {'Deger': veri, 'GuncellemeTarihi': simdi},
              where: 'Anahtar = ?', whereArgs: [key]);
          }
        }
        return eklenen;
      });
    } catch (e) {
      throw Exception(
        'Bireysel yıllık plan ve çalışma takvimi SQLite '
        'veritabanına kaydedilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static _OkunanDokuman _xlsxOku(Uint8List dosyaBytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(dosyaBytes);

    if (decoder.tables.isEmpty) {
      throw Exception(
        'Excel dosyasında çalışma sayfası bulunamadı.',
      );
    }

    final tablo = decoder.tables.values.first;

    final satirlar = tablo.rows
        .map<List<dynamic>>(
          (satir) => satir.map<dynamic>((deger) => deger).toList(),
        )
        .toList();

    final baslikMetinleri = satirlar
        .take(15)
        .expand((satir) => satir)
        .where((e) => e != null)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return _OkunanDokuman(
      satirlar: satirlar,
      baslikMetinleri: baslikMetinleri,
    );
  }

  static _OkunanDokuman _xlsOku(Uint8List dosyaBytes) {
    final reader = XlsReader.fromBytes(dosyaBytes);
    reader.open();

    if (reader.sheetCount <= 0) {
      throw Exception(
        'Excel dosyasında çalışma sayfası bulunamadı.',
      );
    }

    final sayfa = reader.sheet(0);
    final satirlar = <List<dynamic>>[];

    for (int satir = sayfa.firstRow; satir < sayfa.lastRow; satir++) {
      final degerler = <dynamic>[];

      for (int sutun = sayfa.firstCol; sutun < sayfa.lastCol; sutun++) {
        degerler.add(sayfa.cell(satir, sutun));
      }

      satirlar.add(degerler);
    }

    final baslikMetinleri = satirlar
        .take(15)
        .expand((satir) => satir)
        .where((e) => e != null)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return _OkunanDokuman(
      satirlar: satirlar,
      baslikMetinleri: baslikMetinleri,
    );
  }

  static _OkunanDokuman _docOku(Uint8List dosyaBytes) {
    final document = OfficeDocument.fromBytes(
      dosyaBytes,
      OfficeFormat.doc,
    );

    try {
      final markdown = document.toMarkdown();

      if (markdown.trim().isEmpty) {
        throw Exception(
          'DOC dosyasından okunabilir metin çıkarılamadı.',
        );
      }

      return _markdownDokumaniOku(markdown);
    } finally {
      document.dispose();
    }
  }

  static _OkunanDokuman _markdownDokumaniOku(String markdown) {
    final satirMetinleri = markdown
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    final baslikMetinleri = satirMetinleri
        .map(_markdownMetniniTemizle)
        .where((e) => e.isNotEmpty)
        .take(30)
        .toList(growable: false);

    final tablolar = <List<List<dynamic>>>[];
    var aktifTablo = <List<dynamic>>[];

    void aktifTabloyuKapat() {
      if (aktifTablo.isNotEmpty) {
        tablolar.add(aktifTablo);
        aktifTablo = <List<dynamic>>[];
      }
    }

    for (final satir in satirMetinleri) {
      final temizSatir = satir.trim();

      if (!_markdownTabloSatiriMi(temizSatir)) {
        aktifTabloyuKapat();
        continue;
      }

      final hucreler = _markdownTabloHucreleriniOku(temizSatir);

      if (hucreler.isEmpty) {
        continue;
      }

      if (_markdownAyiriciSatiriMi(hucreler)) {
        continue;
      }

      aktifTablo.add(hucreler);
    }

    aktifTabloyuKapat();

    for (final tablo in tablolar) {
      if (_baslikSatiriBul(tablo) >= 0) {
        return _OkunanDokuman(
          satirlar: tablo,
          baslikMetinleri: baslikMetinleri,
        );
      }
    }

    throw Exception(
      'DOC dosyasında HAFTA ve yıllık plan içerik başlıklarını '
      'içeren uygun tablo bulunamadı.',
    );
  }

  static bool _markdownTabloSatiriMi(String satir) {
    if (satir.isEmpty || !satir.contains('|')) {
      return false;
    }

    final hucreler = _markdownTabloHucreleriniOku(satir);
    return hucreler.length >= 2;
  }

  static List<dynamic> _markdownTabloHucreleriniOku(String satir) {
    var temiz = satir.trim();

    if (temiz.startsWith('|')) {
      temiz = temiz.substring(1);
    }

    if (temiz.endsWith('|')) {
      temiz = temiz.substring(0, temiz.length - 1);
    }

    final hucreler = <String>[];
    final tampon = StringBuffer();
    var kacisli = false;

    for (int i = 0; i < temiz.length; i++) {
      final karakter = temiz[i];

      if (kacisli) {
        tampon.write(karakter);
        kacisli = false;
        continue;
      }

      if (karakter == r'\') {
        kacisli = true;
        continue;
      }

      if (karakter == '|') {
        hucreler.add(_markdownMetniniTemizle(tampon.toString()));
        tampon.clear();
        continue;
      }

      tampon.write(karakter);
    }

    if (kacisli) {
      tampon.write(r'\');
    }

    hucreler.add(_markdownMetniniTemizle(tampon.toString()));

    return hucreler.cast<dynamic>();
  }

  static bool _markdownAyiriciSatiriMi(List<dynamic> hucreler) {
    if (hucreler.isEmpty) {
      return false;
    }

    return hucreler.every((hucre) {
      final metin = hucre.toString().trim();
      return RegExp(r'^:?-{3,}:?$').hasMatch(metin);
    });
  }

  static String _markdownMetniniTemizle(String metin) {
    var temiz = metin
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]+\)'),
          (eslesme) => eslesme.group(1) ?? '',
        )
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*'), '')
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll('`', '')
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (temiz.startsWith('*') && temiz.endsWith('*') && temiz.length > 1) {
      temiz = temiz.substring(1, temiz.length - 1).trim();
    }

    return temiz;
  }

  static _OkunanDokuman _docxOku(Uint8List dosyaBytes) {
    final archive = ZipDecoder().decodeBytes(dosyaBytes);

    ArchiveFile? documentFile;

    for (final file in archive.files) {
      if (file.name == 'word/document.xml') {
        documentFile = file;
        break;
      }
    }

    if (documentFile == null) {
      throw Exception(
        'Word dosyasının document.xml içeriği bulunamadı.',
      );
    }

    final content = documentFile.content;

    if (content is! List<int>) {
      throw Exception(
        'Word document.xml içeriği okunamadı.',
      );
    }

    final xmlMetni = utf8.decode(content);
    final document = XmlDocument.parse(xmlMetni);

    final baslikMetinleri = <String>[];

    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'p') {
        continue;
      }

      final metin = _xmlMetniniOku(element);

      if (metin.isNotEmpty) {
        baslikMetinleri.add(metin);
      }

      if (baslikMetinleri.length >= 25) {
        break;
      }
    }

    final tablolar = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'tbl')
        .toList();

    if (tablolar.isEmpty) {
      throw Exception(
        'Word dosyasında yıllık plan tablosu bulunamadı.',
      );
    }

    List<List<dynamic>>? uygunTablo;

    for (final tablo in tablolar) {
      final satirlar = _docxTabloSatirlariniOku(tablo);

      if (_baslikSatiriBul(satirlar) >= 0) {
        uygunTablo = satirlar;
        break;
      }
    }

    if (uygunTablo == null) {
      throw Exception(
        'Word dosyasında HAFTA ve yıllık plan içerik başlıklarını '
        'içeren uygun tablo bulunamadı.',
      );
    }

    return _OkunanDokuman(
      satirlar: uygunTablo,
      baslikMetinleri: baslikMetinleri,
    );
  }

  static List<List<dynamic>> _docxTabloSatirlariniOku(
    XmlElement tablo,
  ) {
    final sonuc = <List<dynamic>>[];
    var birlesimler = <int, (int, String)>{};

    XmlElement? altEleman(XmlElement? eleman, String ad) {
      if (eleman == null) return null;
      for (final alt in eleman.childElements) {
        if (alt.name.local == ad) return alt;
      }
      return null;
    }

    String? deger(XmlElement? eleman) {
      if (eleman == null) return null;
      for (final ozellik in eleman.attributes) {
        if (ozellik.name.local == 'val') return ozellik.value;
      }
      return null;
    }

    final satirlar = tablo.childElements
        .where((e) => e.name.local == 'tr');

    for (final satir in satirlar) {
      final oncekiBosluk = int.tryParse(
            deger(altEleman(altEleman(satir, 'trPr'), 'gridBefore')) ?? '',
          ) ?? 0;
      final hucreler = List<dynamic>.filled(oncekiBosluk, '', growable: true);
      final yeniBirlesimler = <int, (int, String)>{};
      var sutun = oncekiBosluk;

      for (final hucre in satir.childElements
          .where((e) => e.name.local == 'tc')) {
        final ozellikler = altEleman(hucre, 'tcPr');
        final genislik = int.tryParse(
              deger(altEleman(ozellikler, 'gridSpan')) ?? '',
            ) ?? 1;
        if (genislik < 1) {
          throw Exception('Word tablosunda geçersiz birleşik hücre genişliği.');
        }
        final birlesim = altEleman(ozellikler, 'vMerge');
        var metin = _xmlMetniniOku(hucre);

        if (birlesim != null) {
          if (deger(birlesim) != 'restart') {
            final onceki = birlesimler[sutun];
            if (onceki == null || onceki.$1 != genislik) {
              throw Exception(
                'Word tablosunda birleşik hücrenin başlangıcı bulunamadı. '
                'Satır: ${sonuc.length + 1}, sütun: ${sutun + 1}',
              );
            }
            metin = onceki.$2;
          }
          yeniBirlesimler[sutun] = (genislik, metin);
        }

        hucreler.addAll(List<String>.filled(genislik, metin));
        sutun += genislik;
      }

      birlesimler = yeniBirlesimler;
      sonuc.add(hucreler);
    }

    return sonuc;
  }

  static String _xmlMetniniOku(XmlElement element) {
    final metin = StringBuffer();

    void oku(XmlElement eleman) {
      final ad = eleman.name.local;
      if (ad == 't') {
        metin.write(eleman.innerText);
        return;
      }
      if (ad == 'br' || ad == 'cr' || ad == 'tab') {
        metin.write(ad == 'tab' ? ' ' : '\n');
        return;
      }
      for (final alt in eleman.childElements) {
        oku(alt);
      }
      if (ad == 'p') metin.write('\n');
    }

    oku(element);
    return metin.toString()
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[^\S\n]+'), ' ')
        .trim();
  }

  static BireyselYillikPlanOnIzleme _satirlariAyristir({
    required _OkunanDokuman dokuman,
    required String dosyaAdi,
    required String dosyaTuru,
    required String egitimOgretimYili,
    required _BaslikBilgisi baslikBilgisi,
    int? konuKolonu,
  }) {
    final satirlar = dokuman.satirlar;
    final hatalar = <String>[];
    final kayitlar = <BireyselYillikPlanDetayAdayi>[];
    final takvim = <BireyselCalismaTakvimiAdayi>[];

    final baslikSatiri = _baslikSatiriBul(satirlar);

    if (baslikSatiri < 0) {
      return BireyselYillikPlanOnIzleme(
        dosyaAdi: dosyaAdi,
        dosyaTuru: dosyaTuru,
        baslikSatiri: -1,
        tespitEdilenDersAdi: baslikBilgisi.dersAdi,
        tespitEdilenSinifSeviyesi:
            baslikBilgisi.sinifSeviyesi,
        kayitlar: const <BireyselYillikPlanDetayAdayi>[],
        calismaTakvimi:
            const <BireyselCalismaTakvimiAdayi>[],
        hatalar: const <String>[
          'Yıllık plan başlık satırı bulunamadı. Dosyada HAFTA '
              've içerik/kazanım başlıkları bulunmalıdır.',
        ],
      );
    }

    final kolonlar = _kolonlariBul(
      satirlar: satirlar,
      baslikSatiri: baslikSatiri,
    );

    if (konuKolonu != null) {
      final basliklar = satirlar[baslikSatiri];
      if (konuKolonu < 0 || konuKolonu >= basliklar.length) {
        hatalar.add('Seçilen konu sütunu geçersiz.');
      } else {
        kolonlar['konu'] = konuKolonu;
      }
    }

    if (kolonlar['hafta'] == null) {
      hatalar.add('Zorunlu HAFTA sütunu bulunamadı.');
    }

    final icerikVar =
        kolonlar['icerikCercevesi'] != null ||
        kolonlar['konu'] != null ||
        kolonlar['ogrenmeBirimi'] != null;

    final ciktiVar =
        kolonlar['ogrenmeCiktisi'] != null ||
        kolonlar['kazanim'] != null;

    if (!icerikVar && !ciktiVar) {
      hatalar.add(
        'Yıllık plan içerik alanları bulunamadı. '
        'KONU/İÇERİK ÇERÇEVESİ, ÖĞRENME BİRİMİ, '
        'KAZANIM veya ÖĞRENME ÇIKTISI başlıklarından '
        'en az biri bulunmalıdır.',
      );
    }

    if (hatalar.isNotEmpty) {
      return BireyselYillikPlanOnIzleme(
        dosyaAdi: dosyaAdi,
        dosyaTuru: dosyaTuru,
        baslikSatiri: baslikSatiri + 1,
        tespitEdilenDersAdi: baslikBilgisi.dersAdi,
        tespitEdilenSinifSeviyesi:
            baslikBilgisi.sinifSeviyesi,
        kayitlar: const <BireyselYillikPlanDetayAdayi>[],
        calismaTakvimi:
            const <BireyselCalismaTakvimiAdayi>[],
        hatalar: List<String>.unmodifiable(hatalar),
      );
    }

    var sonAy = '';
    var sonTarih = '';
    var sonSaat = '';
    var sonHafta = 0;
    var otomatikHafta = 0;
    var sonHaftaAnahtari = '';

    var sonOgrenmeBirimi = '';
    var sonIcerikCercevesi = '';
    var sonOgrenmeCiktisi = '';
    var sonKonu = '';
    var sonUnite = '';
    var sonKazanim = '';
    var sonYontemTeknik = '';
    var sonAracGerec = '';

    for (int i = baslikSatiri + 1; i < satirlar.length; i++) {
      final tumSatirMetni = _satirMetni(satirlar[i]);

      if (tumSatirMetni.isEmpty) {
        continue;
      }

      final tatilKaydi = _tatilSatiriOku(
        tumSatirMetni,
        egitimOgretimYili,
      );

      if (tatilKaydi != null && _satirTatilSatiriMi(satirlar[i])) {
        takvim.add(tatilKaydi);
        continue;
      }

      final haftaCol = kolonlar['hafta']!;
      var haftaText = _hucre(satirlar, i, haftaCol);

      var ay = _kolonDegeri(
        satirlar,
        i,
        kolonlar['ay'],
      );
      var tarih = _kolonDegeri(
        satirlar,
        i,
        kolonlar['tarih'],
      );
      var saat = _kolonDegeri(
        satirlar,
        i,
        kolonlar['saat'],
      );

      var ogrenmeBirimi = _kolonDegeri(
        satirlar,
        i,
        kolonlar['ogrenmeBirimi'],
      );
      var icerikCercevesi = _kolonDegeri(
        satirlar,
        i,
        kolonlar['icerikCercevesi'],
      );
      var ogrenmeCiktisi = _kolonDegeri(
        satirlar,
        i,
        kolonlar['ogrenmeCiktisi'],
      );
      var surecBilesenleri = _kolonDegeri(
        satirlar,
        i,
        kolonlar['surecBilesenleri'],
      );
      var yontemTeknik = _kolonDegeri(
        satirlar,
        i,
        kolonlar['yontemTeknik'],
      );
      var aracGerec = _kolonDegeri(
        satirlar,
        i,
        kolonlar['aracGerec'],
      );
      var degerlendirme = _kolonDegeri(
        satirlar,
        i,
        kolonlar['degerlendirme'],
      );

      final etkinlik = _kolonDegeri(satirlar, i, kolonlar['etkinlik']);

      var konu = _kolonDegeri(
        satirlar,
        i,
        kolonlar['konu'],
      );
      var unite = _kolonDegeri(
        satirlar,
        i,
        kolonlar['unite'],
      );
      var kazanim = _kolonDegeri(
        satirlar,
        i,
        kolonlar['kazanim'],
      );
      var kazanimAciklamasi = _kolonDegeri(
        satirlar,
        i,
        kolonlar['kazanimAciklamasi'],
      );

      if (tarih.isEmpty && _tarihAraligiOku(haftaText).isNotEmpty) {
        tarih = _tarihAraligiOku(haftaText);
      }

      if (tarih.isNotEmpty) {
        final temizTarih = _tarihAraligiOku(tarih);

        if (temizTarih.isNotEmpty) {
          tarih = temizTarih;
        }
      }

      final okunanHafta = _haftaNoOku(haftaText);

      var yeniHafta = false;

      if (okunanHafta > 0) {
        if (okunanHafta != sonHafta) {
          sonHafta = okunanHafta;
          otomatikHafta =
              otomatikHafta < sonHafta ? sonHafta : otomatikHafta;
          yeniHafta = true;
        }
      } else if (tarih.isNotEmpty) {
        final anahtar = _normalize(tarih);

        if (anahtar != sonHaftaAnahtari) {
          otomatikHafta++;
          sonHafta = otomatikHafta;
          sonHaftaAnahtari = anahtar;
          yeniHafta = true;
        }
      }

      if (ay.isNotEmpty) {
        sonAy = ay;
      } else if (tarih.isNotEmpty) {
        final tarihtenAy = _ilkAyAdi(tarih);

        if (tarihtenAy.isNotEmpty) {
          ay = tarihtenAy;
          sonAy = ay;
        } else {
          ay = sonAy;
        }
      } else {
        ay = sonAy;
      }

      if (tarih.isNotEmpty) {
        sonTarih = tarih;
      } else {
        tarih = sonTarih;
      }

      if (saat.isNotEmpty) {
        sonSaat = saat;
      } else {
        saat = sonSaat;
      }

      if (yeniHafta) {
        sonOgrenmeBirimi = '';
        sonIcerikCercevesi = '';
        sonOgrenmeCiktisi = '';
        sonKonu = '';
        sonUnite = '';
        sonKazanim = '';
      }

      if (ogrenmeBirimi.isNotEmpty) {
        sonOgrenmeBirimi = ogrenmeBirimi;
      } else {
        ogrenmeBirimi = sonOgrenmeBirimi;
      }

      if (icerikCercevesi.isNotEmpty) {
        sonIcerikCercevesi = icerikCercevesi;
      } else {
        icerikCercevesi = sonIcerikCercevesi;
      }

      if (ogrenmeCiktisi.isNotEmpty) {
        sonOgrenmeCiktisi = ogrenmeCiktisi;
      } else {
        ogrenmeCiktisi = sonOgrenmeCiktisi;
      }

      if (konu.isNotEmpty) {
        sonKonu = konu;
      } else {
        konu = sonKonu;
      }

      if (unite.isNotEmpty) {
        sonUnite = unite;
      } else {
        unite = sonUnite;
      }

      if (kazanim.isNotEmpty) {
        sonKazanim = kazanim;
      } else {
        kazanim = sonKazanim;
      }

      if (yontemTeknik.isNotEmpty) {
        sonYontemTeknik = yontemTeknik;
      } else {
        yontemTeknik = sonYontemTeknik;
      }

      if (aracGerec.isNotEmpty) {
        sonAracGerec = aracGerec;
      } else {
        aracGerec = sonAracGerec;
      }

      final bilgiVar = [
        ogrenmeBirimi,
        icerikCercevesi,
        ogrenmeCiktisi,
        surecBilesenleri,
        konu,
        unite,
        kazanim,
        kazanimAciklamasi,
      ].any((e) => e.trim().isNotEmpty);

      if (!bilgiVar) {
        continue;
      }

      if (sonHafta <= 0) {
        otomatikHafta++;
        sonHafta = otomatikHafta;
      }

      final tarihParse = _tarihAraligiParseEt(
        tarih,
        egitimOgretimYili,
      );

      final dogrudanKonu = konu.isNotEmpty
          ? konu
          : icerikCercevesi;

      final dogrudanUnite = unite.isNotEmpty
          ? unite
          : ogrenmeBirimi;

      final dogrudanKazanim = kazanim.isNotEmpty
          ? kazanim
          : ogrenmeCiktisi;

      // Tatil bazen tek birleşik hücre yerine bütün içerik sütunlarına yazılır.
      if (_normalize(konu).contains('tatil') && _normalize(kazanim).contains('tatil') &&
          konu.length < 100 && kazanim.length < 100) {
        takvim.add(BireyselCalismaTakvimiAdayi(haftaNo:sonHafta, ay:ay,
          tarihAraligi:tarih, baslangicTarihi:tarihParse.$1, bitisTarihi:tarihParse.$2,
          kayitTuru:'Tatil',calismaVarMi:false,aciklama:konu,ozelGunAciklamasi:etkinlik));
        continue;
      }
      kayitlar.add(
        BireyselYillikPlanDetayAdayi(
          satirNo: i + 1,
          haftaNo: sonHafta,
          ay: ay.trim(),
          tarihAraligi: tarih.trim(),
          baslangicTarihi: tarihParse.$1,
          bitisTarihi: tarihParse.$2,
          saat: saat.trim(),
          konu: dogrudanKonu.trim(),
          unite: dogrudanUnite.trim(),
          kazanim: dogrudanKazanim.trim(),
          kazanimAciklamasi: kazanimAciklamasi.trim(),
          ogrenmeBirimi: ogrenmeBirimi.trim(),
          icerikCercevesi: icerikCercevesi.trim(),
          ogrenmeCiktisi: ogrenmeCiktisi.trim(),
          surecBilesenleri: surecBilesenleri.trim(),
          yontemTeknik: yontemTeknik.trim(),
          aracGerec: aracGerec.trim(),
          degerlendirme: degerlendirme.trim(),
          etkinlik: etkinlik.trim(),
        ),
      );

      if (yeniHafta && tarih.isNotEmpty) {
        final zatenVar = takvim.any(
          (e) => e.haftaNo == sonHafta && e.kayitTuru == 'DersHaftasi',
        );

        if (!zatenVar) {
          takvim.add(
            BireyselCalismaTakvimiAdayi(
              haftaNo: sonHafta,
              ay: ay.trim(),
              tarihAraligi: tarih.trim(),
              baslangicTarihi: tarihParse.$1,
              bitisTarihi: tarihParse.$2,
              kayitTuru: 'DersHaftasi',
              calismaVarMi: true,
              aciklama: '$sonHafta. Hafta',
              ozelGunAciklamasi: etkinlik.trim(),
            ),
          );
        }
      } else if (tarih.isNotEmpty && etkinlik.isNotEmpty) {
        final index = takvim.indexWhere(
          (e) => e.haftaNo == sonHafta && e.kayitTuru == 'DersHaftasi',
        );

        if (index >= 0 && takvim[index].ozelGunAciklamasi.isEmpty) {
          final mevcut = takvim[index];

          takvim[index] = BireyselCalismaTakvimiAdayi(
            haftaNo: mevcut.haftaNo,
            ay: mevcut.ay,
            tarihAraligi: mevcut.tarihAraligi,
            baslangicTarihi: mevcut.baslangicTarihi,
            bitisTarihi: mevcut.bitisTarihi,
            kayitTuru: mevcut.kayitTuru,
            calismaVarMi: mevcut.calismaVarMi,
            aciklama: mevcut.aciklama,
            ozelGunAciklamasi: etkinlik.trim(),
          );
        }
      }
    }

    if (kayitlar.isEmpty) {
      hatalar.add(
        'Yıllık plan dosyasında kaydedilebilir ders planı '
        'satırı bulunamadı.',
      );
    }

    if (takvim.where((e) => e.kayitTuru == 'DersHaftasi').isEmpty) {
      hatalar.add(
        'Dosyadan çalışma takvimi için ders haftaları çıkarılamadı.',
      );
    }

    takvim.sort((a, b) {
      final aTarih = a.baslangicTarihi ?? '';
      final bTarih = b.baslangicTarihi ?? '';

      if (aTarih.isNotEmpty && bTarih.isNotEmpty) {
        return aTarih.compareTo(bTarih);
      }

      return (a.haftaNo ?? 999).compareTo(b.haftaNo ?? 999);
    });

    return BireyselYillikPlanOnIzleme(
      dosyaAdi: dosyaAdi,
      dosyaTuru: dosyaTuru,
      baslikSatiri: baslikSatiri + 1,
      tespitEdilenDersAdi: baslikBilgisi.dersAdi,
      tespitEdilenSinifSeviyesi:
          baslikBilgisi.sinifSeviyesi,
      kayitlar:
          List<BireyselYillikPlanDetayAdayi>.unmodifiable(
            _haftalikKayitlariBirlestir(kayitlar)),
      calismaTakvimi:
          List<BireyselCalismaTakvimiAdayi>.unmodifiable(takvim),
      hatalar: List<String>.unmodifiable(hatalar),
    );
  }

  static List<BireyselYillikPlanDetayAdayi> _haftalikKayitlariBirlestir(
    List<BireyselYillikPlanDetayAdayi> satirlar,
  ) {
    final sonuc = <BireyselYillikPlanDetayAdayi>[];
    String anahtar(BireyselYillikPlanDetayAdayi kayit) {
      if (kayit.baslangicTarihi != null && kayit.bitisTarihi != null) {
        return '${kayit.baslangicTarihi}/${kayit.bitisTarihi}';
      }
      if (kayit.tarihAraligi.isNotEmpty) {
        return _normalize(kayit.tarihAraligi);
      }
      return '${_normalize(kayit.ay)}/${kayit.haftaNo}';
    }

    String birlestir(String onceki, String yeni) {
      // Birleşik hücrelerden tekrar gelen içerik yalnızca bir kez tutulur.
      return <String>{
        ...onceki.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty),
        ...yeni.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty),
      }.join('\n');
    }

    for (final satir in satirlar) {
      if (sonuc.isEmpty || anahtar(sonuc.last) != anahtar(satir)) {
        sonuc.add(satir);
        continue;
      }
      final onceki = sonuc.last;
      sonuc[sonuc.length - 1] = BireyselYillikPlanDetayAdayi(
        satirNo: onceki.satirNo,
        haftaNo: onceki.haftaNo,
        ay: onceki.ay.isEmpty ? satir.ay : onceki.ay,
        tarihAraligi: onceki.tarihAraligi,
        baslangicTarihi: onceki.baslangicTarihi,
        bitisTarihi: onceki.bitisTarihi,
        // Haftalık ders saati alt konu satırları için tekrar toplanmaz.
        saat: birlestir(onceki.saat, satir.saat),
        konu: birlestir(onceki.konu, satir.konu),
        unite: birlestir(onceki.unite, satir.unite),
        kazanim: birlestir(onceki.kazanim, satir.kazanim),
        kazanimAciklamasi: birlestir(onceki.kazanimAciklamasi, satir.kazanimAciklamasi),
        ogrenmeBirimi: birlestir(onceki.ogrenmeBirimi, satir.ogrenmeBirimi),
        icerikCercevesi: birlestir(onceki.icerikCercevesi, satir.icerikCercevesi),
        ogrenmeCiktisi: birlestir(onceki.ogrenmeCiktisi, satir.ogrenmeCiktisi),
        surecBilesenleri: birlestir(onceki.surecBilesenleri, satir.surecBilesenleri),
        yontemTeknik: birlestir(onceki.yontemTeknik, satir.yontemTeknik),
        aracGerec: birlestir(onceki.aracGerec, satir.aracGerec),
        degerlendirme: birlestir(onceki.degerlendirme, satir.degerlendirme),
        etkinlik: birlestir(onceki.etkinlik, satir.etkinlik),
      );
    }
    return sonuc;
  }

  static Map<String, int?> _kolonlariBul({
    required List<List<dynamic>> satirlar,
    required int baslikSatiri,
  }) {
    return <String, int?>{
      'ay': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['ay'],
      ),
      'tarih': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['tarih', 'tarih araligi'],
      ),
      'hafta': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['hafta'],
      ),
      'saat': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['saat'],
      ),
      'ogrenmeBirimi': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['ogrenme birimi'],
      ),
      'icerikCercevesi': _kolonBul(
        satirlar,
        baslikSatiri,
        const [
          'icerik cercevesi',
          'konu icerik cercevesi',
        ],
      ),
      'ogrenmeCiktisi': _kolonBul(
        satirlar,
        baslikSatiri,
        const [
          'ogrenme ciktisi',
          'ogrenme ciktilari',
          'kazanim ogrenme ciktisi',
        ],
      ),
      'surecBilesenleri': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['surec bilesenleri'],
      ),
      'yontemTeknik': _kolonBul(
        satirlar,
        baslikSatiri,
        const [
          'yontem teknik',
          'ogretim teknikleri',
          'ogretim teknigi',
        ],
      ),
      'aracGerec': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['arac gerec'],
      ),
      'etkinlik': _kolonBul(satirlar, baslikSatiri, const ['belirli gun ve haftalar', 'etkinlik']),
      'degerlendirme': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['degerlendirme', 'aciklama'],
        yasakliTamEslesmeler: const ['kazanim aciklamasi', 'kazanim aciklama'],
      ),
      'konu': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['konu'],
        yasakliTamEslesmeler: const ['konu icerik cercevesi'],
      ),
      'unite': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['unite'],
      ),
      'kazanim': _kolonBul(
        satirlar,
        baslikSatiri,
        const ['kazanim'],
        yasakliTamEslesmeler:
            const ['kazanim ogrenme ciktisi'],
      ),
      'kazanimAciklamasi': _kolonBul(
        satirlar,
        baslikSatiri,
        const [
          'kazanim aciklama',
          'kazanim aciklamasi',
        ],
      ),
    };
  }

  static int _baslikSatiriBul(List<List<dynamic>> satirlar) {
    for (int i = 0; i < satirlar.length; i++) {
      final hucreler = satirlar[i]
          .map((e) => _normalize(e?.toString() ?? ''))
          .where((e) => e.isNotEmpty)
          .toList();

      final haftaVar = hucreler.any(
        (e) => e == 'hafta' || e.contains('hafta'),
      );

      final icerikVar = hucreler.any(
        (e) =>
            e.contains('icerik cercevesi') ||
            e.contains('ogrenme birimi') ||
            e.contains('konu') ||
            e.contains('kazanim') ||
            e.contains('ogrenme ciktisi') ||
            e.contains('ogrenme ciktilari'),
      );

      if (haftaVar && icerikVar) {
        return i;
      }
    }

    return -1;
  }

  static int? _kolonBul(
    List<List<dynamic>> satirlar,
    int baslikSatiri,
    List<String> adaylar, {
    List<String> yasakliTamEslesmeler = const <String>[],
  }) {
    if (baslikSatiri < 0 || baslikSatiri >= satirlar.length) {
      return null;
    }

    final satir = satirlar[baslikSatiri];
    final yasaklar = yasakliTamEslesmeler
        .map(_normalize)
        .toSet();

    for (int i = 0; i < satir.length; i++) {
      final hucre = _normalize(
        satir[i]?.toString() ?? '',
      );

      if (hucre.isEmpty || yasaklar.contains(hucre)) {
        continue;
      }

      for (final aday in adaylar) {
        final normalizeAday = _normalize(aday);

        if (hucre == normalizeAday ||
            hucre.contains(normalizeAday)) {
          return i;
        }
      }
    }

    return null;
  }

  static _BaslikBilgisi _baslikBilgisiBul(
    List<String> metinler,
  ) {
    final birlesik = metinler
        .take(20)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    int? sinifSeviyesi;

    final sinifEslesmesi = RegExp(
      r'\b(9|10|11|12)\s*\.?\s*SINIF\b',
      caseSensitive: false,
    ).firstMatch(birlesik);

    if (sinifEslesmesi != null) {
      sinifSeviyesi = int.tryParse(
        sinifEslesmesi.group(1) ?? '',
      );
    }

    String dersAdi = '';

    final desenler = <RegExp>[
      RegExp(
        r'(?:9|10|11|12)\s*\.?\s*SINIF\s+'
        r'(?:SEÇMELİ\s+)?(.+?)\s+YILLIK\s+(?:DERS\s+)?PLANI',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:9|10|11|12)\s*\.?\s*SINIF\s+'
        r'(?:SEÇMELİ\s+)?(.+?)\s+DERSİ\s+ÜNİTELENDİRİLMİŞ',
        caseSensitive: false,
      ),
    ];

    for (final desen in desenler) {
      final eslesme = desen.firstMatch(birlesik);

      if (eslesme == null) {
        continue;
      }

      dersAdi = (eslesme.group(1) ?? '')
          .replaceAll(RegExp(r'\s+DERSİ$', caseSensitive: false), '')
          .trim();

      if (dersAdi.isNotEmpty) {
        break;
      }
    }

    return _BaslikBilgisi(
      dersAdi: dersAdi,
      sinifSeviyesi: sinifSeviyesi,
    );
  }

  static BireyselCalismaTakvimiAdayi? _tatilSatiriOku(
    String metin,
    String egitimOgretimYili,
  ) {
    final normalizeMetin = _normalize(metin);

    if (!normalizeMetin.contains('tatil')) {
      return null;
    }

    String kayitTuru = 'Tatil';

    if (normalizeMetin.contains('ara tatil')) {
      kayitTuru = 'AraTatil';
    } else if (normalizeMetin.contains('yariyil') ||
        normalizeMetin.contains('subat tatili')) {
      kayitTuru = 'YariyilTatili';
    }

    var tarihAraligi = _tarihAraligiOku(metin);

    if (tarihAraligi.isEmpty) {
      final parantez = RegExp(r'\(([^)]+)\)').firstMatch(metin);

      if (parantez != null) {
        tarihAraligi = _tarihAraligiOku(
          parantez.group(1) ?? '',
        );
      }
    }

    final tarihParse = _tarihAraligiParseEt(
      tarihAraligi,
      egitimOgretimYili,
    );

    return BireyselCalismaTakvimiAdayi(
      haftaNo: null,
      ay: _ilkAyAdi(tarihAraligi),
      tarihAraligi: tarihAraligi,
      baslangicTarihi: tarihParse.$1,
      bitisTarihi: tarihParse.$2,
      kayitTuru: kayitTuru,
      calismaVarMi: false,
      aciklama: metin.trim(),
      ozelGunAciklamasi: '',
    );
  }

  static bool _satirTatilSatiriMi(List<dynamic> satir) {
    final doluHucreler = satir
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .map((e) => e.toString().trim())
        .toList();

    if (doluHucreler.isEmpty) {
      return false;
    }

    final ilk = _normalize(doluHucreler.first);

    return ilk.contains('tatil') && doluHucreler.length <= 2;
  }

  static String _kolonDegeri(
    List<List<dynamic>> satirlar,
    int satir,
    int? sutun,
  ) {
    if (sutun == null) {
      return '';
    }

    return _hucre(satirlar, satir, sutun);
  }

  static String _hucre(
    List<List<dynamic>> satirlar,
    int satir,
    int sutun,
  ) {
    if (satir < 0 ||
        satir >= satirlar.length ||
        sutun < 0 ||
        sutun >= satirlar[satir].length) {
      return '';
    }

    final deger = satirlar[satir][sutun];

    if (deger == null) {
      return '';
    }

    return deger
        .toString()
        .replaceAll('\u00A0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[^\S\n]+'), ' ')
        .trim();
  }

  static String _satirMetni(List<dynamic> satir) {
    return satir
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .map((e) => e.toString().trim())
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _haftaNoOku(String metin) {
    final normalizeMetin = _normalize(metin);

    final haftaEslesmesi = RegExp(
      r'\b(\d{1,2})\s*hafta\b',
    ).firstMatch(normalizeMetin);

    if (haftaEslesmesi != null) {
      final deger = int.tryParse(
            haftaEslesmesi.group(1) ?? '',
          ) ??
          0;

      if (deger >= 1 && deger <= 60) {
        return deger;
      }
    }

    return 0;
  }

  static String _tarihAraligiOku(String metin) {
    if (metin.trim().isEmpty) {
      return '';
    }

    final temiz = metin
        .replaceAll('\u00A0', ' ')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('−', '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final caprazAy = RegExp(
      r'(\d{1,2})\s+'
      r'(Ocak|Şubat|Subat|Mart|Nisan|Mayıs|Mayis|Haziran|'
      r'Temmuz|Ağustos|Agustos|Eylül|Eylul|Ekim|Kasım|Kasim|'
      r'Aralık|Aralik)\s*-\s*'
      r'(\d{1,2})\s+'
      r'(Ocak|Şubat|Subat|Mart|Nisan|Mayıs|Mayis|Haziran|'
      r'Temmuz|Ağustos|Agustos|Eylül|Eylul|Ekim|Kasım|Kasim|'
      r'Aralık|Aralik)',
      caseSensitive: false,
    ).firstMatch(temiz);

    if (caprazAy != null) {
      return caprazAy.group(0)?.trim() ?? '';
    }

    final ayniAy = RegExp(
      r'(\d{1,2})\s*-\s*(\d{1,2})\s+'
      r'(Ocak|Şubat|Subat|Mart|Nisan|Mayıs|Mayis|Haziran|'
      r'Temmuz|Ağustos|Agustos|Eylül|Eylul|Ekim|Kasım|Kasim|'
      r'Aralık|Aralik)',
      caseSensitive: false,
    ).firstMatch(temiz);

    if (ayniAy != null) {
      return ayniAy.group(0)?.trim() ?? '';
    }

    return '';
  }

  static (String?, String?) _tarihAraligiParseEt(
    String tarihAraligi,
    String egitimOgretimYili,
  ) {
    final temiz = _tarihAraligiOku(tarihAraligi);

    if (temiz.isEmpty) {
      return (null, null);
    }

    final yilParcalari = _egitimOgretimYiliniNormalizeEt(
      egitimOgretimYili,
    ).split('-');

    if (yilParcalari.length != 2) {
      return (null, null);
    }

    final egitimBasYili = int.tryParse(yilParcalari[0]);
    final egitimBitYili = int.tryParse(yilParcalari[1]);

    if (egitimBasYili == null || egitimBitYili == null) {
      return (null, null);
    }

    final caprazAy = RegExp(
      r'(\d{1,2})\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)\s*-\s*'
      r'(\d{1,2})\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)',
      caseSensitive: false,
    ).firstMatch(temiz);

    if (caprazAy != null) {
      final basGun = int.tryParse(caprazAy.group(1) ?? '');
      final basAy = _ayNo(caprazAy.group(2) ?? '');
      final bitGun = int.tryParse(caprazAy.group(3) ?? '');
      final bitAy = _ayNo(caprazAy.group(4) ?? '');

      if (basGun == null ||
          basAy == null ||
          bitGun == null ||
          bitAy == null) {
        return (null, null);
      }

      final basYil = basAy >= 8 ? egitimBasYili : egitimBitYili;
      var bitYil = bitAy >= 8 ? egitimBasYili : egitimBitYili;

      if (basAy == 12 && bitAy == 1) {
        bitYil = egitimBitYili;
      }

      return _guvenliTarihAraligi(
        basYil: basYil,
        basAy: basAy,
        basGun: basGun,
        bitYil: bitYil,
        bitAy: bitAy,
        bitGun: bitGun,
      );
    }

    final ayniAy = RegExp(
      r'(\d{1,2})\s*-\s*(\d{1,2})\s+'
      r'([A-Za-zÇĞİÖŞÜçğıöşü]+)',
      caseSensitive: false,
    ).firstMatch(temiz);

    if (ayniAy == null) {
      return (null, null);
    }

    final basGun = int.tryParse(ayniAy.group(1) ?? '');
    final bitGun = int.tryParse(ayniAy.group(2) ?? '');
    final ay = _ayNo(ayniAy.group(3) ?? '');

    if (basGun == null || bitGun == null || ay == null) {
      return (null, null);
    }

    final yil = ay >= 8 ? egitimBasYili : egitimBitYili;

    return _guvenliTarihAraligi(
      basYil: yil,
      basAy: ay,
      basGun: basGun,
      bitYil: yil,
      bitAy: ay,
      bitGun: bitGun,
    );
  }

  static (String?, String?) _guvenliTarihAraligi({
    required int basYil,
    required int basAy,
    required int basGun,
    required int bitYil,
    required int bitAy,
    required int bitGun,
  }) {
    try {
      final bas = DateTime(basYil, basAy, basGun);
      final bit = DateTime(bitYil, bitAy, bitGun);

      if (bas.day != basGun ||
          bas.month != basAy ||
          bit.day != bitGun ||
          bit.month != bitAy) {
        return (null, null);
      }

      return (_tarihIso(bas), _tarihIso(bit));
    } catch (_) {
      return (null, null);
    }
  }

  static String _ilkAyAdi(String tarihAraligi) {
    if (tarihAraligi.trim().isEmpty) {
      return '';
    }

    final eslesme = RegExp(
      r'(Ocak|Şubat|Subat|Mart|Nisan|Mayıs|Mayis|Haziran|'
      r'Temmuz|Ağustos|Agustos|Eylül|Eylul|Ekim|Kasım|Kasim|'
      r'Aralık|Aralik)',
      caseSensitive: false,
    ).firstMatch(tarihAraligi);

    return eslesme?.group(0)?.trim() ?? '';
  }

  static int? _ayNo(String ay) {
    switch (_normalize(ay)) {
      case 'ocak':
        return 1;
      case 'subat':
        return 2;
      case 'mart':
        return 3;
      case 'nisan':
        return 4;
      case 'mayis':
        return 5;
      case 'haziran':
        return 6;
      case 'temmuz':
        return 7;
      case 'agustos':
        return 8;
      case 'eylul':
        return 9;
      case 'ekim':
        return 10;
      case 'kasim':
        return 11;
      case 'aralik':
        return 12;
      default:
        return null;
    }
  }

  static String _tarihIso(DateTime tarih) {
    return '${tarih.year.toString().padLeft(4, '0')}-'
        '${tarih.month.toString().padLeft(2, '0')}-'
        '${tarih.day.toString().padLeft(2, '0')}';
  }

  static Future<void> _profilVeDersiDogrula({
    required Transaction txn,
    required int ogretmenProfilId,
    required int dersId,
  }) async {
    final profil = await txn.query(
      'OgretmenProfil',
      columns: ['OgretmenProfilId'],
      where: 'OgretmenProfilId = ? AND Aktif = ?',
      whereArgs: [ogretmenProfilId, 1],
      limit: 1,
    );

    if (profil.isEmpty) {
      throw Exception(
        'Aktif öğretmen profili bulunamadı. '
        'ÖğretmenProfilId: $ogretmenProfilId',
      );
    }

    final ders = await txn.query(
      'Ders',
      columns: ['DersId'],
      where: 'DersId = ? AND Aktif = ?',
      whereArgs: [dersId, 1],
      limit: 1,
    );

    if (ders.isEmpty) {
      throw Exception(
        'Seçilen aktif ders bulunamadı. DersId: $dersId',
      );
    }
  }

  static Future<int> _yillikPlanBulVeyaOlustur({
    required Transaction txn,
    required int dersId,
    required int sinifSeviyesi,
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    required String dosyaAdi,
    required String simdi,
  }) async {
    final mevcut = await txn.query(
      'YillikPlan',
      columns: ['YillikPlanId'],
      where: 'DersId = ? AND SinifSeviyesi = ? '
          'AND OgretmenProfilId = ? AND EgitimOgretimYili = ?',
      whereArgs: [
        dersId,
        sinifSeviyesi,
        ogretmenProfilId,
        egitimOgretimYili,
      ],
      orderBy: 'YillikPlanId ASC',
      limit: 1,
    );

    if (mevcut.isNotEmpty) {
      return mevcut.first['YillikPlanId'] as int;
    }

    return await txn.insert(
      'YillikPlan',
      {
        'DersId': dersId,
        'SinifSubeId': null,
        'OgretmenProfilId': ogretmenProfilId,
        'SinifSeviyesi': sinifSeviyesi,
        'EgitimOgretimYili': egitimOgretimYili,
        'Aciklama': dosyaAdi.trim().isEmpty
            ? null
            : 'Import dosyası: ${dosyaAdi.trim()}',
        'Aktif': 1,
        'OlusturmaTarihi': simdi,
        'GuncellemeTarihi': null,
      },
    );
  }

  static Future<void> _calismaTakviminiKaydet({
    required Transaction txn,
    required int ogretmenProfilId,
    required String egitimOgretimYili,
    required String dosyaAdi,
    required List<BireyselCalismaTakvimiAdayi> kayitlar,
    required String simdi,
    bool mevcutKayitlariKoru = false,
  }) async {
    final mevcut = await txn.query(
      'CalismaTakvimi',
      columns: ['CalismaTakvimiId'],
      where: 'OgretmenProfilId = ? AND EgitimOgretimYili = ?',
      whereArgs: [
        ogretmenProfilId,
        egitimOgretimYili,
      ],
      limit: 1,
    );

    late final int calismaTakvimiId;

    if (mevcut.isNotEmpty) {
      calismaTakvimiId =
          mevcut.first['CalismaTakvimiId'] as int;

      await txn.update(
        'CalismaTakvimi',
        {
          'KaynakDosyaAdi': _nullIfEmpty(dosyaAdi),
          'Aktif': 1,
          'GuncellemeTarihi': simdi,
        },
        where: 'CalismaTakvimiId = ?',
        whereArgs: [calismaTakvimiId],
      );
    } else {
      calismaTakvimiId = await txn.insert(
        'CalismaTakvimi',
        {
          'OgretmenProfilId': ogretmenProfilId,
          'EgitimOgretimYili': egitimOgretimYili,
          'KaynakDosyaAdi': _nullIfEmpty(dosyaAdi),
          'Aktif': 1,
          'OlusturmaTarihi': simdi,
          'GuncellemeTarihi': null,
        },
      );
    }

    if (!mevcutKayitlariKoru) {
      await txn.delete(
      'CalismaTakvimiDetay',
      where: 'CalismaTakvimiId = ?',
      whereArgs: [calismaTakvimiId],
    );
    }

    for (final kayit in kayitlar) {
      if (mevcutKayitlariKoru) {
        await txn.delete('CalismaTakvimiDetay',
          where: 'CalismaTakvimiId = ? AND KayitTuru = ? AND COALESCE(TarihAraligi, \'\') = ? AND COALESCE(HaftaNo, 0) = ?',
          whereArgs: [calismaTakvimiId, kayit.kayitTuru, kayit.tarihAraligi, kayit.haftaNo ?? 0]);
      }
      await txn.insert(
        'CalismaTakvimiDetay',
        {
          'CalismaTakvimiId': calismaTakvimiId,
          'HaftaNo': kayit.haftaNo,
          'Ay': _nullIfEmpty(kayit.ay),
          'TarihAraligi': _nullIfEmpty(kayit.tarihAraligi),
          'BaslangicTarihi': kayit.baslangicTarihi,
          'BitisTarihi': kayit.bitisTarihi,
          'KayitTuru': kayit.kayitTuru,
          'CalismaVarMi': kayit.calismaVarMi ? 1 : 0,
          'Aciklama': _nullIfEmpty(kayit.aciklama),
          'OzelGunAciklamasi':
              _nullIfEmpty(kayit.ozelGunAciklamasi),
          'Aktif': 1,
          'OlusturmaTarihi': simdi,
          'GuncellemeTarihi': null,
        },
      );
    }
  }

  static String _egitimOgretimYiliniNormalizeEt(String deger) {
    final temiz = deger.trim();

    if (temiz.isEmpty) {
      return '';
    }

    final eslesme = RegExp(
      r'(\d{4})\s*[-/]\s*(\d{4})',
    ).firstMatch(temiz);

    if (eslesme != null) {
      return '${eslesme.group(1)}-${eslesme.group(2)}';
    }

    final baslangic = int.tryParse(temiz);

    if (baslangic != null) {
      return '$baslangic-${baslangic + 1}';
    }

    return temiz;
  }

  static String _normalize(String deger) {
    var sonuc = deger.trim();

    const buyukDonusumler = <String, String>{
      'Ç': 'c',
      'Ğ': 'g',
      'İ': 'i',
      'I': 'i',
      'Ö': 'o',
      'Ş': 's',
      'Ü': 'u',
    };

    buyukDonusumler.forEach((eski, yeni) {
      sonuc = sonuc.replaceAll(eski, yeni);
    });

    sonuc = sonuc.toLowerCase();

    const kucukDonusumler = <String, String>{
      'ç': 'c',
      'ğ': 'g',
      'ı': 'i',
      'ö': 'o',
      'ş': 's',
      'ü': 'u',
      'â': 'a',
      'î': 'i',
      'û': 'u',
    };

    kucukDonusumler.forEach((eski, yeni) {
      sonuc = sonuc.replaceAll(eski, yeni);
    });

    sonuc = sonuc
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return sonuc;
  }

  static String? _nullIfEmpty(String deger) {
    final temiz = deger.trim();
    return temiz.isEmpty ? null : temiz;
  }
}
