import '../models/ortak_import.dart';
import 'bireysel_yillik_plan_service.dart';

class YillikPlanImportTanimi {
  static const alanlar = [
    ImportAlan(
      'hafta',
      'Hafta',
      zorunlu: true,
      alternatifler: ['Hafta No', 'Hafta Numarası'],
      filtrelenebilir: true,
      gruplanabilir: true,
    ),
    ImportAlan(
      'ay',
      'Ay',
      kolonDisiKapsam: ImportBilgiKapsami.blok,
      filtrelenebilir: true,
      gruplanabilir: true,
    ),
    ImportAlan('tarih', 'Tarih', alternatifler: ['Tarih Aralığı']),
    ImportAlan('saat', 'Saat', alternatifler: ['Ders Saati', 'Süre']),
    ImportAlan('konu', 'Konu', alternatifler: ['Konular']),
    ImportAlan('unite', 'Ünite', filtrelenebilir: true),
    ImportAlan('kazanim', 'Kazanım', alternatifler: ['Kazanımlar']),
    ImportAlan('kazanimAciklamasi', 'Kazanım Açıklaması'),
    ImportAlan('ogrenmeBirimi', 'Öğrenme Birimi'),
    ImportAlan(
      'icerikCercevesi',
      'İçerik Çerçevesi',
      alternatifler: ['Konu İçerik Çerçevesi'],
    ),
    ImportAlan(
      'ogrenmeCiktisi',
      'Öğrenme Çıktısı',
      alternatifler: ['Öğrenme Çıktıları', 'Kazanım Öğrenme Çıktısı'],
    ),
    ImportAlan('surecBilesenleri', 'Süreç Bileşenleri'),
    ImportAlan(
      'yontemTeknik',
      'Yöntem Teknik',
      alternatifler: ['Öğretim Teknikleri'],
    ),
    ImportAlan('aracGerec', 'Araç Gereç'),
    ImportAlan('etkinlik', 'Belirli Gün ve Haftalar', alternatifler: ['Etkinlikler']),
    ImportAlan('degerlendirme', 'Değerlendirme', alternatifler: ['Açıklama']),
    ImportAlan('tur', 'Kayıt Türü', kolondan: false, filtrelenebilir: true),
  ];

  static ImportTanimi olustur(String yil) => ImportTanimi(
    id: 'bireysel_yillik_plan',
    ad: 'Yıllık Plan Import',
    aciklama:
        'Seçtiğiniz plan ve takvim kayıtlarını ders, sınıf ve eğitim yılı bilgilerini kontrol ederek bu ekrandan onaylayıp kaydedebilirsiniz. Seçilmeyen mevcut plan kayıtları korunur.',
    uzantilar: const {'xls', 'xlsx', 'csv', 'doc', 'docx'},
    alanlar: alanlar,
    duzenlemeHazirla: (preview, rows) async {
      final asil = preview.veri as BireyselYillikPlanOnIzleme;
      final yeni = BireyselYillikPlanService.eslenmisSatirlariOku(
        rows
            .where((r) => r.degerler['tur'] == 'Plan')
            .map((r) => r.degerler)
            .toList(),
        egitimOgretimYili: yil,
      );
      if (yeni.hatalar.isNotEmpty) throw StateError(yeni.hatalar.join('\n'));
      return onIzlemeyeCevir(
        BireyselYillikPlanOnIzleme(
          dosyaAdi: asil.dosyaAdi,
          dosyaTuru: asil.dosyaTuru,
          baslikSatiri: asil.baslikSatiri,
          tespitEdilenDersAdi: asil.tespitEdilenDersAdi,
          tespitEdilenSinifSeviyesi: asil.tespitEdilenSinifSeviyesi,
          kayitlar: yeni.kayitlar,
          calismaTakvimi: [
            ...yeni.calismaTakvimi.where((r) => r.kayitTuru == 'DersHaftasi'),
            ...asil.calismaTakvimi.where((r) => r.kayitTuru != 'DersHaftasi'),
          ],
          hatalar: asil.hatalar,
        ),
      );
    },
    ozelDuzeniTani: (_) => true,
    ozelOkuyucuAdi: 'Mevcut yıllık plan / birleşik hücre düzeni',
    ozelOku: (file) async => onIzlemeyeCevir(
      await BireyselYillikPlanService.onIzlemeHazirla(
        dosyaBytes: file.bytes,
        dosyaAdi: file.ad,
        dosyaUzantisi: file.uzanti,
        egitimOgretimYili: yil,
      ),
    ),
    hazirla: (rows) async => onIzlemeyeCevir(
      BireyselYillikPlanService.eslenmisSatirlariOku(
        rows.map((r) => r.degerler).toList(),
        egitimOgretimYili: yil,
      ),
    ),
    aktar: (_, _) async => throw StateError(
      'Yıllık planın ders uygunluk ve onay ekranını kullanın.',
    ),
  );

