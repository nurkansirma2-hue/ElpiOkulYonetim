part of 'bireysel_rehberlik_service.dart';

/// Proje iş akışı mevcut, yedeklenen ayarlarda tutulur. Ana öğrenci, ödev ve
/// ders tablolarını değiştirmez; Google yanıtının ham sürümü korunur.
extension RehberlikProjeOdevIslemleri on BireyselRehberlikService {
  String _projeKey(BireyselRehberlikBaglami b, int atama) =>
      'rehberlik_proje:${jsonEncode([b.okulId, b.ogretmenProfilId, atama])}';

  Future<Map<String, dynamic>> _projeOku(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    int atama,
  ) async {
    final rows = await tx.query(
      'UygulamaAyarlari',
      where: 'Anahtar=?',
      whereArgs: [_projeKey(b, atama)],
    );
    return rows.isEmpty
        ? <String, dynamic>{'talepler': <dynamic>[]}
        : Map<String, dynamic>.from(
            jsonDecode(rows.single['Deger'] as String) as Map,
          );
  }

  Future<void> _projeYaz(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    int atama,
    Map<String, dynamic> veri,
  ) async {
    await tx.insert('UygulamaAyarlari', {
      'Anahtar': _projeKey(b, atama),
      'Deger': jsonEncode(veri),
      'GuncellemeTarihi': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Yalnız seçili proje formunun yerel çalışma yanıtlarını ve proje
  /// onay/dağıtım durumunu sıfırlar. Google Forms üzerinde işlem yapmaz.
  /// Kullanıcı onayı çağıran ekrandan alınır; bütün adımlar tek transaction'dır.
  Future<void> projeYanitlariniSifirla(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
  ) => _projeIslem(b, atama, formId, (tx, a, p) async {
    // Ortak formun düzenlemesi yarım kalmışsa yanlış sürümü temizleme.
    final bekleyen = await tx.query(
      'UygulamaAyarlari',
      where: 'Anahtar=?',
      whereArgs: ['bilgi_toplama_duzenleme:$formId'],
    );
    if (bekleyen.isNotEmpty &&
        (jsonDecode(bekleyen.single['Deger'] as String) as Map)['yerelKaydedildi'] != true) {
      throw StateError('Bekleyen form düzenlemesi tamamlanmadan sıfırlanamaz.');
    }
    // Öğrenci ana bilgilerine aktarılmış bağlı değerler korunmalıdır.
    final aktarilmis = await tx.query(
      'OgrenciEkBilgiDeger',
      columns: ['YanitId'],
      where: 'FormId=?',
      whereArgs: [formId],
      limit: 1,
    );
    if (aktarilmis.isNotEmpty) {
      throw StateError(
        'Bu formun öğrenci bilgilerine aktarılmış kayıtları var. '
        'Veri kaybını önlemek için sıfırlama durduruldu.',
      );
    }
    await tx.delete(
      'BilgiToplamaEsleme',
      where: 'FormId=?',
      whereArgs: [formId],
    );
    await tx.delete(
      'BilgiToplamaYanit',
      where: 'FormId=?',
      whereArgs: [formId],
    );
    // Eski silme işaretleri kalırsa yeniden getirilen Google yanıtları
    // yanlışlıkla atlanabilir. Yalnız bu formun işaretlerini temizle.
    await tx.delete(
      'UygulamaAyarlari',
      where: 'Anahtar LIKE ?',
      whereArgs: ['bilgi_toplama_silinen:$formId:%'],
    );
    p['onaylar'] = <String, dynamic>{};
    p['dagitim'] = <String, dynamic>{};
    p['kontenjan'] = <String, dynamic>{};
    p.remove('dagitimImzalari');
    p.remove('dagitimTarihi');
    p.remove('dagitimOnayli');
    p.remove('sonuclandi');
    p.remove('sonucImzasi');
    p.remove('sonucTarihi');
    p.remove('sonucGecmisi');
  }, yazma: true);

  Future<List<Map<String, Object?>>> projeDersleri(
    BireyselRehberlikBaglami b,
    int atama,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atama);
      final rows = await _projeSinifDersleri(tx, b, a);
      await _kontrol(tx, b);
      return rows;
    });
  }

