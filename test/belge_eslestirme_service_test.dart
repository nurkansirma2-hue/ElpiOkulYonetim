import 'package:elpi_okul_yonetim/services/belge_eslestirme_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const govde = 'MATEMATİK YILLIK PLAN HAFTA KAZANIM KONU';
  BelgeEslesmesi? esle(String metin, {String ad = 'plan.xlsx'}) =>
      BelgeEslestirmeService.yillikPlan(
        ad: ad,
        metin: metin,
        ders: 'Matematik',
        seviye: 11,
        yil: '2026-2027',
        okul: 'Elpi Lisesi',
      );
  test('Türkçe ders adı ve tam bağlam eşleşir', () {
    expect(esle('$govde 11. Sınıf 2026/2027 Elpi Lisesi')!.uyarilar, isEmpty);
  });
  test('Yanlış yıl veya sınıf dosya adında da olsa elenir', () {
    expect(esle('$govde 10. sınıf'), isNull);
    expect(esle('$govde 2025-2026'), isNull);
    expect(esle(govde, ad: '2025_2026_plan.xlsx'), isNull);
    expect(esle('$govde 11. sınıf', ad: '10_sinif_plan.xlsx'), isNull);
  });
  test('Eksik bağlam açık uyarı üretir; ad tek başına yeterli değildir', () {
    expect(esle(govde)!.uyarilar, hasLength(3));
    expect(esle('Hafta konu', ad: 'Matematik yıllık plan.xlsx'), isNull);
    expect(esle('Matematik yıllık plan reklam'), isNull);
  });
  test('Bir kelimenin parçası ders kabul edilmez', () {
    expect(
      BelgeEslestirmeService.dersGeciyor('Matematiksel', 'Matematik'),
      false,
    );
  });
  test('Dosya adındaki sınıf ve yıl içerik doğrulaması sayılmaz', () {
    expect(
      esle(govde, ad: '11 sinif 2026-2027 plan.xlsx')!.uyarilar,
      hasLength(3),
    );
  });
}
