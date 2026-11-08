part of 'bireysel_bilgi_toplama_service.dart';

const bilgiFormSablonlari = <String, String>{
  'Bilgi': 'Öğrenci ve veli bilgileri',
  'Katilim': 'Toplantı katılımı',
  'Anket': 'Anket / geri bildirim',
  'Bos': 'Boş form',
};

/// Mevcut ayarlar yedekleme kapsamındadır; tablo veya yıkıcı göç gerektirmez.
extension BilgiToplamaYonetim on BireyselBilgiToplamaService {
  Future<Map<String, dynamic>> yonetim(BilgiToplamaOturumu b, int id) =>
      _islem(b, (tx) async {
        await _form(tx, b, id);
        return _yonetimOku(tx, id);
      });

  Future<Map<String, dynamic>> _yonetimOku(DatabaseExecutor tx, int id) async {
    final r = await tx.query(
      'UygulamaAyarlari',
      where: 'Anahtar=?',
      whereArgs: ['bilgi_form_yonetim:$id'],
    );
    return r.isEmpty
        ? <String, dynamic>{'sablon': 'Bilgi'}
        : Map<String, dynamic>.from(
            jsonDecode(r.single['Deger'] as String) as Map,
          );
  }

  Future<void> _yonetimYaz(
    DatabaseExecutor tx,
    int id,
    Map<String, dynamic> v,
  ) => tx
      .insert('UygulamaAyarlari', {
        'Anahtar': 'bilgi_form_yonetim:$id',
        'Deger': jsonEncode(v),
        'GuncellemeTarihi': BireyselBilgiToplamaService._simdi(),
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  Future<void> sablonKaydet(BilgiToplamaOturumu b, int id, String sablon) =>
      _islem(b, (tx) async {
        final f = await _form(tx, b, id);
        if (!bilgiFormSablonlari.containsKey(sablon) ||
            f['Durum'] != 'Taslak') {
          throw StateError('Şablon yalnız taslakta seçilir.');
        }
        final v = await _yonetimOku(tx, id);
        v['sablon'] = sablon;
        await _yonetimYaz(tx, id, v);
      });

  Future<void> yayinDurumuKaydet(
    BilgiToplamaOturumu b,
    int id,
    String googleId,
    bool acik,
  ) => _islem(b, (tx) async {
    final f = await _form(tx, b, id);
    if (f['GoogleFormId'] != googleId || f['Durum'] == 'Taslak') {
      throw StateError('Form bağlantısı değişti.');
    }
    final v = await _yonetimOku(tx, id);
    v['yayinAcik'] = acik;
    if (acik) {
      v['yayinlandi'] = true;
    }
    v['yayinKontrolTarihi'] = BireyselBilgiToplamaService._simdi();
    if (acik) {
      v.remove('arsiv');
      v.remove('tamam');
    }
    await tx.update(
      'BilgiToplamaForm',
      {
        'Durum': acik ? 'Aktif' : 'Kapali',
        'GuncellemeTarihi': BireyselBilgiToplamaService._simdi(),
      },
      where: 'Id=?',
      whereArgs: [id],
    );
    await _yonetimYaz(tx, id, v);
  });

  Future<void> isaretle(BilgiToplamaOturumu b, int id, String islem) =>
      _islem(b, (tx) async {
        final f = await _form(tx, b, id);
        final v = await _yonetimOku(tx, id);
        switch (islem) {
          case 'Arşivle':
          case 'Tamamla':
            if (f['Durum'] != 'Kapali' || v['yayinAcik'] != false) {
              throw StateError('Önce Google’da yanıt alımını kapatın.');
            }
            v[islem == 'Arşivle' ? 'arsiv' : 'tamam'] = true;
            break;
          case 'Arşivden çıkar':
            v.remove('arsiv');
            break;
          default:
            throw ArgumentError('Geçersiz durum işlemi.');
        }
        await _yonetimYaz(tx, id, v);
      });

  Future<Map<String, dynamic>> formOzeti(BilgiToplamaOturumu b, int id) =>
      _islem(b, (tx) async {
        final f = await _form(tx, b, id), m = await _yonetimOku(tx, id);
        final hedef = await tx.query(
          'BilgiToplamaHedef',
          where: 'FormId=?',
          whereArgs: [id],
        );
        final yy = await _gorunenYanitlar(tx, id);
        final son = <String, Map<String, Object?>>{};
        for (final y in yy) {
          son.putIfAbsent(y['GoogleYanitId'] as String, () => y);
        }
        final bagRows = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: ['bilgi_form_alicilari:$id'],
        );
        final baglar = bagRows.isEmpty
            ? <String>{}
            : (jsonDecode(bagRows.single['Deger'] as String) as List)
                  .cast<String>()
                  .toSet();
        final turler = baglar.map((k) => k.split(':').first).toSet();
        final esitlenebilir =
            turler.length <= 1 && !turler.contains('Ogretmen');
        final kapsam = await _kapsam(tx, b);
        final hedefIds = hedef.map((h) => h['OgrenciId'] as int).toSet();
        final yanitlayan = <int>{};
        String? sonTarih;
        var eslesmeyen = 0;
        for (final y in son.values) {
          final raw = jsonDecode(y['HamYanit'] as String) as Map;
          final t = raw['lastSubmittedTime'] ?? raw['createTime'];
          if (t is String &&
              DateTime.tryParse(t) != null &&
              (sonTarih == null ||
                  DateTime.parse(t).isAfter(DateTime.parse(sonTarih)))) {
            sonTarih = t;
          }
          final aday = kapsam
              .where(
                (o) =>
                    hedefIds.contains(o['OgrenciId']) &&
                    '${o['OkulNo']}'.trim() == '${y['GirilenOkulNo']}'.trim() &&
                    '${o['Ad']} ${o['Soyad']}'.trim().toLowerCase() ==
                        '${y['GirilenAdSoyad']}'.trim().toLowerCase() &&
                    '${o['SinifKodu']}'.trim().toLowerCase() ==
                        '${y['GirilenSinif']}'.trim().toLowerCase(),
              )
              .toList();
          final oid = y['OgrenciId'] as int?;
          if (oid != null && hedefIds.contains(oid)) {
            yanitlayan.add(oid);
          } else if (aday.length == 1) {
            yanitlayan.add(aday.single['OgrenciId'] as int);
          } else {
            eslesmeyen++;
          }
        }
        final pay = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=? AND Deger=?',
          whereArgs: ['bilgi_toplama_paylasildi:$id', f['GoogleFormId']],
        );
        return {
          ...m,
          'durum': m['arsiv'] == true
              ? 'Arşiv'
              : m['tamam'] == true
              ? 'Tamamlandı'
              : (f['Durum'] == 'Taslak' ||
                    (m['yayinlandi'] != true && pay.isEmpty && son.isEmpty))
              ? 'Taslak'
              : 'Yanıt bekleniyor',
          'paylasimBaslatildi': pay.isNotEmpty,
          'beklenen': esitlenebilir ? hedefIds.length : null,
          'yanitlayan': esitlenebilir ? yanitlayan.length : null,
          'yanitlayanIds': yanitlayan.toList(),
          'beklenenIds': hedefIds.toList(),
          'eslesmeyen': eslesmeyen,
          'yanitSayisi': son.length,
          'sonYanit': sonTarih,
          'aliciGrubu': turler.contains('Ogretmen')
              ? 'Öğretmen'
              : turler.contains('Veli')
              ? 'Veli'
              : turler.contains('Ogrenci')
              ? 'Öğrenci'
              : 'Seçilmedi',
        };
      });

