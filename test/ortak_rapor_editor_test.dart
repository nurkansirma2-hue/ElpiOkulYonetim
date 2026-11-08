import 'dart:convert';

import 'package:elpi_okul_yonetim/raporlama/rapor_modeli.dart';
import 'package:elpi_okul_yonetim/raporlama/rapor_tasarim_editoru.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _tanim = RaporTanimi(
  id: 'depo_envanteri',
  listeEtiketi: 'Envanter kalemleri',
  bilgiAlanlari: [
    RaporAlanTanimi(id: 'depo', etiket: 'Depo adı'),
    RaporAlanTanimi(id: 'sorumlu', etiket: 'Teslim sorumlusu'),
    RaporAlanTanimi(id: 'donem', etiket: 'Sayım dönemi'),
    RaporAlanTanimi(id: 'aciklama', etiket: 'Açıklama', serbestMetin: true),
  ],
  sutunAlanlari: [
    RaporAlanTanimi(id: 'stokKod', etiket: 'Stok kodu'),
    RaporAlanTanimi(id: 'urun', etiket: 'Ürün adı'),
    RaporAlanTanimi(id: 'miktar', etiket: 'Miktar'),
    RaporAlanTanimi(id: 'not', etiket: 'Ek not', tur: RaporHucreTuru.bos),
  ],
);

const _veri = RaporVerisi(
  bilgiler: {'depo': 'Merkez depo', 'sorumlu': 'Deniz Kaya', 'donem': 'Ekim 2026'},
  satirlar: [{'stokKod': 'ST-42', 'urun': 'Kalem', 'miktar': 24}],
);

RaporTasarimi _tasarim() => RaporTasarimi(
  ad: 'Envanter tasarımı',
  bilgiler: [
    RaporBilgiAlani(alanId: 'depo'),
    RaporBilgiAlani(alanId: 'sorumlu', konum: 'altSol', altMetin: 'Teslim yetkilisi'),
  ],
  sutunlar: [
    RaporTabloSutunu(alanId: 'stokKod', baslik: 'Stok kodu'),
    RaporTabloSutunu(alanId: 'urun', baslik: 'Ürün adı'),
  ],
);

Future<void> _ac(WidgetTester tester, RaporTasarimi tasarim,
    {bool buyukYazi = false, VoidCallback? degisti}) async {
  await tester.pumpWidget(MaterialApp(
    builder: buyukYazi ? (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ) : null,
    home: Scaffold(body: StatefulBuilder(builder: (context, setState) =>
      ListView(padding: const EdgeInsets.all(12), children: [
        RaporTasarimEditoru(tanim: _tanim, tasarim: tasarim, veri: _veri,
          onDegistir: (islem) {
            setState(islem);
            degisti?.call();
          }),
      ]))),
  ));
  await tester.pumpAndSettle();
}

Future<void> _goster(WidgetTester tester, Finder alan) async {
  if (alan.hitTestable().evaluate().isEmpty) {
    await Scrollable.ensureVisible(tester.element(alan), alignment: 0.5);
  }
  await tester.pumpAndSettle();
}

Future<void> _tikla(WidgetTester tester, String anahtar) async {
  final alan = find.byKey(ValueKey(anahtar));
  await _goster(tester, alan);
  await tester.tap(alan);
  await tester.pumpAndSettle();
}

Future<void> _konumSec(WidgetTester tester, int i, String etiket) async {
  final alan = find.byKey(ValueKey('ortak-bilgi-konum-$i'));
  await _goster(tester, alan);
  await tester.tap(alan);
  await tester.pumpAndSettle();
  await tester.tap(find.text(etiket).last);
  await tester.pumpAndSettle();
}

Future<void> _yerlesimiAc(WidgetTester tester) async {
  final baslik = find.text('Sürükle bırak yerleşimi');
  await _goster(tester, baslik);
  await tester.tap(baslik);
  await tester.pumpAndSettle();
}

