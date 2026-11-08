import '../models/bireysel_gunluk_plan.dart';
import '../models/ortak_import.dart';

/// Kaynak metinler veri olarak işlenir; komut veya şablon kodu çalıştırılmaz.
/// İşleniş bir öğretim önerisidir; resmî kazanım metni aynen korunur.
class GunlukPlanHaftaTaslagi {
  static String birlestir(List<Map<String, Object?>> rows, String alan) => rows
      .map((r) => (r[alan] ?? '').toString().trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .join('\n');

  static ({DateTime bas, DateTime bit, int? saat, String hafta}) haftayiOku(
    List<Map<String, Object?>> rows,
  ) {
    if (rows.isEmpty) {
      throw StateError(
        'Seçilen tarih yıllık planda bir ders haftasıyla eşleşmedi. '
        'Yıllık planın tarih aralıklarını veya tatil kaydını kontrol edin.',
      );
    }
    final araliklar = rows
        .map((r) => '${r['BaslangicTarihi']}|${r['BitisTarihi']}')
        .toSet();
    final haftalar = rows.map((r) => r['HaftaNo']).whereType<int>().toSet();
    if (araliklar.length != 1 || haftalar.length > 1) {
      throw StateError(
        'Seçilen tarihte çakışan hafta/tarih kayıtları var. Yıllık planı düzeltin.',
      );
    }
    final bas = DateTime.parse(rows.first['BaslangicTarihi'] as String);
    final bit = DateTime.parse(rows.first['BitisTarihi'] as String);
    if (bit.isBefore(bas) || bit.difference(bas).inDays > 6) {
      throw StateError(
        'Kaynak tarih aralığı tek bir hafta değil. Yıllık planı kontrol edin.',
      );
    }
    // Birleşik hücreden gelen aynı haftalık saat tekrar toplanmaz.
    final saatler = rows
        .map((r) => (r['Saat'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    int? saat;
    if (saatler.length == 1) {
      final match = RegExp(
        r'^(\d+)\s*(?:saat|ders saati)?$',
        caseSensitive: false,
      ).firstMatch(saatler.single);
      saat = match == null ? null : int.tryParse(match.group(1)!);
      if (saat != null && (saat <= 0 || saat > 60)) saat = null;
    }
    return (
      bas: bas,
      bit: bit,
      saat: saat,
      hafta: haftalar.isEmpty ? '' : '${haftalar.single}. Hafta',
    );
  }

  static BireyselGunlukPlan tamamla(
    BireyselGunlukPlan plan,
    List<Map<String, Object?>> rows,
    Map<String, dynamic> kaynak, {
    String takvimNotu = '',
    String kaynakUyarisi = '',
  }) {
    final hafta = haftayiOku(rows);
    final konuMetni = plan.konu.replaceAllMapped(
      RegExp(r'(^|/\s*)\d+\.\s*'),
      (m) => m.group(1)!,
    );
    final uyari = <String>[];
    final yontemSatirlari = plan.yontemTeknik.split('\n');
    final hataliYontem = yontemSatirlari
        .where(
          (s) => RegExp(
            r'bilgisayar|donanim|projeksiyon|akilli tahta|yazici|atolye|laboratuvar',
          ).hasMatch(importNormalize(s)),
        )
        .toList();
    if (hataliYontem.isNotEmpty) {
      uyari.add(
        'Yöntem alanında araç/ortam bilgisi bulundu ve ayrıldı: ${hataliYontem.join('; ')}',
      );
      plan = plan.copyWith(
        yontemTeknik: yontemSatirlari
            .where((s) => !hataliYontem.contains(s))
            .join('\n'),
        aracGerec: [
          plan.aracGerec,
          ...hataliYontem,
        ].where((s) => s.isNotEmpty).toSet().join('\n'),
      );
    }
    final aciklama = [
      birlestir(rows, 'KazanimAciklamasi'),
      plan.kazanimAciklamasi,
    ].where((s) => s.isNotEmpty).toSet().join('\n');
    final surec = birlestir(rows, 'SurecBilesenleri');
    final unite = [
      birlestir(rows, 'Unite'),
      birlestir(rows, 'OgrenmeBirimi'),
    ].where((s) => s.isNotEmpty).toSet().join('\n');
    if (hafta.saat == null) {
      uyari.add(
        'Ders saati eksik veya çelişkili; saat dağılımı hazırlanamadı.',
      );
    }
    if (plan.kazanim.isEmpty && plan.ogrenmeCiktisi.isEmpty) {
      uyari.add(
        'Seçilen haftanın kazanımı/öğrenme çıktısı kaynakta bulunamadı.',
      );
    }
    if (aciklama.isEmpty && surec.isEmpty) {
      uyari.add(
        'Haftaya ait kazanım açıklaması/süreç bileşenleri bulunamadı. Genel ders açıklaması kullanılmadı.',
      );
    }
    if (plan.dersinIslenisi.isEmpty) {
      uyari.add('DBF uygulama bölümü bu haftayla güvenilir biçimde eşleşmedi.');
    }
    for (final e in {
      'Ünite/tema': unite,
      'Yöntem ve teknikler': plan.yontemTeknik,
      'Araç gereçler': plan.aracGerec,
      'Ölçme değerlendirme': plan.degerlendirme,
    }.entries) {
      if (e.value.isEmpty) uyari.add('${e.key} kaynakta bulunamadı.');
    }
    // Ünitenin bütün temrinlerini her haftaya taşımak yerine ilgili cümleleri seç.
    final hedef = importNormalize(
      '${plan.konu} $aciklama $surec',
    ).split(' ').where((s) => s.length > 3).toSet();
    String ilgili(String text) => text
        .split(RegExp(r'(?<=[.!?])\s+|\n'))
        .where(
          (s) =>
              importNormalize(
                s,
              ).split(' ').where(hedef.contains).toSet().length >=
              2,
        )
        .toSet()
        .join('\n');
    final uygulama = ilgili(plan.dersinIslenisi);
    final uygulamaParcalari = uygulama
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    String saatUygulamasi(int i, int toplam) {
      if (uygulamaParcalari.isEmpty) return '';
      final bas = i * uygulamaParcalari.length ~/ toplam;
      final son = (i + 1) * uygulamaParcalari.length ~/ toplam;
      return bas == son
          ? uygulamaParcalari[bas.clamp(0, uygulamaParcalari.length - 1)]
          : uygulamaParcalari.sublist(bas, son).join(' ');
    }

    final temrin = ilgili(plan.etkinlikler);
    if (plan.etkinlikler.isNotEmpty && temrin.isEmpty) {
      uyari.add(
        'DBF temrinleri içinde haftaya özgü güvenilir eşleşme bulunamadı; başka konunun temrini alınmadı.',
      );
    }
    final kazanimlar = '${plan.kazanim}\n${plan.ogrenmeCiktisi}'
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    final saatDagilimi = <Map<String, dynamic>>[];
    if (hafta.saat != null && kazanimlar.isNotEmpty) {
      // Aynı kazanımı on kez tekrarlamak yerine kaynak uygulamalarıyla süre blokları.
      var blokSayisi = uygulamaParcalari.length > kazanimlar.length
          ? uygulamaParcalari.length
          : kazanimlar.length;
      if (blokSayisi < 3) blokSayisi = 3;
      if (blokSayisi > hafta.saat!) blokSayisi = hafta.saat!;
      for (var i = 0; i < blokSayisi; i++) {
        final bas = i * hafta.saat! ~/ blokSayisi + 1;
        final bit = (i + 1) * hafta.saat! ~/ blokSayisi;
        final hedefler = <String>[
          for (var j = 0; j < kazanimlar.length; j++)
            if (j * blokSayisi ~/ kazanimlar.length == i) kazanimlar[j],
        ];
        final hedefMetni = hedefler.isEmpty
            ? kazanimlar[(i * kazanimlar.length ~/ blokSayisi).clamp(
                0,
                kazanimlar.length - 1,
              )]
            : hedefler.join('\n');
        saatDagilimi.add({
          'saat': bit - bas + 1,
          'bas': bas,
          'bit': bit,
          'hedef': hedefMetni,
        });
      }
    }
    String sureBasligi(Map<String, dynamic> s) =>
        '${s['bas'] == s['bit'] ? s['bas'] : "${s['bas']}–${s['bit']}"}. ders saati (${s['saat']} saat)';
    final toplam = saatDagilimi.fold<int>(0, (s, e) => s + (e['saat'] as int));
    if (saatDagilimi.isNotEmpty && toplam != hafta.saat) {
      throw StateError('İşleniş saat toplamı yıllık planla uyuşmuyor.');
    }
    final islenis = saatDagilimi.isEmpty
        ? ''
        : [
            'Öğretim önerisi — kaynak kazanımlara göre hazırlanmıştır. '
                'Aşağıdaki giriş, gelişme ve değerlendirme ders saatlerinin içindedir.',
            for (var i = 0; i < saatDagilimi.length; i++)
              '${sureBasligi(saatDagilimi[i])}\n'
                  'Hedef: ${saatDagilimi[i]['hedef']}\n'
                  '${i == 0 ? 'Giriş: $konuMetni konusunda öğrencilerin ön bilgileri kısa sorularla belirlenir. ' : ''}'
                  '${i == 0
                      ? 'Gelişme: $konuMetni konusu, bu saatin hedefi ve kazanım açıklamaları üzerinden öğretmen tarafından örneklenir. '
                      : i == saatDagilimi.length - 1
                      ? 'Bağımsız uygulama: Öğrenci $konuMetni konusundaki çalışmasını hedefteki ölçüte göre tamamlar, çözümünü gerekçelendirir ve ürününü gözden geçirir. '
                      : 'Rehberli uygulama: $konuMetni için bu saatin hedefini karşılayan çalışma adım adım yapılır; karşılaşılan güçlükler öğretmen geri bildirimiyle giderilir. '}'
                  '${i == 0 && saatDagilimi.length == 1 ? 'Uygulama: Öğrenci örneklenen beceriyi uygular ve izlediği adımları açıklar. ' : ''}'
                  '${uygulama.isEmpty ? 'DBF’de haftaya özgü uygulama ayrıntısı bulunamadı; öğretmen uygulamayı bu hedefe göre tamamlamalıdır.' : 'Kaynak uygulama: ${saatUygulamasi(i, saatDagilimi.length)}'}\n'
                  '${i == saatDagilimi.length - 1 ? 'Günlük hayatla bağlantı: Öğrenciler bu haftanın hedeflerinin kullanılabileceği bir durumu örneklendirir.\nDeğerlendirme ve sonuç: Öğrenci ürünleri hedeflerle karşılaştırılır; eksikler geri bildirimle ele alınır. ${plan.degerlendirme.isEmpty ? 'Kaynakta ölçme aracı belirtilmemiştir.' : 'Kaynak ölçme esasları, Ölçme değerlendirme bölümünde verilmiştir.'}' : 'Ara değerlendirme: Yapılan çalışma bu saatin hedefleriyle karşılaştırılır; sonraki uygulama için geri bildirim verilir.'}',
            'Toplam: $toplam ders saati. Günlere bölünmemiştir.',
          ].join('\n\n');
    String gun(DateTime t) =>
        '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
    return plan.copyWith(
      tarih: hafta.bas,
      unite: unite,
      kazanimAciklamasi: [
        aciklama,
        surec,
      ].where((s) => s.isNotEmpty).toSet().join('\n'),
      dersinIslenisi: islenis,
      etkinlikler: [takvimNotu, temrin].where((s) => s.isNotEmpty).join('\n\n'),
      aciklamalar: [
        kaynakUyarisi,
        takvimNotu,
        ...uyari,
      ].where((s) => s.isNotEmpty).join('\n'),
      planBilgisi: {
        'bicim': 1,
        'baslangic': hafta.bas.toIso8601String().substring(0, 10),
        'bitis': hafta.bit.toIso8601String().substring(0, 10),
        'haftaTarih': '${hafta.hafta} (${gun(hafta.bas)} – ${gun(hafta.bit)})',
        'dersSaati': hafta.saat == null
            ? 'Belirtilmedi / çelişkili'
            : '${hafta.saat} Saat',
        'saatDagilimi': saatDagilimi,
        'kaynaklar': kaynak,
        'uyarilar': uyari,
        'uretildi': DateTime.now().toIso8601String(),
      },
    );
  }
}
