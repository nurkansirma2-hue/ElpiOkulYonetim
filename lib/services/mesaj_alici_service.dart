part of 'mesajlasma_service.dart';

/// Mevcut gönderim motorunun kişi çözümleme ve kalıcı alıcı bağları.
extension MesajAliciIslemleri on MesajlasmaService {
  Future<List<Map<String, Object?>>> _mesajSiniflari(
    DatabaseExecutor db,
    MesajBaglami b,
  ) => db.rawQuery(
    '''SELECT DISTINCT s.SinifSubeId, s.SinifKodu FROM SinifSube s
        JOIN GecerliDersProgrami dp ON dp.SinifSubeId=s.SinifSubeId
        WHERE s.Aktif=1 AND s.EgitimOgretimYili=? AND dp.OgretmenProfilId=?
          AND dp.EgitimOgretimYili=? ORDER BY s.SinifKodu''',
    [b.yil, b.ogretmenId, b.yil],
  );

  Future<List<Map<String, Object?>>> mesajSiniflari(MesajBaglami b) async =>
      (await _db()).transaction((tx) async {
        await _kontrol(tx, b);
        return _mesajSiniflari(tx, b);
      });

  Future<List<MesajKisi>> _kisiler(
    DatabaseExecutor db,
    MesajBaglami b, {
    bool eskiVeliVarsayimi = false,
  }) async {
    final sonuc = <MesajKisi>[];
    for (final tur in [MesajKisiTuru.ogrenci, MesajKisiTuru.veli]) {
      for (final o in await _ogrenciler(
        db,
        b,
        ogrenciAlici: tur == MesajKisiTuru.ogrenci,
      )) {
        final iliskiEksik =
            tur == MesajKisiTuru.veli &&
            !o.veliIliskisiTanimli &&
            !eskiVeliVarsayimi;
        sonuc.add(
          MesajKisi(
            tur: tur,
            kisiId: '${o.id}',
            sinifId: o.sinifId,
            ad: iliskiEksik ? 'Veli ilişkisi seçilmemiş' : o.veliAdi,
            telefon: iliskiEksik ? '' : o.telefon,
            aciklama: o.aciklama,
            telefonAciklamasi: iliskiEksik ? null : o.telefonAciklamasi,
            veliTuru: tur == MesajKisiTuru.veli && !iliskiEksik
                ? o.veliTuru
                : null,
          ),
        );
      }
    }
    final siniflar = {
      for (final s in await _mesajSiniflari(db, b))
        s['SinifSubeId']: s['SinifKodu'],
    };
    final ogretmenler = await db.rawQuery(
      '''SELECT k.*, i.SinifSubeId
      FROM MesajOgretmenKisi k JOIN MesajOgretmenSinif i ON i.KisiId=k.KisiId
      WHERE k.OkulId=? AND k.SahipProfilId=? AND k.Aktif=1 AND i.EgitimOgretimYili=?
      ORDER BY k.AdSoyad,k.KisiId,i.SinifSubeId''',
      [b.okulId, b.ogretmenId, b.yil],
    );
    final dersler = await db.rawQuery(
      '''SELECT x.KisiId,x.SinifSubeId,d.DersAdi
      FROM MesajOgretmenSinifDers x JOIN Ders d ON d.DersId=x.DersId
      JOIN MesajOgretmenKisi k ON k.KisiId=x.KisiId
      WHERE k.OkulId=? AND k.SahipProfilId=? AND x.EgitimOgretimYili=? AND d.Aktif=1
      ORDER BY d.DersAdi''',
      [b.okulId, b.ogretmenId, b.yil],
    );
    for (final o in ogretmenler.where(
      (o) => siniflar.containsKey(o['SinifSubeId']),
    )) {
      final dersAdlari = dersler
          .where(
            (d) =>
                d['KisiId'] == o['KisiId'] &&
                d['SinifSubeId'] == o['SinifSubeId'],
          )
          .map((d) => d['DersAdi'])
          .join(', ');
      sonuc.add(
        MesajKisi(
          tur: MesajKisiTuru.ogretmen,
          kisiId: o['KisiId'] as String,
          sinifId: o['SinifSubeId'] as int,
          ad: o['AdSoyad'] as String,
          telefon: o['Telefon'] as String,
          aciklama:
              '${siniflar[o['SinifSubeId']]} • ${dersAdlari.isEmpty ? 'Ders bilgisi yok; Import Merkezi’nden programı yeniden aktarın' : dersAdlari}',
        ),
      );
    }
    return sonuc;
  }

