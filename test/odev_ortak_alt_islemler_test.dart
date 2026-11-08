import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/widgets/odev_ortak_alt_islemler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
  });
  for (final width in [320.0, 360.0, 390.0, 400.0, 420.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Alt çubuk: $width dp, yazı ölçeği $scale', (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'NotoSans'),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 640),
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(bottom: 24),
              ),
              child: Scaffold(
                bottomNavigationBar: OdevOrtakAltIslemler(
                  ogrenciEkle: () {},
                  ogrenciCikar: () {},
                  kaydet: () {},
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final buttons = find.byType(OutlinedButton);
        expect(buttons, findsNWidgets(3));
        for (final button in buttons.evaluate()) {
          final size = tester.getSize(find.byWidget(button.widget));
          expect(size.height, 48);
          expect(size.width, greaterThanOrEqualTo(48));
        }
        expect(tester.getSize(find.byType(OdevOrtakAltIslemler)).height, 76);
        if (scale == 1) {
          for (final label in ['Öğrenci Ekle', 'Öğrenci Çıkar', 'Kaydet']) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(label),
            );
            expect(paragraph.didExceedMaxLines, isFalse, reason: label);
          }
        }
      });
    }
  }

  testWidgets('İşlem bağlantıları ve devre dışı durum korunur', (tester) async {
    final calls = [0, 0, 0];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: OdevOrtakAltIslemler(
            ogrenciEkle: () => calls[0]++,
            ogrenciCikar: () => calls[1]++,
            kaydet: () => calls[2]++,
          ),
        ),
      ),
    );
    for (final label in ['Öğrenci Ekle', 'Öğrenci Çıkar', 'Kaydet']) {
      await tester.tap(find.text(label));
    }
    expect(calls, [1, 1, 1]);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(bottomNavigationBar: OdevOrtakAltIslemler()),
      ),
    );
    for (final button in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      expect(button.onPressed, isNull);
    }
  });
}
