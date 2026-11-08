import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_ana_sayfa_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_dbf_import_screen.dart';
import 'package:elpi_okul_yonetim/models/dbf_belgesi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_dbf_service.dart';
import 'package:elpi_okul_yonetim/services/dbf_kaynak_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final factory = WindowsMemoryFactory();
  late Database db;

  setUpAll(() async {
    databaseFactory = factory;
    db = await LocalDatabase.instance.database;
  });

  tearDownAll(() => LocalDatabase.instance.close());

  testWidgets(
    'Geçmiş günün seçilen dersi kendi günlük planını ve temayı açar',
    (tester) async {
      Future<void> gorVeTikla(Finder hedef) async {
        await Scrollable.ensureVisible(tester.element(hedef), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(hedef.hitTestable());
        await tester.pumpAndSettle();
      }

      SharedPreferences.setMockInitialValues({
        'calisma_modu': 'bireysel',
        'ana_sayfa_kompakt': true,
        'ana_sayfa_tema': 'yesil',
        'ana_sayfa_ekran_modu': 'dark',
      });
      final now = DateTime.now();
      final bugun = DateTime(now.year, now.month, now.day);
      var hedef = bugun.subtract(const Duration(days: 1));
      while (hedef.weekday > DateTime.friday) {
        hedef = hedef.subtract(const Duration(days: 1));
      }
      String iso(DateTime t) =>
          '${t.year}-'
          '${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')}';
      final hamYil = '${now.year} / ${now.year + 1}';
      final planYili = '${now.year}-${now.year + 1}';
      await db.insert('OkulProfil', {
        'Id': 1,
        'OkulId': 'okul-1',
        'OkulAdi': 'Test Okulu',
        'OkulKisaAdi': 'TO',
        'EgitimYili': hamYil,
        'Donem': 1,
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgretmenProfil', {
        'OgretmenProfilId': 1,
        'AdSoyad': 'Öğretmen',
        'OkulAdi': 'Test Okulu',
        'EgitimOgretimYili': hamYil,
        'OlusturmaTarihi': 'test',
      });
      for (var seviye = 9; seviye <= 11; seviye++) {
        await db.insert('SinifSube', {
          'SinifSubeId': seviye,
          'SinifKodu': '$seviye-A',
          'SinifSeviyesi': seviye,
          'EgitimOgretimYili': hamYil,
          'OlusturmaTarihi': 'test',
        });
      }
      await db.insert('Ders', {
        'DersId': 1,
        'DersAdi': 'Matematik',
        'OlusturmaTarihi': 'test',
      });
      for (var sira = 1; sira <= 2; sira++) {
        await db.insert('DersSaati', {'DersSaatiId': sira, 'SiraNo': sira});
      }
      final eskiSurum = await db.insert('DersProgramiSurum', {
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': hamYil,
        'BaslangicTarihi': iso(hedef.subtract(const Duration(days: 30))),
        'BitisTarihi': iso(bugun.subtract(const Duration(days: 1))),
        'OlusturmaTarihi': 'test',
      });
      final yeniSurum = await db.insert('DersProgramiSurum', {
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': hamYil,
        'BaslangicTarihi': iso(bugun),
        'OlusturmaTarihi': 'test',
      });
      for (final gun in ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma']) {
        for (var seviye = 9; seviye <= 11; seviye++) {
          final sira = seviye == 10 ? 2 : 1;
          await db.insert('DersProgrami', {
            'DersId': 1,
            'SinifSubeId': seviye,
            'DersSaatiId': sira,
            'Gun': gun,
            'Baslangic': sira == 1 ? '08:00' : '09:00',
            'Bitis': sira == 1 ? '08:40' : '09:40',
            'OgretmenProfilId': 1,
            'EgitimOgretimYili': hamYil,
            'ProgramSurumId': seviye == 11 ? yeniSurum : eskiSurum,
            'OlusturmaTarihi': 'test',
          });
        }
      }
      for (var seviye = 9; seviye <= 11; seviye++) {
        final plan = await db.insert('YillikPlan', {
          'OgretmenProfilId': 1,
          'DersId': 1,
          'SinifSeviyesi': seviye,
          'EgitimOgretimYili': planYili,
          'OlusturmaTarihi': 'test',
        });
        await db.insert('YillikPlanDetay', {
          'YillikPlanId': plan,
          'HaftaNo': 7,
          'BaslangicTarihi': iso(hedef),
          'BitisTarihi': iso(bugun),
          'Konu': '$seviye. sınıf konusu',
          'Kazanim': '$seviye. sınıf kazanımı',
          'OlusturmaTarihi': 'test',
        });
      }
      final oncekiPlanlar = await db.query('YillikPlanDetay');

      await tester.pumpWidget(
        const MaterialApp(home: BireyselAnaSayfaScreen()),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      for (var i = 0; i < bugun.difference(hedef).inDays; i++) {
        await gorVeTikla(find.byIcon(Icons.chevron_left).first);
      }
      expect(find.text('Matematik · 9-A'), findsOneWidget);
      expect(find.text('Yıllık plan konusu'), findsOneWidget);
      expect(find.text('9. sınıf konusu'), findsOneWidget);
      await gorVeTikla(find.text('Sonraki ders'));
      expect(find.text('Matematik · 10-A'), findsOneWidget);
      expect(find.text('Yıllık plan konusu'), findsOneWidget);
      expect(find.text('10. sınıf konusu'), findsOneWidget);
      expect(find.text('9. sınıf konusu'), findsNothing);
      expect(find.text('Haftalık kazanım'), findsNothing);
      await gorVeTikla(find.text('Günlük Plan'));
      expect(find.byType(BireyselDbfImportScreen), findsOneWidget);
      expect(find.textContaining('Ders Bilgi Formu eksik'), findsOneWidget);
      expect(find.text('Günlük Plan Hazırla'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Matematik · 10-A'), findsOneWidget);
      for (final seviye in [9, 10]) {
        await BireyselDbfService.instance.kaydet(
          profilId: 1,
          egitimYili: hamYil,
          dersId: 1,
          sinifSeviyesi: seviye,
          belge: DbfBelgesi.metinden(
            dosyaAdi: 'Matematik.pdf',
            sayfalar: [
              'DERS BİLGİ FORMU DERSİN ADI MATEMATİK '
                  'DERSİN SINIFI $seviye. Sınıf DERSİN SÜRESİ 2 saat',
            ],
            icerikOzeti: 'test',
          ),
          beklenenSurum: 0,
          kaynakAdresi: DbfKaynakService.varsayilanAdres,
          programSurumu: '2026',
        );
      }
      await gorVeTikla(find.text('Günlük Plan'));
      expect(find.text('Günlük Plan Hazırla'), findsOneWidget);
      expect(find.text('10. sınıf kazanımı'), findsOneWidget);
      expect(find.text('9. sınıf kazanımı'), findsNothing);
      expect(
        find.textContaining(
          '${hedef.day.toString().padLeft(2, '0')}.'
          '${hedef.month.toString().padLeft(2, '0')}.${hedef.year}',
        ),
        findsWidgets,
      );
      expect(
        Theme.of(tester.element(find.text('10. sınıf kazanımı'))).brightness,
        Brightness.dark,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await gorVeTikla(find.text('Önceki ders'));
      await gorVeTikla(find.text('Günlük Plan'));
      expect(find.text('9. sınıf kazanımı'), findsOneWidget);
      expect(find.text('10. sınıf kazanımı'), findsNothing);
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
      expect(await db.query('YillikPlanDetay'), oncekiPlanlar);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
