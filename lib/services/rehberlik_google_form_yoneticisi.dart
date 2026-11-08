import 'dart:convert';
import '../models/ogrenci_bilgi_formu.dart';
import 'bireysel_rehberlik_service.dart';
import 'rehberlik_google_form_service.dart';

/// SQLite rehberlik ataması ile Google Forms API arasındaki işlem sırası.
/// OAuth yetkisini UI sağlar; bu sınıf hesap veya token saklamaz.
class RehberlikGoogleFormYoneticisi {
  RehberlikGoogleFormYoneticisi({
    required this.rehberlik,
    required this.google,
  });

  final BireyselRehberlikService rehberlik;
  final RehberlikGoogleFormService google;

  Future<GoogleRehberlikFormSonucu> hazirla({
    required BireyselRehberlikBaglami baglam,
    required int atamaId,
    required String sinifKodu,
    required String erisimBelirteci,
    bool yalnizOgrenciListesi = false,
  }) async {
    await rehberlik.googleYazmaYetkisiniKontrol(baglam, atamaId);
    final ogrenciler = await rehberlik.googleOgrenciSecenekleriniHazirla(
      baglam,
      atamaId,
    );
    // Önce SQLite: aynı atamada ikinci formu sessizce üretme.
    final mevcut = await rehberlik.googleFormKaydiGetir(baglam, atamaId);
    final kayitliSorular = await rehberlik.formSorulari(baglam, atamaId);
    // Eski rehberlik ekranının genel MEB başlıklarını ikinci kez ekleme.
    // Güncel ayrıntılı Öğrenci Bilgi Formu soruları zaten temel listededir.
    final ozelSorular = kayitliSorular.where(
      (s) => !mebTanimaSorulari.contains(s),
    );
    final sorular = RehberlikGoogleFormService.sorulariHazirla(ozelSorular);
    final formId = mevcut?['GoogleFormId']?.toString();
    if (formId != null && formId.isNotEmpty) {
      final gercek = await google.mevcutFormuOku(
        erisimBelirteci: erisimBelirteci,
        googleFormId: formId,
      );
      final eskiler = jsonDecode(mevcut!['SoruEslemeleri'] as String) as Map;
      for (final e in eskiler.entries) {
        final yeni = gercek.soruEslemeleri[e.key];
        // Kaldırılan kimlik sorularının eski yanıt anahtarları yerelde korunur.
        if (yeni == null && googleElleKimlikSorulari.contains(e.key)) continue;
        if (yeni == null ||
            yeni['itemId'] != e.value['itemId'] ||
            yeni['questionId'] != e.value['questionId']) {
          throw StateError(
            'Google Formdaki kayıtlı soru değişmiş. Soruyu geri yükleyip kontrol edin; yeni soru eklenmedi.',
          );
        }
      }
      if (!yalnizOgrenciListesi) {
        await google.eksikSorulariTamamla(
          erisimBelirteci: erisimBelirteci,
          googleFormId: formId,
          sorular: sorular
              .where((s) => s != RehberlikGoogleFormService.ogrenciSecimSorusu)
              .toList(),
        );
      }
      final sonuc = await google.ogrenciListesiniGuncelle(
        erisimBelirteci: erisimBelirteci,
        googleFormId: formId,
        secenekler: ogrenciler.keys.toList(),
      );
      // Mevcut soru haritası ile güncel form birbirinden farklıysa
      // yetkisiz üzerine yazma yapılmaz, öğretmen incelemesi gerekir.
      await rehberlik.googleFormEslemeleriniKaydet(baglam, atamaId, formId, {
        for (final e in eskiler.entries)
          if (googleElleKimlikSorulari.contains(e.key))
            e.key.toString(): Map<String, String>.from(e.value as Map),
        ...sonuc.soruEslemeleri,
      });
      return sonuc;
    }

    final baslik =
        '$sinifKodu • ${baglam.egitimOgretimYili} Öğrenci Tanıma Fişi';
    await rehberlik.googleOlusturmayiBaslat(baglam, atamaId);
    final sonuc = await google.formOlustur(
      erisimBelirteci: erisimBelirteci,
      baslik: baslik,
      sorular: sorular,
      ogrenciSecenekleri: ogrenciler.keys.toList(),
      onFormOlusturuldu: (id) =>
          rehberlik.googleFormKimliginiKaydet(baglam, atamaId, id),
    );
    await rehberlik.googleFormEslemeleriniKaydet(
      baglam,
      atamaId,
      sonuc.googleFormId,
      sonuc.soruEslemeleri,
    );
    return sonuc;
  }

  /// Google Forms'ta daha önce açılmış bir formu manuel olarak bağlamak
  /// yalnız boş sınıf kaydında mümkündür. Böylece bağlantı kesildiğinde
  /// formun tekrar oluşturulması önlenebilir.
  Future<GoogleRehberlikFormSonucu> varOlanFormuBagla({
    required BireyselRehberlikBaglami baglam,
    required int atamaId,
    required String googleFormId,
    required String erisimBelirteci,
  }) async {
    final form = await google.mevcutFormuOku(
      erisimBelirteci: erisimBelirteci,
      googleFormId: googleFormId,
    );
    await rehberlik.googleFormKimliginiKaydet(baglam, atamaId, googleFormId);
    if (form.soruEslemeleri.isNotEmpty) {
      await rehberlik.googleFormEslemeleriniKaydet(
        baglam,
        atamaId,
        googleFormId,
        form.soruEslemeleri,
      );
    }
    return form;
  }
}
