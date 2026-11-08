import 'bireysel_bilgi_toplama_service.dart';
import 'bireysel_rehberlik_service.dart';
import 'ogretmen_gorus_google_service.dart';
import '../models/mesajlasma.dart';

/// Ortak form modülünün fotoğraflı öğretmen görüşü şablonunu yürütür.
/// Fotoğraf aktarımı için mevcut Apps Script adaptörü ve mevcut toplantı kaydı kullanılır.
class BilgiToplamaOgretmenGorusService {
  /// Formdaki açılır listeden seçilen ad, bu sınıfın ders öğretmenleriyle
  /// eşleştirilir. Bu, kimlik doğrulama değil hatırlatma alıcısı seçimidir.
  static Set<String> yanitlayanOgretmenIdleri(
    Iterable<MesajKisi> ogretmenler,
    Iterable<Map<String, dynamic>> yanitlar,
  ) {
    String ad(String s) => s
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase();
    final adlar = yanitlar
        .map((y) => ad('${y['ogretmen'] ?? ''}'))
        .where((s) => s.isNotEmpty)
        .toSet();
    // Aynı isim birden çok kayıtta bulunuyorsa, yanıtlamış olabilecek kişiye
    // tekrar hatırlatma gönderilmemesi için bu kayıtların tamamı dışlanır.
    return {
      for (final k in ogretmenler)
        if (k.tur == MesajKisiTuru.ogretmen && adlar.contains(ad(k.ad)))
          k.kisiId,
    };
  }

  BilgiToplamaOgretmenGorusService({
    required this.formlar,
    required this.kaynak,
    required this.baglam,
    required this.atamaId,
    required this.toplantiId,
    required this.google,
    this.hassasOnay = false,
  });
  final BireyselBilgiToplamaService formlar;
  final BireyselRehberlikService kaynak;
  final BireyselRehberlikBaglami baglam;
  final int atamaId, toplantiId;
  final bool hassasOnay;
  final OgretmenGorusGoogleService google;

  Future<void> _kontrol({bool yazma = false}) async {
    final b = await formlar.hazirla();
    if (b.okulId != baglam.okulId ||
        b.profilId != baglam.ogretmenProfilId ||
        b.yil != baglam.egitimOgretimYili) {
      throw StateError(
        'Formun okul, öğretmen veya eğitim yılı kapsamı değişti.',
      );
    }
    await kaynak.ogretmenGorusDurumu(
      baglam,
      atamaId,
      toplantiId,
      yazma: yazma,
      hassasOnay: hassasOnay,
    );
  }

  Future<void> baglantiyiHazirla() async {
    await _kontrol();
    final b = await formlar.hazirla();
    google.baglantiyiKullan(await formlar.silmeBaglantisi(b));
    await _kontrol();
  }

  Future<Map<String, dynamic>> hazirla(
    String token,
    String hesap,
    Map<String, dynamic> istek,
  ) async {
    await _kontrol(yazma: true);
    await google.kontrol(token);
    final kayit = await kaynak.ogretmenGorusIstegiKaydet(
      baglam,
      atamaId,
      toplantiId,
      hesap: hesap,
      istek: istek,
      hassasOnay: hassasOnay,
    );
    final sabitIstek = Map<String, dynamic>.from(kayit['istek'] as Map);
    final sonuc = await google.olustur(token, sabitIstek);
    await _sonucKaydet(hesap, '${sabitIstek['requestId']}', sonuc);
    return sonuc;
  }

  Future<void> _sonucKaydet(
    String hesap,
    String requestId,
    Map<String, dynamic> sonuc,
  ) async {
    await _kontrol(yazma: true);
    await kaynak.ogretmenGorusSonucKaydet(
      baglam,
      atamaId,
      toplantiId,
      requestId: requestId,
      hesap: hesap,
      sonuc: sonuc,
      hassasOnay: hassasOnay,
    );
  }

  Future<void> _kaydiDogrula(
    String requestId,
    String formId, {
    String? hesap,
  }) async {
    final durum = await kaynak.ogretmenGorusDurumu(
      baglam,
      atamaId,
      toplantiId,
      hassasOnay: hassasOnay,
    );
    final kayit = durum['form'] as Map?;
    if (kayit == null ||
        (kayit['istek'] as Map?)?['requestId'] != requestId ||
        (kayit['sonuc'] as Map?)?['formId'] != formId ||
        (hesap != null && kayit['hesap'] != hesap)) {
      throw StateError(
        'Form, toplantı veya Google hesabı eşleşmiyor. İşlem durduruldu.',
      );
    }
  }

