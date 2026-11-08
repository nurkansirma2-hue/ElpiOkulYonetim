part of 'bireysel_rehberlik_service.dart';

const rehberlikTurleri = {
  'Toplanti': 'Toplantı',
  'Gorusme': 'Görüşme',
  'Gorev': 'Görev / takip',
  'Plan': 'Plan satırı',
  'Etkinlik': 'Etkinlik',
  'GorusTalebi': 'Görüş talebi',
};
const rehberlikDurumlari = ['Planlandi', 'Suruyor', 'Tamamlandi', 'Iptal'];
const rehberlikDurumAdlari = ['Planlandı', 'Sürüyor', 'Tamamlandı', 'İptal'];

/// Kimlik ve veli bilgileri Ogrenci'den okunur; bu alanlar formda çoğaltılmaz.
const mebTanimaSorulari = [
  'Doğum tarihi ve yeri',
  'Ev adresi',
  'Anne bilgileri ve mesleği',
  'Baba bilgileri ve mesleği',
  'Kardeşler ve öğrenim durumları',
  'Birlikte yaşadığı kişiler',
  'Ailenin ekonomik durumu',
  'Sağlık durumu ve özel gereksinimler',
  'İlgi ve yetenekler',
  'Geleceğe ilişkin hedefler',
  'Destek ihtiyacı ve açıklamalar',
];
const mebTanimaKaynak =
    'https://ismetaktar.meb.k12.tr/meb_iys_dosyalar/34/15/365565/dosyalar/2025_03/10111840_ismetaktarmtalsinifrehberlikdosyasibirlestirilmis.pdf';

