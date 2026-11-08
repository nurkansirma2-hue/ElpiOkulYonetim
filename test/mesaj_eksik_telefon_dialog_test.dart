import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/widgets/mesaj_eksik_telefon_dialog.dart';

void main() {
  MesajKisi kisi(int id, {MesajKisiTuru tur = MesajKisiTuru.veli}) => MesajKisi(
    tur: tur,
    kisiId: '$id',
    sinifId: 1,
    ad: 'Kişi $id',
    telefon: '',
    aciklama: '9/A • $id • Öğrenci $id',
  );
  Future<void> dokun(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text).last);
    await t.tap(find.text(text).last);
    await t.pumpAndSettle();
  }

  Future<void> ac(
    WidgetTester t,
    List<MesajKisi> kisiler, {
    Future<void> Function(
      MesajKisi,
      String,
      String,
      String,
      Map<String, Object?>,
    )?
    veliKaydet,
    Future<void> Function(Map<String, String>, List<MesajKisi>)? kaydet,
    void Function(Set<String>?)? sonuc,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final r = await showDialog<Set<String>>(
                  context: c,
                  builder: (_) => MesajEksikTelefonDialog(
                    kisiler: kisiler,
                    kaydet: kaydet ?? (_, _) async {},
                    veliTelefonKaydet: veliKaydet ?? (_, _, _, _, _) async {},
                  ),
                );
                sonuc?.call(r);
              },
              child: const Text('Başla'),
            ),
          ),
        ),
      ),
    );
    await dokun(t, 'Başla');
  }

  testWidgets('atla kaydetmeden ilerler ve atlanan alıcıları döndürür', (
    t,
  ) async {
    var kayit = 0;
    Set<String>? sonuc;
    await ac(
      t,
      [kisi(1), kisi(2)],
      veliKaydet: (_, _, _, _, _) async {
        kayit++;
      },
      sonuc: (r) => sonuc = r,
    );
    await dokun(t, 'Kaydet ve sonrakine geç');
    expect(find.text('1 / 2 kişi'), findsOneWidget);
    await dokun(t, 'Atla');
    expect(find.text('2 / 2 kişi'), findsOneWidget);
    await dokun(t, 'Atla');
    expect(kayit, 0);
    expect(sonuc, {'Veli:1', 'Veli:2'});
    expect(find.byType(MesajEksikTelefonDialog), findsNothing);
  });

  testWidgets(
    'anne varsayılan; kişiler sırayla kaydedilir ve yardımcı düğmeler yoktur',
    (t) async {
      final yazilan = <String>[];
      Set<String>? sonuc;
      await ac(
        t,
        [kisi(1), kisi(2)],
        veliKaydet: (k, tur, ad, tel, _) async {
          yazilan.add('${k.kisiId}:$tur:$tel');
        },
        sonuc: (r) => sonuc = r,
      );
      for (final text in ['Bu kişiyi atla', 'Toplu gir', 'Hepsini atla']) {
        expect(find.text(text), findsNothing);
      }
      expect(find.text('Anne'), findsOneWidget);
      expect(find.text('Veli bilgisi'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('eksik-telefon-Veli:1')),
        '05320000001',
      );
      await dokun(t, 'Kaydet ve sonrakine geç');
      expect(find.text('2 / 2 kişi'), findsOneWidget);
      expect(find.text('Anne'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('eksik-telefon-Veli:2')),
        '05320000002',
      );
      await dokun(t, 'Kaydet ve sonrakine geç');
      expect(yazilan, ['1:Anne:05320000001', '2:Anne:05320000002']);
      expect(sonuc, isEmpty);
    },
  );
  testWidgets(
    'baba ve diğer veli seçilir, taslaklar korunur; kayıt hatasında ilerlemez',
    (t) async {
      var kayit = 0;
      await ac(
        t,
        [kisi(1)],
        veliKaydet: (_, tur, ad, tel, _) async {
          expect(tur, 'Baba');
          expect(ad, 'Baba adı');
          expect(tel, '05320000001');
          if (++kayit == 1) throw StateError('Kayıt değişti');
        },
      );
      await t.tap(find.byType(DropdownButton<String>));
      await t.pumpAndSettle();
      await dokun(t, 'Baba');
      final adAlani = find.byKey(const ValueKey('eksik-veli-adi-Veli:1'));
      await t.enterText(adAlani, 'Baba adı');
      final alan = find.byKey(const ValueKey('eksik-telefon-Veli:1'));
      await t.enterText(alan, '05320000001');
      await t.tap(find.byType(DropdownButton<String>));
      await t.pumpAndSettle();
      await dokun(t, 'Diğer veli');
      expect(t.widget<TextField>(adAlani).controller!.text, '');
      await t.enterText(adAlani, 'Diğer veli adı');
      expect(t.widget<TextField>(alan).controller!.text, '');
      await t.enterText(alan, '05329990000');
      await t.tap(find.byType(DropdownButton<String>));
      await t.pumpAndSettle();
      await dokun(t, 'Baba');
      expect(t.widget<TextField>(alan).controller!.text, '05320000001');
      expect(t.widget<TextField>(adAlani).controller!.text, 'Baba adı');
      await dokun(t, 'Kaydet ve sonrakine geç');
      expect(find.textContaining('Girişleriniz korunuyor'), findsOneWidget);
      expect(find.text('1 / 1 kişi'), findsOneWidget);
      await dokun(t, 'Kaydet ve sonrakine geç');
      expect(kayit, 2);
    },
  );
  testWidgets('boş ve geçersiz numara kaydedilmez; iptal null döner', (
    t,
  ) async {
    Set<String>? sonuc = {'bekliyor'};
    await ac(
      t,
      [kisi(1)],
      veliKaydet: (_, _, _, _, _) async => fail('Kaydet çağrılmamalı'),
      sonuc: (r) => sonuc = r,
    );
    await dokun(t, 'Kaydet ve sonrakine geç');
    expect(find.text('Geçerli tek telefon numarası girin.'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('eksik-telefon-Veli:1')),
      'abc',
    );
    await dokun(t, 'Kaydet ve sonrakine geç');
    expect(find.text('Geçerli tek telefon numarası girin.'), findsOneWidget);
    await dokun(t, 'İşlemi sonlandır');
    expect(sonuc, isNull);
  });
  testWidgets('öğretmen numarası öğretmene yazılır, veli listesi gösterilmez', (
    t,
  ) async {
    var yazma = 0;
    await ac(
      t,
      [kisi(1, tur: MesajKisiTuru.ogretmen)],
      kaydet: (deger, onceki) async {
        expect(deger, {'Ogretmen:1': '05320000001'});
        expect(onceki.single.tur, MesajKisiTuru.ogretmen);
        yazma++;
      },
    );
    expect(find.byType(DropdownButton<String>), findsNothing);
    await t.enterText(
      find.byKey(const ValueKey('eksik-telefon-Ogretmen:1')),
      '05320000001',
    );
    await dokun(t, 'Kaydet ve sonrakine geç');
    expect(yazma, 1);
  });
  testWidgets(
    'kendisi ve velisi birlikte seçilince alanlar ve kayıtlar ayrıdır',
    (t) async {
      var ogrenciKaydi = 0, veliKaydi = 0;
      await ac(
        t,
        [kisi(1, tur: MesajKisiTuru.ogrenci), kisi(1)],
        kaydet: (deger, onceki) async {
          expect(deger, {'Ogrenci:1': '05320000001'});
          expect(onceki.single.tur, MesajKisiTuru.ogrenci);
          ogrenciKaydi++;
        },
        veliKaydet: (k, tur, ad, tel, _) async {
          expect(k.tur, MesajKisiTuru.veli);
          expect(tur, 'Anne');
          expect(ad, 'Anne adı');
          expect(tel, '05320000002');
          veliKaydi++;
        },
      );
      expect(find.text('Veli bilgisi'), findsNothing);
      expect(find.text('Veli adı'), findsNothing);
      expect(find.text('Numara Öğrenci kaydına yazılacak.'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('eksik-telefon-Ogrenci:1')),
        '05320000001',
      );
      await dokun(t, 'Kaydet ve sonrakine geç');
      expect(find.text('2 / 2 kişi'), findsOneWidget);
      expect(find.text('Veli bilgisi'), findsOneWidget);
      expect(find.text('Veli adı'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('eksik-veli-adi-Veli:1')),
        'Anne adı',
      );
      await t.enterText(
        find.byKey(const ValueKey('eksik-telefon-Veli:1')),
        '05320000002',
      );
      await dokun(t, 'Kaydet ve sonrakine geç');
      expect(ogrenciKaydi, 1);
      expect(veliKaydi, 1);
    },
  );

  testWidgets('dar ekranda klavye açıkken ardışık giriş taşmaz', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    await ac(t, List.generate(50, (i) => kisi(i + 1)));
    await t.ensureVisible(find.byKey(const ValueKey('eksik-telefon-Veli:1')));
    await t.enterText(
      find.byKey(const ValueKey('eksik-telefon-Veli:1')),
      '05320000001',
    );
    await dokun(t, 'Kaydet ve sonrakine geç');
    expect(find.text('2 / 50 kişi'), findsOneWidget);
    await dokun(t, 'İşlemi sonlandır');
    expect(t.takeException(), isNull);
  });
}
