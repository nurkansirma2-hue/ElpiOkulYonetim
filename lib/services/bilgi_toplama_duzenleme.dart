part of 'bireysel_bilgi_toplama_service.dart';

/// Uzak işlem tamamlanmadan yerel sorular değiştirilmez. Bekleyen plan
/// bağlantı kesilirse aynı Google kimlikleriyle sürdürülebilir.
extension BilgiToplamaDuzenleme on BireyselBilgiToplamaService {
  String _duzenlemeAnahtari(int id) => 'bilgi_toplama_duzenleme:$id';

  Future<Map<String, Object?>> _duzenlemeAnlik(
    Transaction tx,
    BilgiToplamaOturumu b,
    int id,
  ) async => {
    'form': await _form(tx, b, id),
    'sorular': await tx.query(
      'BilgiToplamaSoru',
      where: 'FormId=?',
      whereArgs: [id],
      orderBy: 'Sira',
    ),
    'hedefler': await tx.query(
      'BilgiToplamaHedef',
      where: 'FormId=?',
      whereArgs: [id],
      orderBy: 'OgrenciId',
    ),
  };

  Future<Map<String, Object?>> formDuzenlemeBilgileri(
    BilgiToplamaOturumu b,
    int id,
  ) => _islem(
    b,
    (tx) async => {
      ...await _duzenlemeAnlik(tx, b, id),
      'yanitVar': (await tx.query(
        'BilgiToplamaYanit',
        columns: ['Id'],
        where: 'FormId=?',
        whereArgs: [id],
        limit: 1,
      )).isNotEmpty,
    },
  );

  Future<Map<String, dynamic>?> bekleyenFormDuzenlemesi(
    BilgiToplamaOturumu b,
    int id,
  ) => _islem(b, (tx) async {
    await _form(tx, b, id);
    final rows = await tx.query(
      'UygulamaAyarlari',
      where: 'Anahtar=?',
      whereArgs: [_duzenlemeAnahtari(id)],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['Deger'] as String) as Map<String, dynamic>;
  });

  Future<Map<String, dynamic>> formDuzenlemeHazirla(
    BilgiToplamaOturumu b,
    int id, {
    required Map<String, Object?> beklenenForm,
    required String baslik,
    List<BilgiToplamaSorusu>? sorular,
    String? hedefTuru,
    Set<int> ogrenciIdleri = const {},
    Set<int> sinifIdleri = const {},
    Map<String, dynamic>? yayinDurumu,
  }) {
    final ss = sorular == null ? null : List<BilgiToplamaSorusu>.of(sorular);
    final beklenen = Map<String, Object?>.of(beklenenForm);
    final oo = Set<int>.of(ogrenciIdleri), siniflar = Set<int>.of(sinifIdleri);
    return _islem(b, (tx) async {
      final eski = await _duzenlemeAnlik(tx, b, id), f = await _form(tx, b, id);
      if (BireyselBilgiToplamaService._ozet(f) !=
          BireyselBilgiToplamaService._ozet(beklenen)) {
        throw StateError('Form değişti. Düzenleme ekranını yeniden açın.');
      }
      if ((await tx.query(
        'UygulamaAyarlari',
        where: 'Anahtar=?',
        whereArgs: [_duzenlemeAnahtari(id)],
      )).isNotEmpty) {
        throw StateError('Önce bekleyen düzenlemeyi tamamlayın.');
      }
      if (baslik.trim().isEmpty || baslik.trim().length > 300) {
        throw const FormatException('Form adı 1–300 karakter olmalıdır.');
      }
      if (f['GoogleFormId'] == null &&
          (await tx.query(
            'UygulamaAyarlari',
            where: 'Anahtar=?',
            whereArgs: [_olusturmaAnahtari(id)],
          )).isNotEmpty) {
        throw StateError(
          'Önce yarım kalan Google oluşturma işlemini tamamlayın.',
        );
      }
      List<Map<String, Object?>>? yeniSorular;
      Set<int>? hedefler;
      if (ss != null) {
        if (hedefTuru == null) {
          throw const FormatException('Hedef türü seçilmeli.');
        }
        if ((await tx.query(
          'BilgiToplamaYanit',
          columns: ['Id'],
          where: 'FormId=?',
          whereArgs: [id],
          limit: 1,
        )).isNotEmpty) {
          throw StateError(
            'Bu forma yanıt gelmiş. Yalnız form adını değiştirebilirsiniz.',
          );
        }
        hedefler = await _formDogrula(
          tx,
          b,
          baslik,
          ss,
          hedefTuru,
          oo,
          siniflar,
        );
        final liste = (eski['sorular'] as List).any(
          (q) => q['AlanAnahtari'] == 'ogrenciSecimi',
        );
        final tum = [
          if (!liste)
            for (final k in BireyselBilgiToplamaService.kimlikler.entries)
              BilgiToplamaSorusu(
                anahtar: k.key,
                baslik: k.value,
                zorunlu: true,
              ),
          ...ss,
        ];
        yeniSorular = [
          for (var i = 0; i < tum.length; i++)
            {
              'FormId': id,
              'AlanAnahtari': tum[i].anahtar,
              'Baslik': tum[i].baslik.trim(),
              'VeriTuru': tum[i].veriTuru,
              'HedefAlan': tum[i].hedefAlan,
              'Secenekler': jsonEncode(tum[i].secenekler),
              'Zorunlu': tum[i].zorunlu ? 1 : 0,
              'Sira': i + (liste ? 2 : 1),
              'GoogleSoruId': f['GoogleFormId'] == null
                  ? null
                  : BireyselBilgiToplamaService._ozet([
                      id,
                      f['Surum'],
                      tum[i].anahtar,
                      i,
                    ]).substring(0, 8),
            },
        ];
        if (liste) {
          final soru = await _ogrenciSecimSorusu(tx, b, id, hedefler);
          soru['GoogleSoruId'] = f['GoogleFormId'] == null
              ? null
              : BireyselBilgiToplamaService._ozet([
                  id,
                  f['Surum'],
                  'ogrenciSecimi',
                  0,
                ]).substring(0, 8);
          yeniSorular.insert(0, soru);
        }
      } else if (hedefTuru != null || oo.isNotEmpty || siniflar.isNotEmpty) {
        throw StateError(
          'Hedef değişikliği soru düzenlemesiyle birlikte yapılmalıdır.',
        );
      }
      final plan = <String, dynamic>{
        'eski': eski,
        'baslik': baslik.trim(),
        'sorular': yeniSorular,
        'hedefTuru': hedefTuru,
        'hedefler': hedefler?.toList(),
        'yayin': yayinDurumu,
        'yerelKaydedildi': false,
      };
      await tx.insert('UygulamaAyarlari', {
        'Anahtar': _duzenlemeAnahtari(id),
        'Deger': jsonEncode(plan),
        'GuncellemeTarihi': BireyselBilgiToplamaService._simdi(),
      });
      return plan;
    });
  }

