part of 'mesajlasma_service.dart';

class _OgretmenImportVerisi {
  _OgretmenImportVerisi(
    this.baglam,
    this.sinifId,
    this.kaynaklar,
    this.kayitlar,
    this.kisiler,
    this.siniflar,
    this.digerSiniflar,
  );
  final MesajBaglami baglam;
  final int sinifId;
  final List<ImportKaynakSatiri> kaynaklar;
  final List<ImportKaydi> kayitlar;
  final List<Map<String, Object?>> kisiler, siniflar;
  final bool digerSiniflar;
}

extension MesajOgretmenImport on MesajlasmaService {
  Future<List<Map<String, Object?>>> _importKisileri(
    DatabaseExecutor db,
    MesajBaglami b,
  ) => db.query(
    'MesajOgretmenKisi',
    where: 'OkulId=? AND SahipProfilId=? AND Aktif=1',
    whereArgs: [b.okulId, b.ogretmenId],
    orderBy: 'KisiId',
  );

  Future<ImportOnIzleme> ogretmenProgramiOnIzleme(
    MesajBaglami b,
    List<ImportKaynakSatiri> kaynaklar, {
    required int sinifId,
    bool digerSiniflar = false,
  }) async {
    final rows = List<ImportKaynakSatiri>.unmodifiable(kaynaklar);
    return (await _db()).transaction((tx) async {
      await _kontrol(tx, b);
      final siniflar = await _mesajSiniflari(tx, b);
      final hedef = siniflar.where((s) => s['SinifSubeId'] == sinifId).toList();
      if (hedef.length != 1) {
        throw StateError('Seçili sınıf güncel ders kapsamınızda değil.');
      }
      final kod = hedef.single['SinifKodu'] as String;
      final kisiler = await _importKisileri(tx, b);
      final bloklar = <String, Set<String>>{};
      for (final r in rows) {
        (bloklar[importNormalize(r.degerler['ogretmen'] ?? '')] ??= {}).add(
          r.degerler['blok'] ?? r.id,
        );
      }
      final kayitlar = <ImportKaydi>[];
      for (final r in rows) {
        final ad = (r.degerler['ogretmen'] ?? '').trim();
        final norm = importNormalize(ad);
        final eslesen = kisiler
            .where((k) => importNormalize(k['AdSoyad'] as String) == norm)
            .toList();
        final mesajlar = <String>[];
        var durum = ImportDurumu.uygun;
        if (r.degerler['yil'] != b.yil) {
          durum = ImportDurumu.hatali;
          mesajlar.add(
            'Belgenin eğitim yılı eksik veya ${b.yil} ile uyuşmuyor.',
          );
        } else if (ad.length > 200 ||
            norm.split(' ').length < 2 ||
            RegExp(r'\d|\b(ogrt|ogretmen|gir)\b').hasMatch(norm)) {
          durum = ImportDurumu.hatali;
          mesajlar.add(
            'Öğretmen adını doğrulayın; geçici veya eksik ad düzeltilmeli.',
          );
        } else if ((r.degerler['sinif'] ?? '').trim().isEmpty) {
          durum = ImportDurumu.hatali;
          mesajlar.add(
            'Programda sınıf okunamadı; satırı düzenleyerek doğrulayın.',
          );
        } else if (importNormalize(r.degerler['sinif']!) !=
                importNormalize(kod) &&
            !digerSiniflar) {
          durum = ImportDurumu.atlanan;
          mesajlar.add('Bu aktarım yalnız $kod sınıfı içindir.');
        } else if (siniflar
                .where(
                  (s) =>
                      importNormalize(s['SinifKodu'] as String) ==
                      importNormalize(r.degerler['sinif']!),
                )
                .length !=
            1) {
          durum = ImportDurumu.atlanan;
          mesajlar.add(
            'Sınıf güncel ders kapsamınızda yok veya sınıf kodu belirsiz.',
          );
        } else if ((r.degerler['dersler'] ?? '').split('\n').length > 50 ||
            (r.degerler['dersler'] ?? '')
                .split('\n')
                .any((d) => d.trim().length > 200)) {
          durum = ImportDurumu.hatali;
          mesajlar.add(
            'Ders adları en fazla 200 karakter ve 50 ders olabilir.',
          );
        } else if (eslesen.length > 1) {
          durum = ImportDurumu.hatali;
          mesajlar.add(
            'Rehberde aynı adlı birden fazla kişi var. Önce adlarını ayırt edecek şekilde düzenleyin.',
          );
        } else {
          if ((r.degerler['dersler'] ?? '').trim().isEmpty) {
            durum = ImportDurumu.uyarili;
            mesajlar.add(
              'Ders adı okunamadı. Ön izlemede ders adını doğrulayın veya düzeltin; boş bırakılırsa yalnız öğretmen-sınıf ilişkisi aktarılır.',
            );
          }
          if ((bloklar[norm]?.length ?? 0) > 1) {
            durum = ImportDurumu.uyarili;
            mesajlar.add(
              'Aynı ad farklı programlarda geçiyor. Aynı kişi ise seçin; farklı kişilerse adlarını ayırt ederek düzeltin.',
            );
          }
          if (eslesen.isNotEmpty) {
            durum = ImportDurumu.uyarili;
            mesajlar.add(
              'Kayıtlı ${eslesen.single['AdSoyad']} kullanılacak; telefonu ve diğer sınıfları korunur.',
            );
          }
          final okul = importNormalize(r.degerler['okul'] ?? '');
          if (okul.isEmpty || !okul.contains(importNormalize(b.okulAdi))) {
            durum = ImportDurumu.uyarili;
            mesajlar.add(
              'Okul adı otomatik doğrulanamadı; belgenin ${b.okulAdi} okuluna ait olduğunu kontrol edin.',
            );
          }
        }
        kayitlar.add(
          ImportKaydi(
            r.id,
            r.konum,
            r.degerler,
            durum: durum,
            mesajlar: mesajlar,
          ),
        );
      }
      final kilitli = List<ImportKaydi>.unmodifiable(kayitlar);
      return ImportOnIzleme(
        kilitli,
        veri: _OgretmenImportVerisi(
          b,
          sinifId,
          rows,
          kilitli,
          kisiler,
          siniflar,
          digerSiniflar,
        ),
        bilgiler: [
          '$kod • ${b.yil} • ${b.okulAdi}',
          'Algılanan belge: ${rows.map((r) => r.degerler['tur'] ?? 'Öğretmen programı').toSet().join(', ')}. '
              '${rows.map((r) => importNormalize(r.degerler['sinif'] ?? '')).toSet().length} sınıf, '
              '${rows.map((r) => importNormalize(r.degerler['ogretmen'] ?? '')).toSet().length} öğretmen.',
          digerSiniflar
              ? 'Belgedeki ders kapsamınızda olan bütün sınıflar aktarıma açık.'
              : 'Yalnız $kod sınıfı aktarıma açık.',
          'Eksik telefonlar mesaj hazırlığında tamamlanabilir.',
          'Yalnız seçilen öğretmen-sınıf bağları eklenir; mevcut kişi, telefon ve sınıf bağları silinmez.',
        ],
      );
    });
  }

