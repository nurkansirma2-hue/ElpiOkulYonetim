part of 'bireysel_bakim_service.dart';

class SifirlamaModulu {
  const SifirlamaModulu(this.id, this.ad, this.aciklama, this.tablolar);
  final String id, ad, aciklama;
  final List<String> tablolar;
}

class SifirlamaEnvanteri {
  SifirlamaEnvanteri._(this.sayilar, this.baglar, this.sema);
  final Map<String, int> sayilar;
  final Map<String, Set<String>> baglar;
  final String sema;

  SifirlamaPlani planla(Set<String> secilen) {
    const tum = BireyselSifirlama.moduller;
    if (secilen.difference(tum.map((m) => m.id).toSet()).isNotEmpty) {
      throw StateError('Geçersiz sıfırlama modülü.');
    }
    final kapsam = Set<String>.of(secilen);
    final nedenler = <String, String>{};
    var degisti = true;
    while (degisti) {
      degisti = false;
      for (final id in kapsam.toList()) {
        for (final bag in baglar[id] ?? <String>{}) {
          if (kapsam.add(bag)) {
            nedenler[bag] = tum.singleWhere((m) => m.id == id).ad;
            degisti = true;
          }
        }
      }
    }
    final tablolar = {
      for (final m in tum.where((m) => kapsam.contains(m.id))) ...m.tablolar,
    };
    return SifirlamaPlani._(
      this,
      Set.unmodifiable(secilen),
      Set.unmodifiable(kapsam),
      Map.unmodifiable(nedenler),
      Set.unmodifiable(tablolar),
    );
  }

  int kayitSayisi(SifirlamaModulu m) =>
      m.tablolar.fold(0, (n, t) => n + (sayilar[t] ?? 0));
}

class SifirlamaPlani {
  SifirlamaPlani._(
    this.envanter,
    this.secilen,
    this.kapsam,
    this.nedenler,
    this.tablolar,
  );
  final SifirlamaEnvanteri envanter;
  final Set<String> secilen, kapsam, tablolar;
  final Map<String, String> nedenler;
  int get kayitSayisi =>
      tablolar.fold(0, (n, t) => n + (envanter.sayilar[t] ?? 0));
}

extension BireyselSifirlama on BireyselBakimService {
  static const moduller = [
    SifirlamaModulu(
      'profil',
      'Öğretmen ve okul profili',
      'Profil silinirse öğretmen kurulumuna dönülür. Bağlı modüller de dahil edilir.',
      ['OgretmenProfil', 'OkulProfil', 'OgretmenAktivasyon'],
    ),
    SifirlamaModulu(
      'siniflar',
      'Sınıflar',
      'Tüm yılların sınıfları ve bağlı modülleri.',
      ['SinifSube'],
    ),
    SifirlamaModulu(
      'dersler',
      'Dersler ve ders saatleri',
      'Ders tanımları, saatler ve ders–sınıf eşleştirmeleri.',
      ['Ders', 'DersSaati', 'DersSinif'],
    ),
    SifirlamaModulu(
      'program',
      'Ders programları',
      'Haftalık programlar, program sürümleri ve program görevleri.',
      ['DersProgrami', 'DersProgramiSurum', 'DersProgramiGorev'],
    ),
    SifirlamaModulu(
      'planlar',
      'Yıllık planlar',
      'Yıllık planlar ve haftalık plan detayları.',
      ['YillikPlan', 'YillikPlanDetay'],
    ),
    SifirlamaModulu(
      'takvim',
      'Çalışma takvimleri',
      'Çalışma takvimleri ve takvim detayları.',
      ['CalismaTakvimi', 'CalismaTakvimiDetay'],
    ),
    SifirlamaModulu(
      'ogrenciler',
      'Öğrenciler ve veli bilgileri',
      'Öğrenci kayıtları, sınıf üyelikleri ve kayıtlı iletişim bilgileri.',
      ['Ogrenci', 'OgrenciSinifKayit', 'OgrenciIletisim'],
    ),
    SifirlamaModulu(
      'fotograflar',
      'Öğrenci fotoğrafları',
      'Uygulamadaki fotoğraf kayıtları; kaynak dosyalar silinmez.',
      ['OgrenciFotograf'],
    ),
    SifirlamaModulu(
      'ogretmenler',
      'Sınıf öğretmenleri ve ders ilişkileri',
      'Öğretmen iletişim rehberi ve öğretmen–sınıf–ders bağlantıları.',
      ['MesajOgretmenKisi', 'MesajOgretmenSinif', 'MesajOgretmenSinifDers'],
    ),
    SifirlamaModulu(
      'gunluk',
      'Günlük planlar',
      'Kaydedilmiş günlük ders planları.',
      ['BireyselGunlukPlan'],
    ),
    SifirlamaModulu(
      'odev',
      'Ödevler ve değerlendirmeler',
      'Ödevler, görev öğrencileri, kontroller, ölçütler ve puanlar.',
      [
        ...OdevNotSemasi.tablolar,
        ...DersUygulamaSemasi.tablolar,
        'OdevTanim',
        'OdevOgrenci',
        'OdevKontrol',
        'OdevKontrolSonuc',
        'OdevDegerlendirmeOlcutu',
        'OdevDegerlendirmePuani',
      ],
    ),
    SifirlamaModulu(
      'rehberlik',
      'Sınıf rehberliği',
      'Rehberlik atamaları, planlar, görüşmeler ve yerel form kayıtları.',
      [
        'RehberlikAtama',
        'RehberlikKayit',
        'RehberlikBag',
        'RehberlikForm',
        'RehberlikGoogleForm',
        'RehberlikFormDavet',
        'RehberlikGoogleYanit',
      ],
    ),
    SifirlamaModulu(
      'formlar',
      'Bilgi toplama formları',
      'Yerel formlar, yanıtlar ve ek bilgiler. Öğrenciye kaydedilmiş ana bilgiler korunur.',
      [
        'BilgiToplamaForm',
        'BilgiToplamaSoru',
        'BilgiToplamaHedef',
        'BilgiToplamaYanit',
        'BilgiToplamaEsleme',
        'OgrenciEkBilgiDeger',
      ],
    ),
    SifirlamaModulu(
      'mesajlar',
      'Mesajlaşma kuyrukları ve geçmişi',
      'SMS/WhatsApp kuyrukları, yerel gönderim durumları ve mesaj formu kayıtları.',
      [
        'MesajKuyrugu',
        'MesajAlici',
        'MesajSms',
        'MesajTekliGecmis',
        'MesajAliciBag',
        'MesajForm',
        'MesajFormCevap',
      ],
    ),
    SifirlamaModulu(
      'seflik',
      'Şeflik',
      'Şeflik tanımları, mekanlar, sorumluluklar ve program saatleri.',
      [
        'SeflikTanim',
        'SeflikMekan',
        'SeflikSorumluMekan',
        'SeflikProgramSaati',
      ],
    ),
    SifirlamaModulu(
      'ayarlar',
      'Bireysel veritabanı ayarları',
      'SQLite içinde tutulan uygulama ayarları; çalışma modu korunur.',
      ['UygulamaAyarlari'],
    ),
  ];
  static const _korunan = {
    'BelgeArsivi',
    'BireyselBelge',
    'BelgeKlasoru',
    'BelgeImportGecmisi',
    'BelgeSilmeBekleyen',
  };