Future<void> _sirala(WidgetTester tester, String tur, double asagi) async {
  final ilk = find.byKey(ValueKey('ortak-$tur-sirala-0'));
  final ikinci = find.byKey(ValueKey('ortak-$tur-sirala-1'));
  await _goster(tester, ilk);
  await _goster(tester, ikinci);
  final baslangic = tester.getCenter(ilk);
  final hedef = tester.getCenter(ikinci) + Offset(0, asagi);
  final hareket = await tester.startGesture(baslangic);
  for (var adim = 1; adim <= 8; adim++) {
    await hareket.moveTo(Offset.lerp(baslangic, hedef, adim / 8)!);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 400));
  await hareket.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Envanter alanları doğrudan konum seçer; görünürlük ve katalog JSONda korunur',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tasarim = _tasarim();
    var degisimSayisi = 0;
    await _ac(tester, tasarim, degisti: () => degisimSayisi++);
    expect(find.text('Depo adı'), findsOneWidget);
    expect(find.text('Okul müdürü'), findsNothing);
    await _konumSec(tester, 0, 'Alt sağ');
    await _tikla(tester, 'ortak-bilgi-goster-0');
    expect(tasarim.bilgiler.first.konum, 'altSag');
    expect(tasarim.bilgiler.first.goster, isFalse);
    expect(_veri.bilgiler['depo'], 'Merkez depo');
    await _tikla(tester, 'ortak-sutun-goster-0');
    await _tikla(tester, 'ortak-sutun-goster-1');
    expect(tasarim.sutunlar.last.goster, isTrue);
    expect(find.text('En az bir görünür sütun seçin.'), findsOneWidget);
    await _tikla(tester, 'ortak-bilgi-ekle-donem');
    await _tikla(tester, 'ortak-sutun-ekle-miktar');
    final kayit = RaporTasarimi.fromJson(
        jsonDecode(jsonEncode(tasarim.toJson(_tanim.id))) as Map<String, dynamic>, _tanim);
    expect(kayit.bilgiler.map((b) => b.alanId), ['depo', 'sorumlu', 'donem']);
    expect(kayit.bilgiler.first.konum, 'altSag');
    expect(kayit.bilgiler.first.goster, isFalse);
    expect(kayit.sutunlar.map((s) => s.alanId), ['stokKod', 'urun', 'miktar']);
    expect(kayit.sutunlar.first.goster, isFalse);
    expect(degisimSayisi, greaterThanOrEqualTo(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sıradan envanter bilgisi sürüklenir; bilgi ve sütun sırası kimlikleri korur',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tasarim = _tasarim();
    await _ac(tester, tasarim);
    await _yerlesimiAc(tester);
    final kaynak = find.byKey(const ValueKey('ortak-bilgi-surukle-1'));
    final hedef = find.byKey(const ValueKey('ortak-bolge-ustSag'));
    await _goster(tester, kaynak);
    await _goster(tester, hedef);
    final hareket = await tester.startGesture(tester.getCenter(kaynak));
    await tester.pump(const Duration(milliseconds: 700));
    await hareket.moveTo(tester.getCenter(hedef));
    await tester.pump(const Duration(milliseconds: 200));
    await hareket.up();
    await tester.pumpAndSettle();
    expect(tasarim.bilgiler[1].konum, 'ustSag');
    expect(find.descendant(of: hedef, matching: kaynak), findsOneWidget);
    final baslik = find.text('Sürükle bırak yerleşimi');
    await _goster(tester, baslik);
    await tester.tap(baslik);
    await tester.pumpAndSettle();
    await _sirala(tester, 'bilgi', 65);
    await _sirala(tester, 'sutun', 32);
    final kayit = RaporTasarimi.fromJson(tasarim.toJson(_tanim.id), _tanim);
    expect(kayit.bilgiler.map((b) => b.alanId), ['sorumlu', 'depo']);
    expect(kayit.bilgiler.first.konum, 'ustSag');
    expect(kayit.bilgiler.first.altMetin, 'Teslim yetkilisi');
    expect(kayit.sutunlar.map((s) => s.alanId), ['urun', 'stokKod']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 genişlik ve büyük yazıda her alanın konumu ve altı sürükleme bölgesi açılır',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tasarim = _tasarim();
    await _ac(tester, tasarim, buyukYazi: true);
    await _konumSec(tester, 0, 'Alt orta');
    await _konumSec(tester, 1, 'Üst sol');
    expect(tasarim.bilgiler.map((b) => b.konum), ['altOrta', 'ustSol']);
    await _yerlesimiAc(tester);
    for (final konum in RaporBilgiAlani.konumlar.keys) {
      expect(find.byKey(ValueKey('ortak-bolge-$konum')), findsOneWidget);
    }
    await _tikla(tester, 'ortak-bilgi-ekle-aciklama');
    expect(tasarim.bilgiler.last.sabitMetin, 'Yeni başlık');
    await _tikla(tester, 'ortak-bilgi-cogalt-aciklama');
    expect(tasarim.bilgiler.where((b) => b.alanId == 'aciklama').length, 2);
    await _tikla(tester, 'ortak-sutun-ekle-not');
    await _tikla(tester, 'ortak-sutun-cogalt-not');
    expect(tasarim.sutunlar.where((s) => s.alanId == 'not').length, 2);
    expect(() => tasarim.dogrula(_tanim), returnsNormally);
    expect(tester.takeException(), isNull);
  });
}
