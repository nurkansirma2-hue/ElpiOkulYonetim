import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/widgets/mesaj_alici_duzenleme_dialog.dart';

void main() {
  for (final durum in ['telefon', 'yeni', 'sinif']) {
    testWidgets('Öğretmen düzenleme: $durum', (t) async {
      String? kaydedilen;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: MesajOgretmenDialog(
        siniflar: const {1: '9-C', 2: '10-D'}, seciliSiniflar: const {1},
        ad: 'Öğretmen', telefon: '05321112233',
        sinifIliskileriKayitli: durum != 'yeni',
        kaydet: (ad, telefon, siniflar) async { kaydedilen = telefon; },
      ))));
      await t.enterText(find.byKey(const ValueKey('mesaj-ogretmen-telefon')), '05324445566');
      if (durum == 'sinif') { await t.tap(find.text('10-D')); await t.pumpAndSettle(); }
      await t.tap(find.text('Kaydet')); await t.pumpAndSettle();
      expect(kaydedilen, durum == 'telefon' ? '05324445566' : null);
      if (durum != 'telefon') {
        expect(find.byKey(const ValueKey('mesaj-ogretmen-dogrula')), findsOneWidget);
      }
    });
  }
}