  Future<List<MesajKisi>> aliciAdaylari(
    MesajBaglami b, {
    MesajKisiTuru? tur,
    int? sinifId,
    Set<int>? izinliOgrenciIdleri,
  }) async {
    final izinli = izinliOgrenciIdleri == null
        ? null
        : Set<int>.of(izinliOgrenciIdleri);
    return (await _db()).transaction((tx) async {
      await _kontrol(tx, b);
      return List.unmodifiable(
        (await _kisiler(tx, b)).where(
          (k) =>
              (tur == null || k.tur == tur) &&
              (sinifId == null || k.sinifId == sinifId) &&
              (izinli == null ||
                  (k.tur != MesajKisiTuru.ogretmen &&
                      izinli.contains(int.tryParse(k.kisiId)))),
        ),
      );
    });
  }

  Future<Map<String, Object?>> _ogretmenBilgisi(
    DatabaseExecutor db,
    MesajBaglami b,
    String id,
  ) async {
    final rows = await db.query(
      'MesajOgretmenKisi',
      where: 'KisiId=? AND OkulId=? AND SahipProfilId=? AND Aktif=1',
      whereArgs: [id, b.okulId, b.ogretmenId],
    );
    if (rows.length != 1) {
      throw StateError('Öğretmen iletişim kaydı aktif kapsamınızda değil.');
    }
    return {
      'kisi': rows.single,
      'siniflar': await db.query(
        'MesajOgretmenSinif',
        where: 'KisiId=?',
        whereArgs: [id],
        orderBy: 'EgitimOgretimYili,SinifSubeId',
      ),
    };
  }

  Future<Map<String, Object?>> ogretmenIletisimBilgisi(
    MesajBaglami b,
    String id,
  ) async => (await _db()).transaction((tx) async {
    await _kontrol(tx, b);
    return _ogretmenBilgisi(tx, b, id);
  });

  /// Önceki yıl kaydedilen kişi de yeni yılın doğrulanmış sınıfına bağlanabilir.
  Future<List<Map<String, Object?>>> ogretmenIletisimKayitlari(
    MesajBaglami b,
  ) async => (await _db()).transaction((tx) async {
    await _kontrol(tx, b);
    return tx.query(
      'MesajOgretmenKisi',
      where: 'OkulId=? AND SahipProfilId=? AND Aktif=1',
      whereArgs: [b.okulId, b.ogretmenId],
      orderBy: 'AdSoyad,KisiId',
    );
  });

