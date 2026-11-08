import 'dart:math';

import '../database/local_database.dart';

class BireyselProfilService {
  BireyselProfilService._();

  static const String _meslekPaketiAnahtari = 'MeslekPaketiAktif';

  static Future<bool?> meslekPaketiTercihiniGetir() async {
    try {
      final db = await LocalDatabase.instance.database;
      final sonuc = await db.query(
        'UygulamaAyarlari',
        columns: ['Deger'],
        where: 'Anahtar = ?',
        whereArgs: [_meslekPaketiAnahtari],
        limit: 1,
      );
      if (sonuc.isEmpty) return null;

      final deger = sonuc.first['Deger'];
      if (deger == '1') return true;
      if (deger == '0') return false;
      throw Exception('Kayıtlı meslek paketi tercihi geçersiz.');
    } catch (e) {
      throw Exception(
        'Meslek paketi tercihi okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<Map<String, dynamic>?> getir() async {
    try {
      final db = await LocalDatabase.instance.database;

      final sonuc = await db.query(
        'OgretmenProfil',
        where: 'Aktif = ?',
        whereArgs: [1],
        orderBy: 'OgretmenProfilId DESC',
        limit: 1,
      );

      if (sonuc.isEmpty) {
        return null;
      }

      return Map<String, dynamic>.from(sonuc.first);
    } catch (e) {
      throw Exception(
        'Bireysel öğretmen profili okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<Map<String, dynamic>?> okulProfiliniGetir() async {
    try {
      final db = await LocalDatabase.instance.database;
      final sonuc = await db.query(
        'OkulProfil',
        where: 'Id = ?',
        whereArgs: [1],
        limit: 1,
      );

      if (sonuc.isEmpty) {
        return null;
      }

      return Map<String, dynamic>.from(sonuc.first);
    } catch (e) {
      throw Exception(
        'Bireysel okul profili okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<bool> profilVarMi() async {
    try {
      final profil = await getir();
      return profil != null;
    } catch (e) {
      throw Exception(
        'Bireysel öğretmen profil durumu kontrol edilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<bool> profilBilgileriTamMi() async {
    try {
      final profil = await getir();

      if (profil == null) {
        return false;
      }

      final adSoyad = (profil['AdSoyad'] ?? '').toString().trim();
      final brans = (profil['Brans'] ?? '').toString().trim();
      final okulAdi = (profil['OkulAdi'] ?? '').toString().trim();

      final yil = (profil['EgitimOgretimYili'] ?? '').toString().trim();
      final okul = await okulProfiliniGetir();

      if (okul == null) {
        return false;
      }

      return adSoyad.isNotEmpty &&
          brans.isNotEmpty &&
          okulAdi.isNotEmpty &&
          yil.isNotEmpty &&
          (okul['OkulId'] ?? '').toString().trim().isNotEmpty &&
          (okul['OkulKisaAdi'] ?? '').toString().trim().isNotEmpty &&
          (okul['OkulAdi'] ?? '').toString().trim() == okulAdi &&
          (okul['EgitimYili'] ?? '').toString().trim() == yil &&
          (okul['Donem'] == 1 || okul['Donem'] == 2) &&
          okul['AktifMi'] == 1;
    } catch (e) {
      throw Exception(
        'Bireysel öğretmen zorunlu profil bilgileri kontrol edilirken '
        'hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<int> kaydet({
    required String adSoyad,
    required String brans,
    required String okulAdi,
    required String okulKisaAdi,
    required String egitimOgretimYili,
    required int donem,
    required bool meslekPaketiAktif,
  }) async {
    final temizAdSoyad = adSoyad.trim();
    final temizBrans = brans.trim();
    final temizOkulAdi = okulAdi.trim();
    final temizOkulKisaAdi = okulKisaAdi.trim();
    final temizEgitimOgretimYili = egitimOgretimYili.trim();

    if (temizAdSoyad.isEmpty) {
      throw Exception('Ad Soyad boş bırakılamaz.');
    }

    if (temizBrans.isEmpty) {
      throw Exception('Branş boş bırakılamaz.');
    }

    if (temizOkulAdi.isEmpty) {
      throw Exception('Okul adı boş bırakılamaz.');
    }

    if (temizOkulKisaAdi.isEmpty) {
      throw Exception('Okul kısa adı boş bırakılamaz.');
    }

    if (donem != 1 && donem != 2) {
      throw Exception('Dönem 1 veya 2 olmalıdır.');
    }

    if (temizEgitimOgretimYili.isEmpty) {
      throw Exception('Eğitim öğretim yılı boş bırakılamaz.');
    }

    try {
      final db = await LocalDatabase.instance.database;
      final simdi = DateTime.now().toIso8601String();

      return await db.transaction<int>((txn) async {
        final tercih = await txn.query(
          'UygulamaAyarlari',
          columns: ['Id'],
          where: 'Anahtar = ?',
          whereArgs: [_meslekPaketiAnahtari],
          limit: 1,
        );
        final tercihVerileri = <String, Object?>{
          'Deger': meslekPaketiAktif ? '1' : '0',
          'GuncellemeTarihi': simdi,
        };
        if (tercih.isEmpty) {
          await txn.insert('UygulamaAyarlari', {
            'Anahtar': _meslekPaketiAnahtari,
            ...tercihVerileri,
          });
        } else {
          final etkilenenSatir = await txn.update(
            'UygulamaAyarlari',
            tercihVerileri,
            where: 'Anahtar = ?',
            whereArgs: [_meslekPaketiAnahtari],
          );
          if (etkilenenSatir != 1) {
            throw Exception('Meslek paketi tercihi güncellenemedi.');
          }
        }

        final okul = await txn.query(
          'OkulProfil',
          where: 'Id = ?',
          whereArgs: [1],
          limit: 1,
        );
        final okulVerileri = <String, Object?>{
          'OkulAdi': temizOkulAdi,
          'OkulKisaAdi': temizOkulKisaAdi,
          'EgitimYili': temizEgitimOgretimYili,
          'Donem': donem,
          'AktifMi': 1,
        };

        if (okul.isEmpty) {
          final random = Random.secure();
          final okulId = List<int>.generate(16, (_) => random.nextInt(256))
              .map((deger) => deger.toRadixString(16).padLeft(2, '0'))
              .join();
          await txn.insert('OkulProfil', {
            ...okulVerileri,
            'Id': 1,
            'OkulId': okulId,
            'OlusturmaTarihi': simdi,
          });
        } else {
          final etkilenenSatir = await txn.update(
            'OkulProfil',
            okulVerileri,
            where: 'Id = ?',
            whereArgs: [1],
          );
          if (etkilenenSatir != 1) {
            throw Exception('Okul profili güncellenemedi.');
          }
        }

        final mevcut = await txn.query(
          'OgretmenProfil',
          where: 'Aktif = ?',
          whereArgs: [1],
          orderBy: 'OgretmenProfilId DESC',
          limit: 1,
        );

        if (mevcut.isNotEmpty) {
          final profilId = mevcut.first['OgretmenProfilId'] as int;

          final etkilenenSatir = await txn.update(
            'OgretmenProfil',
            {
              'AdSoyad': temizAdSoyad,
              'Brans': temizBrans,
              'OkulAdi': temizOkulAdi,
              'EgitimOgretimYili': temizEgitimOgretimYili,
              'GuncellemeTarihi': simdi,
            },
            where: 'OgretmenProfilId = ?',
            whereArgs: [profilId],
          );

          if (etkilenenSatir != 1) {
            throw Exception('Öğretmen profili güncellenemedi.');
          }

          return profilId;
        }

        return await txn.insert(
          'OgretmenProfil',
          {
            'AdSoyad': temizAdSoyad,
            'ProgramdakiAd': null,
            'Brans': temizBrans,
            'OkulAdi': temizOkulAdi,
            'EgitimOgretimYili': temizEgitimOgretimYili,
            'Aktif': 1,
            'OlusturmaTarihi': simdi,
            'GuncellemeTarihi': null,
          },
        );
      });
    } catch (e) {
      throw Exception(
        'Bireysel öğretmen ve okul profili kaydedilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  static Future<void> programdakiAdiGuncelle(String programdakiAd) async {
    final temizProgramdakiAd = programdakiAd.trim();

    if (temizProgramdakiAd.isEmpty) {
      throw Exception('Programdaki öğretmen adı boş bırakılamaz.');
    }

    try {
      final db = await LocalDatabase.instance.database;
      final profil = await getir();

      if (profil == null) {
        throw Exception(
          'Programdaki öğretmen adı kaydedilemedi çünkü bireysel öğretmen '
          'profili bulunamadı.',
        );
      }

      final profilId = profil['OgretmenProfilId'] as int;

      final etkilenenSatir = await db.update(
        'OgretmenProfil',
        {
          'ProgramdakiAd': temizProgramdakiAd,
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        },
        where: 'OgretmenProfilId = ?',
        whereArgs: [profilId],
      );

      if (etkilenenSatir != 1) {
        throw Exception(
          'Öğretmen profilinde beklenen kayıt güncellenemedi. '
          'Etkilenen kayıt sayısı: $etkilenenSatir',
        );
      }
    } catch (e) {
      throw Exception(
        'Ders programındaki öğretmen adı profile kaydedilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }
}
