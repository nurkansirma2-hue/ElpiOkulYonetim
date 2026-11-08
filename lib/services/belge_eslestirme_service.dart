import '../models/ortak_import.dart';

class BelgeEslesmesi {
  const BelgeEslesmesi(this.uyarilar);
  final List<String> uyarilar;
}

/// Dosya adı yalnız aday sıralamaya yardım eder; uygunluk içeriğe dayanır.
class BelgeEslestirmeService {
  static bool dersGeciyor(String metin, String ders) {
    final d = importNormalize(ders);
    return d.isNotEmpty && ' ${importNormalize(metin)} '.contains(' $d ');
  }

  static Set<String> _yillar(String text) => RegExp(
    r'(20\d{2})\s*[-–—/_]\s*(20\d{2})',
  ).allMatches(text).map((m) => '${m[1]}-${m[2]}').toSet();

  static BelgeEslesmesi? yillikPlan({
    required String ad,
    required String metin,
    required String ders,
    required int seviye,
    required String yil,
    required String okul,
  }) {
    final n = importNormalize(metin);
    if (!dersGeciyor(metin, ders) ||
        !n.contains('hafta') ||
        ![
          'konu',
          'kazanim',
          'ogrenme ciktisi',
          'icerik cercevesi',
        ].any(n.contains) ||
        !(n.contains('yillik') || importNormalize(ad).contains('plan'))) {
      return null;
    }
    final seviyeler = RegExp(r'\b(\d{1,2})\s*\.?\s*sinif\b')
        .allMatches(importNormalize('$ad $metin'))
        .map((m) => int.parse(m[1]!))
        .toSet();
    final yillar = _yillar('$ad $metin');
    final hedef = _yillar(yil);
    if (hedef.length != 1 ||
        seviyeler.any((s) => s != seviye) ||
        yillar.any((y) => y != hedef.single)) {
      return null;
    }
    final uyarilar = <String>[
      if (!RegExp(r'\b(\d{1,2})\s*\.?\s*sinif\b').hasMatch(n))
        'Sınıf seviyesi içerikten doğrulanamadı.',
      if (_yillar(metin).isEmpty)
        'Belge içeriğinde eğitim yılı bulunamadı; genel şablon olabilir.',
      if (!dersGeciyor(metin, okul))
        'Okul bilgisi doğrulanamadı; eski okul bilgilerini kontrol edin.',
    ];
    return BelgeEslesmesi(List.unmodifiable(uyarilar));
  }
}