extension RehberlikModulIslemleri on BireyselRehberlikService {
  String _soruAnahtari(BireyselRehberlikBaglami b, Map<String, Object?> a) =>
      'rehberlik_form_sorulari:${jsonEncode([b.okulId, b.ogretmenProfilId, a['SinifSubeId'], a['EgitimOgretimYili']])}';
  Future<List<String>> formSorulari(
    BireyselRehberlikBaglami b,
    int atamaId,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atamaId);
      final rows = await tx.query(
        'UygulamaAyarlari',
        where: 'Anahtar=?',
        whereArgs: [_soruAnahtari(b, a)],
      );
      await _kontrol(tx, b);
      return rows.isEmpty
          ? mebTanimaSorulari
          : List<String>.from(
              jsonDecode(rows.single['Deger'] as String) as List,
            );
    });
  }

  Future<void> formSorulariniKaydet(
    BireyselRehberlikBaglami b,
    int atamaId,
    List<String> sorular,
  ) async {
    if (sorular.isEmpty ||
        sorular.length > 100 ||
        sorular.toSet().length != sorular.length ||
        sorular.any((s) => s.trim().isEmpty || s.length > 300)) {
      throw const FormatException('Sorular geçersiz.');
    }
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atamaId, yazma: true);
        final key = _soruAnahtari(b, a);
        final row = {
          'Anahtar': key,
          'Deger': jsonEncode(sorular),
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        };
        final mevcut = await tx.query(
          'UygulamaAyarlari',
          where: 'Anahtar=?',
          whereArgs: [key],
        );
        if (mevcut.isEmpty) {
          await tx.insert('UygulamaAyarlari', row);
        } else {
          await tx.update(
            'UygulamaAyarlari',
            row,
            where: 'Anahtar=?',
            whereArgs: [key],
          );
        }
        await _kontrol(tx, b);
      }),
    );
  }

  Future<Map<String, Object?>> bagliBelgeGetir(
    BireyselRehberlikBaglami b,
    int atamaId,
    int kayitId,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atamaId);
      final rows = await tx.rawQuery(
        '''SELECT x.BelgeId,x.ArsivId,x.DosyaAdi,x.Uzanti
        FROM RehberlikKayit k JOIN BireyselBelge x ON x.BelgeId=k.BelgeId
        JOIN BelgeArsivi ar ON ar.ArsivId=x.ArsivId
        WHERE k.Id=? AND k.AtamaId=? AND k.Hassas=0 AND ar.OkulId=?
          AND ar.OgretmenProfilId=? AND x.EgitimOgretimYili=?''',
        [
          kayitId,
          atamaId,
          b.okulId,
          b.ogretmenProfilId,
          a['EgitimOgretimYili'],
        ],
      );
      if (rows.length != 1) {
        throw StateError(
          'Bağlı belge bulunamadı, kaldırılmış veya kayıt hassas olarak işaretlenmiş olabilir.',
        );
      }
      await _kontrol(tx, b);
      return rows.single;
    });
  }

  Future<void> belgeBagla(
    BireyselRehberlikBaglami b,
    int atamaId,
    int id,
    String belgeId,
  ) async {
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atamaId, yazma: true);
        final belgeler = await tx.rawQuery(
          '''SELECT x.BelgeId FROM BireyselBelge x
        JOIN BelgeArsivi ar ON ar.ArsivId=x.ArsivId WHERE x.BelgeId=?
          AND ar.OkulId=? AND ar.OgretmenProfilId=? AND x.EgitimOgretimYili=? AND x.Durum='Hazir' ''',
          [belgeId, b.okulId, b.ogretmenProfilId, a['EgitimOgretimYili']],
        );
        if (belgeler.length != 1) {
          throw StateError('Belge bu okul, öğretmen ve yıla ait değil.');
        }
        if (await tx.update(
              'RehberlikKayit',
              {'BelgeId': belgeId},
              where: 'Id=? AND AtamaId=?',
              whereArgs: [id, atamaId],
            ) !=
            1) {
          throw StateError('Belge bağlanacak kayıt bulunamadı.');
        }
        await _kontrol(tx, b);
      }),
    );
  }

  Future<Map<String, Object?>> genelDurum(
    BireyselRehberlikBaglami b,
    int atamaId,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atamaId);
      final rows = await tx.rawQuery(
        '''SELECT COUNT(DISTINCT k.OgrenciId) AS Ogrenci,
        COUNT(DISTINCT CASE WHEN trim(COALESCE(${VeliIliskisi.telefonSql('o')},''))='' THEN k.OgrenciId END) AS EksikVeli
        FROM OgrenciSinifKayit k JOIN Ogrenci o ON o.OgrenciId=k.OgrenciId
        WHERE k.SinifSubeId=? AND k.EgitimOgretimYili=? AND k.Aktif=1 AND o.Aktif=1''',
        [a['SinifSubeId'], a['EgitimOgretimYili']],
      );
      final takvim = await tx.rawQuery(
        '''SELECT d.HaftaNo,d.TarihAraligi,d.Aciklama,d.OzelGunAciklamasi
        FROM CalismaTakvimiDetay d JOIN CalismaTakvimi t ON t.CalismaTakvimiId=d.CalismaTakvimiId
        WHERE t.OgretmenProfilId=? AND t.EgitimOgretimYili=? AND t.Aktif=1 AND d.Aktif=1
        ORDER BY d.BaslangicTarihi,d.HaftaNo''',
        [b.ogretmenProfilId, a['EgitimOgretimYili']],
      );
      await _kontrol(tx, b);
      return {...rows.single, 'Takvim': takvim};
    });
  }

  Future<Map<String, Object?>> _atama(
    DatabaseExecutor tx,
    BireyselRehberlikBaglami b,
    int id, {
    bool yazma = false,
  }) async {
    await _kontrol(tx, b);
    final rows = await tx.query(
      'RehberlikAtama',
      where: 'RehberlikAtamaId = ? AND OkulId = ? AND OgretmenProfilId = ?',
      whereArgs: [id, b.okulId, b.ogretmenProfilId],
    );
    if (rows.length != 1) throw StateError('Rehberlik atamasına erişim yok.');
    final a = rows.single;
    if (yazma) {
      final sinif = await tx.query(
        'SinifSube',
        where: 'SinifSubeId=? AND Aktif=1',
        whereArgs: [a['SinifSubeId']],
      );
      if (sinif.isEmpty) {
        throw StateError('Sınıf aktif değil; geçmiş salt okunur.');
      }
      final bugun = DateTime.now().toIso8601String().substring(0, 10);
      if (a['EgitimOgretimYili'] != b.egitimOgretimYili ||
          (a['BaslangicTarihi'] as String).compareTo(bugun) > 0 ||
          (a['BitisTarihi'] != null &&
              (a['BitisTarihi'] as String).compareTo(bugun) < 0)) {
        throw StateError('Geçmiş veya henüz başlamamış atama salt okunur.');
      }
    }
    return a;
  }

  Future<List<Map<String, Object?>>> sinifOgrencileri(
    BireyselRehberlikBaglami b,
    int atamaId,
  ) async {
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atamaId);
      final rows = await tx.rawQuery(
        '''SELECT o.OgrenciId, o.OkulNo,o.Ad,o.Soyad,
        o.Cinsiyet,${VeliIliskisi.adSql('o')} AS VeliAdi,
        ${VeliIliskisi.telefonSql('o')} AS VeliTelefonu,o.Aktif AS OgrenciAktif,k.Aktif AS KayitAktif, f.FotoVerisi, f.DosyaYolu FROM Ogrenci o
        JOIN OgrenciSinifKayit k ON k.OgrenciId=o.OgrenciId
        LEFT JOIN OgrenciFotograf f ON f.OgrenciId=o.OgrenciId AND f.Aktif=1
        WHERE k.SinifSubeId=? AND k.EgitimOgretimYili=?
        ORDER BY CAST(o.OkulNo AS INTEGER),o.Ad,o.Soyad''',
        [a['SinifSubeId'], a['EgitimOgretimYili']],
      );
      await _kontrol(tx, b);
      return rows;
    });
  }

  Future<void> _ogrenciKontrol(
    DatabaseExecutor tx,
    Map<String, Object?> a,
    int id, {
    bool yazma = false,
  }) async {
    final rows = await tx.query(
      'OgrenciSinifKayit',
      where: 'OgrenciId=? AND SinifSubeId=? AND EgitimOgretimYili=?',
      whereArgs: [id, a['SinifSubeId'], a['EgitimOgretimYili']],
    );
    if (rows.isEmpty) {
      throw StateError('Öğrenci bu sınıf ve eğitim yılında bulunmuyor.');
    }
    if (yazma) {
      final aktif = await tx.query(
        'Ogrenci',
        where: 'OgrenciId=? AND Aktif=1',
        whereArgs: [id],
      );
      if (aktif.isEmpty || rows.every((r) => r['Aktif'] != 1)) {
        throw StateError('Öğrencinin güncel aktif sınıf kaydı bulunmuyor.');
      }
    }
  }

  Future<List<String>> atamaYillari(BireyselRehberlikBaglami b) async {
    final db = await _db();
    await _kontrol(db, b);
    final rows = await db.rawQuery(
      '''SELECT DISTINCT EgitimOgretimYili FROM RehberlikAtama
      WHERE OkulId=? AND OgretmenProfilId=? ORDER BY EgitimOgretimYili DESC''',
      [b.okulId, b.ogretmenProfilId],
    );
    await _kontrol(db, b);
    return {
      b.egitimOgretimYili,
      ...rows.map((r) => r['EgitimOgretimYili'] as String),
    }.toList();
  }

  Future<List<Map<String, Object?>>> kayitlar(
    BireyselRehberlikBaglami b,
    int atamaId, {
    bool hassasOnay = false,
  }) async {
    final db = await _db();
    return db.transaction((tx) async {
      await _atama(tx, b, atamaId);
      final rows = await tx.query(
        'RehberlikKayit',
        where: 'AtamaId=?',
        whereArgs: [atamaId],
        orderBy: 'Tarih,Id',
      );
      await _kontrol(tx, b);
      return rows
          .map(
            (r) => Map<String, Object?>.unmodifiable({
              ...r,
              if (r['Hassas'] == 1 && !hassasOnay) 'Icerik': '{}',
              if (r['Hassas'] == 1 && !hassasOnay) 'Baslik': 'Hassas kayıt',
            }),
          )
          .toList();
    });
  }

  Future<int> kayitKaydet(
    BireyselRehberlikBaglami b,
    int atamaId, {
    int? id,
    required String tur,
    required String baslik,
    String? tarih,
    String durum = 'Planlandi',
    int? ogrenciId,
    Map<String, Object?> icerik = const {},
    bool hassas = false,
    bool hassasOnay = false,
  }) async {
    if (!rehberlikTurleri.containsKey(tur) ||
        !rehberlikDurumlari.contains(durum) ||
        baslik.trim().isEmpty ||
        baslik.length > 300 ||
        jsonEncode(icerik).length > 100000) {
      throw const FormatException(
        'Kayıt türünü, başlığı ve içeriği kontrol edin.',
      );
    }
    if (tarih != null && tarih.isNotEmpty) {
      BireyselRehberlikService._tarih(tarih);
    }
    if (hassas && !hassasOnay) throw StateError('Hassas kayıt erişimini açın.');
    final db = await _db();
    return _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atamaId, yazma: true);
        if (ogrenciId != null) {
          await _ogrenciKontrol(tx, a, ogrenciId, yazma: true);
        }
        final row = <String, Object?>{
          'AtamaId': atamaId,
          'Tur': tur,
          'Baslik': baslik.trim(),
          'Tarih': tarih?.isEmpty == true ? null : tarih,
          'Durum': durum,
          'OgrenciId': ogrenciId,
          'Icerik': jsonEncode(icerik),
          'Hassas': hassas ? 1 : 0,
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        };
        int sonuc;
        if (id == null) {
          row['OlusturmaTarihi'] = DateTime.now().toIso8601String();
          sonuc = await tx.insert('RehberlikKayit', row);
        } else {
          final eski = await tx.query(
            'RehberlikKayit',
            where: 'Id=? AND AtamaId=?',
            whereArgs: [id, atamaId],
          );
          if (eski.length != 1 || (eski.single['Hassas'] == 1 && !hassasOnay)) {
            throw StateError('Kayıt kapsamı veya hassas erişim geçersiz.');
          }
          if (eski.single['Tur'] != tur) {
            throw StateError('Kayıt türü sonradan değiştirilemez.');
          }
          await tx.update(
            'RehberlikKayit',
            row,
            where: 'Id=?',
            whereArgs: [id],
          );
          sonuc = id;
        }
        await _kontrol(tx, b);
        return sonuc;
      }),
    );
  }

  Future<void> bagla(
    BireyselRehberlikBaglami b,
    int atamaId,
    int id,
    int ilgili,
  ) async {
    if (id == ilgili) {
      throw const FormatException('Kayıt kendisine bağlanamaz.');
    }
    final db = await _db();
    await _sirali(
      () => db.transaction((tx) async {
        await _atama(tx, b, atamaId, yazma: true);
        final rows = await tx.query(
          'RehberlikKayit',
          where: 'AtamaId=? AND Id IN (?,?)',
          whereArgs: [atamaId, id, ilgili],
        );
        if (rows.length != 2) {
          throw StateError(
            'İlişkili kayıtlar aynı rehberlik atamasında olmalı.',
          );
        }
        final ilk = id < ilgili ? id : ilgili;
        final ikinci = id < ilgili ? ilgili : id;
        final mevcut = await tx.query(
          'RehberlikBag',
          where: 'KayitId=? AND IlgiliId=?',
          whereArgs: [ilk, ikinci],
        );
        if (mevcut.isEmpty) {
          await tx.insert('RehberlikBag', {'KayitId': ilk, 'IlgiliId': ikinci});
        }
        await _kontrol(tx, b);
      }),
    );
  }

  Future<List<Map<String, Object?>>> baglar(
    BireyselRehberlikBaglami b,
    int atamaId,
  ) async {
    final db = await _db();
    await _atama(db, b, atamaId);
    return db.rawQuery(
      '''SELECT x.* FROM RehberlikBag x JOIN RehberlikKayit k ON k.Id=x.KayitId
      WHERE k.AtamaId=?''',
      [atamaId],
    );
  }

  Future<int> formKaydet(
    BireyselRehberlikBaglami b,
    int atamaId,
    int ogrenciId,
    List<String> sorular,
    Map<String, String> cevaplar, {
    required bool hassasOnay,
  }) async {
    if (!hassasOnay) throw StateError('Hassas form erişimini açın.');
    if (sorular.isEmpty ||
        sorular.length > 100 ||
        sorular.toSet().length != sorular.length ||
        sorular.any((s) => s.trim().isEmpty || s.length > 300) ||
        cevaplar.keys.any((k) => !sorular.contains(k)) ||
        jsonEncode(cevaplar).length > 100000) {
      throw const FormatException(
        'Form sorularını ve cevaplarını kontrol edin.',
      );
    }
    final db = await _db();
    return _sirali(
      () => db.transaction((tx) async {
        final a = await _atama(tx, b, atamaId, yazma: true);
        await _ogrenciKontrol(tx, a, ogrenciId, yazma: true);
        final son = await tx.query(
          'RehberlikForm',
          where: 'AtamaId=? AND OgrenciId=?',
          whereArgs: [atamaId, ogrenciId],
          orderBy: 'Id DESC',
          limit: 1,
        );
        if (son.isNotEmpty) {
          final oncekiSorular = List<String>.from(
            jsonDecode(son.single['Sorular'] as String) as List,
          );
          final oncekiCevaplar = Map<String, String>.from(
            jsonDecode(son.single['Cevaplar'] as String) as Map,
          );
          // Soru sırası ekran düzenidir; cevap anahtarlarının sırası değildir.
          // Eksik cevap ile boş metin aynı, diğer metin farkları gerçektir.
          final ayni =
              oncekiSorular.length == sorular.length &&
              List.generate(
                sorular.length,
                (i) => i,
              ).every((i) => oncekiSorular[i] == sorular[i]) &&
              oncekiCevaplar.keys.every(sorular.contains) &&
              sorular.every(
                (s) => (oncekiCevaplar[s] ?? '') == (cevaplar[s] ?? ''),
              );
          if (ayni) {
            await _kontrol(tx, b);
            return son.single['Id'] as int;
          }
        }
        final id = await tx.insert('RehberlikForm', {
          'AtamaId': atamaId,
          'OgrenciId': ogrenciId,
          'Sorular': jsonEncode(sorular),
          'Cevaplar': jsonEncode(cevaplar),
          'OlusturmaTarihi': DateTime.now().toIso8601String(),
        });
        await _kontrol(tx, b);
        return id;
      }),
    );
  }

  Future<Map<String, Object?>> formVeliBilgileri(
    BireyselRehberlikBaglami b,
    int atamaId,
    int ogrenciId, {
    required bool hassasOnay,
  }) async {
    if (!hassasOnay) throw StateError('Hassas form erişimini açın.');
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atamaId);
      await _ogrenciKontrol(tx, a, ogrenciId);
      final rows = await tx.query(
        'Ogrenci',
        columns: ['VeliTuru', 'AnneAdi', 'AnneTelefon', 'BabaAdi',
          'BabaTelefon', 'VeliAdi', 'VeliTelefonu'],
        where: 'OgrenciId=?',
        whereArgs: [ogrenciId],
      );
      if (rows.length != 1) throw StateError('Öğrenci kaydı bulunamadı.');
      await _kontrol(tx, b);
      return Map<String, Object?>.unmodifiable(rows.single);
    });
  }

  Future<List<Map<String, Object?>>> formlar(
    BireyselRehberlikBaglami b,
    int atamaId,
    int ogrenciId, {
    required bool hassasOnay,
  }) async {
    if (!hassasOnay) throw StateError('Hassas form erişimini açın.');
    final db = await _db();
    return db.transaction((tx) async {
      final a = await _atama(tx, b, atamaId);
      await _ogrenciKontrol(tx, a, ogrenciId);
      final rows = await tx.query(
        'RehberlikForm',
        where: 'AtamaId=? AND OgrenciId=?',
        whereArgs: [atamaId, ogrenciId],
        orderBy: 'Id DESC',
      );
      await _kontrol(tx, b);
      return rows;
    });
  }

  ImportTanimi planImportTanimi(
    BireyselRehberlikBaglami b,
    int atamaId,
  ) => ImportTanimi(
    id: 'rehberlik_plan',
    uzantilar: const {'xls', 'xlsx', 'csv', 'doc', 'docx'},
    ozelOkuyucuAdi: 'Mevcut Word plan tablosu',
    ozelOku: (file) async {
      await BelgeAnalizService.bicimiDogrulaAsync(file);
      final satirlar = BireyselYillikPlanService.hamWordTablosu(
        file.bytes,
        file.uzanti,
      );
      final tanim = planImportTanimi(b, atamaId);
      final tablo = ImportTablosu('Word', satirlar);
      final baslik = tablo.baslikBul(tanim);
      final esleme = tablo.otomatikEsle(tanim, baslik);
      final hatalar = tablo.eslemeHatalari(tanim, baslik, esleme);
      if (hatalar.isNotEmpty) throw FormatException(hatalar.join('\n'));
      return tanim.hazirla(tablo.esle(baslik, esleme));
    },
    ad: 'Rehberlik Planı Import',
    aciklama:
        'Tarih, Hafta, Saat ve Konu eşleştirilir. Aynı haftanın satırları ayrı tutulur. Tekrar yükleme geçmiş faaliyetleri değiştirmez; değişmiş satırlar yeni kayıt olarak eklenir.',
    alanlar: const [
      ImportAlan('tarih', 'Tarih', alternatifler: ['Tarih Aralığı']),
      ImportAlan('hafta', 'Hafta', zorunlu: true, alternatifler: ['Hafta No']),
      ImportAlan('saat', 'Saat'),
      ImportAlan('konu', 'Konu', zorunlu: true, alternatifler: ['Etkinlik']),
      ImportAlan('tur', 'Tür', alternatifler: ['Kayıt Türü']),
    ],
    hazirla: (rows) async => ImportOnIzleme(
      rows.map((r) {
        final hata =
            (r.degerler['konu'] ?? '').trim().isEmpty ||
            (r.degerler['hafta'] ?? '').trim().isEmpty;
        return ImportKaydi(
          r.id,
          r.konum,
          r.degerler,
          durum: hata ? ImportDurumu.hatali : ImportDurumu.uygun,
          mesajlar: hata ? ['Hafta ve konu zorunludur.'] : [],
        );
      }).toList(),
    ),
    aktar: (preview, secimler) async {
      if (preview.engeller.isNotEmpty ||
          secimler.isEmpty ||
          secimler.any(
            (id) => !preview.kayitlar.any((r) => r.id == id && r.aktarilabilir),
          )) {
        throw StateError('Geçerli plan satırlarını seçin.');
      }
      final db = await _db();
      return _sirali(
        () => db.transaction((tx) async {
          await _atama(tx, b, atamaId, yazma: true);
          var eklenen = 0, atlanan = 0;
          final tekrar = <String, int>{};
          for (final r in preview.kayitlar.where((r) => r.aktarilabilir)) {
            final v = r.degerler;
            final temel = jsonEncode([
              v['tarih'] ?? '',
              v['hafta'] ?? '',
              v['saat'] ?? '',
              v['konu'] ?? '',
            ]);
            final sira = (tekrar[temel] ?? 0) + 1;
            tekrar[temel] = sira;
            if (!secimler.contains(r.id)) continue;
            final anahtar = '$temel#$sira';
            final eski = await tx.query(
              'RehberlikKayit',
              where: 'AtamaId=? AND KaynakAnahtar=?',
              whereArgs: [atamaId, anahtar],
            );
            if (eski.isNotEmpty) {
              atlanan++;
              continue;
            }
            final konu = v['konu']!.trim();
            if (konu.isEmpty ||
                konu.length > 300 ||
                (v['hafta'] ?? '').trim().isEmpty) {
              throw const FormatException('Plan satırı geçersiz.');
            }
            final metin = importNormalize('${v['tur'] ?? ''} $konu');
            final hedef = metin.contains('toplanti')
                ? 'Toplanti'
                : metin.contains('form')
                ? 'Gorev'
                : metin.contains('etkinlik')
                ? 'Etkinlik'
                : 'Gorev';
            await tx.insert('RehberlikKayit', {
              'AtamaId': atamaId,
              'Tur': 'Plan',
              'Baslik': konu,
              'Icerik': jsonEncode({...v, 'hedef': hedef}),
              'KaynakAnahtar': anahtar,
              'OlusturmaTarihi': DateTime.now().toIso8601String(),
            });
            eklenen++;
          }
          await _kontrol(tx, b);
          return ImportOzet(
            eklenen: eklenen,
            guncellenen: 0,
            atlanan: atlanan,
            hatali: 0,
            mesaj:
                '$eklenen plan satırı eklendi; $atlanan mevcut satır korundu.',
          );
        }),
      );
    },
  );
}