  Future<List<Map<String, Object?>>> _projeSinifDersleri(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    Map<String, Object?> a,
  ) => tx.rawQuery(
    '''
    SELECT d.DersId,d.DersAdi FROM Ders d WHERE d.Aktif=1 AND (
      EXISTS (SELECT 1 FROM DersSinif s WHERE s.DersId=d.DersId
        AND s.SinifSubeId=? AND s.EgitimOgretimYili=? AND s.Aktif=1)
      OR EXISTS (SELECT 1 FROM GecerliDersProgrami p WHERE p.DersId=d.DersId
        AND p.SinifSubeId=? AND p.EgitimOgretimYili=? AND p.Aktif=1)
      OR EXISTS (SELECT 1 FROM MesajOgretmenSinifDers m
        JOIN MesajOgretmenKisi k ON k.KisiId=m.KisiId
        WHERE m.DersId=d.DersId AND m.SinifSubeId=? AND m.EgitimOgretimYili=?
          AND k.OkulId=? AND k.SahipProfilId=? AND k.Aktif=1))
    ORDER BY d.DersAdi,d.DersId''',
    [
      a['SinifSubeId'],
      a['EgitimOgretimYili'],
      a['SinifSubeId'],
      a['EgitimOgretimYili'],
      a['SinifSubeId'],
      a['EgitimOgretimYili'],
      b.okulId,
      b.ogretmenProfilId,
    ],
  );