  /// Bu rehberdeki kişiler uygulama oturumu/profili değildir. Ders ilişkisi
  /// bilinmiyorsa kullanıcı doğrulaması gerekir; isimden ders ilişkisi üretilmez.
  Future<String> ogretmenIletisimKaydet(
    MesajBaglami b, {
    String? id,
    required String ad,
    String telefon = '',
    required Set<int> sinifIdleri,
    required bool sinifIliskileriniDogruladim,
    Map<String, Object?>? onceki,
  }) {
    final siniflar = Set<int>.of(sinifIdleri);
    final eski = onceki == null ? null : jsonEncode(onceki);
    return _sirali(() async {
      if (ad.trim().isEmpty ||
          ad.trim().length > 200 ||
          telefon.trim().length > 50 ||
          (telefon.trim().isNotEmpty &&
              mesajTelefonNormalize(telefon) == null) ||
          siniflar.isEmpty ||
          !sinifIliskileriniDogruladim) {
        throw const FormatException(
          'Öğretmen adını, telefonunu ve doğrulanmış sınıf ilişkilerini kontrol edin.',
        );
      }
      return (await _db()).transaction((tx) async {
        await _kontrol(tx, b);
        final kapsam = (await _mesajSiniflari(
          tx,
          b,
        )).map((r) => r['SinifSubeId']).toSet();
        if (!kapsam.containsAll(siniflar)) {
          throw StateError('Sınıf ders kapsamınızın dışında.');
        }
        final simdi = DateTime.now().toUtc().toIso8601String();
        final key = id ?? MesajFormIslemleri._id();
        if (id == null) {
          await tx.insert('MesajOgretmenKisi', {
            'KisiId': key,
            'OkulId': b.okulId,
            'SahipProfilId': b.ogretmenId,
            'AdSoyad': ad.trim(),
            'Telefon': telefon.trim(),
            'OlusturmaTarihi': simdi,
            'GuncellemeTarihi': simdi,
          });
        } else {
          if (eski == null ||
              eski != jsonEncode(await _ogretmenBilgisi(tx, b, id))) {
            throw StateError(
              'Öğretmen veya sınıf ilişkileri değişti; ekranı yenileyin.',
            );
          }
          await tx.update(
            'MesajOgretmenKisi',
            {
              'AdSoyad': ad.trim(),
              'Telefon': telefon.trim(),
              'GuncellemeTarihi': simdi,
            },
            where: 'KisiId=?',
            whereArgs: [id],
          );
          // Kalan sınıfların ders bağları korunur. Yalnız çıkarılan sınıfları kaldır.
          for (final bag in (await tx.query(
            'MesajOgretmenSinif',
            where: 'KisiId=? AND EgitimOgretimYili=?',
            whereArgs: [id, b.yil],
          ))) {
            if (!siniflar.contains(bag['SinifSubeId'])) {
              await tx.delete(
                'MesajOgretmenSinif',
                where: 'KisiId=? AND SinifSubeId=? AND EgitimOgretimYili=?',
                whereArgs: [id, bag['SinifSubeId'], b.yil],
              );
            }
          }
        }
        for (final sinif in siniflar) {
          if ((await tx.query(
            'MesajOgretmenSinif',
            where: 'KisiId=? AND SinifSubeId=? AND EgitimOgretimYili=?',
            whereArgs: [key, sinif, b.yil],
          )).isNotEmpty) {
            continue;
          }
          await tx.insert('MesajOgretmenSinif', {
            'KisiId': key,
            'SinifSubeId': sinif,
            'EgitimOgretimYili': b.yil,
            'Kaynak': 'ElleDogrulandi',
            'OlusturmaTarihi': simdi,
          });
        }
        await _kontrol(tx, b);
        return key;
      });
    });
  }