  Future<SifirlamaEnvanteri> sifirlamaEnvanteri() async {
    await _yetki();
    return (await _db()).transaction(_sifirlamaEnvanteri);
  }

  Future<SifirlamaEnvanteri> _sifirlamaEnvanteri(Transaction tx) async {
    final sema = await _sema(tx);
    final adlar = sema.map((r) => r['name'] as String).toSet();
    final sahip = {
      for (final m in moduller)
        for (final t in m.tablolar) t: m.id,
    };
    if (adlar.difference({...sahip.keys, ..._korunan}).isNotEmpty ||
        sahip.keys.toSet().difference(adlar).isNotEmpty) {
      throw StateError(
        'Veritabanı yapısı sıfırlama listesiyle uyuşmuyor. İşlem yapılmadı.',
      );
    }
    final baglar = {for (final m in moduller) m.id: <String>{}};
    final sayilar = <String, int>{};
    final iliskiler = <String, Object?>{};
    for (final t in adlar) {
      final fk = await tx.rawQuery('PRAGMA foreign_key_list("$t")');
      iliskiler[t] = fk;
      for (final r in fk) {
        final ebeveyn = sahip[r['table']], cocuk = sahip[t];
        if (ebeveyn == null) continue;
        if (cocuk == null) {
          throw StateError(
            'Korunan belge verisi sıfırlama kapsamına bağlanmış. İşlem durduruldu.',
          );
        }
        if (cocuk != ebeveyn) baglar[ebeveyn]!.add(cocuk);
      }
      if (sahip.containsKey(t)) {
        sayilar[t] = Sqflite.firstIntValue(
          await tx.rawQuery('SELECT count(*) FROM "$t"'),
        )!;
      }
    }
    return SifirlamaEnvanteri._(
      Map.unmodifiable(sayilar),
      Map.unmodifiable(
        baglar.map((k, v) => MapEntry(k, Set<String>.unmodifiable(v))),
      ),
      jsonEncode([sema, iliskiler]),
    );
  }

  Future<void> seciliModulleriSifirla(
    SifirlamaPlani plan, {
    required String onayMetni,
  }) => _sirali(() async {
    await _yetki();
    if (onayMetni != 'SIFIRLA' || plan.secilen.isEmpty) {
      throw StateError('Modül seçimi ve SIFIRLA onayı gereklidir.');
    }
    final db = await _db();
    try {
      await db.transaction((tx) async {
        final guncel = await _sifirlamaEnvanteri(tx);
        final yeni = guncel.planla(plan.secilen);
        if (guncel.sema != plan.envanter.sema ||
            !yeni.kapsam.containsAll(plan.kapsam) ||
            !plan.kapsam.containsAll(yeni.kapsam) ||
            yeni.tablolar.any(
              (t) => guncel.sayilar[t] != plan.envanter.sayilar[t],
            )) {
          throw StateError(
            'Veriler veya ilişkiler değişti. Seçimleri yeniden kontrol edip onaylayın.',
          );
        }
        await _yetki();
        final sira = await _siraGetir(tx, yeni.tablolar.toList());
        for (final t in sira.reversed) {
          await tx.delete(t);
        }
        if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw StateError('Veri ilişkileri doğrulanamadı.');
        }
        await _yetki();
      });
    } catch (e) {
      throw StateError(
        'Sıfırlama uygulanmadı; işlem geri alındı. Orijinal hata: $e',
      );
    }
  });
}