  Future<Map<String, dynamic>> yayinaHazirla(
    String token,
    String hesap,
    String requestId,
    String formId,
  ) async {
    await _kontrol(yazma: true);
    await _kaydiDogrula(requestId, formId, hesap: hesap);
    final kayit =
        (await kaynak.ogretmenGorusDurumu(
              baglam,
              atamaId,
              toplantiId,
              hassasOnay: hassasOnay,
            ))['form']
            as Map;
    if ((kayit['yonetim'] as Map?)?['acik'] == false ||
        (kayit['yonetim'] as Map?)?['arsiv'] == true) {
      throw StateError('Önce formun yanıt alımını açın.');
    }
    final sonuc = await google.yayinla(token, requestId, formId);
    // Adaptörün kontrolüne ek olarak mesajlaşma geçidinde de zorunlu doğrulama.
    if (sonuc['published'] != true || sonuc['acceptingResponses'] != true) {
      throw StateError('Form yayımlanmadı; mesajlaşma açılmadı.');
    }
    OgretmenGorusGoogleService.baglanti('${sonuc['responderUrl']}');
    await _sonucKaydet(hesap, requestId, sonuc);
    return sonuc;
  }

  Future<List<Map<String, dynamic>>> yanitlar(
    String token,
    String requestId,
    String formId,
  ) async {
    await _kontrol();
    await _kaydiDogrula(requestId, formId);
    final yanitlar = await google.yanitlar(token, requestId, formId);
    await _kontrol();
    await kaynak.ogretmenGorusYonet(
      baglam,
      atamaId,
      toplantiId,
      requestId: requestId,
      formId: formId,
      hassasOnay: hassasOnay,
      yanitlar: yanitlar,
    );
    final kayit =
        (await kaynak.ogretmenGorusDurumu(
              baglam,
              atamaId,
              toplantiId,
              hassasOnay: hassasOnay,
            ))['form']
            as Map;
    return (kayit['yanitlar'] as List)
        .map((y) => Map<String, dynamic>.from(y as Map))
        .toList();
  }

  Future<void> durumAyarla(
    String token,
    String requestId,
    String formId,
    String islem,
  ) async {
    await _kontrol(yazma: true);
    await _kaydiDogrula(requestId, formId);
    if (islem == 'Aç' || islem == 'Kapat') {
      await google.yanitAliminiAyarla(token, formId, islem == 'Aç');
    }
    await _kontrol(yazma: true);
    await kaynak.ogretmenGorusYonet(
      baglam,
      atamaId,
      toplantiId,
      requestId: requestId,
      formId: formId,
      hassasOnay: hassasOnay,
      islem: islem,
    );
  }

  Future<List<String>> yanitlariSil(
    String token,
    String requestId,
    String formId,
    Set<String> secilenler, {
    bool Function()? devamEt,
  }) async {
    await _kontrol(yazma: true);
    await _kaydiDogrula(requestId, formId);
    final durum = await kaynak.ogretmenGorusDurumu(
      baglam,
      atamaId,
      toplantiId,
      hassasOnay: hassasOnay,
    );
    final eski = ((durum['form'] as Map)['yanitlar'] as List? ?? [])
        .cast<Map>();
    if (secilenler.isEmpty ||
        !secilenler.every((id) => eski.any((y) => y['responseId'] == id))) {
      throw StateError('Silinecek yanıtları yeniden seçin.');
    }
    final hatalar = <String>[];
    for (final id in secilenler) {
      if (devamEt != null && !devamEt()) {
        hatalar.add('İşlem durduruldu; kalan yanıtlar korundu.');
        break;
      }
      try {
        await _kontrol(yazma: true);
        await google.yanitSil(token, formId, id);
        await _kontrol(yazma: true);
        await kaynak.ogretmenGorusYonet(
          baglam,
          atamaId,
          toplantiId,
          requestId: requestId,
          formId: formId,
          hassasOnay: hassasOnay,
          silinenId: id,
        );
      } catch (_) {
        hatalar.add(
          'Yanıt $id silinemedi. Yerel kayıt korundu; yeniden deneyin.',
        );
      }
    }
    return hatalar;
  }
}
