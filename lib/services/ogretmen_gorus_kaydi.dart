part of 'bireysel_rehberlik_service.dart';

/// Ayrı tablo gerektirmeyen, toplantı/okul/profil/yıl kapsamlı form kaydı.
extension OgretmenGorusKaydi on BireyselRehberlikService {
  String _gorusAnahtari(
    BireyselRehberlikBaglami b,
    int atama,
    int toplanti, {
    String? yil,
  }) =>
      'ogretmen_gorus_v1:${jsonEncode([b.okulId, b.ogretmenProfilId, yil ?? b.egitimOgretimYili, atama, toplanti])}';

  Future<Map<String, Object?>> _gorusKapsami(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    int atama,
    int toplanti, {
    required bool yazma,
    required bool hassasOnay,
  }) async {
    final a = await _atama(tx, b, atama, yazma: yazma);
    final k = await tx.query(
      'RehberlikKayit',
      where: 'Id=? AND AtamaId=? AND Tur=?',
      whereArgs: [toplanti, atama, 'Toplanti'],
    );
    if (k.length != 1 || (k.single['Hassas'] == 1 && !hassasOnay)) {
      throw StateError('Toplantıya erişim yok veya hassas kayıt kilitli.');
    }
    final s = await tx.query(
      'SinifSube',
      where: 'SinifSubeId=? AND EgitimOgretimYili=?',
      whereArgs: [a['SinifSubeId'], a['EgitimOgretimYili']],
    );
    if (s.length != 1) throw StateError('Toplantının sınıfı bulunamadı.');
    return {
      ...a,
      'SinifKodu': s.single['SinifKodu'],
      'Baslik': k.single['Baslik'],
    };
  }

  Future<Map<String, Object?>> ogretmenGorusDurumu(
    BireyselRehberlikBaglami b,
    int atama,
    int toplanti, {
    bool yazma = false,
    bool hassasOnay = false,
  }) async {
    final db = await _db();
    return db.transaction((tx) async {
      final kapsam = await _gorusKapsami(
        tx,
        b,
        atama,
        toplanti,
        yazma: yazma,
        hassasOnay: hassasOnay,
      );
      final rows = await tx.query(
        'UygulamaAyarlari',
        where: 'Anahtar=?',
        whereArgs: [
          _gorusAnahtari(
            b,
            atama,
            toplanti,
            yil: kapsam['EgitimOgretimYili'] as String,
          ),
        ],
      );
      await _kontrol(tx, b);
      return {
        ...kapsam,
        'form': rows.isEmpty
            ? null
            : Map<String, dynamic>.from(
                jsonDecode(rows.single['Deger'] as String) as Map,
              ),
      };
    });
  }

