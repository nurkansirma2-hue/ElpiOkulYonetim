import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/bireysel_gunluk_plan.dart';
import 'package:elpi_okul_yonetim/models/dbf_belgesi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_yillik_plan_service.dart';
import 'package:elpi_okul_yonetim/services/dbf_gunluk_plan_taslagi.dart';
import 'package:elpi_okul_yonetim/services/gunluk_plan_hafta_taslagi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_gunluk_plan_belge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BireyselYillikPlanOnIzleme yillik;
  late DbfBelgesi dbf;
  setUpAll(() async {
    yillik = await BireyselYillikPlanService.onIzlemeHazirla(
      dosyaBytes: await File(
        'test/fixtures/gunluk_plan/ntp_yillik_plan.docx',
      ).readAsBytes(),
      dosyaAdi: 'NTP yıllık plan.docx',
      dosyaUzantisi: 'docx',
      egitimOgretimYili: '2026-2027',
    );
    dbf = DbfBelgesi.metinden(
      dosyaAdi: 'NTP DBF.pdf',
      sayfalar:
          (jsonDecode(
                    await File(
                      'test/fixtures/gunluk_plan/ntp_dbf_metni.json',
                    ).readAsString(),
                  )
                  as List)
              .cast<String>(),
      icerikOzeti: 'orijinal NTP DBF',
    );
  });
  BireyselGunlukPlan hazirla(int hafta) {
    final r = yillik.kayitlar.singleWhere((r) => r.haftaNo == hafta);
    final p = BireyselGunlukPlan(
      okulId: 'qa-okul',
      ogretmenProfilId: 1,
      egitimOgretimYili: '2026-2027',
      ogretmenAdi: 'Örnek Öğretmen',
      okulAdi: 'Örnek Okul',
      dersAdi: dbf.dersAdi,
      sinifKodu: '10-A',
      dersId: 1,
      sinifSubeId: 1,
      sinifSeviyesi: 10,
      tarih: DateTime.parse(r.baslangicTarihi!),
      konu: r.konu,
      kazanim: r.kazanim,
      yontemTeknik: r.yontemTeknik,
      aracGerec: r.aracGerec,
      degerlendirme: r.degerlendirme,
      planBilgisi: {'kazanimAciklamasi': r.kazanimAciklamasi},
    );
    final kaynak = DbfGunlukPlanTaslagi.tamamla(p, dbf);
    return GunlukPlanHaftaTaslagi.tamamla(
      kaynak,
      [
        {
          'HaftaNo': r.haftaNo,
          'BaslangicTarihi': r.baslangicTarihi,
          'BitisTarihi': r.bitisTarihi,
          'Saat': r.saat,
          'Unite': r.unite,
          'KazanimAciklamasi': r.kazanimAciklamasi,
        },
      ],
      {'yillikPlanDosyasi': yillik.dosyaAdi, 'dbfDosyasi': dbf.dosyaAdi},
      takvimNotu: r.etkinlik,
    );
  }

  test(
    'Özgün yıllık planın 10 saat, kazanım açıklaması, etkinlik ve tatilleri doğru okunur',
    () {
      expect(yillik.basarili, isTrue, reason: yillik.hatalar.join('\n'));
      final ilk = yillik.kayitlar.singleWhere((r) => r.haftaNo == 1);
      expect(ilk.saat, '10');
      expect(ilk.kazanimAciklamasi, contains('Form uygulaması'));
      expect(ilk.etkinlik, contains('İlköğretim Haftası'));
      expect(yillik.kayitlar.any((r) => r.haftaNo == 10), isFalse);
      expect(
        yillik.calismaTakvimi.any((r) => r.haftaNo == 10 && !r.calismaVarMi),
        isTrue,
      );
      expect(ilk.yontemTeknik, isNot(contains('Donanım')));
    },
  );
  test(
    'Eski DBF yöntem, ortam ve ölçme başlıkları okunur; genel açıklama kazanıma kopyalanmaz',
    () {
      final p = hazirla(1);
      expect(p.kazanimAciklamasi, contains('arayüz'));
      expect(p.kazanimAciklamasi, isNot(contains('Bu derste, verilen görevi')));
      expect(p.aracGerec, contains('bilgisayar'));
      expect(p.yontemTeknik, contains('beyin'));
      expect(p.dersinIslenisi, contains('Form uygulaması'));
      expect(p.dersinIslenisi, isNot(contains('Kapsülleme')));
      expect(
        (p.planBilgisi['saatDagilimi'] as List).fold<int>(
          0,
          (s, r) => s + (r['saat'] as int),
        ),
        10,
      );
      final yalnizDbf = DbfGunlukPlanTaslagi.tamamla(
        p.copyWith(yontemTeknik: '', aracGerec: '', degerlendirme: ''),
        dbf,
      );
      expect(yalnizDbf.yontemTeknik, contains('beyin'));
      expect(yalnizDbf.aracGerec, contains('laboratuvar'));
      expect(yalnizDbf.degerlendirme, contains('gözlem formu'));
    },
  );
  test(
    'Özgün NTP haftaları farklı işleniş üretir; on saatlik DOCX/PDF örneği oluşur',
    () async {
      final a = hazirla(1), b = hazirla(6);
      expect(a.dersinIslenisi, isNot(b.dersinIslenisi));
      expect(b.dersinIslenisi, contains('Mantıksal'));
      expect(b.dersinIslenisi, contains('Toplam: 10'));
      final path = Platform.environment['GUNLUK_PLAN_QA'];
      if (path != null) {
        await Directory(path).create(recursive: true);
        await File(
          '$path/ntp_gunluk_plan.docx',
        ).writeAsBytes(BireyselGunlukPlanBelgeService.docxOlustur(a));
        await File(
          '$path/ntp_gunluk_plan.pdf',
        ).writeAsBytes(await BireyselGunlukPlanBelgeService.pdfOlustur(a));
      }
    },
  );
}
