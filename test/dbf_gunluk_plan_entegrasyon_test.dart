import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/dbf_belgesi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_dbf_service.dart';
import 'package:elpi_okul_yonetim/services/dbf_kaynak_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_gunluk_plan_service.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_gunluk_plan_screen.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late DbfBelgesi dbf;
  Future<void> dbfKaydet() async {
    await BireyselDbfService.instance.kaydet(
      profilId: 1,
      egitimYili: '2026/2027',
      dersId: 1,
      sinifSeviyesi: 9,
      belge: dbf,
      beklenenSurum: 0,
      kaynakAdresi: DbfKaynakService.varsayilanAdres,
      programSurumu: '2026',
    );
  }

  Future<dynamic> hazirla({int ders = 1, bool yeniden = false}) =>
      BireyselGunlukPlanService.hazirla(
        ogretmenProfilId: 1,
        egitimOgretimYili: '2026/2027',
        dersId: ders,
        yenidenOlustur: yeniden,
        sinifSeviyesi: 9,
        sinifSubeId: 1,
        tarih: DateTime(2026, 10, 14),
      );
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    dbf = DbfBelgesi.metinden(
      dosyaAdi: 'MEB.pdf',
      sayfalar:
          (jsonDecode(
                    await File(
                      'test/fixtures/dbf/meb_dbf_metni.json',
                    ).readAsString(),
                  )
                  as List)
              .cast<String>(),
      icerikOzeti: 'fixture',
    );
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'O',
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'OgretmenProfilId': 1,
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('SinifSube', {
      'SinifSubeId': 1,
      'SinifKodu': '9-A',
      'SinifSeviyesi': 9,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    for (final id in [1, 2]) {
      await db.insert('Ders', {
        'DersId': id,
        'DersAdi': dbf.dersAdi,
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'DersId': id,
        'SinifSubeId': 1,
        'DersSaatiId': 1,
        'Gun': id == 1 ? 'Çarşamba' : 'Perşembe',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      final p = await db.insert('YillikPlan', {
        'OgretmenProfilId': 1,
        'DersId': id,
        'SinifSeviyesi': 9,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('YillikPlanDetay', {
        'YillikPlanId': p,
        'HaftaNo': 6,
        'Saat': '2',
        'BaslangicTarihi': '2026-10-12',
        'BitisTarihi': '2026-10-16',
        'Konu': 'Norm Yazı Yazma',
        'Kazanim': 'BTU.1.1. Temel teknik resim uygulamaları yapabilme',
        'OlusturmaTarihi': 'test',
      });
    }
  });
  tearDown(() => LocalDatabase.instance.close());
  test(
    'Kaynak SQLite kaydından okunur; başka ders kimliğine taşınmaz',
    () async {
      await dbfKaydet();
      final p = await hazirla();
      expect(p.ogrenmeCiktisi, 'Temel teknik resim uygulamaları yapabilme');
      expect(p.dersinIslenisi, contains('norm yazı biçimini uygulaması'));
      expect(p.etkinlikler, contains('norm yazı olarak yazmak'));
      await expectLater(hazirla(ders: 2), throwsStateError);
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
    },
  );
  test(
    'Kayıtlı boş alanlar otomatik değiştirilmez; yeniden üretim önceki sürümü saklar',
    () async {
      await dbfKaydet();
      final kayit = await BireyselGunlukPlanService.kaydet(
        (await hazirla()).copyWith(
          yontemTeknik: 'Öğretmenin yöntemi',
          dersinIslenisi: '',
          etkinlikler: '',
        ),
      );
      final once = await db.query('BireyselGunlukPlan');
      final p = await hazirla();
      expect(p.id, kayit.id);
      expect(p.yontemTeknik, 'Öğretmenin yöntemi');
      expect(p.dersinIslenisi, isEmpty);
      expect(await db.query('BireyselGunlukPlan'), once);
      final saved = await BireyselGunlukPlanService.kaydet(
        await hazirla(yeniden: true),
      );
      expect(saved.surum, 2);
      expect(saved.dersinIslenisi, contains('norm yazı biçimini uygulaması'));
      final gecmis = await BireyselGunlukPlanService.gecmisiGetir(saved.id!);
      expect(gecmis.single.yontemTeknik, 'Öğretmenin yöntemi');
      expect(gecmis.single.dersinIslenisi, isEmpty);
    },
  );
  testWidgets(
    'Kayıtlı plan kaynakla üzerine yazılmadan ve değiştirilmiş sayılmadan açılır',
    (tester) async {
      await dbfKaydet();
      await BireyselGunlukPlanService.kaydet(
        (await hazirla()).copyWith(dersinIslenisi: ''),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BireyselGunlukPlanScreen(
            ogretmenProfilId: 1,
            egitimOgretimYili: '2026/2027',
            dersId: 1,
            dersAdi: dbf.dersAdi,
            sinifSeviyesi: 9,
            tarih: DateTime(2026, 10, 14),
            baslangicSinifKodu: '9-A',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final alan = find.byKey(const ValueKey('gunluk-plan-dersinIslenisi'));
      await tester.scrollUntilVisible(
        alan,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<TextFormField>(alan).controller!.text, isEmpty);
      final durum = find.text('Plan kaydedildi.');
      await tester.scrollUntilVisible(
        durum,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(durum, findsOneWidget);
      expect(find.text('Kaydedilmemiş değişiklikler var.'), findsNothing);
      expect((await db.query('BireyselGunlukPlan')).single['Surum'], 1);
      expect(tester.takeException(), isNull);
    },
  );
}
