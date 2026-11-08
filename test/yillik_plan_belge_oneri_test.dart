import 'package:elpi_okul_yonetim/models/import_ilerleme.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/drive_belge_service.dart';
import 'package:elpi_okul_yonetim/services/yillik_plan_belge_oneri_service.dart';
import 'package:elpi_okul_yonetim/screens/yillik_plan_belge_oneri_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'support/windows_memory_database.dart';

class SahteDrive extends DriveBelgeService {
  String? hesap;
  ImportDosya? icerik;
  int indirme = 0;
  @override
  Future<List<Map<String, dynamic>>> adaylariListele(String token) async => [
    for (var i = 0; i < 20; i++)
      {
        'id': '$i',
        'name': 'Matematik plan $i',
        'version': '1',
        'size': '100',
        'capabilities': {'canDownload': true},
      },
  ];
  @override
  Future<ImportDosya> indir({
    required String token,
    required String dosyaId,
    required Set<String> uzantilar,
    String? beklenenSurum,
    int boyutSiniri = DriveBelgeService.azamiBoyut,
    void Function(ImportIlerleme)? ilerleme,
  }) async {
    indirme++;
    expect(beklenenSurum, '1');
    expect(boyutSiniri, 5 * 1024 * 1024);
    return icerik!;
  }

  @override
  Future<ImportDosya?> sec(
    Set<String> uzantilar, {
    Future<void> Function(String)? hesapSecildi,
    void Function(ImportIlerleme)? ilerleme,
  }) async {
    await hesapSecildi?.call('secilen@example.com');
    return ImportDosya('plan.xlsx', Uint8List.fromList([1]));
  }

  @override
  Future<String?> erisim(String deger) async {
    hesap = deger;
    return icerik == null ? null : 'test-token';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late SahteDrive drive;
  late YillikPlanBelgeOneriService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    db = await LocalDatabase.instance.database;
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul-1',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'Okul',
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
    drive = SahteDrive();
    service = YillikPlanBelgeOneriService(drive: drive);
  });
  tearDown(() async {
    service.dispose();
    await LocalDatabase.instance.close();
  });
  Future<List<YillikPlanBelgeAdayi>> ara() => service.ara(
    profilId: 1,
    ders: 'Matematik',
    seviye: 11,
    yil: '2026-2027',
    okul: 'Okul',
  );
  test(
    'Bağlantısız profilde hesap aranmaz; yalnız seçilen eposta saklanır',
    () async {
      expect(await ara(), isEmpty);
      expect(drive.hesap, isNull);
      await service.sec(1, {'xlsx'});
      await ara();
      expect(drive.hesap, 'secilen@example.com');
      final ayarlar = await db.query(
        'UygulamaAyarlari',
        where: "Anahtar LIKE 'drive.hesap.%'",
      );
      expect(ayarlar.single['Deger'], 'secilen@example.com');
    },
  );
  test('Başka okul bağlantıyı devralmaz; yanlış profil reddedilir', () async {
    await service.sec(1, {'xlsx'});
    await db.update('OkulProfil', {'OkulId': 'okul-2'}, where: 'Id = 1');
    expect(await ara(), isEmpty);
    expect(drive.hesap, isNull);
    await expectLater(service.sec(2, {'xlsx'}), throwsStateError);
  });
  test('İçerik doğrulanır ve yirmi adaydan yalnız üçü indirilir', () async {
    final xml = utf8.encode(
      '<w:document xmlns:w="urn:test"><w:body><w:p>'
      '<w:r><w:t>Matematik yıllık plan 11. sınıf 2026-2027 Okul Hafta Konu</w:t></w:r>'
      '</w:p></w:body></w:document>',
    );
    final zip = Archive()
      ..addFile(ArchiveFile('word/document.xml', xml.length, xml));
    drive.icerik = ImportDosya(
      'plan.docx',
      Uint8List.fromList(ZipEncoder().encode(zip)!),
    );
    await service.sec(1, {'docx'});
    final sonuc = await ara();
    expect(drive.indirme, 3);
    expect(sonuc, hasLength(3));
    expect(sonuc.first.uyarilar, isEmpty);
  });
  testWidgets('Öneriyi kullanma, manuel seçim ve iptal ayrı sonuç verir', (
    tester,
  ) async {
    int? sonuc;
    final adaylar = [
      YillikPlanBelgeAdayi(ImportDosya('plan.xlsx', Uint8List(1)), [
        'Yıl doğrulanamadı',
      ]),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              sonuc = await yillikPlanBelgeOnerisiniGoster(ctx, adaylar);
            },
            child: const Text('Aç'),
          ),
        ),
      ),
    );
    for (final (etiket, deger) in [
      ('Kullan ve ön izle', 0),
      ('Başka Belge Seç', -1),
      ('İptal', null),
    ]) {
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      expect(find.text('Yıl doğrulanamadı'), findsOneWidget);
      await tester.tap(find.text(etiket));
      await tester.pumpAndSettle();
      expect(sonuc, deger);
    }
  });
}
