import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/database/veli_iliskisi.dart';
import 'package:elpi_okul_yonetim/widgets/veli_secim_dialog.dart';

void main() {
  for (final tur in ['Anne', 'Baba', 'Diger']) {
    testWidgets(
      'boş $tur için ad ve telefon girilir; diğer türün taslağı karışmaz',
      (t) async {
        VeliSecimi? sonuc;
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    sonuc = await showDialog<VeliSecimi>(
                      context: c,
                      builder: (_) => VeliSecimDialog(
                        ogrenci: VeliIliskisi.gorunum({'VeliTuru': tur}),
                      ),
                    );
                  },
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Aç'));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(ValueKey('veli-adi-$tur')), 'Yeni Veli');
        await t.enterText(find.byKey(ValueKey('veli-telefon-$tur')), 'abc');
        await t.tap(find.text('Kaydet'));
        await t.pumpAndSettle();
        expect(
          find.text('Geçerli tek telefon numarası girin.'),
          findsOneWidget,
        );
        expect(sonuc, isNull);
        await t.enterText(
          find.byKey(ValueKey('veli-telefon-$tur')),
          '05321112233',
        );
        final diger = tur == 'Baba' ? 'Anne' : 'Baba';
        await t.tap(find.byType(DropdownButton<String>));
        await t.pumpAndSettle();
        await t.tap(find.text(diger).last);
        await t.pumpAndSettle();
        expect(
          t
              .widget<TextFormField>(find.byKey(ValueKey('veli-adi-$diger')))
              .controller!
              .text,
          isEmpty,
        );
        await t.tap(find.byType(DropdownButton<String>));
        await t.pumpAndSettle();
        await t.tap(find.text(VeliIliskisi.turler[tur]!).last);
        await t.pumpAndSettle();
        expect(
          t
              .widget<TextFormField>(find.byKey(ValueKey('veli-adi-$tur')))
              .controller!
              .text,
          'Yeni Veli',
        );
        await t.tap(find.text('Kaydet'));
        await t.pumpAndSettle();
        expect(sonuc!.tur, tur);
        expect(sonuc!.ad, 'Yeni Veli');
        expect(sonuc!.telefon, '05321112233');
        expect(sonuc!.onceki, isNotNull);
      },
    );
  }
}
