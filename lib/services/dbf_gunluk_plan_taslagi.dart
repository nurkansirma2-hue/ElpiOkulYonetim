import '../models/bireysel_gunluk_plan.dart';
import '../models/dbf_belgesi.dart';
import '../models/ortak_import.dart';

/// MEB DBF başlıklarından kaynak metin aktarır; eksik resmî metin üretmez.
/// Bölüm eşleşmesi belirsizse başka bir ünitenin uygulamasını seçmez.
class DbfGunlukPlanTaslagi {
  static String _duz(String s) => s
      .replaceAll(RegExp('[\uFFFE\uFFFD\u00ad]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _bolum(String text, String bas, List<String> sonlar) {
    final start = RegExp(bas, caseSensitive: false).firstMatch(text);
    if (start == null) return '';
    var end = text.length;
    for (final son in sonlar) {
      final match = RegExp(
        son,
        caseSensitive: false,
      ).firstMatch(text.substring(start.end));
      if (match != null && start.end + match.start < end) {
        end = start.end + match.start;
      }
    }
    return text
        .substring(start.end, end)
        .trim()
        .replaceFirst(RegExp(r'^[:：]\s*'), '');
  }

  static String _isimDeseni(String name) =>
      name.split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+');

  static BireyselGunlukPlan tamamla(BireyselGunlukPlan plan, DbfBelgesi dbf) {
    if (dbf.sinifSeviyesi != plan.sinifSeviyesi ||
        importNormalize(dbf.dersAdi) != importNormalize(plan.dersAdi)) {
      throw StateError('DBF ders veya sınıf bilgisi günlük planla uyuşmuyor.');
    }
    if (plan.konu.trim().isEmpty &&
        plan.kazanim.trim().isEmpty &&
        plan.ogrenmeCiktisi.trim().isEmpty) {
      return plan;
    }
    plan = _eskiBicimiTamamla(plan, dbf);
    final text = _duz(dbf.sayfalar.join(' '));
    final uygulamalar = _bolum(text, r'Öğrenme\s+Öğretme\s+Uygulamaları', [
      r'ÖĞRENME\s+ÖĞRETME\s+ORTAM',
      r'ÖĞRENME\s+BİRİMİ\s*/\s*MODÜL',
    ]);
    final heads = RegExp(
      r'(?:^|[.!?]\s+)([^:.!?]{3,90}):\s*',
    ).allMatches(uygulamalar).toList();
    final moduller = <String, String>{};
    for (var i = 0; i < heads.length; i++) {
      moduller[heads[i].group(1)!.trim()] = uygulamalar
          .substring(
            heads[i].end,
            i + 1 < heads.length ? heads[i + 1].start : uygulamalar.length,
          )
          .trim();
    }
    final hedef = importNormalize(
      '${plan.kazanim} ${plan.ogrenmeCiktisi} ${plan.konu}',
    );
    int puan(String name) {
      final kelimeler = importNormalize(name)
          .split(' ')
          .where(
            (s) =>
                s.length > 2 &&
                !{'uygulamalari', 'uygulama', 'temel'}.contains(s),
          )
          .toSet();
      final eslesen = kelimeler
          .where((s) => hedef.split(' ').contains(s))
          .length;
      final asgari = kelimeler.length == 1 ? 1 : 2;
      return kelimeler.isNotEmpty && eslesen >= asgari ? eslesen : 0;
    }

    final sirali = moduller.keys.where((n) => puan(n) > 0).toList()
      ..sort((a, b) => puan(b).compareTo(puan(a)));
    // Aynı puanlı iki ünite, bir haftada birden fazla kazanım içeriyor olabilir.
    final secili = sirali.length == 1 ? sirali.first : null;
    final degerlendirme = _bolum(
      text,
      r'ÖĞRENME\s+KANITLARI\s*\(Ölçme\s+ve\s+Değerlendirme\)',
      [r'ÖĞRENME\s*[- ]?\s*ÖĞRETME\s+YAŞANTILARI'],
    );
    final donanim = _bolum(text, r'ÖĞRENME\s+ÖĞRETME\s+ORTAM\s+VE\s+DONANIMI', [
      r'ÖĞRENME\s+BİRİMİ\s*/\s*MODÜL',
    ]);
    final uygulamaAciklama = _bolum(
      text,
      r'DERSİN\s+UYGULANMASINA\s+İLİŞKİN\s+AÇIKLAMALAR',
      [],
    );
    final yontem =
        RegExp(
          r'Bu etkinliklerde\s+(.*?)\s+gibi yöntem ve teknikler',
          caseSensitive: false,
        ).firstMatch(uygulamaAciklama)?.group(1) ??
        '';
    final temel = _bolum(text, r'Temel\s+Kabuller', [r'Ön\s+Değerlendirme']);
    final on = _bolum(text, r'Ön\s+Değerlendirme', [r'Köprü\s+kurma']);
    final kopru = _bolum(text, r'Köprü\s+kurma', [
      r'Öğrenme\s+Öğretme\s+Uygulamaları',
    ]);
    final bilesenler = _bolum(text, r'PROGRAMLAR\s+ARASI\s+BİLEŞENLER', [
      r'ÖĞRENME\s+ÇIKTILARI',
    ]);
    var temrin = '';
    var cikti = '';
    if (secili != null) {
      final temrinler = _bolum(
        text,
        r'UYGULAMA\s+FAALİYETLERİ\s*/\s*TEMRİNLER',
        [r'DERSİN\s+UYGULANMASINA\s+İLİŞKİN\s+AÇIKLAMALAR'],
      );
      temrin = _bolum(
        temrinler,
        _isimDeseni(secili),
        moduller.keys.where((n) => n != secili).map(_isimDeseni).toList(),
      );
      final ciktilar = _bolum(text, r'ÖĞRENME\s+ÇIKTILARI', [
        r'ÖĞRENME\s+KANITLARI',
      ]);
      final adaylar = RegExp(r'.*?yapabilme', caseSensitive: false)
          .allMatches(ciktilar)
          .map((m) => m.group(0)!.trim())
          .where((s) => puan(s) > 0)
          .toList();
      if (adaylar.length == 1) cikti = adaylar.single;
    }
    String baslik(String ad, String icerik) =>
        icerik.isEmpty ? '' : '$ad\n$icerik';
    final islenis = secili == null
        ? ''
        : [
            baslik('Temel kabuller (DBF)', temel),
            baslik('Ön değerlendirme (DBF)', on),
            baslik('Köprü kurma (DBF)', kopru),
            baslik(
              'Öğrenme öğretme uygulamaları - $secili (DBF)',
              moduller[secili]!,
            ),
          ].where((s) => s.isNotEmpty).join('\n\n');
    final etkinlik = secili == null
        ? ''
        : [
            baslik('Uygulama faaliyetleri / temrinler - $secili (DBF)', temrin),
            baslik(
              'Programlar arası bileşenler ve ilişkiler (DBF)',
              bilesenler,
            ),
          ].where((s) => s.isNotEmpty).join('\n\n');
    String doldur(String eski, String yeni) =>
        eski.trim().isEmpty && yeni.length <= 20000 ? yeni : eski;
    // Yalnız kazanım ayrıntıları tablosunda haftanın konusuyla eşleşen cümleler.
    // Genel ders açıklamaları kazanım açıklaması olarak kullanılmaz.
    final ayrintilar = _bolum(
      text,
      r'ÖĞRENME\s+ÇIKTISI\s+GRUBU\s+VE\s+AÇIKLAMALARI\s+İÇERİK\s+ÇERÇEVESİ',
      [r'UYGULAMA\s+FAALİYETLERİ\s*/\s*TEMRİNLER'],
    );
    final kelimeler = importNormalize(plan.konu)
        .split(' ')
        .where(
          (s) =>
              s.length > 3 &&
              !{'temel', 'uygulamalari', 'uygulama'}.contains(s),
        )
        .map((s) => s.substring(0, s.length < 5 ? s.length : 5))
        .toSet();
    final detay = kelimeler.isEmpty
        ? ''
        : ayrintilar
              .split(RegExp(r'(?<=[.!?])\s+'))
              .where((s) {
                final duz = importNormalize(s);
                return kelimeler.where(duz.contains).length >=
                    (kelimeler.length == 1 ? 1 : 2);
              })
              .join('\n');
    return plan.copyWith(
      kazanimAciklamasi: doldur(plan.kazanimAciklamasi, detay),
      ogrenmeCiktisi: doldur(plan.ogrenmeCiktisi, cikti),
      yontemTeknik: doldur(plan.yontemTeknik, yontem),
      aracGerec: doldur(plan.aracGerec, donanim),
      degerlendirme: doldur(plan.degerlendirme, degerlendirme),
      dersinIslenisi: doldur(plan.dersinIslenisi, islenis),
      etkinlikler: doldur(plan.etkinlikler, etkinlik),
    );
  }

  /// Önceki MEB DBF düzeni: numaralı kazanım ve madde işaretli ayrıntılar.
  static BireyselGunlukPlan _eskiBicimiTamamla(
    BireyselGunlukPlan plan,
    DbfBelgesi dbf,
  ) {
    final text = _duz(dbf.sayfalar.join(' '));
    final bolum = _bolum(
      text,
      r'ÖĞRENME\s+BİRİMİ\s+KONULAR\s+ÖĞRENME\s+BİRİMİ\s+KAZANIMLARI\s+ve\s+KAZANIM\s+AÇIKLAMALARI',
      [r'UYGULAMA\s+FAALİYETLERİ\s*/\s*TEMRİNLER'],
    );
    if (bolum.isEmpty) return plan;
    final hedef = importNormalize('${plan.kazanim} ${plan.ogrenmeCiktisi}');
    final basliklar = RegExp(
      r'(?:^|\s)\d{1,2}\.\s+([^•]+?)(?=\s*[•])',
    ).allMatches(bolum).toList();
    final ayrintilar = <String>[];
    for (var i = 0; i < basliklar.length; i++) {
      final kazanim = basliklar[i].group(1)!.trim();
      if (!hedef.contains(importNormalize(kazanim))) continue;
      final parca = bolum.substring(
        basliklar[i].end,
        i + 1 < basliklar.length ? basliklar[i + 1].start : bolum.length,
      );
      for (final m in RegExp(r'[•]\s*([^•]+)').allMatches(parca)) {
        final cumle = m.group(1)!.split(RegExp(r'(?<=[.!?])\s+')).first.trim();
        if (cumle.isNotEmpty) ayrintilar.add(cumle);
      }
    }
    final aciklama = ayrintilar.toSet().join('\n');
    final temrinler = _bolum(text, r'UYGULAMA\s+FAALİYETLERİ\s*/\s*TEMRİNLER', [
      r'DERSİN\s+UYGULANMASINA\s+İLİŞKİN\s+AÇIKLAMALAR',
    ]);
    final kelimeler = importNormalize(
      plan.konu,
    ).split(' ').where((s) => s.length > 3).toSet();
    final temrin = RegExp(r'(?:^|\s)\d{1,2}\.\s+(.+?)(?=\s+\d{1,2}\.\s|$)')
        .allMatches(temrinler)
        .map((m) => m.group(1)!.trim())
        .where((s) {
          final duz = importNormalize(s);
          return kelimeler.where(duz.contains).length >= 2;
        })
        .join('\n');
    String doldur(String eski, String yeni) =>
        eski.isEmpty && yeni.length <= 20000 ? yeni : eski;
    return plan.copyWith(
      kazanimAciklamasi: doldur(plan.kazanimAciklamasi, aciklama),
      dersinIslenisi: doldur(
        plan.dersinIslenisi,
        plan.kazanimAciklamasi.isNotEmpty ? plan.kazanimAciklamasi : aciklama,
      ),
      etkinlikler: doldur(plan.etkinlikler, temrin),
      aracGerec: doldur(
        plan.aracGerec,
        _bolum(text, r'EĞİTİM\s*[-–]?\s*ÖĞRETİM\s+ORTAM\s+VE\s+DONANIMI', [
          r'ÖLÇME\s+VE\s+DEĞERLENDİRME',
        ]),
      ),
      degerlendirme: doldur(
        plan.degerlendirme,
        _bolum(text, r'ÖLÇME\s+VE\s+DEĞERLENDİRME', [
          r'KAZANIM\s+SAYISI\s+VE\s+SÜRE\s+TABLOSU',
        ]),
      ),
    );
  }
}
