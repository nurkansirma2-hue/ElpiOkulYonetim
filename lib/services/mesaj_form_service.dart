part of 'mesajlasma_service.dart';

extension MesajFormIslemleri on MesajlasmaService {
  static Map<String, dynamic> cevapDosyasiOku(String text, String formId) {
    if (text.length > 100000) {
      throw const FormatException('Cevap dosyası çok büyük.');
    }
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic> ||
        raw['formId'] != formId ||
        raw['cevapId'] is! String ||
        raw['yanitlayan'] is! String ||
        raw['sinifGorusu'] is! String ||
        raw['ogrenciGorusleri'] is! Map ||
        (raw['ogrenciGorusleri'] as Map).entries.any(
          (e) => e.key is! String || e.value is! String,
        )) {
      throw const FormatException(
        'Cevap dosyası biçimi veya talep kodu geçersiz.',
      );
    }
    return raw;
  }

  Future<String> cevapSablonu(MesajBaglami b, String id) async {
    final f = await _form(await _db(), b, id);
    return const JsonEncoder.withIndent('  ').convert({
      'formId': id,
      'cevapId': _id(),
      'yanitlayan': '',
      'sinifGorusu': '',
      'ogrenciGorusleri': {
        for (final o in jsonDecode(f['Ogrenciler'] as String) as List)
          o['id'].toString(): '',
      },
    });
  }

  static String _id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Future<Map<String, Object?>> _form(
    DatabaseExecutor tx,
    MesajBaglami b,
    String id, {
    String? egitimOgretimYili,
  }) async {
    await _kontrol(tx, b);
    final rows = await tx.query(
      'MesajForm',
      where: 'Id=? AND OkulId=? AND OgretmenProfilId=? AND EgitimOgretimYili=?',
      whereArgs: [id, b.okulId, b.ogretmenId, egitimOgretimYili ?? b.yil],
    );
    if (rows.length != 1) {
      throw StateError('Görüş talebi aktif kapsamınızda bulunmuyor.');
    }
    return rows.single;
  }

  Future<String> formOlustur(
    MesajBaglami b, {
    required String kaynakModul,
    required String kaynakKayit,
    required String baslik,
    required String aliciTuru,
    required Set<int> ogrenciIdleri,
    required bool sinifGeneli,
    required String soru,
  }) async {
    if (!['Ogretmen', 'Ogrenci', 'Veli'].contains(aliciTuru) ||
        baslik.trim().isEmpty ||
        baslik.length > 300 ||
        soru.trim().isEmpty ||
        soru.length > 4000 ||
        kaynakModul.isEmpty ||
        kaynakKayit.isEmpty ||
        (!sinifGeneli && ogrenciIdleri.isEmpty)) {
      throw const FormatException(
        'Talep başlığı, soru, alıcı türü ve değerlendirme kapsamını kontrol edin.',
      );
    }
    final db = await _db();
    return _sirali(
      () => db.transaction((tx) async {
        await _kontrol(tx, b);
        final uygun = await _ogrenciler(tx, b);
        if (ogrenciIdleri.any((id) => !uygun.any((o) => o.id == id))) {
          throw StateError(
            'Seçilen öğrenci güncel ders kapsamınızda bulunmuyor.',
          );
        }
        final id = _id();
        await tx.insert('MesajForm', {
          'Id': id,
          'OkulId': b.okulId,
          'OgretmenProfilId': b.ogretmenId,
          'EgitimOgretimYili': b.yil,
          'KaynakModul': kaynakModul,
          'KaynakKayit': kaynakKayit,
          'Baslik': baslik.trim(),
          'AliciTuru': aliciTuru,
          'SinifGeneli': sinifGeneli ? 1 : 0,
          'Ogrenciler': jsonEncode(
            uygun
                .where((o) => ogrenciIdleri.contains(o.id))
                .map((o) => {'id': o.id, 'ad': o.ad, 'no': o.okulNo})
                .toList(),
          ),
          'Soru': soru.trim(),
          'OlusturmaTarihi': DateTime.now().toIso8601String(),
        });
        await _kontrol(tx, b);
        return id;
      }),
    );
  }

  Future<List<Map<String, Object?>>> formlariGetir(
    MesajBaglami b,
    String modul,
    String kaynak, {
    String? egitimOgretimYili,
  }) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _kontrol(tx, b);
      return tx.query(
        'MesajForm',
        where:
            'OkulId=? AND OgretmenProfilId=? AND EgitimOgretimYili=? AND KaynakModul=? AND KaynakKayit=?',
        whereArgs: [
          b.okulId,
          b.ogretmenId,
          egitimOgretimYili ?? b.yil,
          modul,
          kaynak,
        ],
        orderBy: 'OlusturmaTarihi DESC',
      );
    });
  }

  Future<List<Map<String, Object?>>> cevaplariGetir(
    MesajBaglami b,
    String id, {
    String? egitimOgretimYili,
  }) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _form(tx, b, id, egitimOgretimYili: egitimOgretimYili);
      return tx.query(
        'MesajFormCevap',
        where: 'FormId=?',
        whereArgs: [id],
        orderBy: 'OlusturmaTarihi DESC',
      );
    });
  }

  Future<String> formMetni(MesajBaglami b, String id) async {
    final f = await _form(await _db(), b, id);
    final ogrenciler = jsonDecode(f['Ogrenciler'] as String) as List;
    return '${f['Baslik']}\n${f['Soru']}\nTalep kodu: $id\n'
        '${f['SinifGeneli'] == 1 ? 'Sınıf geneli değerlendirmeniz:\n' : ''}'
        '${ogrenciler.map((o) => "${o['no']} • ${o['ad']}:\n").join()}'
        'Lütfen yanıtınızda talep kodunu ve adınızı belirtin.';
  }

  /// Dışarıdan gelen cevap önce ortak ekranda incelenir; kimlik beyana dayalıdır.
  Future<void> cevapKaydet(
    MesajBaglami b,
    String formId,
    String yanitlayan,
    String sinifGorusu,
    Map<String, String> ogrenciGorusleri, {
    String? cevapId,
  }) async {
    if (yanitlayan.trim().isEmpty ||
        yanitlayan.length > 200 ||
        sinifGorusu.length > 10000 ||
        ogrenciGorusleri.values.any((s) => s.length > 10000) ||
        (sinifGorusu.trim().isEmpty &&
            ogrenciGorusleri.values.every((v) => v.trim().isEmpty))) {
      throw const FormatException(
        'Yanıtlayan ve en az bir değerlendirme girin.',
      );
    }
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final f = await _form(tx, b, formId);
        final ids = (jsonDecode(f['Ogrenciler'] as String) as List)
            .map((o) => o['id'].toString())
            .toSet();
        if ((f['SinifGeneli'] == 0 && sinifGorusu.trim().isNotEmpty) ||
            ogrenciGorusleri.keys.any((id) => !ids.contains(id))) {
          throw StateError('Cevap talebin kapsamı dışında.');
        }
        final id = cevapId ?? _id();
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
          throw const FormatException('Cevap kimliği geçersiz.');
        }
        final eski = await tx.query(
          'MesajFormCevap',
          where: 'Id=?',
          whereArgs: [id],
        );
        final row = {
          'Id': id,
          'FormId': formId,
          'Yanitlayan': yanitlayan.trim(),
          'SinifGorusu': sinifGorusu.trim(),
          'OgrenciGorusleri': jsonEncode(ogrenciGorusleri),
          'OlusturmaTarihi': DateTime.now().toIso8601String(),
        };
        if (eski.isNotEmpty) {
          if ([
            'FormId',
            'Yanitlayan',
            'SinifGorusu',
            'OgrenciGorusleri',
          ].any((k) => eski.single[k] != row[k])) {
            throw StateError(
              'Aynı cevap kimliği farklı içerikle kullanılamaz.',
            );
          }
        } else {
          await tx.insert('MesajFormCevap', row);
        }
        await _kontrol(tx, b);
      }),
    );
  }
}
