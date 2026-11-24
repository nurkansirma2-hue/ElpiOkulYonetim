part of 'mesajlasma_service.dart';

/// İletişim ana öğrenci kaydındadır; yakınlık mevcut yedeklenen ayarlardadır.
/// Import motoru ortak kalır, burada yalnız veli güncelleme kuralları bulunur.
class _VeliAktarimPaketi {
  _VeliAktarimPaketi(
    this.baglam,
    this.sinifId,
    this.onceki,
    this.degisiklikler,
  );
  final MesajBaglami baglam;
  final int sinifId;
  final Map<int, Map<String, String>> onceki, degisiklikler;
}

extension VeliBilgileriIslemleri on MesajlasmaService {
  static const alanlar = <String, String>{
    'Telefon': 'Öğrenci Tel',
    'AnneAdi': 'Anne Adı',
    'AnneTelefon': 'Anne Tel',
    'BabaAdi': 'Baba Adı',
    'BabaTelefon': 'Baba Tel',
    'VeliTuru': 'Veli Türü',
    'VeliAdi': 'Diğer Veli Adı',
    'VeliYakinlik': 'Diğer Veli Yakınlığı',
    'VeliTelefonu': 'Diğer Veli Telefonu',
  };
  static const kimlikler = <String, String>{
    'OkulId': 'Okul Kimliği',
    'ProfilId': 'Profil Kimliği',
    'Yil': 'Eğitim Yılı',
    'SinifSubeId': 'Sınıf Kimliği',
    'OgrenciId': 'Öğrenci Kimliği',
    'OkulNo': 'Okul No',
    'Ad': 'Ad',
    'Soyad': 'Soyad',
    'SinifKodu': 'Sınıf/Şube',
  };

  String _yakinlikAnahtari(MesajBaglami b, int id) =>
      'ogrenci_veli_yakinlik:${b.okulId}:$id';

  Future<List<Map<String, String>>> _veliSatirlari(
    DatabaseExecutor tx,
    MesajBaglami b,
    int sinifId,
  ) async {
    await _kontrol(tx, b);
    if (!(await _mesajSiniflari(
      tx,
      b,
    )).any((s) => s['SinifSubeId'] == sinifId)) {
      throw StateError('Sınıf ders kapsamınızda değil.');
    }
    final uygun = (await _ogrenciler(
      tx,
      b,
    )).where((o) => o.sinifId == sinifId).toList();
    final sonuc = <Map<String, String>>[];
    for (final o in uygun) {
      final kayit = (await tx.query(
        'Ogrenci',
        where: 'OgrenciId=?',
        whereArgs: [o.id],
      )).single;
      final yakinlik = await tx.query(
        'UygulamaAyarlari',
        where: 'Anahtar=?',
        whereArgs: [_yakinlikAnahtari(b, o.id)],
      );
      sonuc.add({
        'OkulId': b.okulId,
        'ProfilId': '${b.ogretmenId}',
        'Yil': b.yil,
        'SinifSubeId': '$sinifId',
        'SinifKodu': o.sinif,
        for (final k in [
          'OgrenciId',
          'OkulNo',
          'Ad',
          'Soyad',
          'GuncellemeTarihi',
          ...alanlar.keys.where((k) => k != 'VeliYakinlik'),
        ])
          k: (kayit[k] ?? '').toString(),
        'VeliYakinlik': yakinlik.isEmpty
            ? ''
            : yakinlik.single['Deger'].toString(),
      });
    }
    return sonuc;
  }

  Future<List<Map<String, String>>> veliSinifBilgileri(
    MesajBaglami b,
    int sinifId,
  ) async {
    final db = await _db();
    return db.transaction((tx) => _veliSatirlari(tx, b, sinifId));
  }