  static ImportOnIzleme onIzlemeyeCevir(
    BireyselYillikPlanOnIzleme p,
  ) => ImportOnIzleme(
    [
      for (var i = 0; i < p.kayitlar.length; i++)
        ImportKaydi('plan:$i', 'Satır ${p.kayitlar[i].satirNo}', {
          'hafta': '${p.kayitlar[i].haftaNo}',
          'ay': p.kayitlar[i].ay,
          'tarih': p.kayitlar[i].tarihAraligi,
          'saat': p.kayitlar[i].saat,
          'konu': p.kayitlar[i].konu,
          'unite': p.kayitlar[i].unite,
          'kazanim': p.kayitlar[i].kazanim,
          'kazanimAciklamasi': p.kayitlar[i].kazanimAciklamasi,
          'ogrenmeBirimi': p.kayitlar[i].ogrenmeBirimi,
          'icerikCercevesi': p.kayitlar[i].icerikCercevesi,
          'ogrenmeCiktisi': p.kayitlar[i].ogrenmeCiktisi,
          'surecBilesenleri': p.kayitlar[i].surecBilesenleri,
          'yontemTeknik': p.kayitlar[i].yontemTeknik,
          'aracGerec': p.kayitlar[i].aracGerec,
          'degerlendirme': p.kayitlar[i].degerlendirme,
          'etkinlik': p.kayitlar[i].etkinlik,
          'tur': 'Plan',
        }),
      for (var i = 0; i < p.calismaTakvimi.length; i++)
        if (p.calismaTakvimi[i].kayitTuru != 'DersHaftasi')
          ImportKaydi('takvim:$i', p.calismaTakvimi[i].aciklama, {
            'hafta': '${p.calismaTakvimi[i].haftaNo ?? ''}',
            'ay': p.calismaTakvimi[i].ay,
            'tarih': p.calismaTakvimi[i].tarihAraligi,
            'tur': p.calismaTakvimi[i].kayitTuru,
            'degerlendirme': p.calismaTakvimi[i].ozelGunAciklamasi,
          }),
    ],
    veri: p,
    engeller: p.hatalar,
    bilgiler: const [
      'Bir haftanın planını seçtiğinizde o haftanın ders takvimi de birlikte hazırlanır. Tatil kayıtlarını ayrıca seçebilirsiniz.',
    ],
  );

  static BireyselYillikPlanOnIzleme secimiUygula(ImportSecimi secim) {
    final preview = secim.onIzleme;
    final selected = secim.secimler;
    final eligible = preview.kayitlar
        .where((r) => r.aktarilabilir)
        .map((r) => r.id)
        .toSet();
    if (preview.engeller.isNotEmpty ||
        selected.isEmpty ||
        !eligible.containsAll(selected)) {
      throw StateError('Geçerli plan kayıtlarını seçin.');
    }
    final p = preview.veri as BireyselYillikPlanOnIzleme;
    final plans = [
      for (var i = 0; i < p.kayitlar.length; i++)
        if (selected.contains('plan:$i')) p.kayitlar[i],
    ];
    if (plans.isEmpty) throw StateError('En az bir plan haftası seçin.');
    final weeks = plans.map((r) => r.haftaNo).toSet();
    final calendar = [
      for (var i = 0; i < p.calismaTakvimi.length; i++)
        if (selected.contains('takvim:$i') ||
            (p.calismaTakvimi[i].kayitTuru == 'DersHaftasi' &&
                weeks.contains(p.calismaTakvimi[i].haftaNo)))
          p.calismaTakvimi[i],
    ];
    return BireyselYillikPlanOnIzleme(
      dosyaAdi: secim.dosya.ad,
      dosyaTuru: p.dosyaTuru,
      baslikSatiri: p.baslikSatiri,
      tespitEdilenDersAdi: p.tespitEdilenDersAdi,
      tespitEdilenSinifSeviyesi: p.tespitEdilenSinifSeviyesi,
      kayitlar: List.unmodifiable(plans),
      calismaTakvimi: List.unmodifiable(calendar),
      hatalar: p.hatalar,
    );
  }
}
