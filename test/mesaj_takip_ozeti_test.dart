import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/widgets/mesajlasma_gorunumu.dart';

MesajAlicisi alici(
  List<(String, String, String)> kisiler, {
  bool eski = false,
}) => MesajAlicisi(
  {
    'AliciId': 1,
    'Sira': 1,
    'Telefon': '905321112233',
    'AliciAdi': kisiler.map((k) => k.$2).join(' / '),
    'Durum': 'Acildi',
    'Ogrenciler': jsonEncode([
      for (final k in kisiler)
        {'tur': 'Ogretmen', 'kisiId': k.$1, 'aciklama': k.$3},
    ]),
  },
  baglar: eski
      ? []
      : [
          for (final k in kisiler)
            {
              'Tur': 'Ogretmen',
              'KisiId': k.$1,
              'AnlikGoruntu': jsonEncode({'ad': k.$2, 'aciklama': k.$3}),
            },
        ],
);

void main() {
  Future<void> ac(WidgetTester t, MesajAlicisi a, {double scale = 1}) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(
          body: Dialog(
            child: SizedBox(
              width: 520,
              height: 380,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  MesajTakipAliciOzeti(alici: a, sira: '1 / 2'),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Gönderdim, sıradakine geç'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('yalnız etkin öğretmen ve ona ait dersler görünür', (t) async {
    await ac(t, alici([('1', 'Ayşe Öğretmen', '9-C • Matematik 9')]));
    expect(find.textContaining('Ayşe Öğretmen'), findsOneWidget);
    expect(find.text('9-C • Matematik 9'), findsOneWidget);
    await ac(t, alici([('2', 'Ali Öğretmen', '9-C • Tarih 9')]));
    expect(find.textContaining('Ayşe Öğretmen'), findsNothing);
    expect(find.textContaining('Matematik'), findsNothing);
    expect(find.textContaining('Ali Öğretmen'), findsOneWidget);
    expect(find.text('9-C • Tarih 9'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final eski in [false, true]) {
    testWidgets(
      'ortak numara uzun isim listesi yerine kapsam sayısını gösterir: $eski',
      (t) async {
        await ac(
          t,
          alici([
            ('1', 'Ayşe Öğretmen', '9-C • Matematik 9'),
            ('2', 'Ali Öğretmen', '9-C • Tarih 9'),
            ('3', 'Ece Öğretmen', '9-C • Yabancı Dil 9'),
          ], eski: eski),
        );
        expect(find.textContaining('Ayşe Öğretmen'), findsOneWidget);
        expect(find.textContaining('Ali Öğretmen'), findsNothing);
        expect(find.textContaining('Ece Öğretmen'), findsNothing);
        expect(find.textContaining('Tarih'), findsNothing);
        expect(find.textContaining('Yabancı Dil'), findsNothing);
        expect(find.textContaining('3 öğretmen'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('uzun öğretmen ve ders adı büyük yazıda taşmaz', (t) async {
    await ac(
      t,
      alici([
        (
          '1',
          'Çok Uzun Adı Olan Ders Öğretmeni',
          '9-C • DİN KÜLTÜRÜ VE AHLAK BİLGİSİ 9, PEYGAMBERİMİZİN HAYATI',
        ),
      ]),
      scale: 2,
    );
    expect(t.takeException(), isNull);
    final textler = t.widgetList<Text>(find.byType(Text));
    expect(
      textler
          .where((w) => w.data?.contains('DİN KÜLTÜRÜ') == true)
          .single
          .maxLines,
      2,
    );
  });
}