  /// İlk istek Google çağrısından önce kaydedilir. Sonraki deneme aynı fotoğraflı
  /// anlık görüntüyü kullanır; token saklanmaz, öğrenci ana kaydı değiştirilmez.
  Future<Map<String, dynamic>> ogretmenGorusIstegiKaydet(
    BireyselRehberlikBaglami b,
    int atama,
    int toplanti, {
    required String hesap,
    required Map<String, dynamic> istek,
    bool hassasOnay = false,
  }) async {
    if (hesap.trim().isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_-]{32,64}$').hasMatch('${istek['requestId']}')) {
      throw const FormatException(
        'Google hesabı veya form istek kimliği geçersiz.',
      );
    }
    final db = await _db();
    return _sirali(
      () => db.transaction((tx) async {
        final a = await _gorusKapsami(
          tx,
          b,
          atama,
          toplanti,
          yazma: true,
          hassasOnay: hassasOnay,
        );
        final key = _gorusAnahtari(b, atama, toplanti);
        final eski = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [key],
        );
        if (eski.isNotEmpty) {
          final v = Map<String, dynamic>.from(
            jsonDecode(eski.single['Deger'] as String) as Map,
          );
          if (v['hesap'] != hesap) {
            throw StateError('Formu hazırlayan Google hesabını seçin.');
          }
          return v;
        }
        final ids = ((istek['ogrenciler'] as List?) ?? [])
            .map((o) => (o as Map)['id'])
            .toList();
        final aktif = await tx.rawQuery(
          '''SELECT DISTINCT o.OgrenciId FROM Ogrenci o
        JOIN OgrenciSinifKayit k ON k.OgrenciId=o.OgrenciId
        WHERE o.Aktif=1 AND k.Aktif=1 AND k.SinifSubeId=? AND k.EgitimOgretimYili=?''',
          [a['SinifSubeId'], b.egitimOgretimYili],
        );
        final izinli = aktif.map((o) => o['OgrenciId']).toSet();
        if (ids.isEmpty ||
            ids.length > 100 ||
            ids.toSet().length != ids.length ||
            ids.length != izinli.length ||
            !ids.every(izinli.contains) ||
            istek['kapsam'] != key ||
            istek['sinif'] != a['SinifKodu'] ||
            istek['yil'] != b.egitimOgretimYili) {
          throw StateError(
            'Öğrenci listesi veya toplantı kapsamı değişti. Ön izlemeyi yeniden açın.',
          );
        }
        final v = <String, dynamic>{'hesap': hesap, 'istek': istek};
        final json = jsonEncode(v);
        if (utf8.encode(json).length > 12 * 1024 * 1024) {
          throw StateError('Form fotoğrafları çok büyük.');
        }
        await tx.insert('UygulamaAyarlari', {
          'Anahtar': key,
          'Deger': json,
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        });
        await _kontrol(tx, b);
        return v;
      }),
    );
  }

  String ogretmenGorusKapsamAnahtari(
    BireyselRehberlikBaglami b,
    int atama,
    int toplanti,
  ) => _gorusAnahtari(b, atama, toplanti);

  Future<void> ogretmenGorusSonucKaydet(
    BireyselRehberlikBaglami b,
    int atama,
    int toplanti, {
    required String requestId,
    required String hesap,
    required Map<String, dynamic> sonuc,
    bool hassasOnay = false,
  }) async {
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        await _gorusKapsami(
          tx,
          b,
          atama,
          toplanti,
          yazma: true,
          hassasOnay: hassasOnay,
        );
        final key = _gorusAnahtari(b, atama, toplanti);
        final rows = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [key],
        );
        if (rows.length != 1) {
          throw StateError('Kaydedilmiş form isteği bulunamadı.');
        }
        final v = Map<String, dynamic>.from(
          jsonDecode(rows.single['Deger'] as String) as Map,
        );
        if ((v['istek'] as Map)['requestId'] != requestId ||
            v['hesap'] != hesap ||
            sonuc['requestId'] != requestId ||
            sonuc['ready'] != true ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,300}$').hasMatch('${sonuc['formId']}') ||
            (v['sonuc'] != null &&
                (v['sonuc'] as Map)['formId'] != sonuc['formId'])) {
          throw StateError('Google formu ile yerel toplantı kaydı uyuşmuyor.');
        }
        v['sonuc'] = sonuc;
        await tx.update(
          'UygulamaAyarlari',
          {
            'Deger': jsonEncode(v),
            'GuncellemeTarihi': DateTime.now().toIso8601String(),
          },
          where: 'Anahtar=?',
          whereArgs: [key],
        );
        await _kontrol(tx, b);
      }),
    );
  }

  Future<void> ogretmenGorusYonet(
    BireyselRehberlikBaglami b,
    int atama,
    int toplanti, {
    required String requestId,
    required String formId,
    bool hassasOnay = false,
    List<Map<String, dynamic>>? yanitlar,
    List<String>? aliciIdleri,
    String? silinenId,
    String? islem,
  }) async {
    await _sirali(() async {
      final db = await _db();
      await db.transaction((tx) async {
        await _gorusKapsami(
          tx,
          b,
          atama,
          toplanti,
          yazma: silinenId != null || islem != null || aliciIdleri != null,
          hassasOnay: hassasOnay,
        );
        final key = _gorusAnahtari(b, atama, toplanti);
        final rows = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [key],
        );
        if (rows.length != 1) throw StateError('Form kaydı bulunamadı.');
        final v = Map<String, dynamic>.from(
          jsonDecode(rows.single['Deger'] as String) as Map,
        );
        if ((v['istek'] as Map)['requestId'] != requestId ||
            (v['sonuc'] as Map?)?['formId'] != formId) {
          throw StateError('Form kimliği değişti.');
        }
        if (aliciIdleri != null) {
          final kapsam = await _gorusKapsami(
            tx,
            b,
            atama,
            toplanti,
            yazma: true,
            hassasOnay: hassasOnay,
          );
          for (final id in aliciIdleri.toSet()) {
            final aday = await tx.rawQuery(
              'SELECT k.KisiId FROM MesajOgretmenKisi k JOIN MesajOgretmenSinif i ON k.KisiId=i.KisiId WHERE k.KisiId=? AND k.OkulId=? AND k.SahipProfilId=? AND k.Aktif=1 AND i.SinifSubeId=? AND i.EgitimOgretimYili=?',
              [
                id,
                b.okulId,
                b.ogretmenProfilId,
                kapsam['SinifSubeId'],
                b.egitimOgretimYili,
              ],
            );
            if (aday.isEmpty) {
              throw StateError('Öğretmen alıcı kapsamı değişti.');
            }
          }
          v['aliciIdleri'] = aliciIdleri.toSet().toList();
        }
        final silinen = (v['silinenYanitlar'] as List? ?? [])
            .cast<String>()
            .toSet();
        if (silinenId != null) silinen.add(silinenId);
        final gelen =
            yanitlar ??
            (v['yanitlar'] as List? ?? [])
                .cast<Map>()
                .map((y) => Map<String, dynamic>.from(y))
                .toList();
        if (gelen.any((y) => y['responseId'] is! String) ||
            jsonEncode(gelen).length > 8000000) {
          throw StateError('Yanıt verisi geçersiz veya çok büyük.');
        }
        v['yanitlar'] = gelen
            .where((y) => !silinen.contains(y['responseId']))
            .toList();
        v['silinenYanitlar'] = silinen.toList();
        if (yanitlar != null) {
          v['sonEsitleme'] = DateTime.now().toIso8601String();
        }
        final m = Map<String, dynamic>.from(v['yonetim'] as Map? ?? {});
        if (islem != null) {
          switch (islem) {
            case 'Kapat':
              m['acik'] = false;
              break;
            case 'Aç':
              m['acik'] = true;
              m.remove('arsiv');
              m.remove('tamam');
              break;
            case 'Tamamla':
            case 'Arşivle':
              if (m['acik'] != false) {
                throw StateError('Önce yanıt alımını kapatın.');
              }
              m[islem == 'Tamamla' ? 'tamam' : 'arsiv'] = true;
              break;
            case 'Arşivden çıkar':
              m.remove('arsiv');
              break;
            default:
              throw ArgumentError('Durum işlemi geçersiz.');
          }
        }
        v['yonetim'] = m;
        await tx.update(
          'UygulamaAyarlari',
          {
            'Deger': jsonEncode(v),
            'GuncellemeTarihi': DateTime.now().toIso8601String(),
          },
          where: 'Anahtar=?',
          whereArgs: [key],
        );
        await _kontrol(tx, b);
      });
    });
  }
}