  Future<void> kisiTelefonlariniKaydet(
    MesajBaglami b,
    Map<String, String> telefonlar, {
    required List<MesajKisi> beklenen,
    Map<String, String> adlar = const {},
  }) {
    final degerler = Map<String, String>.of(telefonlar),
        isimler = Map<String, String>.of(adlar),
        eski = List<MesajKisi>.of(beklenen);
    return _sirali(() async {
      if (isimler.entries.any(
        (e) =>
            !degerler.containsKey(e.key) ||
            e.value.trim().isEmpty ||
            e.value.trim().length > 200,
      )) {
        throw const FormatException('Veli adını kontrol edin.');
      }
      await (await _db()).transaction((tx) async {
        await _kontrol(tx, b);
        final adaylar = await _kisiler(tx, b);
        // Bütün kayıtlar yazmadan önce kontrol edilir: aynı kişinin farklı
        // sınıflardan seçimi ilk güncellemeden sonra sahte çakışma üretmez.
        final yazilacak = <String, MesajKisi>{};
        for (final e in degerler.entries) {
          if (e.value.trim().length > 50 ||
              mesajTelefonNormalize(e.value) == null) {
            throw const FormatException('Geçerli tek telefon numarası girin.');
          }
          final snapshot = eski.where((k) => k.secimAnahtari == e.key).toList();
          if (snapshot.isEmpty) {
            throw StateError('Telefonun önceki alıcı bilgisi eksik.');
          }
          for (final k in snapshot) {
            if (!adaylar.any(
              (c) =>
                  c.bagAnahtari == k.bagAnahtari &&
                  jsonEncode(c.anlikGoruntu) == jsonEncode(k.anlikGoruntu),
            )) {
              throw StateError(
                'Alıcı, telefon veya veli ilişkisi değişti; yeniden kontrol edin.',
              );
            }
          }
          yazilacak[e.key] = snapshot.first;
        }
        for (final e in yazilacak.entries) {
          final k = e.value;
          if (isimler.containsKey(e.key) && k.tur != MesajKisiTuru.veli) {
            throw const FormatException(
              'Bu işlem yalnız veli adını düzenleyebilir.',
            );
          }
          if (k.tur == MesajKisiTuru.veli && k.veliTuru == null) {
            throw StateError(
              'Telefon girmeden önce öğrencinin veli ilişkisini seçin.',
            );
          }
          final ogretmen = k.tur == MesajKisiTuru.ogretmen;
          final alan = k.tur == MesajKisiTuru.ogrenci
              ? 'Telefon'
              : ogretmen
              ? 'Telefon'
              : k.veliTuru == 'Diger'
              ? 'VeliTelefonu'
              : '${k.veliTuru}Telefon';
          await tx.update(
            ogretmen ? 'MesajOgretmenKisi' : 'Ogrenci',
            {
              alan: degerler[e.key]!.trim(),
              if (isimler.containsKey(e.key))
                (k.veliTuru == 'Diger' ? 'VeliAdi' : '${k.veliTuru}Adi'):
                    isimler[e.key]!.trim(),
              'GuncellemeTarihi': DateTime.now().toUtc().toIso8601String(),
            },
            where: ogretmen ? 'KisiId=?' : 'OgrenciId=?',
            whereArgs: [k.kisiId],
          );
        }
        await _kontrol(tx, b);
      });
    });
  }

  Future<void> _aliciBaginiYaz(
    DatabaseExecutor tx,
    int aliciId,
    MesajKisi k, {
    bool eskiKayit = false,
  }) => tx
      .insert('MesajAliciBag', {
        'AliciId': aliciId,
        'Tur': k.tur.kod,
        'KisiId': k.kisiId,
        'SinifSubeId': k.sinifId,
        'AnlikGoruntu': jsonEncode(k.anlikGoruntu),
        'EskiKayit': eskiKayit ? 1 : 0,
      })
      .then((_) {});

