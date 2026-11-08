import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'support/windows_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('mesajlaşmada veli türü seçimi telefon kopyalamaz', (t) async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    final db = await LocalDatabase.instance.database;
    addTearDown(LocalDatabase.instance.close);
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul',
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
    await db.insert('SinifSube', {
      'SinifKodu': '9-A',
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ders', {'DersAdi': 'Ders', 'OlusturmaTarihi': 'test'});
    await db.insert('DersSaati', {'SiraNo': 1});
    await db.insert('DersProgrami', {
      'SinifSubeId': 1,
      'DersId': 1,
      'DersSaatiId': 1,
      'Gun': 'Pazartesi',
      'OgretmenProfilId': 1,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('Ogrenci', {
      'OkulNo': '1',
      'Ad': 'Öğrenci',
      'Soyad': 'Test',
      'AnneAdi': 'Anne1',
      'AnneTelefon': '05321112233',
      'VeliTuru': 'Diger',
      'VeliAdi': 'Başka veli',
      'VeliTelefonu': '05324445566',
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgrenciSinifKayit', {
      'OgrenciId': 1,
      'SinifSubeId': 1,
      'EgitimOgretimYili': '2026/2027',
      'OlusturmaTarihi': 'test',
    });
    var launches = 0;
    final service = MesajlasmaService(
      databaseGetir: () async => db,
      modGetir: () async => CalismaModu.bireyselOgretmen,
      whatsappAc: (_, _) async {
        launches++;
      },
    );
    await t.pumpWidget(MaterialApp(home: MesajlasmaScreen(service: service)));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('mesaj-ogrenci-arama')),
      'Öğrenci',
    );
    await t.pumpAndSettle();
    final edit = find.byKey(const ValueKey('veli-duzenle-1'));
    await t.scrollUntilVisible(
      edit,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(edit);
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(find.byType(DropdownButton<String>).last);
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(find.text('Anne').last);
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(find.text('Kaydet').last);
    await t.pumpAndSettle();
    final o = (await db.query('Ogrenci')).single;
    expect(o['VeliTuru'], 'Anne');
    expect(o['VeliTelefonu'], '05324445566');
    expect(o['AnneTelefon'], '05321112233');
    expect(
      (await service.ogrenciler(await service.hazirla())).single.telefon,
      '05321112233',
    );
    expect(launches, 0);
    await t.ensureVisible(edit);
    await t.tap(edit);
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(find.byType(DropdownButton<String>).last);
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(find.text('Baba').last);
    await t.pump(const Duration(milliseconds: 350));
    await t.enterText(find.byKey(const ValueKey('veli-adi-Baba')), 'Yeni Baba');
    await t.enterText(
      find.byKey(const ValueKey('veli-telefon-Baba')),
      '05329990000',
    );
    await t.tap(find.text('Kaydet').last);
    await t.pumpAndSettle();
    final baba = (await db.query('Ogrenci')).single;
    expect(baba['VeliTuru'], 'Baba');
    expect(baba['BabaAdi'], 'Yeni Baba');
    expect(baba['BabaTelefon'], '05329990000');
    expect(baba['AnneTelefon'], '05321112233');
    expect(baba['VeliTelefonu'], '05324445566');
    expect(t.takeException(), isNull);
  });
}
