import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/widgets/mesaj_alici_secim_sliver.dart';

void main() {
  testWidgets(
    'listeler kapalı başlar ve seçimden sonra kapanır; seçimler korunur',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var secilen = <String, MesajKisi>{};
      var import = 0;
      const kisiler = [
        MesajKisi(
          tur: MesajKisiTuru.ogrenci,
          kisiId: '1',
          sinifId: 1,
          ad: 'Ali',
          telefon: '05321112233',
          aciklama: '9-C • 001 • Ali',
        ),
        MesajKisi(
          tur: MesajKisiTuru.veli,
          kisiId: '1',
          sinifId: 1,
          ad: 'Anne',
          telefon: '05321112234',
          aciklama: '9-C • 001 • Ali',
          veliTuru: 'Anne',
        ),
        MesajKisi(
          tur: MesajKisiTuru.ogretmen,
          kisiId: 'o1',
          sinifId: 1,
          ad: 'Ayşe Öğretmen',
          telefon: '05321112235',
          aciklama: '9-C • Matematik',
        ),
        MesajKisi(
          tur: MesajKisiTuru.ogrenci,
          kisiId: '2',
          sinifId: 2,
          ad: 'Veli',
          telefon: '05321112236',
          aciklama: '10-D • 002 • Veli',
        ),
      ];
      await t.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (c, set) => Scaffold(
              body: CustomScrollView(
                slivers: [
                  MesajAliciSecimSliver(
                    adaylar: kisiler,
                    siniflar: const {1: '9-C', 2: '10-D'},
                    secilenler: secilen,
                    degistir: (s) => set(
                      () => secilen = {for (final k in s) k.secimAnahtari: k},
                    ),
                    veliDuzenle: (_) async {},
                    ogretmenDuzenle: (_, _) async {},
                    kisiDuzenle: (_) async {},
                    programdanAktar: (_) async {
                      import++;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Future<void> tikla(Finder f) async {
        if (f.evaluate().isEmpty) {
          t
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await t.pumpAndSettle();
        }
        if (f.evaluate().isEmpty) {
          await t.scrollUntilVisible(
            f,
            150,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await t.ensureVisible(f.last);
        await t.pumpAndSettle();
        await t.tap(f.last);
        await t.pumpAndSettle();
      }

      Future<void> sinif(String ad) async {
        final scroll = t.state<ScrollableState>(find.byType(Scrollable).first);
        scroll.position.jumpTo(0);
        await t.pumpAndSettle();
        await tikla(find.byType(DropdownButton<int>));
        await tikla(find.text(ad).last);
      }

      await sinif('9-C');
      expect(
        find.byKey(const ValueKey('mesaj-alici-liste-basligi')),
        findsNothing,
      );
      expect(find.widgetWithText(ExpansionTile, 'Alıcı grubu'), findsOneWidget);
      expect(find.text('Sınıf öğrencileri'), findsNothing);
      expect(find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')), findsNothing);
      await tikla(find.text('Alıcı grubu'));
      expect(find.text('Sınıf öğrencileri'), findsOneWidget);
      expect(find.text('Sınıfta derse giren öğretmenler'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      await tikla(find.text('Sınıf öğrencileri'));
      expect(find.text('Sınıf öğrencileri'), findsNothing);
      expect(find.text('Kendisi'), findsOneWidget);
      expect(find.text('Velisi'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mesaj-alici-liste-basligi')),
        findsNothing,
      );
      await tikla(find.text('Velisi'));
      expect(find.text('Velisi'), findsNothing);
      expect(find.text('Mesaj alıcısı: Velisi'), findsOneWidget);
      expect(find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')), findsNothing);
      await tikla(find.text('Öğrenci listesi (0/1 seçili)'));
      await tikla(find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')));
      expect(find.byType(SimpleDialog), findsNothing);
      expect(secilen.keys, contains('Veli:1'));
      expect(find.text('Öğrenci listesi (1/1 seçili)'), findsOneWidget);
      expect(find.textContaining('Seçilen alıcılar'), findsNothing);
      expect(find.text('Alıcıları göster / düzenle'), findsNothing);
      expect(find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')), findsNothing);
      await tikla(find.byKey(const ValueKey('mesaj-ogrenci-hedef-basligi')));
      await tikla(find.text('Kendisi'));
      expect(find.text('Öğrenci listesi (0/1 seçili)'), findsOneWidget);
      await tikla(find.text('Öğrenci listesi (0/1 seçili)'));
      await tikla(find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')));
      expect(secilen.keys, containsAll(['Veli:1', 'Ogrenci:1']));
      expect(find.text('Öğrenci listesi (1/1 seçili)'), findsOneWidget);
      await tikla(find.text('Öğrenci listesi (1/1 seçili)'));
      await tikla(
        find.descendant(
          of: find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(secilen.keys, contains('Veli:1'));
      expect(secilen.keys, isNot(contains('Ogrenci:1')));
      await tikla(find.text('Alıcı grubu'));
      await tikla(find.text('Sınıfta derse giren öğretmenler'));
      expect(find.text('Sınıfta derse giren öğretmenler'), findsNothing);
      expect(
        find.byKey(const ValueKey('mesaj-ogrenci-hedef-basligi')),
        findsNothing,
      );
      expect(
        find.widgetWithText(ExpansionTile, 'Öğretmen listesi (0/1 seçili)'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mesaj-aday-Ogretmen:o1')),
        findsNothing,
      );
      await tikla(find.text('Öğretmen listesi (0/1 seçili)'));
      await tikla(find.byKey(const ValueKey('mesaj-aday-Ogretmen:o1')));
      expect(secilen.keys, contains('Ogretmen:o1'));
      expect(find.text('Öğretmen listesi (1/1 seçili)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mesaj-aday-Ogretmen:o1')),
        findsNothing,
      );
      expect(import, 0);
      await sinif('10-D');
      expect(
        find.widgetWithText(ExpansionTile, 'Öğrenci listesi (0/1 seçili)'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mesaj-aday-Ogrenci:2')), findsNothing);
      await tikla(find.text('Öğrenci listesi (0/1 seçili)'));
      await tikla(find.byKey(const ValueKey('mesaj-aday-Ogrenci:2')));
      expect(find.byType(SimpleDialog), findsNothing);
      expect(secilen.keys, containsAll(['Veli:1', 'Ogretmen:o1', 'Ogrenci:2']));
      expect(find.byKey(const ValueKey('mesaj-aday-Ogrenci:2')), findsNothing);
      await tikla(find.text('Alıcı grubu'));
      await tikla(find.text('Sınıfta derse giren öğretmenler'));
      expect(import, 1);
      await tikla(find.text('Öğretmen listesi (0/0 seçili)'));
      expect(
        find.widgetWithText(ExpansionTile, 'Öğretmen listesi (0/0 seçili)'),
        findsOneWidget,
      );
      await sinif('Tüm sınıflar');
      await tikla(find.text('Öğrenci listesi (1/2 seçili)'));
      await tikla(find.text('Görünenleri seç'));
      expect(find.byType(SimpleDialog), findsNothing);
      expect(
        secilen.keys,
        containsAll(['Ogrenci:1', 'Ogrenci:2', 'Veli:1', 'Ogretmen:o1']),
      );
      expect(find.text('Öğrenci listesi (2/2 seçili)'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