  Future<List<Map<String, dynamic>>> projeTalepleri(
    BireyselRehberlikBaglami b,
    int atama,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _atama(tx, b, atama);
      final v = await _projeOku(tx, b, atama);
      final formlar = await tx.query(
        'BilgiToplamaForm',
        columns: ['Id'],
        where: '''OkulId=? AND OgretmenProfilId=?
          AND NOT EXISTS (SELECT 1 FROM UygulamaAyarlari a
            WHERE a.Anahtar='bilgi_toplama_form_silinen:' || BilgiToplamaForm.Id)''',
        whereArgs: [b.okulId, b.ogretmenProfilId],
      );
      final izinli = formlar.map((f) => f['Id']).toSet();
      await _kontrol(tx, b);
      return (v['talepler'] as List)
          .where((p) => izinli.contains(p['formId']))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  /// Form ortak servisle oluşturulur. Bağ yalnız aynı okul/profil/yıl ve sınıf
  /// hedefleri, anlık ders seçenekleri ve zorunlu üç tercih doğrulanınca kurulur.
  Future<void> projeFormunuBagla(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    Map<int, String> dersler,
    String aciklama, {
    String? sonGun,
  }) async {
    if (aciklama.length > 1500 ||
        (sonGun != null && DateTime.tryParse(sonGun) == null)) {
      throw const FormatException('Açıklama veya son gün geçersiz.');
    }
    final kopya = Map<int, String>.of(dersler);
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atama, yazma: true);
        if (kopya.length < 3 ||
            kopya.length > 100 ||
            kopya.keys.contains(0) ||
            kopya.values.any(
              (ad) => ad.trim().isEmpty || ad != ad.trim() || ad.length > 200,
            ) ||
            kopya.values.map(importNormalize).toSet().length != kopya.length) {
          throw const FormatException(
            'En az üç farklı ders seçin; ders adları boş veya tekrarlı olamaz.',
          );
        }
        final f = await tx.query(
          'BilgiToplamaForm',
          where:
              'Id=? AND OkulId=? AND OgretmenProfilId=? AND EgitimOgretimYili=?',
          whereArgs: [
            formId,
            b.okulId,
            b.ogretmenProfilId,
            a['EgitimOgretimYili'],
          ],
        );
        if (f.length != 1) throw StateError('Form kapsamı değişti.');
        await _projeFormKontrol(tx, b, formId);
        final uygun = await _projeSinifDersleri(tx, b, a);
        if (!kopya.entries.every(
          (e) =>
              // Negatif kimlik yalnız bu formda öğretmenin elle eklediği derstir.
              // Ana ders kataloğuna veya başka modüllerin programına yazılmaz.
              e.key < 0 ||
              uygun.any((d) => d['DersId'] == e.key && d['DersAdi'] == e.value),
        )) {
          throw StateError(
            'Dersler sınıfın güncel ders kayıtlarında bulunmuyor. Listeyi yenileyin.',
          );
        }
        final hedefler = await tx.query(
          'BilgiToplamaHedef',
          where: 'FormId=?',
          whereArgs: [formId],
        );
        if (hedefler.isEmpty) throw StateError('Hedef öğrenci yok.');
        for (final h in hedefler) {
          await _ogrenciKontrol(tx, a, h['OgrenciId'] as int, yazma: true);
        }
        final sorular = await tx.query(
          'BilgiToplamaSoru',
          where: 'FormId=?',
          whereArgs: [formId],
        );
        for (var i = 1; i <= 3; i++) {
          final q = sorular.where((q) => q['AlanAnahtari'] == 'projeTercih$i');
          if (q.length != 1 ||
              q.single['Zorunlu'] != 1 ||
              q.single['VeriTuru'] != 'Secenek' ||
              jsonEncode(jsonDecode(q.single['Secenekler'] as String)) !=
                  jsonEncode(kopya.values.toList())) {
            throw StateError('Üç zorunlu ders tercihi form ile uyuşmuyor.');
          }
        }
        if (!sorular.any((q) => q['AlanAnahtari'] == 'ogrenciSecimi')) {
          throw StateError('Öğrenci numarasını içeren kimlik listesi gerekli.');
        }
        final v = await _projeOku(tx, b, atama);
        final talepler = v['talepler'] as List;
        if (talepler.any((p) => p['formId'] == formId)) return;
        talepler.add({
          'formId': formId,
          'baslik': f.single['Baslik'],
          'aciklama': aciklama,
          'sonGun': sonGun,
          'dersler': {for (final e in kopya.entries) '${e.key}': e.value},
          'ogrenciler': hedefler.map((h) => h['OgrenciId']).toList(),
          'onaylar': <String, dynamic>{},
          'dagitim': <String, dynamic>{},
          'kontenjan': <String, dynamic>{},
          'surum': 0,
        });
        await _projeYaz(tx, b, atama, v);
        await _kontrol(tx, b);
      }),
    );
  }

  Future<T> _projeIslem<T>(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    Future<T> Function(Transaction, Map<String, Object?>, Map<String, dynamic>)
    f, {
    bool yazma = false,
  }) async {
    final db = await _db();
    return _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atama, yazma: yazma);
        await _projeFormKontrol(tx, b, formId);
        final v = await _projeOku(tx, b, atama);
        final p = (v['talepler'] as List).where((p) => p['formId'] == formId);
        if (p.length != 1) {
          throw StateError('Proje formu bu atamaya ait değil.');
        }
        final proje = Map<String, dynamic>.from(p.single as Map);
        final result = await f(tx, a, proje);
        if (yazma) {
          final list = v['talepler'] as List;
          list[list.indexWhere((p) => p['formId'] == formId)] = proje;
          proje['surum'] = (proje['surum'] as int) + 1;
          await _projeYaz(tx, b, atama, v);
        }
        await _kontrol(tx, b);
        return result;
      }),
    );
  }

  String _projeCevap(Map raw, Map soru) {
    final duz = raw['_yerelDuzeltme'];
    if (duz is Map && duz['cevaplar'] is Map) {
      return (duz['cevaplar'][soru['AlanAnahtari']] ?? '').toString();
    }
    final a = raw['answers'];
    final cevap = a is Map ? a[soru['GoogleSoruId']] : null;
    final metin = cevap is Map ? cevap['textAnswers'] : null;
    final values = metin is Map ? metin['answers'] : null;
    return values is List && values.length == 1 && values.single is Map
        ? (values.single['value'] ?? '').toString()
        : '';
  }

  Future<void> _projeFormKontrol(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    int formId,
  ) async {
    final rows = await tx.query(
      'BilgiToplamaForm',
      columns: ['Id'],
      where: '''Id=? AND OkulId=? AND OgretmenProfilId=?
        AND NOT EXISTS (SELECT 1 FROM UygulamaAyarlari a
          WHERE a.Anahtar='bilgi_toplama_form_silinen:' || BilgiToplamaForm.Id)''',
      whereArgs: [formId, b.okulId, b.ogretmenProfilId],
    );
    if (rows.length != 1) {
      throw StateError('Proje formu silinmiş veya kapsamınızdan çıkmış.');
    }
  }

  Future<List<Map<String, dynamic>>> _projeTercihler(
    DatabaseExecutor tx,
    Map<String, Object?> a,
    Map<String, dynamic> p,
  ) async {
    final form = p['formId'];
    final ogrenciler = await tx.rawQuery(
      '''SELECT o.OgrenciId,o.OkulNo,o.Ad,o.Soyad,
      o.Aktif AS OgrenciAktif,k.Aktif AS KayitAktif FROM Ogrenci o
      LEFT JOIN OgrenciSinifKayit k ON k.OgrenciId=o.OgrenciId
        AND k.SinifSubeId=? AND k.EgitimOgretimYili=?
      ORDER BY CAST(o.OkulNo AS INTEGER),o.OkulNo,o.OgrenciId''',
      [a['SinifSubeId'], a['EgitimOgretimYili']],
    );
    final yanitlar = await tx.query(
      'BilgiToplamaYanit',
      where: 'FormId=?',
      whereArgs: [form],
      orderBy: 'Id DESC',
    );
    // Ortak Yanıtlar ekranıyla aynı eski-sürüm ve silme denetimi.
    // Yerel düzeltme orijinal Google yanıtını geçmişte tutabilir;
    // eski sürüm ikinci aktif tercih olarak değerlendirilmemelidir.
    final byId = {for (final y in yanitlar) y['Id']: y};
    final eskiSurumler = <int>{};
    for (final y in yanitlar) {
      final raw = jsonDecode(y['HamYanit'] as String) as Map;
      final duzeltme = raw['_yerelDuzeltme'];
      if (duzeltme is! Map) continue;
      final eski = byId[duzeltme['oncekiYanitId']];
      if (eski != null && eski['GoogleYanitId'] == y['GoogleYanitId']) {
        eskiSurumler.add(eski['Id'] as int);
      }
    }
    final son = <String, Map<String, Object?>>{};
    final silinen = (await tx.query(
      'UygulamaAyarlari',
      columns: ['Anahtar'],
      where: 'Anahtar LIKE ?',
      whereArgs: ['bilgi_toplama_silinen:$form:%'],
    )).map((r) => r['Anahtar']).toSet();
    for (final y in yanitlar) {
      final id = y['GoogleYanitId'] as String;
      final ozet = sha256.convert(utf8.encode(jsonEncode(id))).toString();
      final raw = jsonDecode(y['HamYanit'] as String) as Map;
      if (eskiSurumler.contains(y['Id']) ||
          raw['_yerelTemizlendi'] == true ||
          silinen.contains('bilgi_toplama_silinen:$form:$ozet')) {
        continue;
      }
      son.putIfAbsent(id, () => y);
    }
    final eslesen = <int, List<Map<String, Object?>>>{};
    final belirsiz = <Map<String, Object?>>[];
    for (final y in son.values) {
      final raw = jsonDecode(y['HamYanit'] as String) as Map;
      final qs = jsonDecode(y['SoruAnlikGoruntusu'] as String) as List;
      final kimlik = qs.where((q) => q['AlanAnahtari'] == 'ogrenciSecimi');
      int? oid = y['OgrenciId'] as int?;
      if (oid == null && kimlik.length == 1) {
        final secilen = _projeCevap(raw, kimlik.single as Map);
        final opts = (jsonDecode(kimlik.single['Secenekler'] as String) as List)
            .whereType<Map>()
            .where((s) => s['etiket'] == secilen)
            .toList();
        if (opts.length == 1) oid = opts.single['ogrenciId'] as int?;
      }
      if (oid == null || !(p['ogrenciler'] as List).contains(oid)) {
        belirsiz.add(y);
        continue;
      }
      (eslesen[oid] ??= []).add(y);
    }
    final dersler = Map<String, dynamic>.from(p['dersler'] as Map);
    final onaylar = Map<String, dynamic>.from(p['onaylar'] as Map);
    final sonuc = <Map<String, dynamic>>[];
    for (final o in ogrenciler.where(
      (o) => (p['ogrenciler'] as List).contains(o['OgrenciId']),
    )) {
      final oid = o['OgrenciId'] as int;
      final yy = eslesen[oid] ?? [];
      final hatalar = <String>[];
      final tercihler = <int>[];
      String? imza;
      if (yy.isEmpty) {
        hatalar.add('Yanıt bekleniyor.');
      } else if (yy.length != 1) {
        hatalar.add(
          'Aynı öğrenciye ait birden fazla yanıt var. Ortak formdan inceleyin.',
        );
      } else {
        final y = yy.single;
        if (y['Durum'] == 'Reddedildi') {
          hatalar.add('Yanıt ortak formda reddedilmiş.');
        }
        final raw = jsonDecode(y['HamYanit'] as String) as Map;
        final qs = jsonDecode(y['SoruAnlikGoruntusu'] as String) as List;
        imza = '${y['Id']}:${y['KaynakSurum']}';
        for (var i = 1; i <= 3; i++) {
          final q = qs.where((q) => q['AlanAnahtari'] == 'projeTercih$i');
          final cevap = q.length == 1 ? _projeCevap(raw, q.single as Map) : '';
          final ders = dersler.entries.where((e) => e.value == cevap).toList();
          if (ders.length != 1) {
            hatalar.add('$i. ders tercihi eksik veya geçersiz.');
          } else {
            tercihler.add(int.parse(ders.single.key));
          }
        }
        if (tercihler.toSet().length != tercihler.length) {
          hatalar.add('Üç farklı ders seçilmelidir.');
        }
      }
      if (o['OgrenciAktif'] != 1 || o['KayitAktif'] != 1) {
        hatalar.add('Öğrenci kaydı pasif.');
      }
      final onay = onaylar['$oid'];
      sonuc.add({
        ...o,
        'tercihler': tercihler,
        'hatalar': hatalar,
        'imza': imza,
        'yanitId': yy.length == 1 ? yy.single['Id'] : null,
        'onayli': hatalar.isEmpty && onay is Map && onay['imza'] == imza,
        'bekliyor': yy.isEmpty,
      });
    }
    for (final y in belirsiz) {
      sonuc.add({
        'OgrenciId': null,
        'OkulNo': y['GirilenOkulNo'],
        'Ad': y['GirilenAdSoyad'],
        'Soyad': '',
        'tercihler': <int>[],
        'hatalar': ['Öğrenci kimliği eşleşmedi. Ortak formdan inceleyin.'],
        'yanitId': y['Id'],
        'imza': null,
        'onayli': false,
        'bekliyor': false,
      });
    }
    return sonuc;
  }

  Future<List<Map<String, dynamic>>> projeTercihleri(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
  ) => _projeIslem(b, atama, formId, (tx, a, p) => _projeTercihler(tx, a, p));

  Future<void> projeTercihleriniOnayla(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    Map<int, String> imzalar,
  ) {
    final kopya = Map<int, String>.of(imzalar);
    return _projeIslem(b, atama, formId, (tx, a, p) async {
      if (kopya.isEmpty) throw StateError('Geçerli tercih seçin.');
      final rows = await _projeTercihler(tx, a, p);
      for (final e in kopya.entries) {
        final r = rows.singleWhere((r) => r['OgrenciId'] == e.key);
        if ((r['hatalar'] as List).isNotEmpty || r['imza'] != e.value) {
          throw StateError(
            'Tercihler değişti veya hatalı. Yenileyip yeniden kontrol edin.',
          );
        }
        (p['onaylar'] as Map)['${e.key}'] = {
          'imza': e.value,
          'tercihler': r['tercihler'],
        };
      }
      // Değişen onay, eski dağıtımı kesin sonuç gibi göstermez.
      p['dagitimOnayli'] = false;
      p['sonuclandi'] = false;
    }, yazma: true);
  }

  /// Her tercih turunda okul numarası sırası kullanılır. Hiçbir öğrenci tercih
  /// etmediği bir derse otomatik atanmaz. Kapasitesi dolanlar açıkta kalır.
  Future<Map<String, dynamic>> projeDagitimOnizle(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    Map<int, int>? kontenjan,
  ) => _projeIslem(b, atama, formId, (tx, a, p) async {
    final rows = await _projeTercihler(tx, a, p);
    final dersler = (p['dersler'] as Map).keys
        .map((k) => int.parse(k as String))
        .toSet();
    if (kontenjan != null &&
        (kontenjan.length != dersler.length ||
            !dersler.containsAll(kontenjan.keys) ||
            kontenjan.values.any((v) => v < 0))) {
      throw const FormatException(
        'Her ders için sıfır veya pozitif kontenjan girin.',
      );
    }
    final dagitim = <String, int>{};
    final sayilar = {for (final d in dersler) d: 0};
    for (var tercih = 0; tercih < 3; tercih++) {
      for (final r in rows.where((r) => r['onayli'] == true)) {
        final oid = '${r['OgrenciId']}';
        if (dagitim.containsKey(oid)) continue;
        final d = (r['tercihler'] as List)[tercih] as int;
        if (kontenjan == null || sayilar[d]! < kontenjan[d]!) {
          dagitim[oid] = d;
          sayilar[d] = sayilar[d]! + 1;
        }
      }
    }
    return {
      'dagitim': dagitim,
      'surum': p['surum'],
      'imzalar': {
        for (final r in rows.where((r) => r['onayli'] == true))
          '${r['OgrenciId']}': r['imza'],
      },
      'kontenjan': kontenjan == null
          ? null
          : {for (final e in kontenjan.entries) '${e.key}': e.value},
      'acikta': rows
          .where(
            (r) =>
                r['OgrenciId'] != null &&
                !dagitim.containsKey('${r['OgrenciId']}'),
          )
          .length,
    };
  });

  Future<void> projeDagitiminiKaydet(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    Map<String, dynamic> plan,
  ) {
    final kopya = jsonDecode(jsonEncode(plan)) as Map<String, dynamic>;
    return _projeIslem(b, atama, formId, (tx, a, p) async {
      if (p['surum'] != kopya['surum']) {
        throw StateError('Dağıtım değişti. Ön izlemeyi yenileyin.');
      }
      final rows = await _projeTercihler(tx, a, p);
      final imzalar = {
        for (final r in rows.where((r) => r['onayli'] == true))
          '${r['OgrenciId']}': r['imza'],
      };
      if (jsonEncode(imzalar) != jsonEncode(kopya['imzalar'])) {
        throw StateError('Yanıtlar değişti. Yeniden kontrol edin.');
      }
      final dagitim = Map<String, dynamic>.from(kopya['dagitim'] as Map);
      if (dagitim.isEmpty) throw StateError('Dağıtılacak onaylı öğrenci yok.');
      final sayilar = <int, int>{};
      for (final e in dagitim.entries) {
        final r = rows.singleWhere((r) => '${r['OgrenciId']}' == e.key);
        if (r['onayli'] != true ||
            !(r['tercihler'] as List).contains(e.value)) {
          throw StateError('Dağıtım öğrencinin onaylı tercihleri dışında.');
        }
        sayilar[e.value as int] = (sayilar[e.value] ?? 0) + 1;
      }
      final kapasite = kopya['kontenjan'] as Map?;
      final dersler = (p['dersler'] as Map).keys.toSet();
      if (kapasite != null &&
          (kapasite.length != dersler.length ||
              !dersler.containsAll(kapasite.keys) ||
              kapasite.values.any((v) => v is! int || v < 0))) {
        throw const FormatException('Ders kontenjanları geçersiz.');
      }
      if (kapasite != null &&
          sayilar.entries.any(
            (e) =>
                kapasite['${e.key}'] is! int ||
                e.value > (kapasite['${e.key}'] as int),
          )) {
        throw StateError('Kontenjan aşıldı. Dağıtımı düzenleyin.');
      }
      p['dagitim'] = dagitim;
      p['kontenjan'] = kapasite ?? {};
      p['dagitimImzalari'] = imzalar;
      p['dagitimOnayli'] = true;
      p['dagitimTarihi'] = DateTime.now().toUtc().toIso8601String();
      p['sonuclandi'] = false;
    }, yazma: true);
  }

  Future<List<Map<String, Object?>>> projeDersOgretmenleri(
    BireyselRehberlikBaglami b,
    int atama,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atama);
      final rows = await tx.rawQuery(
        '''SELECT DISTINCT d.DersId,k.KisiId,k.AdSoyad AS OgretmenAdi
        FROM MesajOgretmenSinifDers d JOIN MesajOgretmenKisi k ON k.KisiId=d.KisiId
        WHERE d.SinifSubeId=? AND d.EgitimOgretimYili=?
        AND k.OkulId=? AND k.SahipProfilId=? AND k.Aktif=1''',
        [
          a['SinifSubeId'],
          a['EgitimOgretimYili'],
          b.okulId,
          b.ogretmenProfilId,
        ],
      );
      await _kontrol(tx, b);
      return rows;
    });
  }

  String _projeSonucImzasi(
    Map<String, dynamic> p,
    List<Map<String, dynamic>> rows,
  ) {
    final dag = Map<String, dynamic>.from(p['dagitim'] as Map);
    final keys = dag.keys.toList()..sort();
    final ids = rows.where((r) => r['onayli'] == true).toList()
      ..sort(
        (a, b) => (a['OgrenciId'] as int).compareTo(b['OgrenciId'] as int),
      );
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              p['formId'],
              for (final key in keys) [key, dag[key]],
              for (final r in ids) [r['OgrenciId'], r['imza']],
            ]),
          ),
        )
        .toString();
  }

  Future<List<Map<String, Object?>>> _projeOgretmenAdaylari(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    Map<String, Object?> a,
  ) => tx.rawQuery(
    '''
    SELECT k.KisiId,k.AdSoyad FROM MesajOgretmenKisi k
    JOIN MesajOgretmenSinif s ON s.KisiId=k.KisiId
    WHERE k.OkulId=? AND k.SahipProfilId=? AND k.Aktif=1
      AND s.SinifSubeId=? AND s.EgitimOgretimYili=?
    ORDER BY k.AdSoyad,k.KisiId''',
    [b.okulId, b.ogretmenProfilId, a['SinifSubeId'], a['EgitimOgretimYili']],
  );

  Future<Map<String, dynamic>> _projeAnaliz(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    Map<String, Object?> a,
    Map<String, dynamic> p,
  ) async {
    final rows = await _projeTercihler(tx, a, p);
    final dag = Map<String, dynamic>.from(p['dagitim'] as Map);
    final imzalar = Map<String, dynamic>.from(
      p['dagitimImzalari'] as Map? ?? {},
    );
    final onayli = rows.where((r) => r['onayli'] == true).toList();
    final dagGuncel =
        p['dagitimOnayli'] == true &&
        onayli.length == imzalar.length &&
        onayli.every((r) => imzalar['${r['OgrenciId']}'] == r['imza']);
    final imza = _projeSonucImzasi(p, rows);
    final dersler = Map<String, dynamic>.from(p['dersler'] as Map);
    final adaylar = await _projeOgretmenAdaylari(tx, b, a);
    final baglar = await tx.query(
      'MesajOgretmenSinifDers',
      where: 'SinifSubeId=? AND EgitimOgretimYili=?',
      whereArgs: [a['SinifSubeId'], a['EgitimOgretimYili']],
    );
    final eslemeler = Map<String, dynamic>.from(
      p['dersOgretmenleri'] as Map? ?? {},
    );
    final dersAnalizi = <Map<String, dynamic>>[];
    for (final e in dersler.entries) {
      final id = int.parse(e.key);
      final kayitli = eslemeler[e.key] as List?;
      final ogretmenIds =
          kayitli?.cast<String>().toSet() ??
          baglar
              .where((d) => d['DersId'] == id)
              .map((d) => d['KisiId'] as String)
              .toSet();
      dersAnalizi.add({
        'dersId': id,
        'dersAdi': e.value,
        'tercihler': [
          for (var i = 0; i < 3; i++)
            rows
                .where(
                  (r) =>
                      (r['hatalar'] as List).isEmpty &&
                      (r['tercihler'] as List).length > i &&
                      (r['tercihler'] as List)[i] == id,
                )
                .length,
        ],
        'yerlesen': dagGuncel ? dag.values.where((d) => d == id).length : 0,
        'ogretmenler': adaylar
            .where((k) => ogretmenIds.contains(k['KisiId']))
            .toList(),
      });
    }
    final ogrenciler = <Map<String, dynamic>>[];
    for (final r in rows) {
      final dersId = dagGuncel ? dag['${r['OgrenciId']}'] as int? : null;
      final tercihler = (r['tercihler'] as List).cast<int>();
      ogrenciler.add({
        ...r,
        'dersId': dersId,
        'dersAdi': dersler['$dersId'],
        'yerlesmeSirasi': dersId == null ? null : tercihler.indexOf(dersId) + 1,
        'durum': r['bekliyor'] == true
            ? 'Yanıt bekleniyor'
            : (r['hatalar'] as List).isNotEmpty
            ? 'Kontrol gerekli'
            : r['onayli'] != true
            ? 'Tercih onayı bekliyor'
            : dersId == null
            ? 'Yerleşmedi'
            : '${tercihler.indexOf(dersId) + 1}. tercihine yerleşti',
      });
    }
    final toplam = (p['ogrenciler'] as List).length;
    final tam =
        dagGuncel &&
        rows.length == toplam &&
        rows.every(
          (r) => r['onayli'] == true && dag.containsKey('${r['OgrenciId']}'),
        );
    return {
      'toplam': toplam,
      'gecerli': rows.where((r) => (r['hatalar'] as List).isEmpty).length,
      'bekleyen': rows.where((r) => r['bekliyor'] == true).length,
      'sorunlu': rows
          .where(
            (r) => r['bekliyor'] != true && (r['hatalar'] as List).isNotEmpty,
          )
          .length,
      'onayli': onayli.length,
      'yerlesen': dagGuncel ? dag.length : 0,
      'dagitimGuncel': dagGuncel,
      'sonuclanabilir': tam,
      'sonuclandi': tam && p['sonuclandi'] == true && p['sonucImzasi'] == imza,
      'sonucTarihi': p['sonucTarihi'],
      'imza': imza,
      'dersler': dersAnalizi,
      'ogrenciler': ogrenciler,
    };
  }

  Future<Map<String, dynamic>> projeAnalizi(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
  ) => _projeIslem(b, atama, formId, (tx, a, p) => _projeAnaliz(tx, b, a, p));

  Future<void> projeSonuclandir(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    String beklenenImza,
  ) => _projeIslem(b, atama, formId, (tx, a, p) async {
    final analiz = await _projeAnaliz(tx, b, a, p);
    if (analiz['imza'] != beklenenImza) {
      throw StateError('Yanıt veya dağıtım değişti. Analizi yenileyin.');
    }
    if (analiz['sonuclanabilir'] != true) {
      throw StateError(
        'Bütün hedef öğrencilerin geçerli tercihleri onaylanıp derslere yerleştirilmeden sonuçlandırılamaz.',
      );
    }
    p['sonuclandi'] = true;
    p['sonucImzasi'] = beklenenImza;
    p['sonucTarihi'] = DateTime.now().toUtc().toIso8601String();
    final gecmis = (p['sonucGecmisi'] as List? ?? []).toList();
    if (!gecmis.any((g) => g['imza'] == beklenenImza)) {
      gecmis.add({
        'imza': beklenenImza,
        'tarih': p['sonucTarihi'],
        'dagitim': Map<String, dynamic>.from(p['dagitim'] as Map),
      });
    }
    p['sonucGecmisi'] = gecmis;
  }, yazma: true);

  Future<void> projeDersOgretmeniEsle(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    int dersId,
    Set<String> kisiIds,
  ) {
    final ids = Set<String>.of(kisiIds);
    return _projeIslem(b, atama, formId, (tx, a, p) async {
      if (!(p['dersler'] as Map).containsKey('$dersId')) {
        throw StateError('Ders bu proje formunda yok.');
      }
      final adaylar = await _projeOgretmenAdaylari(tx, b, a);
      if (ids.isEmpty ||
          !ids.every((id) => adaylar.any((k) => k['KisiId'] == id))) {
        throw StateError(
          'Yalnız bu sınıfın kayıtlı ders öğretmenleri seçilebilir.',
        );
      }
      final eslemeler = Map<String, dynamic>.from(
        p['dersOgretmenleri'] as Map? ?? {},
      );
      eslemeler['$dersId'] = ids.toList()..sort();
      p['dersOgretmenleri'] = eslemeler;
    }, yazma: true);
  }

  Future<Map<String, dynamic>> projeSonucMesaji(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    int dersId,
  ) => _projeIslem(b, atama, formId, (tx, a, p) async {
    // Gönderim de güncel, yazılabilir rehberlik ataması ister.
    await _atama(tx, b, atama, yazma: true);
    return _projeSonucMesajiTx(tx, b, a, p, dersId);
  });

  /// Ortak mesaj motorunun mevcut işlemi içinde de doğrulanır. İç içe
  /// transaction açmadan, bekleyen gönderimin güncel sonucunu kontrol eder.
  Future<Map<String, dynamic>> projeSonucMesajiniDogrula(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    int dersId,
  ) async {
    final a = await _atama(tx, b, atama, yazma: true);
    final veri = await _projeOku(tx, b, atama);
    final projeler = (veri['talepler'] as List)
        .where((p) => p['formId'] == formId)
        .toList();
    if (projeler.length != 1) {
      throw StateError('Proje formu bu atamaya ait değil.');
    }
    return _projeSonucMesajiTx(
      tx,
      b,
      a,
      Map<String, dynamic>.from(projeler.single as Map),
      dersId,
    );
  }

  Future<Map<String, dynamic>> _projeSonucMesajiTx(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    Map<String, Object?> a,
    Map<String, dynamic> p,
    int dersId,
  ) async {
    await _projeFormKontrol(tx, b, p['formId'] as int);
    final analiz = await _projeAnaliz(tx, b, a, p);
    if (analiz['sonuclandi'] != true) {
      throw StateError('Önce güncel proje ders seçimini sonuçlandırın.');
    }
    final ders = (analiz['dersler'] as List)
        .cast<Map<String, dynamic>>()
        .where((d) => d['dersId'] == dersId)
        .firstOrNull;
    if (ders == null) throw StateError('Ders bu proje formunda yok.');
    final ogretmenler = (ders['ogretmenler'] as List)
        .cast<Map<String, Object?>>();
    if (ogretmenler.isEmpty) {
      throw StateError('Bu ders için öğretmen eşleştirin.');
    }
    final rows = (analiz['ogrenciler'] as List)
        .cast<Map<String, dynamic>>()
        .where((r) => r['dersId'] == dersId)
        .toList();
    if (rows.isEmpty) throw StateError('Bu derse yerleşmiş öğrenci yok.');
    final sinif = await tx.query(
      'SinifSube',
      columns: ['SinifKodu'],
      where: 'SinifSubeId=?',
      whereArgs: [a['SinifSubeId']],
    );
    final metin =
        'Proje ödevi ders seçimi kesin sonuçları\n${b.okulAdi}\n${a['EgitimOgretimYili']} • ${sinif.single['SinifKodu']}\nDers: ${ders['dersAdi']}\n'
        '${rows.map((r) => "${r['OkulNo']} - ${r['Ad']} ${r['Soyad']}").join('\n')}\nSınıf rehber öğretmeni: ${b.ogretmenAdi}';
    if (metin.length > 4000) {
      throw StateError('Liste mesaj sınırını aşıyor. Ders raporunu kullanın.');
    }
    final ids = ogretmenler.map((k) => k['KisiId'] as String).toList()..sort();
    return {
      'dersId': dersId,
      'dersAdi': ders['dersAdi'],
      'sinifId': a['SinifSubeId'],
      'aliciIds': ids,
      'metin': metin,
      'imza': sha256
          .convert(utf8.encode(jsonEncode([analiz['imza'], ids, metin])))
          .toString(),
    };
  }

  Future<void> projeDavetiniKaydet(
    BireyselRehberlikBaglami b,
    int atama,
    int formId,
    String baglanti,
    String metin,
  ) => _projeIslem(b, atama, formId, (tx, a, p) async {
    final uri = Uri.tryParse(baglanti);
    if (uri == null ||
        uri.scheme != 'https' ||
        !{'docs.google.com', 'forms.gle'}.contains(uri.host) ||
        metin.length > 10000) {
      throw const FormatException('Form bağlantısı veya mesaj metni geçersiz.');
    }
    final form = await tx.query(
      'BilgiToplamaForm',
      where:
          'Id=? AND OkulId=? AND OgretmenProfilId=? AND EgitimOgretimYili=? AND Durum=?',
      whereArgs: [
        formId,
        b.okulId,
        b.ogretmenProfilId,
        a['EgitimOgretimYili'],
        'Aktif',
      ],
    );
    if (form.length != 1) throw StateError('Etkin form bulunamadı.');
    p['formLinki'] = baglanti;
    p['mesajMetni'] = metin;
  }, yazma: true);
}
