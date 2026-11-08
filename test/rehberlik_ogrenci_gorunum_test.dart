import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elpi_okul_yonetim/screens/bireysel_rehberlik_dosyasi_screen.dart';
import 'package:elpi_okul_yonetim/screens/rehberlik_tanima_form_screen.dart';
import 'package:elpi_okul_yonetim/services/bireysel_rehberlik_service.dart';
import 'package:elpi_okul_yonetim/widgets/ana_sayfa_gorunumu.dart';
import 'package:elpi_okul_yonetim/widgets/modul_ust_bar.dart';

class _Database implements Database, Transaction {
  _Database(this.students);
  final List<Map<String, Object?>> students;
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => action(this);
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #query) {
      final table = i.positionalArguments.first;
      final rows = switch (table) {
        'OkulProfil' => [
          {'OkulId': 'okul', 'OkulAdi': 'Okul', 'EgitimYili': '2026-2027'},
        ],
        'OgretmenProfil' => [
          {
            'OgretmenProfilId': 1,
            'AdSoyad': 'Nurkan',
            'OkulAdi': 'Okul',
            'EgitimOgretimYili': '2026-2027',
          },
        ],
        'OgrenciSinifKayit' => [
          {'Aktif': 1},
        ],
        'Ogrenci' => [
          {'VeliTuru': 'Anne', 'AnneAdi': 'Örnek'},
        ],
        'RehberlikAtama' => [
          {
            'RehberlikAtamaId': 1,
            'SinifSubeId': 1,
            'EgitimOgretimYili': '2026-2027',
            'BaslangicTarihi': '2000-01-01',
          },
        ],
        _ => <Map<String, Object?>>[],
      };
      return Future<List<Map<String, Object?>>>.value(rows);
    }
    if (i.memberName == #rawQuery) {
      final sql = i.positionalArguments.first as String;
      return Future<List<Map<String, Object?>>>.value(
        sql.contains('SELECT o.OgrenciId')
            ? students
            : sql.contains('COUNT(DISTINCT')
            ? [
                {'Ogrenci': students.length, 'EksikVeli': 0},
              ]
            : [],
      );
    }
    return super.noSuchMethod(i);
  }
}

void main() {
  testWidgets(
    'öğrenciler iki görünümde açılır, veli ve import düğmeleri yoktur',
    (t) async {
      const visual = bool.fromEnvironment('REHBERLIK_OGRENCI_GORSEL');
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      if (visual) {
        await t.runAsync(() async {
          await (FontLoader('NotoSans')
                ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
                ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      var students = <Map<String, Object?>>[
        for (var i = 0; i < 8; i++)
          {
            'OgrenciId': i + 1,
            'OkulNo': '${3001 + i}',
            'Ad': 'ÖĞRENCİ ${i + 1}',
            'Soyad': 'ÖRNEK',
            'OgrenciAktif': 1,
            'KayitAktif': 1,
            'VeliAdi': 'Gizli veli bilgisi',
          },
      ];
      if (visual) {
        students =
            (jsonDecode(
                      File(
                        'C:/OkulYonetim/work/rehberlik-ogrenci-ui/gorunum-verisi.json',
                      ).readAsStringSync(),
                    )
                    as List)
                .map(
                  (r) => <String, Object?>{
                    ...Map<String, Object?>.from(r as Map),
                    'FotoVerisi': r['photo'] == null
                        ? null
                        : Uint8List.fromList(
                            base64Decode(r['photo'] as String),
                          ),
                  },
                )
                .toList();
      }
      final db = _Database(students);
      final service = BireyselRehberlikService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      const b = BireyselRehberlikBaglami(
        okulId: 'okul',
        ogretmenProfilId: 1,
        okulAdi: 'Okul',
        ogretmenAdi: 'Nurkan',
        egitimOgretimYili: '2026-2027',
      );
      ModulUstBarBaglantisi.aktif = ModulUstBarBaglantisi(
        sahip: service,
        ayarlar: () async {},
        profil: () async {},
        bildirimler: () async {},
      );
      addTearDown(() => ModulUstBarBaglantisi.aktif = null);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AnaSayfaTemasi.mavi.olustur(Brightness.light),
            home: BireyselRehberlikDosyasiScreen(
              service: service,
              baglam: b,
              atama: const {
                'RehberlikAtamaId': 1,
                'SinifKodu': '9-C',
                'SinifSubeId': 1,
                'EgitimOgretimYili': '2026-2027',
                'BaslangicTarihi': '2000-01-01',
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final title in [
        'Sınıf Genel Durumu',
        'Görüşler',
        'Rehberlik Planım',
        'Görev ve Belgeler',
      ]) {
        expect(find.text(title), findsNothing);
      }
      expect(find.text('Toplantılar'), findsOneWidget);
      await t.tap(find.text('Öğrencilerim'));
      await t.pumpAndSettle();
      expect(find.text('Toplu form resmi import'), findsNothing);
      expect(find.text('Fotoğraflı sınıf listesi'), findsNothing);
      expect(find.textContaining('Veli:'), findsNothing);
      final bar = find.byKey(const ValueKey('rehberlik-ogrenci-alt-cubuk'));
      final rect = t.getRect(bar);
      expect(
        t.getRect(find.byType(ListView).first).bottom,
        lessThanOrEqualTo(rect.top),
      );
      Future<void> capture(String name) async {
        if (!visual) return;
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'C:/OkulYonetim/work/rehberlik-ogrenci-ui/$name.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('duz-liste');
      await t.tap(find.byTooltip('Liste görünümü'));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckedPopupMenuItem<bool>).last);
      await t.pumpAndSettle();
      expect(find.textContaining('Fotoğraflı görünüm'), findsOneWidget);
      expect(t.getRect(bar), rect);
      if (visual) {
        await t.runAsync(() async {
          final context = t.element(find.byType(ListView).first);
          for (final image in t.widgetList<Image>(find.byType(Image))) {
            await precacheImage(image.image, context);
          }
        });
        await t.pumpAndSettle();
      }
      await capture('fotografli-liste');
      await t.tap(find.text('Ara'));
      await t.pumpAndSettle();
      expect(
        t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isFalse,
      );
      await t.enterText(find.byType(TextField), '${students.first['OkulNo']}');
      await t.pumpAndSettle();
      expect(find.textContaining('1 öğrenci'), findsOneWidget);
      await t.tap(
        find.byKey(
          ValueKey('rehberlik-ogrenci-${students.first['OgrenciId']}'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(RehberlikTanimaFormScreen), findsOneWidget);
      expect(find.text('Hassas formu görüntüle'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('Adınız Soyadınız')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