  /// Yeni seçim ekranı için aynı MesajKuyrugu/MesajAlici ve gönderim motoru.
  Future<MesajKuyrugu> kisilerleKuyrukOlustur(
    MesajBaglami b,
    MesajKisiOnIzleme onizleme,
    String metin, {
    required String kaynakModul,
    String? kaynakKayit,
    Set<int>? izinliOgrenciIdleri,
    Map<String, String>? kisiMesajlari,
  }) {
    final secilen = List<MesajKisi>.of(onizleme.secilenler);
    final izinli = izinliOgrenciIdleri == null
        ? null
        : Set<int>.of(izinliOgrenciIdleri);
    final ozel = kisiMesajlari == null
        ? null
        : Map<String, String>.of(kisiMesajlari);
    return _sirali(() async {
      final p = MesajKisiOnIzleme(secilen), text = metin.trim();
      if (text.isEmpty ||
          text.length > 4000 ||
          kaynakModul.trim().isEmpty ||
          kaynakModul.length > 100 ||
          (kaynakKayit?.length ?? 0) > 200 ||
          p.telefonGruplari.isEmpty ||
          p.gecersizler.isNotEmpty) {
        throw const FormatException(
          'Alıcıları ve eksik telefonları kontrol edin; mesaj 1–4000 karakter olmalı.',
        );
      }
      if (izinli != null &&
          secilen.any(
            (k) =>
                k.tur == MesajKisiTuru.ogretmen ||
                !izinli.contains(int.tryParse(k.kisiId)),
          )) {
        throw StateError('Alıcılar kaynak işlemin öğrenci kapsamı dışında.');
      }
      final id = MesajFormIslemleri._id(), db = await _db();
      await db.transaction((tx) async {
        await _kontrol(tx, b);
        final guncel = await _kisiler(tx, b);
        for (final k in secilen) {
          if (!guncel.any(
            (c) =>
                c.bagAnahtari == k.bagAnahtari &&
                jsonEncode(c.anlikGoruntu) == jsonEncode(k.anlikGoruntu),
          )) {
            throw StateError('Alıcı bilgileri değişti. Ön izlemeyi yenileyin.');
          }
        }
        await _kaynakKisiKontrol(tx, b, kaynakModul, kaynakKayit, secilen);
        await tx.insert('MesajKuyrugu', {
          'KuyrukId': id,
          'OkulId': b.okulId,
          'OgretmenProfilId': b.ogretmenId,
          'OgretmenAdi': b.ogretmenAdi,
          'OkulAdi': b.okulAdi,
          'EgitimOgretimYili': b.yil,
          'KaynakModul': kaynakModul.trim(),
          'KaynakKayit': kaynakKayit,
          'Metin': text,
          'OlusturmaTarihi': DateTime.now().toIso8601String(),
        });
        var sira = 0;
        for (final e in p.telefonGruplari.entries) {
          final mesajlar = ozel == null
              ? <String>[]
              : e.value
                    .map((k) => ozel[k.secimAnahtari]?.trim() ?? '')
                    .toSet()
                    .toList();
          if (ozel != null &&
              (mesajlar.contains('') || mesajlar.join('\n\n').length > 4000)) {
            throw const FormatException(
              'Alıcıya özel mesaj eksik veya birleşik mesaj çok uzun.',
            );
          }
          // Aynı telefonda farklı kişi türlerine ait özel içerik otomatik
          // birleştirilmez; yanlış alıcıya özel bağlantı açılmasını önler.
          if (ozel != null &&
              mesajlar.length > 1 &&
              !e.value.every((k) => k.tur == MesajKisiTuru.veli)) {
            throw StateError(
              'Aynı telefondaki farklı alıcı türlerinin özel mesajlarını ayrı hazırlayın.',
            );
          }
          final aliciId = await tx.insert('MesajAlici', {
            'KuyrukId': id,
            'Sira': ++sira,
            'Telefon': e.key,
            'AliciAdi': e.value.map((k) => k.ad).toSet().join(' / '),
            'Ogrenciler': jsonEncode([
              for (final k in e.value)
                {
                  'id': k.tur == MesajKisiTuru.ogretmen
                      ? null
                      : int.parse(k.kisiId),
                  'tur': k.tur.kod,
                  'kisiId': k.kisiId,
                  'sinifId': k.sinifId,
                  'aciklama': k.aciklama,
                  if (ozel != null) 'mesaj': ozel[k.secimAnahtari]!.trim(),
                },
            ]),
          });
          for (final k in e.value) {
            await _aliciBaginiYaz(tx, aliciId, k);
          }
        }
        await _kontrol(tx, b);
      });
      return kuyrukGetir(b, id);
    });
  }