  Future<Map<String, Map<String, int>>> sayisalOzet(
    BilgiToplamaOturumu b,
    int id,
  ) => _islem(b, (tx) async {
    await _form(tx, b, id);
    final sorular = await tx.query(
      'BilgiToplamaSoru',
      where: 'FormId=?',
      whereArgs: [id],
      orderBy: 'Sira',
    );
    final yy = await _gorunenYanitlar(tx, id);
    final son = <String, Map<String, Object?>>{};
    for (final y in yy) {
      son.putIfAbsent(y['GoogleYanitId'] as String, () => y);
    }
    final sonuc = <String, Map<String, int>>{};
    for (final q in sorular.where(
      (s) => {'Secenek', 'EvetHayir', 'Sayi'}.contains(s['VeriTuru']),
    )) {
      final sayilar = <String, int>{};
      for (final y in son.values) {
        try {
          final v = BireyselBilgiToplamaService._cevap(
            jsonDecode(y['HamYanit'] as String) as Map,
            q,
          ).trim();
          if (v.isNotEmpty) sayilar[v] = (sayilar[v] ?? 0) + 1;
        } on FormatException {
          /* Desteklenmeyen yanıt sayılmaz. */
        }
      }
      sonuc[q['Baslik'] as String] = sayilar;
    }
    return sonuc;
  });
}