  Future<ImportOnIzleme> ogretmenProgramiDuzenle(
    MesajBaglami b,
    ImportOnIzleme onceki,
    List<ImportKaynakSatiri> rows,
  ) {
    final v = onceki.veri;
    if (v is! _OgretmenImportVerisi ||
        !b.ayni(v.baglam) ||
        rows.length != v.kaynaklar.length ||
        rows.map((r) => r.id).toSet().length != rows.length ||
        rows.any((r) => !v.kaynaklar.any((s) => s.id == r.id))) {
      throw StateError('Ön izleme kaynağı değişti; dosyayı yeniden seçin.');
    }
    return ogretmenProgramiOnIzleme(
      b,
      rows.map((r) {
        final eski = v.kaynaklar.singleWhere((s) => s.id == r.id);
        return ImportKaynakSatiri(r.id, eski.konum, {
          ...eski.degerler,
          'ogretmen': r.degerler['ogretmen'] ?? '',
          'sinif': r.degerler['sinif'] ?? '',
          'dersler': r.degerler['dersler'] ?? '',
        });
      }).toList(),
      sinifId: v.sinifId,
      digerSiniflar: v.digerSiniflar,
    );
  }

  Future<ImportOzet> ogretmenProgramiAktar(
    MesajBaglami b,
    ImportOnIzleme p,
    Set<String> secimler,
  ) {
    final secilen = Set<String>.of(secimler), v = p.veri;
    if (v is! _OgretmenImportVerisi ||
        !b.ayni(v.baglam) ||
        secilen.isEmpty ||
        secilen.any(
          (id) => !v.kayitlar.any((r) => r.id == id && r.aktarilabilir),
        )) {
      throw StateError(
        'Ön izlemeyi kontrol edip aktarılabilir kayıtları seçin.',
      );
    }
    return _sirali(
      () async => (await _db()).transaction((tx) async {
        await _kontrol(tx, b);
        if (jsonEncode(await _mesajSiniflari(tx, b)) !=
                jsonEncode(v.siniflar) ||
            jsonEncode(await _importKisileri(tx, b)) != jsonEncode(v.kisiler)) {
          throw StateError(
            'Sınıf veya öğretmen rehberi değişti. Ön izlemeyi yeniden hazırlayın.',
          );
        }
        final zaman = DateTime.now().toUtc().toIso8601String();
        var yeni = 0, bag = 0, tekrar = 0, dersBagi = 0;
        final dersler = (await tx.query(
          'Ders',
          where: 'Aktif=1',
          orderBy: 'DersId',
        )).map((r) => Map<String, Object?>.from(r)).toList();
        final ids = <String, String>{};
        for (final r in v.kayitlar.where((r) => secilen.contains(r.id))) {
          final hedefler = v.siniflar
              .where(
                (s) =>
                    importNormalize(s['SinifKodu'] as String) ==
                    importNormalize(r.degerler['sinif'] ?? ''),
              )
              .toList();
          if (hedefler.length != 1 ||
              (!v.digerSiniflar &&
                  hedefler.single['SinifSubeId'] != v.sinifId)) {
            throw StateError('Aktarılacak sınıf kapsamı geçersiz.');
          }
          final hedefId = hedefler.single['SinifSubeId'] as int;
          final ad = r.degerler['ogretmen']!.trim(),
              norm = importNormalize(r.degerler['ogretmen']!);
          var id = ids[norm];
          if (id == null) {
            final eski = v.kisiler
                .where((k) => importNormalize(k['AdSoyad'] as String) == norm)
                .toList();
            if (eski.length > 1) {
              throw StateError('Öğretmen eşleştirmesi belirsiz.');
            }
            id = eski.isEmpty
                ? MesajFormIslemleri._id()
                : eski.single['KisiId'] as String;
            if (eski.isEmpty) {
              await tx.insert('MesajOgretmenKisi', {
                'KisiId': id,
                'OkulId': b.okulId,
                'SahipProfilId': b.ogretmenId,
                'AdSoyad': ad,
                'Telefon': '',
                'OlusturmaTarihi': zaman,
                'GuncellemeTarihi': zaman,
              });
              yeni++;
            }
            ids[norm] = id;
          }
          final eskiBag = await tx.query(
            'MesajOgretmenSinif',
            where: 'KisiId=? AND SinifSubeId=? AND EgitimOgretimYili=?',
            whereArgs: [id, hedefId, b.yil],
          );
          if (eskiBag.isEmpty) {
            await tx.insert('MesajOgretmenSinif', {
              'KisiId': id,
              'SinifSubeId': hedefId,
              'EgitimOgretimYili': b.yil,
              'Kaynak': 'DersProgrami',
              'OlusturmaTarihi': zaman,
            });
            bag++;
          } else {
            tekrar++;
          }
          for (final ders
              in (r.degerler['dersler'] ?? '')
                  .split('\n')
                  .map((d) => d.trim())
                  .where((d) => d.isNotEmpty)
                  .toSet()) {
            final eslesen = dersler
                .where(
                  (d) =>
                      importNormalize(d['DersAdi'] as String) ==
                      importNormalize(ders),
                )
                .toList();
            if (eslesen.length > 1) {
              throw StateError(
                '$ders için birden fazla ders kaydı var; ders adlarını doğrulayın.',
              );
            }
            final int dersId;
            if (eslesen.isEmpty) {
              dersId = await tx.insert('Ders', {
                'DersAdi': ders,
                'OlusturmaTarihi': zaman,
              });
              dersler.add({'DersId': dersId, 'DersAdi': ders});
            } else {
              dersId = eslesen.single['DersId'] as int;
            }
            final sinifDersi = await tx.query(
              'DersSinif',
              where: 'DersId=? AND SinifSubeId=? AND EgitimOgretimYili=?',
              whereArgs: [dersId, hedefId, b.yil],
            );
            if (sinifDersi.isEmpty) {
              await tx.insert('DersSinif', {
                'DersId': dersId,
                'SinifSubeId': hedefId,
                'EgitimOgretimYili': b.yil,
                'Aktif': 1,
                'OlusturmaTarihi': zaman,
              });
            } else {
              await tx.update(
                'DersSinif',
                {'Aktif': 1},
                where: 'DersSinifId=?',
                whereArgs: [sinifDersi.single['DersSinifId']],
              );
            }
            final eski = await tx.query(
              'MesajOgretmenSinifDers',
              where:
                  'KisiId=? AND SinifSubeId=? AND EgitimOgretimYili=? AND DersId=?',
              whereArgs: [id, hedefId, b.yil, dersId],
            );
            if (eski.isEmpty) {
              await tx.insert('MesajOgretmenSinifDers', {
                'KisiId': id,
                'SinifSubeId': hedefId,
                'EgitimOgretimYili': b.yil,
                'DersId': dersId,
              });
              dersBagi++;
            }
          }
        }
        await _kontrol(tx, b);
        return ImportOzet(
          eklenen: yeni,
          guncellenen: bag + dersBagi,
          atlanan: v.kayitlar.length - secilen.length + tekrar,
          hatali: 0,
          mesaj:
              '$yeni yeni öğretmen, $bag sınıf ilişkisi, $dersBagi ders ilişkisi kaydedildi. $tekrar mevcut sınıf ilişkisi korundu. Telefonlar korundu.',
        );
      }),
    );
  }
}