  Future<void> formDuzenlemeyiKaydet(
    BilgiToplamaOturumu b,
    int id,
  ) => _islem(b, (tx) async {
    final row = (await tx.query(
      'UygulamaAyarlari',
      where: 'Anahtar=?',
      whereArgs: [_duzenlemeAnahtari(id)],
    )).single;
    final plan = jsonDecode(row['Deger'] as String) as Map;
    if (plan['yerelKaydedildi'] == true) return;
    final eski = plan['eski'] as Map;
    if (BireyselBilgiToplamaService._ozet(await _duzenlemeAnlik(tx, b, id)) !=
        BireyselBilgiToplamaService._ozet(eski)) {
      throw StateError('Form düzenleme sırasında değişti; kayıt durduruldu.');
    }
    final f = eski['form'] as Map;
    if (plan['sorular'] != null) {
      if ((await tx.query(
        'BilgiToplamaYanit',
        columns: ['Id'],
        where: 'FormId=?',
        whereArgs: [id],
        limit: 1,
      )).isNotEmpty) {
        throw StateError(
          'Forma yanıt geldi. Soru ve hedef değişiklikleri kaydedilmedi.',
        );
      }
      final kapsam = (await _kapsam(tx, b)).map((o) => o['OgrenciId']).toSet();
      if (!(plan['hedefler'] as List).every(kapsam.contains)) {
        throw StateError('Hedef öğrencilerin ders kapsamı değişti.');
      }
      await tx.delete('BilgiToplamaSoru', where: 'FormId=?', whereArgs: [id]);
      await tx.delete('BilgiToplamaHedef', where: 'FormId=?', whereArgs: [id]);
      for (final soru in plan['sorular'] as List) {
        await tx.insert(
          'BilgiToplamaSoru',
          Map<String, Object?>.from(soru as Map),
        );
      }
      for (final oid in plan['hedefler'] as List) {
        await tx.insert('BilgiToplamaHedef', {'FormId': id, 'OgrenciId': oid});
      }
    }
    await tx.update(
      'BilgiToplamaForm',
      {
        'Baslik': plan['baslik'],
        'GuncellemeTarihi': BireyselBilgiToplamaService._simdi(),
        if (plan['sorular'] != null) ...{
          'HedefTuru': plan['hedefTuru'],
          'Surum': (f['Surum'] as int) + 1,
          'Durum': f['GoogleFormId'] == null ? 'Taslak' : 'Aktif',
        },
      },
      where: 'Id=?',
      whereArgs: [id],
    );
    plan['yerelKaydedildi'] = true;
    await tx.update(
      'UygulamaAyarlari',
      {'Deger': jsonEncode(plan)},
      where: 'Anahtar=?',
      whereArgs: [_duzenlemeAnahtari(id)],
    );
  });

  Future<void> formDuzenlemeyiBitir(BilgiToplamaOturumu b, int id) =>
      _islem(b, (tx) async {
        await _form(tx, b, id);
        await tx.delete(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [_duzenlemeAnahtari(id)],
        );
      });
}