  Future<void> _kaynakKisiKontrol(
    DatabaseExecutor db,
    MesajBaglami b,
    String kaynak,
    String? kayit,
    List<MesajKisi> kisiler,
  ) async {
    if (kaynak == odevBildirimArsivModulu) {
      throw StateError('Arşivlenmiş ödev mesajı yeniden gönderilemez.');
    }
    if (kaynak == 'OdevBildirim') {
      final odev = await db.query(
        'OdevTanim',
        columns: ['OdevId'],
        where:
            'OdevId=? AND OgretmenProfilId=? AND EgitimOgretimYili=? AND Aktif=1',
        whereArgs: [int.tryParse(kayit ?? ''), b.ogretmenId, b.yil],
      );
      if (odev.length != 1) {
        throw StateError(
          'Ödev silinmiş veya kapsamınızdan çıkmış; bildirim gönderilemez.',
        );
      }
    }
    if ({
      MesajlasmaService.formPaylasimOgrenciModulu,
      MesajlasmaService.formPaylasimVeliModulu,
      MesajlasmaService.formDuzeltmeOgrenciModulu,
    }.contains(kaynak)) {
      final tur = kaynak == MesajlasmaService.formPaylasimVeliModulu
          ? MesajKisiTuru.veli
          : MesajKisiTuru.ogrenci;
      if (kisiler.any((k) => k.tur != tur)) {
        throw StateError('Alıcı türü kaynak form ile uyuşmuyor.');
      }
    }
    await _formPaylasimKapsami(
      db,
      b,
      kaynak,
      kayit,
      kisiler
          .where((k) => k.tur != MesajKisiTuru.ogretmen)
          .map((k) => int.parse(k.kisiId)),
    );
  }

  Future<void> _aliciKontrol(
    DatabaseExecutor db,
    MesajBaglami b,
    MesajKuyrugu q,
    MesajAlicisi a,
  ) async {
    await _kontrol(db, b);
    final guncel = await db.query(
      'MesajKuyrugu',
      columns: ['KaynakModul'],
      where: 'KuyrukId=?',
      whereArgs: [q.id],
    );
    if (guncel.length != 1 ||
        guncel.single['KaynakModul'] == odevBildirimArsivModulu) {
      throw StateError(
        'Bu mesaj silindi veya arşivlendi; gönderim başlatılamaz.',
      );
    }

    if (a.baglar.isEmpty) {
      throw StateError(
        'Alıcı kimliği bulunamadı; güncel bilgilerle yeni kuyruk hazırlayın.',
      );
    }
    final adaylar = await _kisiler(
      db,
      b,
      eskiVeliVarsayimi: a.baglar.any((r) => r['EskiKayit'] == 1),
    );
    final secilen = <MesajKisi>[];
    for (final bag in a.baglar) {
      final eslesen = adaylar
          .where(
            (k) =>
                k.tur.kod == bag['Tur'] &&
                k.kisiId == bag['KisiId'] &&
                k.sinifId == bag['SinifSubeId'],
          )
          .toList();
      if (eslesen.length != 1 || eslesen.single.normalizeTelefon != a.telefon) {
        throw StateError(
          'Alıcının telefonu veya ders kapsamı değişti; güncel bilgilerle yeni mesaj hazırlayın.',
        );
      }
      final k = eslesen.single;
      final onceki = jsonDecode(bag['AnlikGoruntu'] as String) as Map;
      if (bag['EskiKayit'] == 1
          ? onceki['aciklama'] != k.aciklama
          : jsonEncode(onceki) != jsonEncode(k.anlikGoruntu)) {
        throw StateError(
          'Alıcı veya veli ilişkisi değişti; ön izlemeyi yenileyin.',
        );
      }
      secilen.add(k);
    }
    await _kaynakKisiKontrol(db, b, q.kaynakModul, q.kaynakKayit, secilen);
    await _kontrol(db, b);
  }
}
