import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/bireysel_gunluk_plan.dart';
import 'package:elpi_okul_yonetim/services/bireysel_gunluk_plan_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_gunluk_plan_belge_service.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_gunluk_plan_screen.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_gunluk_plan_akisi.dart';
import 'support/windows_memory_database.dart';
import 'support/gunluk_plan_fixture.dart';
import 'package:elpi_okul_yonetim/services/bireysel_yillik_plan_service.dart';
import 'dart:typed_data';

class _GecikmeliDb extends WindowsMemoryDatabase {
  Future<void>? bekle;
  bool durdu = false;
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (table == 'YillikPlanDetay' && bekle != null) {
      final future = bekle!;
      bekle = null;
      durdu = true;
      await future;
    }
    return super.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }
}

class _GecikmeliFactory extends WindowsMemoryFactory {
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final database = db = _GecikmeliDb();
    await options?.onConfigure?.call(database);
    await options?.onCreate?.call(database, options.version!);
    await options?.onOpen?.call(database);
    return database;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  Future<BireyselGunlukPlan> hazirla({
    int ders = 1,
    int sinif = 1,
    int gun = 14,
    bool yeniden = false,
  }) => BireyselGunlukPlanService.hazirla(
    ogretmenProfilId: 1,
    egitimOgretimYili: '2026/2027',
    dersId: ders,
    sinifSeviyesi: 9,
    sinifSubeId: sinif,
    tarih: DateTime(2026, 10, gun),
    yenidenOlustur: yeniden,
  );
  Future<void> detayEkle({
    int ders = 1,
    String konu = 'Denklemler',
    int hafta = 6,
    String bas = '2026-10-12',
    String bit = '2026-10-16',
    String saat = '2',
  }) async {
    await db.insert('YillikPlanDetay', {
      'YillikPlanId': ders,
      'HaftaNo': hafta,
      'BaslangicTarihi': bas,
      'BitisTarihi': bit,
      'Saat': saat,
      'Konu': konu,
      'Unite': 'Cebir',
      'Kazanim': '$konu konusunda çözüm adımlarını açıklar.',
      'KazanimAciklamasi': '$konu için çözüm sırası incelenir.',
      'OlusturmaTarihi': 'test',
    });
  }

  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = _GecikmeliFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    db = await LocalDatabase.instance.database;
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
      'OkulAdi': 'Çınar Okulu',
      'OkulKisaAdi': 'ÇO',
      'EgitimYili': '2026/2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'OgretmenProfilId': 1,
      'AdSoyad': 'Ayşe Öğretmen',
      'OkulAdi': 'Çınar Okulu',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
    for (final id in [1, 2]) {
      await db.insert('SinifSube', {
        'SinifSubeId': id,
        'SinifKodu': '9-${id == 1 ? 'A' : 'B'}',
        'SinifSeviyesi': 9,
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('Ders', {
        'DersId': id,
        'DersAdi': id == 1 ? 'Matematik' : 'Fizik',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersProgrami', {
        'DersId': id,
        'SinifSubeId': id,
        'DersSaatiId': 1,
        'Gun': 'Çarşamba',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('YillikPlan', {
        'YillikPlanId': id,
        'DersId': id,
        'SinifSeviyesi': 9,
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'Aciklama': 'Import dosyası: ders-$id.docx',
        'OlusturmaTarihi': 'test',
      });
      await detayEkle(ders: id, konu: id == 1 ? 'Denklemler' : 'Kuvvetler');
      await gunlukPlanTestDbfEkle(
        db,
        dersId: id,
        dersAdi: id == 1 ? 'Matematik' : 'Fizik',
      );
    }
  });
  tearDown(() => LocalDatabase.instance.close());
  test(
    'Seçili ders ve şube kaynakları karışmaz; kapsam dışı şube reddedilir',
    () async {
      final a = await hazirla();
      final b = await hazirla(ders: 2, sinif: 2);
      expect(a.konu, 'Denklemler');
      expect(b.konu, 'Kuvvetler');
      expect((a.planBilgisi['kaynaklar'] as Map)['dbfOzeti'], 'ders-1-v1');
      await expectLater(hazirla(ders: 1, sinif: 2), throwsStateError);
    },
  );
  test(
    'Haftanın farklı günleri tek kaydı açar; yeniden oluşturma eski sürümü korur',
    () async {
      final ilk = await BireyselGunlukPlanService.kaydet(
        await hazirla(gun: 12),
      );
      expect((await hazirla(gun: 16)).id, ilk.id);
      await db.update('YillikPlanDetay', {
        'Konu': 'Eşitsizlikler',
      }, where: 'YillikPlanId = 1');
      expect((await hazirla()).konu, 'Denklemler');
      final yeni = await BireyselGunlukPlanService.kaydet(
        await hazirla(yeniden: true),
      );
      expect(yeni.id, ilk.id);
      expect(yeni.surum, 2);
      expect(yeni.konu, 'Eşitsizlikler');
      final gecmis = await BireyselGunlukPlanService.gecmisiGetir(ilk.id!);
      expect(gecmis.single.konu, 'Denklemler');
      expect(
        (gecmis.single.planBilgisi['kaynaklar'] as Map)['yillikPlanSatirlari'],
        isNotEmpty,
      );
      expect(await db.query('BireyselGunlukPlan'), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await expectLater(
        BireyselGunlukPlanService.kaydet(ilk.copyWith(konu: 'Eski')),
        throwsStateError,
      );
    },
  );
  test(
    'Eksik DBF ve yıllık plan açıkça bildirilir; kaynak yokken yeni kayıt oluşmaz',
    () async {
      await db.delete('UygulamaAyarlari');
      await expectLater(
        hazirla(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'mesaj',
            contains('Ders bilgi formu eksik'),
          ),
        ),
      );
      await db.delete('YillikPlanDetay', where: 'YillikPlanId = 1');
      await expectLater(
        hazirla(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'mesaj',
            contains('Yıllık plan eksik'),
          ),
        ),
      );
      expect(await db.query('BireyselGunlukPlan'), isEmpty);
    },
  );
  test(
    'Kaynak kaldırılınca kayıtlı plan aynı kaynak sürümüyle açılır',
    () async {
      final ilk = await BireyselGunlukPlanService.kaydet(await hazirla());
      await db.delete('YillikPlanDetay');
      await db.delete(
        'UygulamaAyarlari',
        where: 'Anahtar LIKE ?',
        whereArgs: ['dbf.v1.%'],
      );
      final kayitli = await hazirla(gun: 16);
      expect(kayitli.planBilgisi, ilk.planBilgisi);
      await expectLater(hazirla(yeniden: true), throwsStateError);
      expect((await hazirla()).surum, 1);
    },
  );
  test(
    'Saat toplamı doğru; birleşik hücrenin tekrarı iki kez toplanmaz',
    () async {
      await detayEkle(konu: 'Problem çözme');
      final p = await hazirla();
      expect(p.dersSaati, '2 Saat');
      expect(
        (p.planBilgisi['saatDagilimi'] as List).fold<int>(
          0,
          (n, r) => n + (r['saat'] as int),
        ),
        2,
      );
      expect(p.dersinIslenisi, contains('Toplam: 2 ders saati'));
      expect(p.kazanim, contains('Problem çözme'));
    },
  );
  test(
    'Tarih çakışması reddedilir; eksik/çelişkili saat ve açıklama uydurulmaz',
    () async {
      await detayEkle(hafta: 7);
      await expectLater(hazirla(), throwsStateError);
      await db.delete('YillikPlanDetay', where: 'YillikPlanId = 1');
      await detayEkle(saat: '2');
      await detayEkle(saat: '4');
      final p = await hazirla();
      expect(p.dersinIslenisi, isEmpty);
      expect(p.aciklamalar, contains('çelişkili'));
      await expectLater(hazirla(gun: 21), throwsStateError);
    },
  );
  test('Tatil tarihi için normal plan oluşturulmaz', () async {
    final t = await db.insert('CalismaTakvimi', {
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026/2027',
      'KaynakDosyaAdi': 'ders-1.docx',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('CalismaTakvimiDetay', {
      'CalismaTakvimiId': t,
      'HaftaNo': 6,
      'BaslangicTarihi': '2026-10-12',
      'BitisTarihi': '2026-10-16',
      'CalismaVarMi': 0,
      'KayitTuru': 'AraTatil',
      'Aciklama': 'Ara tatil',
      'OlusturmaTarihi': 'test',
    });
    await expectLater(
      hazirla(),
      throwsA(
        isA<StateError>().having((e) => e.message, 'mesaj', contains('tatil')),
      ),
    );
    expect(await db.query('BireyselGunlukPlan'), isEmpty);
  });
  test(
    'Alan düzenlemesi ve DBF sürümleri geçmişte kayıpsız saklanır',
    () async {
      final ilk = await BireyselGunlukPlanService.kaydet(await hazirla());
      final duzen = await BireyselGunlukPlanService.kaydet(
        ilk.copyWith(kazanimAciklamasi: 'Öğretmenin açıklaması'),
      );
      expect(duzen.surum, 2);
      await gunlukPlanTestDbfEkle(db, surum: 2);
      expect((await hazirla()).kazanimAciklamasi, 'Öğretmenin açıklaması');
      final yeni = await BireyselGunlukPlanService.kaydet(
        await hazirla(yeniden: true),
      );
      expect(yeni.surum, 3);
      final eski = await BireyselGunlukPlanService.gecmisiGetir(ilk.id!);
      expect(eski, hasLength(2));
      expect(eski.first.kazanimAciklamasi, 'Öğretmenin açıklaması');
      expect((eski.last.planBilgisi['kaynaklar'] as Map)['dbfSurum'], 1);
      expect((yeni.planBilgisi['kaynaklar'] as Map)['dbfSurum'], 2);
    },
  );
  test(
    'Donanım yöntem alanında kalmaz ve farklı haftaların işlenişi değişir',
    () async {
      await db.update('YillikPlanDetay', {
        'YontemTeknik': 'Bilgisayar ve projeksiyon',
      }, where: 'YillikPlanId = 1');
      final a = await hazirla();
      expect(a.yontemTeknik, isNot(contains('Bilgisayar')));
      expect(a.aracGerec, contains('Bilgisayar'));
      await detayEkle(
        konu: 'Geometrik çizimler',
        hafta: 7,
        bas: '2026-10-19',
        bit: '2026-10-23',
        saat: '4',
      );
      final b = await hazirla(gun: 21);
      expect(a.dersinIslenisi, isNot(b.dersinIslenisi));
      expect(b.dersinIslenisi, contains('Toplam: 4'));
    },
  );
  test(
    'DOCX güvenli XML, A4 ve Türkçe karakterler; örnek gerçek servislerden üretilir',
    () async {
      final p = await hazirla();
      final docx = BireyselGunlukPlanBelgeService.docxOlustur(
        p.copyWith(aciklamalar: '<komut> & “Türkçe” şğıİöü'),
      );
      final zip = ZipDecoder().decodeBytes(docx);
      final xml = utf8.decode(
        zip.findFile('word/document.xml')!.content as List<int>,
      );
      final parsed = XmlDocument.parse(xml);
      expect(parsed.innerText, contains('<komut> & “Türkçe” şğıİöü'));
      expect(xml, contains('w:w="11906" w:h="16838"'));
      expect(
        parsed.innerText.indexOf('İmzalar'),
        greaterThan(parsed.innerText.indexOf('Özet / işleniş')),
      );
      for (final b in BireyselGunlukPlanBelgeService.bolumler(p).keys) {
        expect(parsed.innerText, contains(b));
      }
      if (Platform.environment['GUNLUK_PLAN_QA'] case final String path) {
        await Directory(path).create(recursive: true);
        await File(
          '$path/gunluk_plan_ornek.docx',
        ).writeAsBytes(BireyselGunlukPlanBelgeService.docxOlustur(p));
        await File(
          '$path/gunluk_plan_ornek.pdf',
        ).writeAsBytes(await BireyselGunlukPlanBelgeService.pdfOlustur(p));
      }
    },
  );
  test(
    'Gerçek import dersin takvimini saklar; sonraki ders importu olayları karıştırmaz',
    () async {
      Future<void> yukle(int ders, String etkinlik) async {
        final on = BireyselYillikPlanService.eslenmisSatirlariOku([
          {
            'hafta': '6',
            'tarih': '12-16 Ekim',
            'saat': '2',
            'konu': 'Denklemler',
            'kazanim': 'Denklem çözüm adımlarını açıklar.',
            'etkinlik': etkinlik,
          },
        ], egitimOgretimYili: '2026-2027');
        expect(on.basarili, isTrue);
        await BireyselYillikPlanService.kaydet(
          dersId: ders,
          sinifSeviyesi: 9,
          ogretmenProfilId: 1,
          egitimOgretimYili: '2026-2027',
          onIzleme: on,
        );
      }

      await yukle(1, 'Birinci ders etkinliği');
      await yukle(2, 'İkinci ders sınavı');
      final p = await hazirla();
      expect(p.etkinlikler, contains('Birinci ders etkinliği'));
      expect(p.etkinlikler, isNot(contains('İkinci ders sınavı')));
      expect((p.planBilgisi['kaynaklar'] as Map)['takvimKaynakSurumu'], 1);
      final q = await hazirla(ders: 2, sinif: 2);
      expect(q.etkinlikler, contains('İkinci ders sınavı'));
    },
  );
  test(
    'Word birleşik hafta/tarih/saat hücreleri içeriği korur ve saati çoğaltmaz',
    () async {
      String cell(String value, {bool bas = false, bool devam = false}) =>
          '<w:tc>'
          '<w:tcPr>${bas
              ? '<w:vMerge w:val="restart"/>'
              : devam
              ? '<w:vMerge/>'
              : ''}</w:tcPr>'
          '<w:p><w:r><w:t>$value</w:t></w:r></w:p></w:tc>';
      final xml =
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:tbl>'
          '<w:tr>${['Hafta', 'Tarih', 'Saat', 'Ünite', 'Konu', 'Kazanım', 'Kazanım Açıklaması'].map((s) => cell(s)).join()}</w:tr>'
          '<w:tr>${['6. Hafta', '12-16 Ekim', '2', 'Cebir'].map((s) => cell(s, bas: true)).join()}'
          '${cell('Denklemler')}${cell('Denklem çözer.')}${cell('Çözüm adımları açıklanır.')}</w:tr>'
          '<w:tr>${List.generate(4, (_) => cell('', devam: true)).join()}'
          '${cell('Problemler')}${cell('Problem kurar.')}${cell('Günlük problemleri inceler.')}</w:tr>'
          '</w:tbl></w:body></w:document>';
      final content = utf8.encode(xml);
      final bytes = Uint8List.fromList(
        ZipEncoder().encode(
          Archive()..addFile(
            ArchiveFile('word/document.xml', content.length, content),
          ),
        )!,
      );
      final on = await BireyselYillikPlanService.onIzlemeHazirla(
        dosyaBytes: bytes,
        dosyaAdi: 'birlesik.docx',
        dosyaUzantisi: 'docx',
        egitimOgretimYili: '2026-2027',
      );
      expect(on.basarili, isTrue);
      expect(on.kayitlar, hasLength(1));
      expect(on.kayitlar.single.saat, '2');
      expect(on.kayitlar.single.kazanim, contains('Problem kurar.'));
      expect(
        on.kayitlar.single.kazanimAciklamasi,
        contains('Günlük problemleri inceler.'),
      );
      await BireyselYillikPlanService.kaydet(
        dersId: 1,
        sinifSeviyesi: 9,
        ogretmenProfilId: 1,
        egitimOgretimYili: '2026-2027',
        onIzleme: on,
      );
      final p = await hazirla();
      expect(p.dersSaati, '2 Saat');
      expect(p.kazanim, contains('Denklem çözer.'));
      expect(p.kazanim, contains('Problem kurar.'));
    },
  );
  test('Import aynı haftanın çelişkili saatlerini gizlemez', () async {
    final on = BireyselYillikPlanService.eslenmisSatirlariOku([
      {
        'hafta': '6',
        'tarih': '12-16 Ekim',
        'saat': '2',
        'konu': 'Denklemler',
        'kazanim': 'Denklem çözer.',
      },
      {
        'hafta': '6',
        'tarih': '12-16 Ekim',
        'saat': '4',
        'konu': 'Problemler',
        'kazanim': 'Problem kurar.',
      },
    ], egitimOgretimYili: '2026-2027');
    expect(on.kayitlar.single.saat, '2\n4');
    await BireyselYillikPlanService.kaydet(
      dersId: 1,
      sinifSeviyesi: 9,
      ogretmenProfilId: 1,
      egitimOgretimYili: '2026-2027',
      onIzleme: on,
    );
    final p = await hazirla();
    expect(p.dersinIslenisi, isEmpty);
    expect(p.aciklamalar, contains('çelişkili'));
  });
  test('Eski gün bazlı plan aynı haftada DBF eksikken de açılır', () async {
    final id = await db.insert('BireyselGunlukPlan', {
      'Surum': 1,
      'OkulId': 'okul-1',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026-2027',
      'DersId': 1,
      'SinifSubeId': 1,
      'SinifSeviyesi': 9,
      'OgretmenAdi': 'Ayşe Öğretmen',
      'OkulAdi': 'Çınar Okulu',
      'DersAdi': 'Matematik',
      'SinifKodu': '9-A',
      'Tarih': '2026-10-14',
      'Konu': 'Eski günlük plan',
      'OlusturmaTarihi': 'test',
    });
    await db.delete(
      'UygulamaAyarlari',
      where: 'Anahtar LIKE ?',
      whereArgs: ['dbf.v1.%'],
    );
    final p = await BireyselGunlukPlanService.kayitliHaftayiGetir(
      ogretmenProfilId: 1,
      egitimOgretimYili: '2026/2027',
      dersId: 1,
      sinifSeviyesi: 9,
      sinifKodu: '9-A',
      tarih: DateTime(2026, 10, 16),
    );
    expect(p!.id, id);
    expect(p.konu, 'Eski günlük plan');
    expect(p.surum, 1);
    expect(await db.query('BireyselGunlukPlan'), hasLength(1));
  });
  Widget ekran(int ders, {Key? key}) => MaterialApp(
    home: BireyselGunlukPlanScreen(
      key: key,
      ogretmenProfilId: 1,
      egitimOgretimYili: '2026/2027',
      dersId: ders,
      dersAdi: ders == 1 ? 'Matematik' : 'Fizik',
      sinifSeviyesi: 9,
      tarih: DateTime(2026, 10, 14),
      baslangicSinifKodu: ders == 1 ? '9-A' : '9-B',
    ),
  );
  testWidgets(
    'Üretim sırasında ders değişirse eski ders yeni ekran altında görünmez',
    (tester) async {
      const key = ValueKey('plan');
      final kapi = Completer<void>();
      (db as _GecikmeliDb).bekle = kapi.future;
      await tester.pumpWidget(ekran(1, key: key));
      await tester.pump();
      expect((db as _GecikmeliDb).durdu, isTrue);
      await tester.pumpWidget(ekran(2, key: key));
      kapi.complete();
      await tester.pumpAndSettle();
      final alan = find.byKey(const ValueKey('gunluk-plan-konu'));
      await tester.scrollUntilVisible(
        alan,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<TextFormField>(alan).controller!.text, 'Kuvvetler');
      expect(
        (await db.query('BireyselGunlukPlan')).every((p) => p['DersId'] == 2),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Buton kontrolü sırasında seçim değişirse eski plan açılmaz', (
    tester,
  ) async {
    var gecerli = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => bireyselGunlukPlanAc(
                c,
                ogretmenProfilId: 1,
                egitimOgretimYili: '2026/2027',
                dersId: 1,
                dersAdi: 'Matematik',
                sinifSeviyesi: 9,
                tarih: DateTime(2026, 10, 14),
                baslangicSinifKodu: '9-A',
                secimGecerliMi: () => gecerli,
              ),
              child: const Text('Üret'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Üret'));
    gecerli = false;
    await tester.pumpAndSettle();
    expect(find.byType(BireyselGunlukPlanScreen), findsNothing);
  });
  testWidgets('Eksik kaynak hatası sonrası tekrar deneme aynı derste üretir', (
    tester,
  ) async {
    await db.delete('UygulamaAyarlari');
    await tester.pumpWidget(ekran(1));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ders bilgi formu eksik'), findsOneWidget);
    await gunlukPlanTestDbfEkle(db);
    await tester.tap(find.text('Tekrar Dene'));
    await tester.pumpAndSettle();
    final alan = find.byKey(const ValueKey('gunluk-plan-konu'));
    await tester.scrollUntilVisible(
      alan,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<TextFormField>(alan).controller!.text, 'Denklemler');
    expect(await db.query('BireyselGunlukPlan'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
