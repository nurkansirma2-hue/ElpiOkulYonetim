import 'dart:io';

import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/bireysel_seflik.dart';
import 'package:elpi_okul_yonetim/services/bireysel_ders_programi_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bireysel şeflik saatlerinin ders programında görünmesi', () {
    late Database db;
    final factory = WindowsMemoryFactory();
    const yil = '2026/2027';
    final tarih = DateTime(2026, 10, 12);

    Future<List<BireyselHaftalikDers>> haftalik([DateTime? gun]) =>
        BireyselDersProgramiService.haftalikProgramiGetir(
          ogretmenProfilId: 1,
          egitimOgretimYili: yil,
          tarih: gun ?? tarih,
        );

    Future<BireyselBugunDersDurumu> gunluk([DateTime? gun]) =>
        BireyselDersProgramiService.bugununDurumunuGetir(
          ogretmenProfilId: 1,
          egitimOgretimYili: yil,
          tarih: gun ?? tarih,
        );

    Future<void> meslekPaketi(String deger) async {
      await db.insert('UygulamaAyarlari', {
        'Anahtar': 'MeslekPaketiAktif',
        'Deger': deger,
        'GuncellemeTarihi': 'test',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    Future<void> saatEkle(int no, {Map<String, Object?>? degerler}) async {
      await db.insert('SeflikProgramSaati', {
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': yil,
        'Gun': 'Pazartesi',
        'DersSaatiNo': no,
        'Baslangic': '10:00',
        'Bitis': '10:40',
        'BaslangicTarihi': '2026-10-05',
        'BitisTarihi': '2026-10-16',
        'Kaynak': 'Import',
        'HamMetin': 'ATÖLYE ŞEFLİĞİ',
        'Aktif': 1,
        'OlusturmaTarihi': 'test',
        ...?degerler,
      });
    }

    setUpAll(() async {
      databaseFactory = factory;
      db = await LocalDatabase.instance.database;
      for (var id = 1; id <= 2; id++) {
        await db.insert('OgretmenProfil', {
          'OgretmenProfilId': id,
          'AdSoyad': 'Öğretmen $id',
          'EgitimOgretimYili': yil,
          'Aktif': id == 1 ? 1 : 0,
          'OlusturmaTarihi': 'test',
        });
      }
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
      for (final tablo in [
        'SeflikProgramSaati',
        'SeflikTanim',
        'DersProgramiGorev',
        'DersProgrami',
        'DersProgramiSurum',
        'DersSinif',
        'SinifSube',
        'Ders',
        'DersSaati',
        'UygulamaAyarlari',
      ]) {
        await db.delete(tablo);
      }
      await meslekPaketi('1');
    });

    tearDownAll(() async {
      await factory.db?.close();
    });

    test('İthal şeflik günlük ve haftalık programa görev olarak katılır', () async {
      final eklenen = await BireyselDersProgramiService.kaydet(
        ogretmenProfilId: 1,
        egitimOgretimYili: yil,
        baslangicTarihi: tarih,
        kayitlar: const [
          BireyselDersProgramiKayitGirdisi(
            gun: 'Pazartesi', dersSaatiNo: 1,
            baslangic: '08:00', bitis: '08:40',
            dersAdi: 'Matematik', sinif: '9-A', derslik: '',
          ),
          BireyselDersProgramiKayitGirdisi(
            gun: 'Pazartesi', dersSaatiNo: 2,
            baslangic: '09:00', bitis: '09:40',
            dersAdi: 'Koordinatörlük', sinif: '', derslik: '',
          ),
        ],
        seflikImportu: SeflikProgramiImportu(
          baslangicTarihi: tarih,
          saatler: const [
            SeflikProgramSaatiGirdisi(
              gun: 'Pazartesi', dersSaatiNo: 3,
              baslangic: '10:00', bitis: '10:40',
              hamMetin: 'ATÖLYE ŞEFLİĞİ',
            ),
          ],
        ),
      );
      expect(eklenen, 2);
      final hafta = await haftalik();
      final bugun = await gunluk();
      expect(hafta.map((d) => d.dersSaatiNo), [1, 2, 3]);
      expect(bugun.dersler.map((d) => d.dersSaatiNo), [1, 2, 3]);
      expect(hafta.last.dersAdi, 'ATÖLYE ŞEFLİĞİ');
      expect(hafta.last.gorevMi, isTrue);
      expect(hafta.last.seflikMi, isTrue);
      expect(hafta.last.dersId, 0);
      expect(hafta.last.sinif, isEmpty);
      expect(bugun.dersler.last.dersAdi, 'ATÖLYE ŞEFLİĞİ');
      expect(bugun.dersler.last.gorevMi, isTrue);
      expect(bugun.dersler.last.seflikMi, isTrue);
      expect(bugun.dersler.last.konu, isEmpty);
      expect(bugun.dersler.last.sinifSeviyesi, isNull);
      expect(hafta.first.gorevMi, isFalse);
      expect(hafta[1].gorevMi, isTrue);
      expect(hafta[1].seflikMi, isFalse);
      expect((await db.query('Ders')).single['DersAdi'], 'Matematik');
      expect((await db.query('SinifSube')).single['SinifKodu'], '9-A');
      expect(await db.query('DersSinif'), hasLength(1));
      expect(await db.query('YillikPlan'), isEmpty);
    });

    test('Profil, eğitim yılı, aktiflik ve geçerlilik tarihleri korunur', () async {
      await saatEkle(1);
      await saatEkle(2, degerler: {'OgretmenProfilId': 2});
      await saatEkle(3, degerler: {'EgitimOgretimYili': '2025/2026'});
      await saatEkle(4, degerler: {'Aktif': 0});
      await saatEkle(5, degerler: {
        'BaslangicTarihi': '2026-10-19', 'BitisTarihi': null,
      });
      await saatEkle(6, degerler: {'BitisTarihi': '2026-10-09'});
      expect((await haftalik()).map((d) => d.dersSaatiNo), [1]);
      expect((await gunluk()).dersler.map((d) => d.dersSaatiNo), [1]);
      expect(await haftalik(DateTime(2026, 10, 4)), isEmpty);
      expect((await haftalik(DateTime(2026, 10, 5))).map((d) => d.dersSaatiNo), [1, 6]);
      expect((await haftalik(DateTime(2026, 10, 16))).map((d) => d.dersSaatiNo), [1]);
      expect(await haftalik(DateTime(2026, 10, 17)), isEmpty);
      expect((await haftalik(DateTime(2026, 10, 19))).map((d) => d.dersSaatiNo), [5]);
      expect((await gunluk(DateTime(2026, 10, 19))).dersler.map((d) => d.dersSaatiNo), [5]);
    });

    test('Meslek paketi kapatılınca şeflik gizlenir, kayıt korunur', () async {
      await saatEkle(1);
      await meslekPaketi('0');
      expect(await haftalik(), isEmpty);
      expect((await gunluk()).dersler, isEmpty);
      expect(await db.query('SeflikProgramSaati'), hasLength(1));
      await db.delete('UygulamaAyarlari');
      expect(await haftalik(), isEmpty);
      expect((await gunluk()).dersler, isEmpty);
      await meslekPaketi('1');
      expect(await haftalik(), hasLength(1));
      expect((await gunluk()).dersler, hasLength(1));
    });

    test('Bağlı şeflik tanımı adı ve kendi geçerliliğiyle kullanılır', () async {
      final id = await db.insert('SeflikTanim', {
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': yil,
        'SeflikTuru': 'AtolyeLaboratuvar',
        'HaftalikSaat': 1,
        'BaslangicTarihi': '2026-10-12',
        'BitisTarihi': '2026-10-16',
        'OlusturmaTarihi': 'test',
      });
      await saatEkle(1, degerler: {
        'SeflikId': id, 'Kaynak': 'Manuel', 'HamMetin': null,
      });
      expect((await haftalik()).single.dersAdi, 'Atölye/Laboratuvar Şefliği');
      expect((await gunluk()).dersler.single.seflikMi, isTrue);
      expect(await haftalik(DateTime(2026, 10, 5)), isEmpty);
      await db.update('SeflikTanim', {'Aktif': 0},
        where: 'SeflikId = ?', whereArgs: [id]);
      expect(await haftalik(), isEmpty);
      expect((await gunluk()).dersler, isEmpty);
    });
  }, skip: !Platform.isWindows);
}
