part of 'mesajlasma_service.dart';

extension MesajSablonIslemleri on MesajlasmaService {
  String _sablonAnahtari(MesajBaglami b) =>
      'mesaj_sablonlari:${jsonEncode([b.okulId, b.ogretmenId])}';

  Future<MesajSablonListesi> _sablonlariOku(
    DatabaseExecutor db,
    MesajBaglami b,
  ) async {
    final key = _sablonAnahtari(b);
    final rows = await db.query(
      'UygulamaAyarlari',
      where: 'Anahtar=?',
      whereArgs: [key],
    );
    final ham = rows.isEmpty ? null : rows.single['Deger'] as String;
    if (ham == null) {
      return MesajSablonListesi(key, null, varsayilanMesajSablonlari);
    }
    final paket = jsonDecode(ham) as Map;
    if (paket['surum'] != 1) {
      throw StateError('Hazır mesaj kayıt sürümü desteklenmiyor.');
    }
    final liste = (paket['mesajlar'] as List)
        .map((r) => MesajSablonu.oku(Map<String, dynamic>.from(r as Map)))
        .toList();
    return MesajSablonListesi(key, ham, liste);
  }

  Future<MesajSablonListesi> hazirMesajlariGetir(MesajBaglami b) async =>
      (await _db()).transaction((tx) async {
        await _kontrol(tx, b);
        final sonuc = await _sablonlariOku(tx, b);
        await _kontrol(tx, b);
        return sonuc;
      });

  Future<MesajSablonListesi> hazirMesajKaydet(
    MesajBaglami b, {
    required MesajSablonListesi beklenen,
    MesajSablonu? eski,
    required MesajKisiTuru tur,
    required String baslik,
    required String metin,
  }) {
    final ad = baslik.trim(), mesaj = metin.trim();
    return _sablonlariDegistir(b, beklenen, (liste) {
      if (ad.isEmpty ||
          ad.length > 100 ||
          mesaj.isEmpty ||
          mesaj.length > 4000) {
        throw const FormatException(
          'Başlık 1–100, mesaj 1–4000 karakter olmalıdır.',
        );
      }
      final degiskenler = RegExp(
        r'\{[^{}]*\}',
      ).allMatches(mesaj).map((m) => m.group(0)!);
      if (degiskenler.any(
            (d) => !{'{Tarih}', '{Sinif}', '{OgrenciAdi}'}.contains(d),
          ) ||
          RegExp(r'[{}]').hasMatch(
            mesaj.replaceAll(RegExp(r'\{(?:Tarih|Sinif|OgrenciAdi)\}'), ''),
          )) {
        throw const FormatException(
          'Yalnız {Tarih}, {Sinif}, {OgrenciAdi} değişkenleri kullanılabilir.',
        );
      }
      if (tur == MesajKisiTuru.ogretmen && mesaj.contains('{OgrenciAdi}')) {
        throw const FormatException(
          'Öğretmen mesajında öğrenci adı değişkeni kullanılamaz.',
        );
      }
      if (liste.any(
        (s) =>
            s.id != eski?.id &&
            s.tur == tur &&
            importNormalize(s.baslik) == importNormalize(ad),
      )) {
        throw StateError('Bu alıcı grubunda aynı başlık zaten var.');
      }
      if (eski != null && !liste.any((s) => s.id == eski.id)) {
        throw StateError(
          'Hazır mesaj değişmiş veya silinmiş; listeyi yenileyin.',
        );
      }
      final yeni = MesajSablonu(
        eski?.id ?? MesajFormIslemleri._id(),
        tur,
        ad,
        mesaj,
      );
      final sonuc = [
        for (final s in liste)
          if (s.id != eski?.id) s,
        yeni,
      ];
      if (sonuc.where((s) => s.tur == tur).length > 100) {
        throw StateError(
          'Bir alıcı grubunda en fazla 100 hazır mesaj olabilir.',
        );
      }
      return sonuc;
    });
  }

  Future<MesajSablonListesi> hazirMesajSil(
    MesajBaglami b, {
    required MesajSablonListesi beklenen,
    required MesajSablonu eski,
  }) => _sablonlariDegistir(b, beklenen, (liste) {
    if (!liste.any((s) => s.id == eski.id)) {
      throw StateError('Hazır mesaj zaten silinmiş.');
    }
    return liste.where((s) => s.id != eski.id).toList();
  });

  Future<MesajSablonListesi> _sablonlariDegistir(
    MesajBaglami b,
    MesajSablonListesi beklenen,
    List<MesajSablonu> Function(List<MesajSablonu>) degistir,
  ) => _sirali(
    () async => (await _db()).transaction((tx) async {
      await _kontrol(tx, b);
      final simdi = await _sablonlariOku(tx, b);
      if (simdi.kapsam != beklenen.kapsam || simdi.kayit != beklenen.kayit) {
        throw StateError(
          'Hazır mesajlar değişti; listeyi yenileyip tekrar deneyin.',
        );
      }
      final liste = degistir(simdi.sablonlar);
      final ham = jsonEncode({
        'surum': 1,
        'mesajlar': liste.map((s) => s.json).toList(),
      });
      final row = {
        'Anahtar': simdi.kapsam,
        'Deger': ham,
        'GuncellemeTarihi': DateTime.now().toUtc().toIso8601String(),
      };
      if (simdi.kayit == null) {
        await tx.insert('UygulamaAyarlari', row);
      } else {
        await tx.update(
          'UygulamaAyarlari',
          row,
          where: 'Anahtar=?',
          whereArgs: [simdi.kapsam],
        );
      }
      await _kontrol(tx, b);
      return MesajSablonListesi(simdi.kapsam, ham, liste);
    }),
  );
}
