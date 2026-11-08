import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/widgets/ortak_genisleyen_bolum.dart';
import 'package:elpi_okul_yonetim/widgets/uygulama_ekle_tanitim.dart';

void main() {
  testWidgets('ortak başlık çift okla açılır, kapanır ve form değerini korur', (
    t,
  ) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              OrtakGenisleyenBolum(
                key: const PageStorageKey('bir'),
                title: const Text('Birinci'),
                maintainState: true,
                children: [
                  TextField(
                    controller: c,
                    decoration: const InputDecoration(labelText: 'Değer'),
                  ),
                ],
              ),
              const OrtakGenisleyenBolum(
                key: PageStorageKey('iki'),
                title: Text('İkinci'),
                children: [Text('İkinci içerik')],
              ),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.byTooltip('Genişlet').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Korunan değer');
    await t.tap(find.byTooltip('Daralt'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await t.tap(find.byTooltip('Genişlet').first);
    await t.pumpAndSettle();
    expect(c.text, 'Korunan değer');
    expect(find.text('İkinci içerik'), findsNothing);
    expect(find.byIcon(Icons.keyboard_double_arrow_up), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    '3 saniye vurgu ve ardından bir daha gösterme tercihi kalıcıdır',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();
      Widget sayfa(Key key) => MaterialApp(
        home: Scaffold(
          body: UygulamaEkleTanitim(
            key: key,
            child: FilledButton(
              onPressed: () {},
              child: const Text('Uygulama Ekle'),
            ),
          ),
        ),
      );
      await t.pumpWidget(sayfa(const ValueKey(1)));
      await t.pump();
      expect(find.byKey(const ValueKey('uygulama-ekle-vurgu')), findsOneWidget);
      expect(find.text('Bir daha gösterme'), findsNothing);
      await t.pump(const Duration(milliseconds: 2999));
      expect(find.byKey(const ValueKey('uygulama-ekle-vurgu')), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const ValueKey('uygulama-ekle-vurgu')), findsNothing);
      expect(find.text('Bir daha gösterme'), findsOneWidget);
      await t.tap(
        find.byKey(const ValueKey('uygulama-ekle-bir-daha-gosterme')),
      );
      await t.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          UygulamaEkleTanitim.tercihAnahtari,
        ),
        isTrue,
      );
      await t.pumpWidget(sayfa(const ValueKey(2)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('uygulama-ekle-vurgu')), findsNothing);
      expect(find.text('Bir daha gösterme'), findsNothing);
      expect(find.text('Uygulama Ekle'), findsOneWidget);
    },
  );
  testWidgets('animasyon bitmeden çıkış zamanlayıcıyı güvenle iptal eder', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UygulamaEkleTanitim(child: Text('Ekle'))),
      ),
    );
    await t.pump();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 4));
    expect(t.takeException(), isNull);
  });
}
