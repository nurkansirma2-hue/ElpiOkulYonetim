import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/services/baslangic_belgeleri_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_belge_service.dart';
import 'support/windows_memory_database.dart';

class _DosyaBundle extends CachingAssetBundle {
  String? hata;
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith(hata ?? '\u0000')) throw StateError('Test okuma hatası');
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory alan;
  late BireyselBelgeService belgeler;
  late BaslangicBelgeleriService baslangic;
  late _DosyaBundle bundle;
  late String arsiv;
  CalismaModu? mod = CalismaModu.bireyselOgretmen;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mod = CalismaModu.bireyselOgretmen;
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    final db = await LocalDatabase.instance.database;
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'baslangic-test',
      'OkulAdi': 'Test Okulu',
      'OkulKisaAdi': 'Test',
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Test Öğretmen',
      'OkulAdi': 'Test Okulu',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    alan = await Directory.systemTemp.createTemp('baslangic_belgeleri_test_');
    belgeler = BireyselBelgeService(
      databaseGetir: () async => db,
      alanGetir: () async => alan,
      modGetir: () async => mod,
    );
    arsiv = (await belgeler.arsivleriGetir()).aktif.id;
    bundle = _DosyaBundle();
    baslangic = BaslangicBelgeleriService(bundle: bundle);
  });

  tearDown(() async {
    await LocalDatabase.instance.close();
    await alan.delete(recursive: true);
  });

  test(
    'Sekiz özgün dosya birebir eklenir; eşzamanlı tekrar çoğaltmaz',
    () async {
      await Future.wait([
        baslangic.yukle(belgeler, arsiv),
        baslangic.yukle(belgeler, arsiv),
      ]);
      final liste = await belgeler.listele(arsivId: arsiv);
      expect(
        liste.map((b) => b.dosyaAdi).toSet(),
        BaslangicBelgeleriService.dosyalar.toSet(),
      );
      for (final belge in liste) {
        final yol = await belgeler.dosyaYolunuGetir(
          arsivId: arsiv,
          belgeId: belge.id,
        );
        expect(
          await File(yol).readAsBytes(),
          await File(
            'assets/baslangic_belgeleri/${belge.dosyaAdi}',
          ).readAsBytes(),
        );
      }
    },
  );

  test('Çöp kutusuna taşınan veya kalıcı silinen dosya geri gelmez', () async {
    await baslangic.yukle(belgeler, arsiv);
    final liste = await belgeler.listele(arsivId: arsiv);
    await belgeler.belgeyiDuzenle(liste[0], sil: true);
    await belgeler.belgeyiDuzenle(liste[1], sil: true);
    await belgeler.kaliciSil(liste[1], onay: 'SİL');
    await baslangic.yukle(belgeler, arsiv);
    expect(await belgeler.listele(arsivId: arsiv), hasLength(6));
    expect(
      await belgeler.listele(arsivId: arsiv, copKutusu: true),
      hasLength(1),
    );
  });

  test('Yarım kalan yükleme yalnız kalan dosyaları tamamlar', () async {
    bundle.hata = '12.xls';
    await expectLater(baslangic.yukle(belgeler, arsiv), throwsStateError);
    expect(await belgeler.listele(arsivId: arsiv), hasLength(3));
    bundle.hata = null;
    await baslangic.yukle(belgeler, arsiv);
    expect(await belgeler.listele(arsivId: arsiv), hasLength(8));
  });

  test('Bireysel mod dışında kayıt oluşturulmaz', () async {
    mod = null;
    await expectLater(baslangic.yukle(belgeler, arsiv), throwsStateError);
    mod = CalismaModu.bireyselOgretmen;
    expect(await belgeler.listele(arsivId: arsiv), isEmpty);
  });
}
