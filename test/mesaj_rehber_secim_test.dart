import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/widgets/mesaj_eksik_telefon_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const kanal = MethodChannel('elpi_okul_yonetim/mesajlasma');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, null),
  );
  Future<void> tikla(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text).last);
    await t.pumpAndSettle();
    await t.tap(find.text(text).last);
    await t.pumpAndSettle();
  }

  Future<void> ac(
    WidgetTester t, {
    required Future<void> Function(Map<String, String>, List<MesajKisi>) kaydet,
    MesajKisiTuru tur = MesajKisiTuru.ogretmen,
    String? veli,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<Set<String>>(
                context: c,
                builder: (_) => MesajEksikTelefonDialog(
                  kisiler: [
                    MesajKisi(
                      tur: tur,
                      kisiId: '1',
                      sinifId: 1,
                      ad: 'Test Kişi',
                      telefon: '',
                      aciklama: 'Ders',
                      veliTuru: veli,
                    ),
                  ],
                  kaydet: kaydet,
                ),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await tikla(t, 'Aç');
  }

  testWidgets(
    'rehber numarası otomatik kaydedilmez; Kaydet ilgili öğretmene yazar',
    (t) async {
      var kayit = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kanal, (call) async {
            expect(call.method, 'rehberTelefonSec');
            return '05321112233';
          });
      await ac(
        t,
        kaydet: (deger, onceki) async {
          kayit++;
          expect(deger, {'Ogretmen:1': '05321112233'});
          expect(onceki.single.tur, MesajKisiTuru.ogretmen);
        },
      );
      await tikla(t, 'Rehberden seç');
      expect(kayit, 0);
      expect(
        t
            .widget<TextField>(
              find.byKey(const ValueKey('eksik-telefon-Ogretmen:1')),
            )
            .controller!
            .text,
        '05321112233',
      );
      await tikla(t, 'Kaydet ve sonrakine geç');
      expect(kayit, 1);
    },
  );
  for (final sonuc in ['iptal', 'gecersiz', 'hata']) {
    testWidgets('rehber $sonuc: mevcut giriş korunur, kayıt yapılmaz', (
      t,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kanal, (call) async {
            if (sonuc == 'hata') {
              throw PlatformException(code: 'REHBER_ACILAMADI');
            }
            return sonuc == 'iptal' ? null : 'abc';
          });
      await ac(t, kaydet: (_, _) async => fail('Kaydet çağrılmamalı'));
      final alan = find.byKey(const ValueKey('eksik-telefon-Ogretmen:1'));
      await t.enterText(alan, '05329990000');
      await tikla(t, 'Rehberden seç');
      expect(t.widget<TextField>(alan).controller!.text, '05329990000');
      if (sonuc != 'iptal') {
        expect(
          find.textContaining('Rehberden numara alınamadı'),
          findsOneWidget,
        );
      }
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('anne varsayılan seçilir ve rehber düğmesi kullanılabilir', (
    t,
  ) async {
    await ac(
      t,
      tur: MesajKisiTuru.veli,
      kaydet: (_, _) async => fail('Kaydet çağrılmamalı'),
    );
    final b = t.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Rehberden seç'),
    );
    expect(b.onPressed, isNotNull);
    expect(find.text('Anne'), findsOneWidget);
  });
}