  Future<Map<int, Map<String, Object?>>> veliFotograflari(
    MesajBaglami b,
    int sinifId,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _kontrol(tx, b);
      final ids = (await _ogrenciler(
        tx,
        b,
      )).where((o) => o.sinifId == sinifId).map((o) => o.id).toSet();
      if (ids.isEmpty) return <int, Map<String, Object?>>{};
      final rows = await tx.rawQuery(
        'SELECT OgrenciId,FotoVerisi,DosyaYolu FROM OgrenciFotograf '
        'WHERE Aktif=1 AND OgrenciId IN (${List.filled(ids.length, '?').join(',')})',
        ids.toList(),
      );
      return {for (final r in rows) r['OgrenciId'] as int: r};
    });
  }

  ImportTanimi veliImportTanimi(MesajBaglami b, int sinifId) => ImportTanimi(
    id: 'ogrenci_veli_iletisim',
    ad: 'Veli Bilgilerini İçe Aktar (Excel)',
    aciklama:
        'Yalnız seçilen sınıfın mevcut kayıtları güncellenir. '
        'Kimlik, okul numarası, ad ve soyad alanlarını değiştirmeyin. '
        'Boş hücreler mevcut bilgileri silmez. Veli türü: Anne / Baba / Diğer. '
        'Diğer için ad, yakınlık ve geçerli telefon gerekir.',
    alanlar: [
      for (final k in ['OkulNo', 'Ad', 'Soyad'])
        ImportAlan(k, kimlikler[k]!, zorunlu: true),
      for (final e in alanlar.entries) ImportAlan(e.key, e.value),
      for (final e in kimlikler.entries.where(
        (e) => !{'OkulNo', 'Ad', 'Soyad'}.contains(e.key),
      ))
        ImportAlan(e.key, e.value, zorunlu: true),
    ],
    hazirla: (rows) => veliOnizle(b, sinifId, rows),
    aktar: veliAktar,
  );

  Future<ImportOnIzleme> veliOnizle(
    MesajBaglami b,
    int sinifId,
    List<ImportKaynakSatiri> kaynaklar, {
    List<Map<String, String>>? beklenen,
  }) async {
    final mevcut = await veliSinifBilgileri(b, sinifId);
    final onceki = {for (final o in mevcut) int.parse(o['OgrenciId']!): o};
    final degisiklikler = <int, Map<String, String>>{};
    final adet = <String, int>{};
    for (final r in kaynaklar) {
      final id = r.degerler['OgrenciId'] ?? '';
      adet[id] = (adet[id] ?? 0) + 1;
    }
    final rows = <ImportKaydi>[];
    for (final r in kaynaklar) {
      final id = int.tryParse(r.degerler['OgrenciId'] ?? '');
      final o = onceki[id];
      final hatalar = <String>[];
      final patch = <String, String>{};
      if (o == null || kimlikler.keys.any((k) => r.degerler[k] != o[k])) {
        hatalar.add(
          'Kimlik veya sınıf eşleşmiyor. Güncel dolu şablonu kullanın.',
        );
      }
      if ((adet[r.degerler['OgrenciId']] ?? 0) > 1) {
        hatalar.add('Aynı öğrenci dosyada birden fazla kez bulunuyor.');
      }
      if (o != null && beklenen != null) {
        final eski = beklenen.where((x) => x['OgrenciId'] == o['OgrenciId']);
        if (eski.length != 1 || !_veliAyni(eski.single, o)) {
          hatalar.add('Kayıt düzenleme sırasında değişti. Listeyi yenileyin.');
        }
      }
      for (final k in alanlar.keys) {
        var v = (r.degerler[k] ?? '').trim();
        if (k == 'VeliTuru' && v == 'Diğer') v = 'Diger';
        if (v.isEmpty || v == o?[k]) continue;
        if (v.length > (k.contains('Telefon') ? 50 : 200)) {
          hatalar.add('${alanlar[k]} çok uzun.');
        }
        if (k.contains('Telefon') && mesajTelefonNormalize(v) == null) {
          hatalar.add('${alanlar[k]} geçersiz.');
        }
        if (k == 'VeliTuru' && !VeliIliskisi.turler.containsKey(v)) {
          hatalar.add('Veli türü Anne, Baba veya Diğer olmalı.');
        }
        patch[k] = v;
      }
      final son = {...?o, ...patch};
      if (patch.isNotEmpty &&
          son['VeliTuru'] == 'Diger' &&
          ((son['VeliAdi'] ?? '').trim().isEmpty ||
              (son['VeliYakinlik'] ?? '').trim().isEmpty ||
              mesajTelefonNormalize(son['VeliTelefonu'] ?? '') == null)) {
        hatalar.add('Diğer veli için ad, yakınlık ve geçerli telefon gerekli.');
      }
      if (id != null && hatalar.isEmpty && patch.isNotEmpty) {
        degisiklikler[id] = Map.unmodifiable(patch);
      }
      rows.add(
        ImportKaydi(
          r.id,
          r.konum,
          {...r.degerler, for (final k in patch.keys) k: patch[k]!},
          durum: hatalar.isNotEmpty
              ? ImportDurumu.hatali
              : patch.isEmpty
              ? ImportDurumu.atlanan
              : ImportDurumu.uygun,
          mesajlar: hatalar.isNotEmpty
              ? hatalar
              : patch.isEmpty
              ? ['Değişiklik yok; mevcut bilgiler korunacak.']
              : [
                  for (final k in patch.keys)
                    '${alanlar[k]}: ${o?[k] ?? ""} → ${patch[k]}',
                ],
        ),
      );
    }
    return ImportOnIzleme(
      rows,
      veri: _VeliAktarimPaketi(b, sinifId, onceki, degisiklikler),
      engeller: rows.any((r) => r.durum == ImportDurumu.hatali)
          ? ['Hatalı satırları düzeltip önizlemeyi yeniden oluşturun.']
          : [],
      bilgiler: [
        'Yeni öğrenci oluşturulmaz. Boş hücreler mevcut bilgileri silmez.',
      ],
    );
  }

  bool _veliAyni(Map<String, String> a, Map<String, String> b) => [
    ...kimlikler.keys,
    ...alanlar.keys,
    'GuncellemeTarihi',
  ].every((k) => a[k] == b[k]);

  Future<ImportOzet> veliAktar(ImportOnIzleme p, Set<String> secimler) async {
    final paket = p.veri;
    if (paket is! _VeliAktarimPaketi ||
        p.engeller.isNotEmpty ||
        secimler.isEmpty ||
        secimler.any(
          (id) => !p.kayitlar.any((r) => r.id == id && r.aktarilabilir),
        )) {
      throw StateError('Geçerli önizleme ve açık kayıt seçimi gerekli.');
    }
    final ids = p.kayitlar
        .where((r) => secimler.contains(r.id))
        .map((r) => int.parse(r.degerler['OgrenciId']!))
        .toSet();
    final db = await _db();
    await db.transaction((tx) async {
      final guncel = {
        for (final o in await _veliSatirlari(tx, paket.baglam, paket.sinifId))
          int.parse(o['OgrenciId']!): o,
      };
      for (final id in ids) {
        if (guncel[id] == null || !_veliAyni(paket.onceki[id]!, guncel[id]!)) {
          throw StateError(
            'Bilgiler veya kapsam değişti. Önizlemeyi yenileyin.',
          );
        }
        final patch = paket.degisiklikler[id];
        if (patch == null) throw StateError('Güncelleme bulunamadı.');
        final veri = <String, Object?>{
          for (final e in patch.entries)
            if (e.key != 'VeliYakinlik') e.key: e.value,
          'GuncellemeTarihi': DateTime.now().toUtc().toIso8601String(),
        };
        await tx.update('Ogrenci', veri, where: 'OgrenciId=?', whereArgs: [id]);
        if (patch.containsKey('VeliYakinlik')) {
          await tx.insert('UygulamaAyarlari', {
            'Anahtar': _yakinlikAnahtari(paket.baglam, id),
            'Deger': patch['VeliYakinlik'],
            'GuncellemeTarihi': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await _kontrol(tx, paket.baglam);
    });
    return ImportOzet(
      eklenen: 0,
      guncellenen: ids.length,
      atlanan: p.kayitlar.length - ids.length,
      hatali: 0,
      mesaj: '${ids.length} öğrencinin iletişim ve veli bilgisi güncellendi.',
    );
  }
}
