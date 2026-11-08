import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/database/mesajlasma_semasi.dart';
import 'package:elpi_okul_yonetim/database/mesaj_alici_semasi.dart';
import 'package:elpi_okul_yonetim/database/rehberlik_semasi.dart';
import 'package:elpi_okul_yonetim/database/bilgi_toplama_semasi.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_bakim_service.dart';
import 'package:elpi_okul_yonetim/services/ogrenci_import_tanimi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_import_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Telefon biçimleri aynı alıcıya dönüşür; hatalı/çoklu numara reddedilir',
    () {
      for (final raw in [
        '0532 123 45 67',
        '5321234567',
        '+90 (532) 123-45-67',
        '00905321234567',
        '905321234567',
      ]) {
        expect(mesajTelefonNormalize(raw), '905321234567');
      }
      expect(mesajTelefonNormalize('+44 7700 900123'), '447700900123');
      for (final raw in [
        '',
        'abc05321234567',
        '05321234567/05321234568',
        '123',
        '+0905321234567',
        '000',
        '053212345670',
        '900000000000',
        '05321234567 05321234568',
      ]) {
        expect(mesajTelefonNormalize(raw), isNull, reason: raw);
      }
    },
  );

  group('Bireysel mesajlaşma — gerçek bellek SQLite', () {
    late Database db;
    late MesajlasmaService service;
    late MesajBaglami context;
    late Directory temp;
    CalismaModu? mod = CalismaModu.bireyselOgretmen;
    var launches = 0;
    var fail = false;
    Completer<void>? launchWait;
    setUp(() async {
      await LocalDatabase.instance.close();
      databaseFactory = WindowsMemoryFactory();
      db = await LocalDatabase.instance.database;
      temp = await Directory.systemTemp.createTemp('mesajlasma_test_');
      mod = CalismaModu.bireyselOgretmen;
      launches = 0;
      fail = false;
      launchWait = null;
      SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
      service = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => mod,
        whatsappAc: (tel, text) async {
          launches++;
          expect(tel, startsWith('90'));
          expect(text, contains('Mesaj'));
          if (fail) throw StateError('WhatsApp kurulu değil');
          await launchWait?.future;
        },
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
        'AdSoyad': 'Öğretmen',
        'OkulAdi': 'Okul',
        'EgitimOgretimYili': '2026/2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('Ders', {
        'DersAdi': 'Matematik',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersSaati', {'SiraNo': 1});
      for (var i = 1; i <= 3; i++) {
        await db.insert('SinifSube', {
          'SinifKodu': '$i-A',
          'EgitimOgretimYili': '2026/2027',
          'OlusturmaTarihi': 'test',
        });
        if (i < 3) {
          await db.insert('DersProgrami', {
            'SinifSubeId': i,
            'DersId': 1,
            'DersSaatiId': 1,
            'Gun': i == 1 ? 'Pazartesi' : 'Salı',
            'OgretmenProfilId': 1,
            'EgitimOgretimYili': '2026/2027',
            'OlusturmaTarihi': 'test',
          });
        }
      }
      for (var i = 1; i <= 5; i++) {
        await db.insert('Ogrenci', {
          'OkulNo': '$i',
          'Ad': 'Öğrenci$i',
          'Soyad': 'Test',
          'VeliAdi': 'Veli$i',
          'VeliTelefonu': i == 1
              ? '05321234567'
              : i == 2
              ? '+90 532 123 45 67'
              : i == 3
              ? '05321234568'
              : null,
          'OlusturmaTarihi': 'test',
        });
        await db.insert('OgrenciSinifKayit', {
          'OgrenciId': i,
          'SinifSubeId': i == 5
              ? 3
              : i == 2
              ? 2
              : 1,
          'EgitimOgretimYili': '2026/2027',
          'OlusturmaTarihi': 'test',
        });
      }
      context = await service.hazirla();
    });
    tearDown(() async {
      launchWait?.complete();
      await LocalDatabase.instance.close();
      await temp.delete(recursive: true);
    });
    Future<MesajKuyrugu> create() async => service.kuyrukOlustur(
      context,
      MesajOnIzleme(await service.ogrenciler(context)),
      'Mesaj: toplantı & bilgi\nİyi günler 👋',
      kaynakModul: 'Belgelerim',
      kaynakKayit: 'belge-1',
    );

    test(
      'Kapsam, mükerrer ve eksik numaralar; kuyruk kaydı gönderim yapmaz',
      () async {
        final students = await service.ogrenciler(context);
        expect(students.map((o) => o.id).toSet(), {1, 2, 3, 4});
        final preview = MesajOnIzleme(students);
        expect(preview.alicilar.length, 2);
        expect(preview.birlestirilen, 1);
        expect(preview.gecersizler.single.id, 4);
        final q = await create();
        expect(q.alicilar.length, 2);
        expect(launches, 0);
        expect(jsonDecode(q.alicilar.first.ogrenciler), hasLength(2));
        expect(q.onaylanan, 0);
      },
    );
    test(
      'Açılmadan onay yok; açılma gönderim değildir; yeni servis kaldığı yerden sürer',
      () async {
        var q = await create();
        await expectLater(
          service.aliciyiSonuclandir(
            context,
            q.id,
            q.siradaki!.id,
            gonderdim: true,
          ),
          throwsStateError,
        );
        await service.aliciyiAc(context, q.id, q.siradaki!.id);
        q = await service.kuyrukGetir(context, q.id);
        expect(q.siradaki!.durum, 'Acildi');
        expect(q.onaylanan, 0);
        final resumed = MesajlasmaService(
          databaseGetir: () async => db,
          modGetir: () async => mod,
        );
        final restored = await resumed.kuyrukGetir(context, q.id);
        expect(restored.siradaki!.id, q.siradaki!.id);
        await resumed.aliciyiSonuclandir(
          context,
          q.id,
          q.siradaki!.id,
          gonderdim: true,
        );
        await expectLater(
          resumed.aliciyiSonuclandir(
            context,
            q.id,
            q.siradaki!.id,
            gonderdim: true,
          ),
          throwsStateError,
        );
        q = await service.kuyrukGetir(context, q.id);
        expect(q.onaylanan, 1);
        expect(q.alicilar.first.onayTarihi, isNotNull);
        await service.aliciyiSonuclandir(
          context,
          q.id,
          q.siradaki!.id,
          gonderdim: false,
        );
        q = await service.kuyrukGetir(context, q.id);
        expect(q.siradaki, isNull);
        expect(q.atlanan, 1);
        expect(launches, 1);
      },
    );
    test(
      'anne telefon değişimi anlık okunur; eski kuyruk yeni telefona gönderilmez',
      () async {
        await db.update('Ogrenci', {
          'AnneAdi': 'Annesi',
          'AnneTelefon': '05321112233',
          'VeliTuru': 'Anne',
        }, where: 'OgrenciId=1');
        final students = await service.ogrenciler(context);
        final o = students.firstWhere((o) => o.id == 1);
        expect(o.telefon, '05321112233');
        final q = await service.kuyrukOlustur(
          context,
          MesajOnIzleme([o]),
          'Mesaj',
          kaynakModul: 'Test',
        );
        await db.update('Ogrenci', {
          'AnneTelefon': '05329998877',
        }, where: 'OgrenciId=1');
        expect(
          (await service.ogrenciler(
            context,
          )).firstWhere((o) => o.id == 1).telefon,
          '05329998877',
        );
        await expectLater(
          service.aliciyiAc(context, q.id, q.siradaki!.id),
          throwsStateError,
        );
        expect(launches, 0);
        expect(
          (await service.kuyrukGetir(context, q.id)).siradaki!.telefon,
          '905321112233',
        );
      },
    );
    test('Eşzamanlı çift açma yalnız bir kez başlatılır', () async {
      final q = await create();
      launchWait = Completer<void>();
      final first = service.aliciyiAc(context, q.id, q.siradaki!.id);
      final second = service.aliciyiAc(context, q.id, q.siradaki!.id);
      final rejected = expectLater(second, throwsStateError);
      while (launches == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      launchWait!.complete();
      launchWait = null;
      await first;
      await rejected;
      expect(launches, 1);
    });
    test('Açılamayan WhatsApp alıcıyı korur; tekrar denenebilir', () async {
      var q = await create();
      fail = true;
      await expectLater(
        service.aliciyiAc(context, q.id, q.siradaki!.id),
        throwsStateError,
      );
      q = await service.kuyrukGetir(context, q.id);
      expect(q.siradaki!.durum, 'Acilamadi');
      expect(q.onaylanan, 0);
      fail = false;
      await service.aliciyiAc(context, q.id, q.siradaki!.id);
      expect(
        (await service.kuyrukGetir(context, q.id)).siradaki!.durum,
        'Acildi',
      );
    });
    test(
      'Ön izlemeden sonra iletişim değişmesi yeni onay ister; boş import silmez',
      () async {
        final preview = MesajOnIzleme(await service.ogrenciler(context));
        await service.iletisimKaydet(context, 1, 'Yeni Veli', '05321234569');
        await expectLater(
          service.kuyrukOlustur(
            context,
            preview,
            'Mesaj',
            kaynakModul: 'Import',
          ),
          throwsStateError,
        );
        final row = ImportKaynakSatiri('1', 'Satır', {
          'okulNo': '1',
          'ad': 'Öğrenci1',
          'soyad': 'Test',
          'sinif': '1-A',
        });
        final p = await OgrenciImportTanimi.tanim.hazirla([row]);
        await OgrenciImportTanimi.tanim.aktar(p, {'1'});
        final o = (await db.query('Ogrenci', where: 'OgrenciId = 1')).single;
        expect(o['VeliAdi'], 'Yeni Veli');
        expect(o['VeliTelefonu'], '05321234569');
      },
    );
    test(
      'İsteğe bağlı import veli kolonları alınır; hatalı telefon aktarılmaz',
      () async {
        final p = await OgrenciImportTanimi.tanim.hazirla([
          ImportKaynakSatiri('1', 'Satır', {
            'okulNo': '1',
            'ad': 'Öğrenci1',
            'soyad': 'Test',
            'sinif': '1-A',
            'veliAdi': 'Anne',
            'veliTelefonu': '+90 532 111 22 33',
          }),
          ImportKaynakSatiri('2', 'Satır', {
            'okulNo': '2',
            'ad': 'Öğrenci2',
            'soyad': 'Test',
            'sinif': '2-A',
            'veliTelefonu': 'abc',
          }),
        ]);
        expect(p.kayitlar.last.durum, ImportDurumu.hatali);
        await OgrenciImportTanimi.tanim.aktar(p, {'1'});
        final o = (await db.query('Ogrenci', where: 'OgrenciId = 1')).single;
        expect(o['VeliAdi'], 'Anne');
        expect(o['VeliTelefonu'], '905321112233');
        final again = await OgrenciImportTanimi.tanim.hazirla([
          ImportKaynakSatiri('1', 'Satır', {
            'okulNo': '1',
            'ad': 'Öğrenci1',
            'soyad': 'Test',
            'sinif': '1-A',
            'veliAdi': 'Baba',
            'veliTelefonu': '05321112244',
          }),
        ]);
        await OgrenciImportTanimi.tanim.aktar(again, {'1'});
        expect(
          (await db.query('Ogrenci', where: 'OgrenciId = 1')).single['VeliAdi'],
          'Baba',
        );
      },
    );
    test('Özel XLS/XLSX okuyucusu da veli kolonlarını korur', () async {
      final excel = Excel.createExcel();
      excel['Liste'].appendRow(['1. Sınıf A Şubesi']);
      excel['Liste'].appendRow([
        'Okul No',
        'Adı',
        'Soyadı',
        'Veli Adı',
        'Veli Telefonu',
      ]);
      excel['Liste'].appendRow([1, 'Öğrenci1', 'Test', 'Anne', '05321112233']);
      final preview = await BireyselImportService.ogrenciOnIzlemeHazirla(
        dosyaAdi: 'liste.xlsx',
        dosyaBytes: Uint8List.fromList(excel.encode()!),
      );
      await BireyselImportService.ogrencileriKaydet(preview);
      final o = (await db.query('Ogrenci', where: 'OgrenciId = 1')).single;
      expect(o['VeliAdi'], 'Anne');
      expect(o['VeliTelefonu'], '05321112233');
    });
    test(
      'Kurumsal mod, değişen yıl/öğretmen/okul ve kapsam dışı öğrenci engellenir',
      () async {
        final q = await create();
        await expectLater(
          service.iletisimKaydet(context, 5, 'Veli', '05321112233'),
          throwsStateError,
        );
        mod = null;
        await expectLater(service.kuyrukGetir(context, q.id), throwsStateError);
        await expectLater(
          service.aliciyiAc(context, q.id, q.siradaki!.id),
          throwsStateError,
        );
        mod = CalismaModu.bireyselOgretmen;
        await db.update('OgretmenProfil', {'AdSoyad': 'Başka Öğretmen'});
        await expectLater(service.kuyrukGetir(context, q.id), throwsStateError);
        await db.update('OgretmenProfil', {
          'AdSoyad': 'Öğretmen',
          'EgitimOgretimYili': '2027/2028',
        });
        await expectLater(service.kuyrukGetir(context, q.id), throwsStateError);
        await db.update('OgretmenProfil', {'EgitimOgretimYili': '2026/2027'});
        await db.update('OkulProfil', {'OkulId': 'okul-2'});
        await expectLater(service.kuyrukGetir(context, q.id), throwsStateError);
        expect(launches, 0);
      },
    );
    test(
      'Kuyruk sonrası telefon/sınıf değişirse eski alıcı otomatik açılmaz',
      () async {
        final q = await create();
        await service.iletisimKaydet(context, 1, 'Veli1', '05321234569');
        await expectLater(
          service.aliciyiAc(context, q.id, q.siradaki!.id),
          throwsStateError,
        );
        await service.iletisimKaydet(context, 1, 'Veli1', '05321234567');
        await db.update('DersProgrami', {'Aktif': 0});
        await expectLater(
          service.aliciyiAc(context, q.id, q.siradaki!.id),
          throwsStateError,
        );
        expect(launches, 0);
      },
    );
    test(
      'Yedek kuyruk/onayları korur; v12 yedeği kontrollü tamamlanır',
      () async {
        var q = await create();
        await service.aliciyiAc(context, q.id, q.siradaki!.id);
        await service.aliciyiSonuclandir(
          context,
          q.id,
          q.siradaki!.id,
          gonderdim: true,
        );
        final backup = BireyselBakimService(
          databaseGetir: () async => db,
          alanGetir: () async => temp,
          modGetir: () async => mod,
        );
        final saved = await backup.yedekle();
        final checked = await backup.incele(saved.dosya);
        expect(checked.sayilar['MesajAlici'], 2);
        await backup.geriYukle(checked, onayMetni: 'GERİ YÜKLE');
        q = await service.kuyrukGetir(context, q.id);
        expect(q.onaylanan, 1);
        expect(q.siradaki!.durum, 'Bekliyor');
        final a = ZipDecoder().decodeBytes(await saved.dosya.readAsBytes());
        final meta =
            jsonDecode(
                  utf8.decode(a.findFile('yedek.json')!.content as List<int>),
                )
                as Map;
        meta['sema'] = 12;
        final tables = meta['tablolar'] as Map, cols = meta['kolonlar'] as Map;
        (cols['Ogrenci'] as List).remove('VeliTuru');
        for (final r in tables['Ogrenci'] as List) {
          (r as Map).remove('VeliTuru');
        }
        for (final t in [
          ...MesajAliciSemasi.tablolar,
          'MesajOgretmenSinifDers',
          'OgrenciIletisim',
          ...BilgiToplamaSemasi.tablolar,
          ...RehberlikSemasi.googleTablolari,
          'MesajSms',
          'MesajTekliGecmis',
          'OdevDegerlendirmeOlcutu',
          'OdevDegerlendirmePuani',
        ]) {
          tables.remove(t);
          cols.remove(t);
        }
        for (final f in BilgiToplamaSemasi.ogrenciAlanlari) {
          (cols['Ogrenci'] as List).remove(f);
          for (final r in tables['Ogrenci'] as List) {
            (r as Map).remove(f);
          }
        }
        // v12 yedeğinde sonraki sürümlerin modül tabloları bulunmaz.
        tables.remove('BireyselIslenenDers');
        cols.remove('BireyselIslenenDers');
        tables.remove('BireyselGunlukPlan');
        cols.remove('BireyselGunlukPlan');
        tables.remove('RehberlikAtama');
        cols.remove('RehberlikAtama');
        for (final t in RehberlikSemasi.modulTablolari) {
          tables.remove(t);
          cols.remove(t);
        }
        for (final t in MesajlasmaSemasi.tablolar) {
          tables.remove(t);
          cols.remove(t);
        }
        for (final f in MesajlasmaSemasi.iletisimAlanlari) {
          (cols['Ogrenci'] as List).remove(f);
          for (final r in tables['Ogrenci'] as List) {
            (r as Map).remove(f);
          }
        }
        final bytes = utf8.encode(jsonEncode(meta));
        final old = Archive()
          ..addFile(ArchiveFile('yedek.json', bytes.length, bytes));
        final legacy = await File(
          '${temp.path}/v12.zip',
        ).writeAsBytes(ZipEncoder().encode(old)!);
        final oldChecked = await backup.incele(legacy);
        expect(oldChecked.sayilar['MesajKuyrugu'], 0);
        await backup.geriYukle(oldChecked, onayMetni: 'GERİ YÜKLE');
        expect(await db.query('Ogrenci'), hasLength(5));
        expect((await db.query('Ogrenci')).first['VeliTelefonu'], isNull);
        expect(await db.query('MesajKuyrugu'), isEmpty);
      },
    );
    test(
      'Sıfırlama geçmişi korur; eski kuyruk yeni okula devredilmez',
      () async {
        final q = await create();
        await LocalDatabase.instance.bireyselVerileriSifirla(
          onayMetni: 'SIFIRLA',
        );
        expect(await db.query('MesajKuyrugu'), hasLength(1));
        expect(await db.query('MesajAlici'), hasLength(2));
        await expectLater(service.kuyrukGetir(context, q.id), throwsStateError);
      },
    );

    Future<void> tap(WidgetTester tester, String label) async {
      final finder = find.text(label);
      await tester.ensureVisible(finder.last);
      await tester.tap(finder.last);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      // Onay diyaloğu açıkken işlem kilidi ve ilerleme göstergesi sürer.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byType(AlertDialog).evaluate().isEmpty) {
        await tester.pumpAndSettle();
      }
    }

    testWidgets('Dar ekranda seçim, onay, WhatsApp, beyan ve devam', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MesajlasmaScreen(
            service: service,
            baslangicMetni: 'Mesaj deneme',
            baslangicOgrenciIdleri: const {1, 2, 3, 4},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, 'Ön İzle ve Onayla');
      expect(
        find.textContaining('1 eksik/geçersiz telefon gönderim dışında'),
        findsOneWidget,
      );
      await tap(tester, 'WhatsApp ile gönder');
      expect(launches, 1);
      expect(find.text('Gönderdim, sıradakine geç'), findsOneWidget);
      expect(find.text('SIM Üzerinden Otomatik SMS Gönder'), findsNothing);
      await tap(tester, 'Daha sonra devam et');
      await tap(tester, 'Gönderim Geçmişi');
      await tester.tap(find.byTooltip('Geçmiş işlemleri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tap(tester, 'Devam et: Mesaj deneme');
      expect(launches, 1);
      await tap(tester, 'Gönderdim, sıradakine geç');
      expect(launches, 2);
      expect((await service.kuyruklar(context)).single.onaylanan, 1);
      await tap(tester, 'Atla');
      expect(find.byKey(const ValueKey('whatsapp-devam')), findsNothing);
      expect((await service.kuyruklar(context)).single.atlanan, 1);
      expect(tester.takeException(), isNull);
    });
    testWidgets('Talep kapsamı seçim, yenileme ve kuyruk onayında korunur', (
      tester,
    ) async {
      final izinli = <int>{1};
      await tester.pumpWidget(
        MaterialApp(
          home: MesajlasmaScreen(
            service: service,
            kaynakModul: 'SinifRehberligim',
            kaynakKayit: 'talep',
            baslangicMetni: 'Öğrenci1 görüşü',
            baslangicOgrenciIdleri: const {1, 2, 3},
            izinliOgrenciIdleri: izinli,
          ),
        ),
      );
      await tester.pumpAndSettle();
      izinli.add(3); // Çağıranın sonradan değiştirmesi kapsamı genişletmemeli.
      expect(find.text('Gönderim Geçmişi'), findsNothing);
      expect(
        tester
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .items,
        hasLength(2),
      );
      await tap(tester, 'Görünenleri Seç');
      await tester.tap(find.byTooltip('Yenile'));
      await tester.pumpAndSettle();
      await tap(tester, 'Ön İzle ve Onayla');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('1 tekil telefon'),
        ),
        findsOneWidget,
      );
      await tap(tester, 'SMS ile gönder');
      await tap(tester, 'Vazgeç');
      expect(await db.query('MesajAlici'), isEmpty);
      expect(await db.query('MesajTekliGecmis'), isEmpty);
      expect(launches, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Boş talep kapsamı genel mesajlaşmaya dönüşmez', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MesajlasmaScreen(
            service: service,
            baslangicMetni: 'Görüş',
            baslangicOgrenciIdleri: const {1},
            izinliOgrenciIdleri: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Ön İzle ve Onayla'),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.byTooltip('Yenile'));
      await tester.pumpAndSettle();
      expect(await db.query('MesajKuyrugu'), isEmpty);
      expect(find.text('Gönderim Geçmişi'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Klavye açık dar ekranda mesaj alanı taşmaz', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(() {
        tester.view.resetViewInsets();
        tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(home: MesajlasmaScreen(service: service)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isWindows);
  test('v12 iletişim migration eski öğrenci verisini korur', () async {
    final db = WindowsMemoryDatabase();
    try {
      await db.execute(
        'CREATE TABLE Ogrenci (OgrenciId INTEGER PRIMARY KEY, Ad TEXT)',
      );
      await db.insert('Ogrenci', {'OgrenciId': 1, 'Ad': 'Ayşe'});
      await db.transaction(MesajlasmaSemasi.hazirla);
      expect((await db.query('Ogrenci')).single, {
        'OgrenciId': 1,
        'Ad': 'Ayşe',
        'VeliAdi': null,
        'VeliTelefonu': null,
      });
      expect(await db.query('MesajKuyrugu'), isEmpty);
    } finally {
      await db.close();
    }
  }, skip: !Platform.isWindows);
}
