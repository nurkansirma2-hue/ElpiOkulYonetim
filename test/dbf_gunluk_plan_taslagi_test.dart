import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';
import 'package:elpi_okul_yonetim/models/bireysel_gunluk_plan.dart';
import 'package:elpi_okul_yonetim/models/dbf_belgesi.dart';
import 'package:elpi_okul_yonetim/services/dbf_dosya_service.dart';
import 'package:elpi_okul_yonetim/services/dbf_gunluk_plan_taslagi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DbfBelgesi dbf;
  setUpAll(() async {
    loadPdfium(
      modulePath: File('build/native_assets/windows/pdfium.dll').absolute.path,
    );
    dbf = await DbfDosyaService.pdfOku(
      'meb.pdf',
      await File('test/fixtures/dbf/meb_dbf.pdf').readAsBytes(),
      hazirla: () async {},
    );
  });
  BireyselGunlukPlan plan({
    String konu = 'Norm Yazı Yazma',
    String kazanim = 'BTU.1.1. Temel teknik resim uygulamaları yapabilme',
  }) => BireyselGunlukPlan(
    okulId: 'okul',
    ogretmenProfilId: 1,
    egitimOgretimYili: '2026-2027',
    ogretmenAdi: 'Öğretmen',
    okulAdi: 'Okul',
    dersAdi: dbf.dersAdi,
    sinifKodu: '9-A',
    dersId: 1,
    sinifSubeId: 1,
    sinifSeviyesi: 9,
    tarih: DateTime(2026, 10, 14),
    konu: konu,
    kazanim: kazanim,
  );
  test(
    'Gerçek DBF norm yazı planının altı boş alanını kaynak metinle tamamlar',
    () {
      final p = DbfGunlukPlanTaslagi.tamamla(plan(), dbf);
      expect(p.ogrenmeCiktisi, 'Temel teknik resim uygulamaları yapabilme');
      expect(p.yontemTeknik, contains('beyin fırtınası'));
      expect(p.aracGerec, contains('teknik resim defteri'));
      expect(p.degerlendirme, contains('gözlem formu'));
      expect(p.dersinIslenisi, contains('norm yazı biçimini uygulaması'));
      expect(p.dersinIslenisi, contains('Temel kabuller'));
      expect(
        p.dersinIslenisi,
        isNot(contains('Temel Elektronik Uygulamaları:')),
      );
      expect(
        p.etkinlikler,
        contains('Verilen boşluklara harfleri norm yazı olarak yazmak'),
      );
      expect(p.etkinlikler, contains('D3.2. Planlı olmak'));
      expect(p.etkinlikler, isNot(contains('trafik lambası')));
      expect(p.konu, 'Norm Yazı Yazma');
      expect(p.kazanim, startsWith('BTU.1.1.'));
      File('../output/dbf_norm_yazi_sonuc.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(p.icerikAlanlari),
      );
    },
  );
  test('Elektronik ve üç boyutlu tasarım kendi ünitesinden alınır', () {
    for (final e in [
      (
        'Dirençler',
        'Temel elektronik uygulamaları yapabilme',
        'direnç renk kodlarını',
      ),
      (
        '3B Nesne İşlemleri',
        'Üç boyutlu çizim uygulamaları yapabilme',
        'modeller geliştirmesi',
      ),
    ]) {
      final p = DbfGunlukPlanTaslagi.tamamla(
        plan(konu: e.$1, kazanim: e.$2),
        dbf,
      );
      expect(p.ogrenmeCiktisi.toLowerCase(), e.$2.toLowerCase());
      expect(p.dersinIslenisi, contains(e.$3));
      expect(
        p.dersinIslenisi,
        isNot(contains('norm yazı biçimini uygulaması')),
      );
    }
  });
  test('Dolu alanlar korunur; eşleşmeyen kazanıma ünite uydurulmaz', () {
    final eski = plan().copyWith(
      ogrenmeCiktisi: 'Elle yazıldı',
      yontemTeknik: 'Özel yöntem',
      aracGerec: 'Özel araç',
      degerlendirme: 'Özel ölçüt',
      dersinIslenisi: 'Öğretmenin planı',
      etkinlikler: 'Özel etkinlik',
    );
    expect(
      DbfGunlukPlanTaslagi.tamamla(eski, dbf).icerikAlanlari,
      eski.icerikAlanlari,
    );
    final bos = DbfGunlukPlanTaslagi.tamamla(
      plan(konu: 'Bilinmeyen konu', kazanim: 'Belirsiz'),
      dbf,
    );
    expect(bos.dersinIslenisi, isEmpty);
    expect(bos.etkinlikler, isEmpty);
    expect(bos.ogrenmeCiktisi, isEmpty);
  });
}
