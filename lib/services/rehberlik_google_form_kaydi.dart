part of 'bireysel_rehberlik_service.dart';

/// Sınıf başına tek Google Form kimliğini, mevcut rehberlik atama yetkisiyle
/// korur. Kimlik önce kaydedilir; soru eşleştirmeleri sonra tamamlanabilir.
extension RehberlikGoogleFormKaydi on BireyselRehberlikService {
  Future<List<Map<String, Object?>>> _googleSinifFormlari(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    Map<String, Object?> a,
  ) async {
    final rows = await tx.rawQuery(
      '''SELECT f.* FROM RehberlikGoogleForm f
      JOIN RehberlikAtama k ON k.RehberlikAtamaId=f.AtamaId
      WHERE k.OkulId=? AND k.OgretmenProfilId=? AND k.SinifSubeId=? AND k.EgitimOgretimYili=?''',
      [b.okulId, b.ogretmenProfilId, a['SinifSubeId'], a['EgitimOgretimYili']],
    );
    if (rows.length > 1) {
      throw StateError(
        'Bu sınıf ve yıl için birden fazla eski Google Form kaydı var. Kayıtlar korunarak işlem durduruldu; bağlantıları kontrol edin.',
      );
    }
    return rows;
  }

  /// Seçenek metni değişebilir; öğrenci kimliği değişmez. Tarihsel etiketler
  /// silinmez. Aynı etiket başka öğrenciye verilirse otomatik eşleşme durur.
  Future<Map<String, int>> googleOgrenciSecenekleriniHazirla(
    BireyselRehberlikBaglami b,
    int atamaId,
  ) async {
    final db = await _db();
    return _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atamaId, yazma: true);
        final rows = await tx.rawQuery(
          '''SELECT DISTINCT o.OgrenciId,o.OkulNo,o.Ad,o.Soyad
        FROM Ogrenci o JOIN OgrenciSinifKayit k ON k.OgrenciId=o.OgrenciId
        WHERE o.Aktif=1 AND k.Aktif=1 AND k.SinifSubeId=? AND k.EgitimOgretimYili=?''',
          [a['SinifSubeId'], a['EgitimOgretimYili']],
        );
        if (rows.isEmpty) {
          throw StateError('Sınıfta aktif öğrenci yok. Liste güncellenmedi.');
        }
        final numaralar = <String>{};
        for (final o in rows) {
          final no = (o['OkulNo'] ?? '').toString().trim();
          if (!RegExp(r'^[0-9]+$').hasMatch(no) ||
              (o['Ad'] ?? '').toString().trim().isEmpty ||
              (o['Soyad'] ?? '').toString().trim().isEmpty) {
            throw const FormatException(
              'Öğrenci adı, soyadı veya okul numarası eksik/hatalı. Öğrenci kayıtlarını düzeltin.',
            );
          }
          if (!numaralar.add(BigInt.parse(no).toString())) {
            throw StateError(
              'Sınıfta aynı okul numarasını kullanan birden fazla öğrenci var. Liste güncellenmedi.',
            );
          }
        }
        final sirali = [...rows]
          ..sort(
            (x, y) => BigInt.parse(
              x['OkulNo'].toString().trim(),
            ).compareTo(BigInt.parse(y['OkulNo'].toString().trim())),
          );
        final secenekler = <String, int>{
          for (final o in sirali)
            googleOgrenciSecenegi(o): o['OgrenciId'] as int,
        };
        final forms = await _googleSinifFormlari(tx, b, a);
        final sahibi = forms.isEmpty ? atamaId : forms.single['AtamaId'];
        final key = 'rehberlik_google_secim_gecmisi:$sahibi';
        final eski = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [key],
        );
        final gecmis = eski.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(
                jsonDecode(eski.single['Deger'] as String) as Map,
              );
        for (final e in secenekler.entries) {
          final ids = List<int>.from(gecmis[e.key] as List? ?? []);
          if (!ids.contains(e.value)) ids.add(e.value);
          gecmis[e.key] = ids;
        }
        await tx.insert('UygulamaAyarlari', {
          'Anahtar': key,
          'Deger': jsonEncode(gecmis),
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return secenekler;
      }),
    );
  }

  Future<Map<String, Object?>> _googleSecimAdayi(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    int atamaId,
    String secim,
  ) async {
    final a = await _atama(tx, b, atamaId);
    final settings = await tx.query(
      'UygulamaAyarlari',
      where: 'Anahtar=?',
      whereArgs: [
        'rehberlik_google_secim_gecmisi:${(await _googleSinifFormlari(tx, b, a)).firstOrNull?['AtamaId'] ?? atamaId}',
      ],
    );
    final gecmis = settings.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(settings.single['Deger'] as String) as Map;
    final ids = List<int>.from(gecmis[secim.trim()] as List? ?? []);
    if (ids.length != 1) {
      return {
        'adayId': null,
        'uyari': ids.length > 1
            ? 'Bu seçim geçmişte birden fazla öğrenciye ait olmuş. Eşleşmeyi ayrıca doğrulayın.'
            : 'Seçim kayıtlı öğrenci listesinde doğrulanamadı. Eşleşmeyi ayrıca doğrulayın.',
      };
    }
    final rows = await tx.rawQuery(
      '''SELECT o.OgrenciId,o.OkulNo,o.Ad,o.Soyad,o.Aktif,k.Aktif AS KayitAktif
      FROM Ogrenci o JOIN OgrenciSinifKayit k ON k.OgrenciId=o.OgrenciId
      WHERE o.OgrenciId=? AND k.SinifSubeId=? AND k.EgitimOgretimYili=?''',
      [ids.single, a['SinifSubeId'], a['EgitimOgretimYili']],
    );
    if (rows.isEmpty ||
        rows.every((o) => o['Aktif'] != 1 || o['KayitAktif'] != 1)) {
      return {
        'adayId': null,
        'gecmisOgrenciId': ids.single,
        'uyari':
            'Öğrenci artık bu sınıfta aktif değil. Geçmiş kaydı korundu; otomatik eşleşme yapılmadı.',
      };
    }
    final o = rows.first;
    // Numara çakışması, adlar farklı olsa bile otomatik eşleşmeyi durdurur.
    final cakisan = await tx.rawQuery(
      '''SELECT DISTINCT o.OgrenciId FROM Ogrenci o
      JOIN OgrenciSinifKayit k ON k.OgrenciId=o.OgrenciId
      WHERE o.Aktif=1 AND k.Aktif=1 AND k.SinifSubeId=? AND k.EgitimOgretimYili=?
      AND CAST(o.OkulNo AS INTEGER)=CAST(? AS INTEGER)''',
      [a['SinifSubeId'], a['EgitimOgretimYili'], o['OkulNo']],
    );
    if (cakisan.length != 1) {
      return {
        'adayId': null,
        'uyari': 'Okul numarası çakışıyor. Eşleşmeyi ayrıca doğrulayın.',
      };
    }
    return {
      'adayId': ids.single,
      'uyari': googleOgrenciSecenegi(o) == secim.trim()
          ? null
          : 'Ad veya okul numarası değişmiş. Eski seçenek, kayıtlı öğrenci kimliğine göre önerildi; geçmişi kontrol edin.',
    };
  }

  Future<Map<String, Object?>> googleSecimOgrenciAdayi(
    BireyselRehberlikBaglami b,
    int atamaId,
    String secim,
  ) async {
    final db = await _db();
    return db.transaction((tx) => _googleSecimAdayi(tx, b, atamaId, secim));
  }

  Future<void> googleYazmaYetkisiniKontrol(
    BireyselRehberlikBaglami b,
    int atamaId,
  ) async {
    final db = await _db();
    await db.transaction((tx) => _atama(tx, b, atamaId, yazma: true));
  }

  /// forms.create idempotency anahtarı kabul etmez. Belirsiz ağ sonucunda
  /// ikinci bir form üretmek yerine mevcut formu bağlayarak kurtarılır.
  Future<void> googleOlusturmayiBaslat(
    BireyselRehberlikBaglami b,
    int atamaId,
  ) async {
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atamaId, yazma: true);
        final key =
            'rehberlik_google_sinif_olusturma:${b.okulId}:${b.ogretmenProfilId}:${a['SinifSubeId']}:${a['EgitimOgretimYili']}';
        final atamalar = await tx.query(
          'RehberlikAtama',
          where:
              'OkulId=? AND OgretmenProfilId=? AND SinifSubeId=? AND EgitimOgretimYili=?',
          whereArgs: [
            b.okulId,
            b.ogretmenProfilId,
            a['SinifSubeId'],
            a['EgitimOgretimYili'],
          ],
        );
        final anahtarlar = [
          key,
          for (final row in atamalar)
            'rehberlik_google_olusturma:${row['RehberlikAtamaId']}',
        ];
        final eski = await tx.query(
          'UygulamaAyarlari',
          where:
              'Anahtar IN (${List.filled(anahtarlar.length, '?').join(',')})',
          whereArgs: anahtarlar,
        );
        if (eski.isNotEmpty) {
          throw StateError(
            'Önceki form oluşturma işleminin sonucu belirsiz. Google Forms hesabınızı kontrol edin; Bağlantı ayarlarından mevcut formun düzenleme bağlantısını bağlayın. Tekrar form oluşturulmadı.',
          );
        }
        await tx.insert('UygulamaAyarlari', {
          'Anahtar': key,
          'Deger': 'Baslatildi',
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        });
      }),
    );
  }

  Future<Map<String, Object?>?> googleFormKaydiGetir(
    BireyselRehberlikBaglami baglam,
    int atamaId,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, baglam, atamaId);
      final satirlar = await _googleSinifFormlari(tx, baglam, a);
      return satirlar.isEmpty
          ? null
          : Map<String, Object?>.from(satirlar.single);
    });
  }

  /// Google Forms forms.create yanıtı döner dönmez çağrılır. Aynı atama
  /// için başka bir Google form kimliği varsa hiçbir kaydı değiştirmez.
  Future<void> googleFormKimliginiKaydet(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    String googleFormId,
  ) async {
    if (googleFormId.trim().isEmpty) {
      throw const FormatException('Google Form kimliği boş olamaz.');
    }
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, baglam, atamaId, yazma: true);
        final mevcut = await _googleSinifFormlari(tx, baglam, a);
        if (mevcut.isNotEmpty) {
          if (mevcut.single['GoogleFormId'] == googleFormId) return;
          throw StateError(
            'Bu sınıfa ait Google Form zaten kayıtlı. Yeni form oluşturmayın.',
          );
        }
        await tx.insert('RehberlikGoogleForm', {
          'AtamaId': atamaId,
          'GoogleFormId': googleFormId,
          'SoruEslemeleri': '{}',
          'Durum': 'Taslak',
          'OlusturmaTarihi': DateTime.now().toIso8601String(),
        });
      }),
    );
  }

  /// Doğrulanan soru kimlikleri kaydedilir. Kayıtlı form kimliği eşleşmeli;
  /// farklı bir forma ait cevaplar aynı sınıfa karıştırılamaz.
  Future<void> googleFormEslemeleriniKaydet(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    String googleFormId,
    Map<String, Map<String, String>> eslemeler,
  ) async {
    if (eslemeler.isEmpty ||
        eslemeler.entries.any(
          (e) =>
              e.key.trim().isEmpty ||
              (e.value['itemId'] ?? '').isEmpty ||
              (e.value['questionId'] ?? '').isEmpty,
        )) {
      throw const FormatException('Google soru eşleştirmeleri eksik.');
    }
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, baglam, atamaId, yazma: true);
        final mevcut = await _googleSinifFormlari(tx, baglam, a);
        if (mevcut.isEmpty || mevcut.single['GoogleFormId'] != googleFormId) {
          throw StateError('Kayıtlı Google Form bulunamadı.');
        }
        final eskiler = jsonDecode(mevcut.single['SoruEslemeleri'] as String);
        if (eskiler is Map && eskiler.isNotEmpty) {
          // Mevcut Google questionId ve itemId asla değiştirilemez.
          for (final key in eskiler.keys) {
            if (!eslemeler.containsKey(key) ||
                eskiler[key] is! Map ||
                eskiler[key]['itemId'] != eslemeler[key]?['itemId'] ||
                eskiler[key]['questionId'] != eslemeler[key]?['questionId']) {
              throw StateError(
                'Kayıtlı soru eşleştirmesi değişmiş; Google Formu kontrol edin.',
              );
            }
          }
          if (eskiler.length == eslemeler.length) return;
        }
        await tx.update(
          'RehberlikGoogleForm',
          {
            'SoruEslemeleri': jsonEncode(eslemeler),
            'GuncellemeTarihi': DateTime.now().toIso8601String(),
          },
          where: 'Id=? AND GoogleFormId=?',
          whereArgs: [mevcut.single['Id'], googleFormId],
        );
      }),
    );
  }

  /// Aynı Google responseId'nin farklı öğrenciye tekrar kaydedilmesini engeller.
  /// Hassas yanıt içeriği takip tablosunda ikinci kez tutulmaz.
  Future<int> googleYanitiOnayla(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    String googleYanitId,
    int ogrenciId,
    Map<String, String> cevaplar, {
    bool eslesmeDegisikligiOnayi = false,
  }) async {
    if (googleYanitId.trim().isEmpty || cevaplar.isEmpty) {
      throw const FormatException('Google yanıtı eksik.');
    }
    final db = await _db();
    return _sirali(
      () => db.transaction((tx) async {
        final atama = await _atama(tx, baglam, atamaId, yazma: true);
        await _ogrenciKontrol(tx, atama, ogrenciId, yazma: true);
        final forms = await _googleSinifFormlari(tx, baglam, atama);
        if (forms.isEmpty) {
          throw StateError('Sınıfa ait Google Form kaydı yok.');
        }
        final formId = forms.single['Id'] as int;
        final mevcut = await tx.query(
          'RehberlikGoogleYanit',
          where: 'FormId=? AND GoogleYanitId=?',
          whereArgs: [formId, googleYanitId],
          limit: 1,
        );
        if (mevcut.isNotEmpty && mevcut.single['Durum'] == 'Onaylandi') {
          throw StateError('Bu Google yanıtı daha önce onaylanmış.');
        }
        int? davetId;
        final secim = cevaplar[googleOgrenciSecimSorusu]?.trim() ?? '';
        if (secim.isNotEmpty) {
          final harita =
              jsonDecode(forms.single['SoruEslemeleri'] as String) as Map;
          if (!harita.containsKey(googleOgrenciSecimSorusu)) {
            throw StateError(
              'Bu formun öğrenci seçim sorusu henüz doğrulanmamış. Önce formu kontrol edin.',
            );
          }
          final aday = await _googleSecimAdayi(tx, baglam, atamaId, secim);
          if (aday['adayId'] != ogrenciId && !eslesmeDegisikligiOnayi) {
            throw StateError(
              'Önerilen öğrenciyle seçiminiz farklı veya şüpheli. Eşleşme değişikliği ayrıca onaylanmalı.',
            );
          }
        } else {
          final kod = (cevaplar['Öğrenci davet kodu'] ?? '')
              .trim()
              .toLowerCase();
          final davetler = await tx.query(
            'RehberlikFormDavet',
            where: 'FormId=? AND OgrenciId=? AND KodOzeti=?',
            whereArgs: [
              formId,
              ogrenciId,
              sha256.convert(utf8.encode(kod)).toString(),
            ],
          );
          if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(kod) ||
              davetler.length != 1 ||
              davetler.single['IptalTarihi'] != null ||
              (davetler.single['SonGecerlilikTarihi'] != null &&
                  DateTime.parse(
                    davetler.single['SonGecerlilikTarihi'] as String,
                  ).isBefore(DateTime.now()))) {
            throw StateError(
              'Davet bu öğrenciye ait değil veya süresi dolmuş. Yanıt kaydedilmedi.',
            );
          }
          davetId = davetler.single['Id'] as int;
        }
        final temiz = Map<String, String>.from(cevaplar)
          ..remove('Öğrenci davet kodu')
          ..remove(googleOgrenciSecimSorusu);
        if (secim.isNotEmpty) {
          temiz.removeWhere((key, _) => googleElleKimlikSorulari.contains(key));
        }
        if (temiz.values.every((v) => v.trim().isEmpty)) {
          throw const FormatException(
            'Öğrenci bilgileri boş. Yalnız öğrenci seçimi fişe kaydedilemez.',
          );
        }
        if (secim.isNotEmpty) {
          // Kimlik soruları elle tekrar istenmez; onaylanan SQLite öğrencisi esas alınır.
          final o = (await tx.query(
            'Ogrenci',
            where: 'OgrenciId=?',
            whereArgs: [ogrenciId],
          )).single;
          temiz['Adınız Soyadınız'] = '${o['Ad']} ${o['Soyad']}';
          temiz['Okul numaranız'] = o['OkulNo'].toString();
          final sinif = (await tx.query(
            'SinifSube',
            where: 'SinifSubeId=?',
            whereArgs: [atama['SinifSubeId']],
          )).single;
          temiz['Sınıfınız'] = sinif['SinifKodu'].toString();
          final okul = await tx.query(
            'OkulProfil',
            where: 'OkulId=?',
            whereArgs: [baglam.okulId],
          );
          final okulAdi = okul.firstOrNull?['OkulAdi']?.toString().trim() ?? '';
          if (okulAdi.isNotEmpty) temiz['Okulunuz'] = okulAdi;
        }
        if (temiz.values.every((v) => v.trim().isEmpty) ||
            temiz.keys.any((k) => k.trim().isEmpty || k.length > 300)) {
          throw const FormatException(
            'Öğrenciye ait form cevapları boş veya hatalı.',
          );
        }
        final son = await tx.query(
          'RehberlikForm',
          where: 'AtamaId=? AND OgrenciId=?',
          whereArgs: [atamaId, ogrenciId],
          orderBy: 'Id DESC',
          limit: 1,
        );
        final sorular = <String>[];
        final birlesik = <String, String>{};
        if (son.isNotEmpty) {
          sorular.addAll(
            List<String>.from(
              jsonDecode(son.single['Sorular'] as String) as List,
            ),
          );
          birlesik.addAll(
            Map<String, String>.from(
              jsonDecode(son.single['Cevaplar'] as String) as Map,
            ),
          );
        }
        for (final e in temiz.entries) {
          if (!sorular.contains(e.key)) sorular.add(e.key);
          if (e.value.trim().isNotEmpty) birlesik[e.key] = e.value;
        }
        if (sorular.length > 100 || jsonEncode(birlesik).length > 100000) {
          throw const FormatException('Form kayıt sınırını aşıyor.');
        }
        final tarih = DateTime.now().toIso8601String();
        final fisId = await tx.insert('RehberlikForm', {
          'AtamaId': atamaId,
          'OgrenciId': ogrenciId,
          'Sorular': jsonEncode(sorular),
          'Cevaplar': jsonEncode(birlesik),
          'OlusturmaTarihi': tarih,
        });
        final veri = <String, Object?>{
          'Durum': 'Onaylandi',
          'RehberlikFormId': fisId,
          'DavetId': davetId,
          'KontrolTarihi': tarih,
        };
        if (mevcut.isEmpty) {
          await tx.insert('RehberlikGoogleYanit', {
            ...veri,
            'FormId': formId,
            'GoogleYanitId': googleYanitId,
            'OlusturmaTarihi': tarih,
          });
        } else {
          await tx.update(
            'RehberlikGoogleYanit',
            veri,
            where: 'Id=?',
            whereArgs: [mevcut.single['Id']],
          );
        }
        await _kontrol(tx, baglam);
        return fisId;
      }),
    );
  }

  Future<void> googleFormuAktifIsaretle(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    String googleFormId,
  ) async {
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, baglam, atamaId, yazma: true);
        final forms = await _googleSinifFormlari(tx, baglam, a);
        if (forms.isEmpty) throw StateError('Form bulunamadı.');
        final degisen = await tx.update(
          'RehberlikGoogleForm',
          {
            'Durum': 'Aktif',
            'GuncellemeTarihi': DateTime.now().toIso8601String(),
          },
          where: 'Id=? AND GoogleFormId=?',
          whereArgs: [forms.single['Id'], googleFormId],
        );
        if (degisen != 1) {
          throw StateError('Yayınlanan form sınıf atamasında bulunamadı.');
        }
      }),
    );
  }

  Future<bool> googleDavetVarMi(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    int ogrenciId,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      final atama = await _atama(tx, baglam, atamaId);
      await _ogrenciKontrol(tx, atama, ogrenciId);
      final rows = await tx.rawQuery(
        '''SELECT d.Id FROM RehberlikFormDavet d
        JOIN RehberlikGoogleForm f ON f.Id=d.FormId
        WHERE f.AtamaId=? AND d.OgrenciId=? LIMIT 1''',
        [atamaId, ogrenciId],
      );
      return rows.isNotEmpty;
    });
  }

  /// Öğrenciye özel 128-bit davet kodu yalnız bir kez gösterilir. SQLite
  /// içinde kodun kendisi yerine SHA-256 özeti tutulur.
  Future<String> googleDavetKoduUret(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    int ogrenciId,
  ) async {
    final random = Random.secure();
    final kod = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final ozet = sha256.convert(utf8.encode(kod)).toString();
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final atama = await _atama(tx, baglam, atamaId, yazma: true);
        await _ogrenciKontrol(tx, atama, ogrenciId, yazma: true);
        final formlar = await tx.query(
          'RehberlikGoogleForm',
          where: 'AtamaId=?',
          whereArgs: [atamaId],
          limit: 1,
        );
        if (formlar.isEmpty) throw StateError('Önce Google Form oluşturun.');
        final formId = formlar.single['Id'] as int;
        final eski = await tx.query(
          'RehberlikFormDavet',
          where: 'FormId=? AND OgrenciId=?',
          whereArgs: [formId, ogrenciId],
          limit: 1,
        );
        final yeni = {
          'KodOzeti': ozet,
          'SonGecerlilikTarihi': DateTime.now()
              .add(const Duration(days: 30))
              .toIso8601String(),
          'IptalTarihi': null,
        };
        if (eski.isEmpty) {
          await tx.insert('RehberlikFormDavet', {
            ...yeni,
            'FormId': formId,
            'OgrenciId': ogrenciId,
            'OlusturmaTarihi': DateTime.now().toIso8601String(),
          });
        } else {
          await tx.update(
            'RehberlikFormDavet',
            yeni,
            where: 'Id=?',
            whereArgs: [eski.single['Id']],
          );
        }
      }),
    );
    return kod;
  }

  /// Eksik öğrenci davetlerini tek transaction'da oluşturur. Eski davetler
  /// asla yenilenmez: kodun düz metni saklanmadığından eski link geri
  /// gösterilemez. Dönen kodlar yalnız bu oturumda görünür.
  Future<Map<int, String>> googleTopluDavetHazirla(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    Iterable<int> ogrenciIdleri, {
    String? baglantiSablonu,
  }) async {
    if (baglantiSablonu != null) {
      googleDavetBaglantisi(baglantiSablonu, 'a' * 32);
    }
    final ids = ogrenciIdleri.toSet();
    if (ids.isEmpty) return const <int, String>{};
    final db = await _db();
    return _sirali(
      () => db.transaction((tx) async {
        final atama = await _atama(tx, baglam, atamaId, yazma: true);
        final formlar = await tx.query(
          'RehberlikGoogleForm',
          where: 'AtamaId=?',
          whereArgs: [atamaId],
          limit: 1,
        );
        if (formlar.isEmpty) {
          throw StateError('Önce Google Form oluşturun.');
        }
        final formId = formlar.single['Id'] as int;
        final sonuc = <int, String>{};
        final random = Random.secure();
        for (final id in ids) {
          await _ogrenciKontrol(tx, atama, id, yazma: true);
          final mevcut = await tx.query(
            'RehberlikFormDavet',
            where: 'FormId=? AND OgrenciId=?',
            whereArgs: [formId, id],
            limit: 1,
          );
          if (mevcut.isNotEmpty) continue;
          final kod = List.generate(
            16,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
          await tx.insert('RehberlikFormDavet', {
            'FormId': formId,
            'OgrenciId': id,
            'KodOzeti': sha256.convert(utf8.encode(kod)).toString(),
            'SonGecerlilikTarihi': DateTime.now()
                .add(const Duration(days: 30))
                .toIso8601String(),
            'OlusturmaTarihi': DateTime.now().toIso8601String(),
          });
          if (baglantiSablonu != null) {
            await tx.insert('UygulamaAyarlari', {
              'Anahtar': 'rehberlik_google_davet_link:$formId:$id',
              'Deger': googleDavetBaglantisi(baglantiSablonu, kod),
              'GuncellemeTarihi': DateTime.now().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          sonuc[id] = kod;
        }
        return Map<int, String>.unmodifiable(sonuc);
      }),
    );
  }

  /// Davet bağlantısı kimlik doğrulaması değildir. Erişim sınıfla sınırlandırılır.
  Future<Map<String, Object?>> googleSinifDurumu(
    BireyselRehberlikBaglami b,
    int atamaId, {
    bool davetleriDahilEt = true,
  }) async {
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atamaId);
      final forms = await _googleSinifFormlari(tx, b, a);
      if (forms.isEmpty) {
        return {
          'davetler': <Map<String, Object?>>[],
          'yanitlar': <Map<String, Object?>>[],
        };
      }
      final id = forms.single['Id'];
      final davetler = !davetleriDahilEt
          ? <Map<String, Object?>>[]
          : await tx.query(
              'RehberlikFormDavet',
              where: 'FormId=?',
              whereArgs: [id],
            );
      final sonuc = <Map<String, Object?>>[];
      for (final d in davetler) {
        final link = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: ['rehberlik_google_davet_link:$id:${d['OgrenciId']}'],
        );
        sonuc.add({
          ...d,
          'Baglanti': link.isEmpty ? null : link.single['Deger'],
        });
      }
      return {
        'davetler': sonuc,
        'yanitlar': await tx.query(
          'RehberlikGoogleYanit',
          where: 'FormId=?',
          whereArgs: [id],
        ),
      };
    });
  }

  /// Davet kodundan sadece öğrenci adayı döndürür; veli kimliği değildir.
  Future<void> googleMevcutDavetiSurdur(
    BireyselRehberlikBaglami b,
    int atamaId,
    int ogrenciId,
    String baglanti, {
    required bool sureyiUzat,
  }) async {
    final uri = Uri.tryParse(baglanti);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'docs.google.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment) {
      throw const FormatException('Google davet bağlantısını kontrol edin.');
    }
    final entries = uri.queryParametersAll.entries
        .where((e) => RegExp(r'^entry\.[0-9]+$').hasMatch(e.key))
        .toList();
    if (entries.length != 1 || entries.single.value.length != 1) {
      throw const FormatException(
        'Yalnız öğrenci davet alanını içeren bağlantıyı kullanın.',
      );
    }
    final kod = entries.single.value.single.trim().toLowerCase();
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atamaId, yazma: true);
        await _ogrenciKontrol(tx, a, ogrenciId, yazma: true);
        final forms = await tx.query(
          'RehberlikGoogleForm',
          where: 'AtamaId=?',
          whereArgs: [atamaId],
        );
        if (forms.isEmpty) throw StateError('Form kaydı bulunamadı.');
        final formId = forms.single['Id'];
        final sablon = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: ['rehberlik_google_davet_sablonu:$atamaId'],
        );
        if (sablon.isEmpty ||
            Uri.parse(sablon.single['Deger'] as String).path != uri.path) {
          throw const FormatException('Bağlantı bu sınıfın formuna ait değil.');
        }
        final ornek = Uri.parse(sablon.single['Deger'] as String)
            .queryParameters
            .entries
            .where((e) => e.value == _davetSablonOrnegi)
            .toList();
        if (ornek.length != 1 || entries.single.key != ornek.single.key) {
          throw const FormatException(
            'Bağlantı doğru öğrenci davet alanına ait değil.',
          );
        }
        final rows = await tx.query(
          'RehberlikFormDavet',
          where: 'FormId=? AND OgrenciId=? AND KodOzeti=?',
          whereArgs: [
            formId,
            ogrenciId,
            sha256.convert(utf8.encode(kod)).toString(),
          ],
        );
        if (rows.length != 1) {
          throw StateError(
            'Bu bağlantı seçilen öğrencinin mevcut davetine ait değil.',
          );
        }
        await tx.insert('UygulamaAyarlari', {
          'Anahtar': 'rehberlik_google_davet_link:$formId:$ogrenciId',
          'Deger': baglanti,
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (sureyiUzat) {
          await tx.update(
            'RehberlikFormDavet',
            {
              'SonGecerlilikTarihi': DateTime.now()
                  .add(const Duration(days: 30))
                  .toIso8601String(),
              'IptalTarihi': null,
            },
            where: 'Id=?',
            whereArgs: [rows.single['Id']],
          );
        }
      }),
    );
  }

  Future<int?> googleYanitOgrenciAdayi(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    String kod,
  ) async {
    final temiz = kod.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(temiz)) return null;
    final db = await _db();
    return db.transaction((tx) async {
      final atama = await _atama(tx, baglam, atamaId);
      final forms = await _googleSinifFormlari(tx, baglam, atama);
      if (forms.isEmpty) return null;
      final rows = await tx.rawQuery(
        '''SELECT d.OgrenciId, d.SonGecerlilikTarihi, d.IptalTarihi
        FROM RehberlikFormDavet d
        JOIN RehberlikGoogleForm f ON f.Id=d.FormId
        WHERE f.Id=? AND d.KodOzeti=?''',
        [forms.single['Id'], sha256.convert(utf8.encode(temiz)).toString()],
      );
      if (rows.length != 1 || rows.single['IptalTarihi'] != null) return null;
      final son = rows.single['SonGecerlilikTarihi'];
      if (son != null &&
          DateTime.parse(son as String).isBefore(DateTime.now())) {
        return null;
      }
      final id = rows.single['OgrenciId'] as int;
      await _ogrenciKontrol(tx, atama, id);
      return id;
    });
  }

  /// Kod kimlik doğrulaması değildir: doğru öğrenci ve veli öğretmen
  /// tarafından ayrıca kontrol edilir. Süresi geçen/iptal edilen reddedilir.
  Future<int> googleDavetKoduDogrula(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    int ogrenciId,
    String kod,
  ) async {
    final temizKod = kod.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(temizKod)) {
      throw const FormatException('Yanıtta geçerli öğrenci davet kodu yok.');
    }
    final db = await _db();
    return db.transaction((tx) async {
      final atama = await _atama(tx, baglam, atamaId);
      await _ogrenciKontrol(tx, atama, ogrenciId);
      final ozet = sha256.convert(utf8.encode(temizKod)).toString();
      final davetler = await tx.rawQuery(
        '''SELECT d.Id, d.SonGecerlilikTarihi, d.IptalTarihi
        FROM RehberlikFormDavet d
        JOIN RehberlikGoogleForm f ON f.Id=d.FormId
        WHERE f.AtamaId=? AND d.OgrenciId=? AND d.KodOzeti=?''',
        [atamaId, ogrenciId, ozet],
      );
      if (davetler.length != 1 ||
          davetler.single['IptalTarihi'] != null ||
          (davetler.single['SonGecerlilikTarihi'] != null &&
              DateTime.parse(
                davetler.single['SonGecerlilikTarihi'] as String,
              ).isBefore(DateTime.now()))) {
        throw StateError(
          'Davet kodu bu öğrenciye ait değil, iptal edilmiş veya süresi dolmuş.',
        );
      }
      return davetler.single['Id'] as int;
    });
  }

  static const _davetSablonOrnegi = 'OKUL_DAVET_KODU';
  String googleDavetBaglantisi(String sablon, String davetKodu) {
    final uri = Uri.tryParse(sablon);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'docs.google.com' ||
        !uri.path.contains('/forms/') ||
        !uri.path.endsWith('/viewform')) {
      throw const FormatException(
        'Google Forms ön doldurulmuş bağlantısı geçersiz.',
      );
    }
    final uygun = uri.queryParameters.entries
        .where(
          (e) =>
              RegExp(r'^entry\.[0-9]+$').hasMatch(e.key) &&
              e.value == _davetSablonOrnegi,
        )
        .toList();
    if (uygun.length != 1) {
      throw const FormatException(
        'Google Formda davet kodu alanına OKUL_DAVET_KODU yazıp ön doldurulmuş bağlantıyı alın.',
      );
    }
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            uygun.single.key: davetKodu,
          },
        )
        .toString();
  }

  Future<void> googleDavetSablonuKaydet(
    BireyselRehberlikBaglami baglam,
    int atamaId,
    String sablon,
  ) async {
    googleDavetBaglantisi(sablon, 'a' * 32);
    if (sablon.length > 3000) {
      throw const FormatException('Davet bağlantısı fazla uzun.');
    }
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        await _atama(tx, baglam, atamaId, yazma: true);
        final row = {
          'Anahtar': 'rehberlik_google_davet_sablonu:$atamaId',
          'Deger': sablon,
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        };
        final mevcut = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [row['Anahtar']],
          limit: 1,
        );
        if (mevcut.isEmpty) {
          await tx.insert('UygulamaAyarlari', row);
        } else {
          await tx.update(
            'UygulamaAyarlari',
            row,
            where: 'Anahtar=?',
            whereArgs: [row['Anahtar']],
          );
        }
      }),
    );
  }

  Future<String?> googleDavetSablonuGetir(
    BireyselRehberlikBaglami baglam,
    int atamaId,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _atama(tx, baglam, atamaId);
      final rows = await tx.query(
        'UygulamaAyarlari',
        where: 'Anahtar=?',
        whereArgs: ['rehberlik_google_davet_sablonu:$atamaId'],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.single['Deger'] as String?;
    });
  }
}
