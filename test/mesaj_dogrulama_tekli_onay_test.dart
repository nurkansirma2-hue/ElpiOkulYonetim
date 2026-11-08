import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/database/local_database.dart';
import 'support/windows_memory_database.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';

class _Service extends MesajlasmaService {
  int acildi = 0, onaylandi = 0;
  String durum = 'Bekliyor';
  bool varMi = false, hata = false;
  @override
  Future<void> gecmisiOnayla(
    MesajBaglami b, {
    required Map<String, Set<int>> kuyrukAlicilari,
    required Set<String> tekliKayitlar,
  }) async {
    await aliciyiSonuclandir(b, 'q', 1, gonderdim: true);
  }

  @override
  Future<List<Map<String, Object?>>> tekliGecmis(MesajBaglami b) async => [];
  @override
  Future<void> tekliGonder(
    MesajBaglami b,
    String metin, {
    MesajOnIzleme? ogrenciler,
    MesajKisiOnIzleme? kisiler,
    required bool sms,
    required String kaynakModul,
    String? kaynakKayit,
    Map<int, String>? ogrenciMesajlari,
    Set<int>? izinliOgrenciIdleri,
  }) async {
    if (hata) throw StateError('WhatsApp açılamadı');
    acildi++;
  }

  @override
  Future<MesajBaglami> hazirla() async =>
      const MesajBaglami('okul', 1, 'Öğretmen', 'Okul', '2026-2027');
  @override
  Future<List<MesajOgrencisi>> ogrenciler(MesajBaglami b) async => [
    const MesajOgrencisi(1, '001', 'Öğrenci', 1, '9-C', 'Veli', '05321112233'),
  ];
  MesajKuyrugu get q => MesajKuyrugu(
    {
      'KuyrukId': 'q',
      'Metin': 'Mesaj deneme',
      'KaynakModul': 'Test',
      'OlusturmaTarihi': '2026-10-25',
    },
    [
      MesajAlicisi({
        'AliciId': 1,
        'Sira': 1,
        'Telefon': '905321112233',
        'AliciAdi': 'Veli',
        'Durum': durum,
        'Ogrenciler': jsonEncode([
          {'id': 1, 'sinifId': 1, 'aciklama': '9-C • Öğrenci'},
        ]),
      }),
    ],
  );
  @override
  Future<List<MesajKuyrugu>> kuyruklar(MesajBaglami b) async =>
      varMi ? [q] : [];
  @override
  Future<MesajKuyrugu> kuyrukGetir(MesajBaglami b, String id) async => q;
  @override
  Future<MesajKuyrugu> kuyrukOlustur(
    MesajBaglami b,
    MesajOnIzleme preview,
    String metin, {
    required String kaynakModul,
    String? kaynakKayit,
    Map<int, String>? ogrenciMesajlari,
  }) async {
    varMi = true;
    return q;
  }

  @override
  Future<void> aliciyiAc(
    MesajBaglami b,
    String id,
    int alici, {
    bool tekrar = false,
  }) async {
    if (hata) {
      durum = 'Acilamadi';
      throw StateError('WhatsApp açılamadı');
    }
    acildi++;
    durum = 'Acildi';
  }

  @override
  Future<void> aliciyiSonuclandir(
    MesajBaglami b,
    String id,
    int alici, {
    required bool gonderdim,
  }) async {
    if (durum != 'Acildi' || !gonderdim) {
      throw StateError('Geçersiz gönderim onayı.');
    }
    onaylandi++;
    durum = 'Onaylandi';
  }
}

void main() {
  setUp(() async {
    await LocalDatabase.instance.close();
    databaseFactory = WindowsMemoryFactory();
    SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
    final db = await LocalDatabase.instance.database;
    await db.insert('OkulProfil', {
      'Id': 1,
      'OkulId': 'okul',
      'OkulAdi': 'Okul',
      'OkulKisaAdi': 'O',
      'EgitimYili': '2026-2027',
      'Donem': 1,
      'OlusturmaTarihi': 'test',
    });
    await db.insert('OgretmenProfil', {
      'AdSoyad': 'Öğretmen',
      'OkulAdi': 'Okul',
      'EgitimOgretimYili': '2026-2027',
      'OlusturmaTarihi': 'test',
    });
  });
  tearDown(LocalDatabase.instance.close);
  Future<void> tikla(WidgetTester t, Finder f) async {
    await t.ensureVisible(f.last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(f.last);
    await t.pump(const Duration(milliseconds: 350));
    if (find.byType(AlertDialog).evaluate().isEmpty) await t.pumpAndSettle();
  }

  Future<void> ac(
    WidgetTester t,
    MesajlasmaService s, {
    bool yeni = false,
    String text = 'Mesaj deneme',
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: MesajlasmaScreen(
          service: s,
          kaynakModul: yeni ? 'Mesajlasma' : 'Test',
          baslangicOgrenciIdleri: yeni ? const {} : const {1},
          baslangicMetni: text,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> gonder(WidgetTester t) async {
    await tikla(t, find.text('Ön İzle ve Onayla'));
    await tikla(t, find.text('WhatsApp ile gönder'));
  }

  testWidgets('tekli gönderim kuyruk ve dönüş onayı oluşturmaz', (t) async {
    final s = _Service();
    await ac(t, s);
    await gonder(t);
    expect(s.acildi, 1);
    expect(s.varMi, false);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('Mesajı gönderdiniz mi?'), findsNothing);
    expect(s.onaylandi, 0);
    expect(find.byKey(const ValueKey('whatsapp-devam')), findsNothing);
  });
  testWidgets('tekli açılış hatasında taslak korunur ve kuyruk oluşmaz', (
    t,
  ) async {
    final s = _Service()..hata = true;
    await ac(t, s);
    await gonder(t);
    expect(s.varMi, false);
    expect(s.onaylandi, 0);
    expect(find.textContaining('WhatsApp açılamadı'), findsOneWidget);
    await tikla(t, find.text('Ön İzle ve Onayla'));
    expect(find.text('Mesajı gönder'), findsOneWidget);
    await tikla(t, find.text('Düzelt'));
  });
  testWidgets('önceki tekli bekleyen kayıt yeniden açılmadan onaylanır', (
    t,
  ) async {
    final s = _Service()
      ..varMi = true
      ..durum = 'Acildi';
    await ac(t, s);
    await tikla(t, find.text('Gönderim Geçmişi'));
    await tikla(t, find.byType(ListTile).first);
    expect(find.byType(AlertDialog), findsNothing);
    expect(s.acildi, 0);
    await tikla(t, find.byKey(const ValueKey('gecmisi-onayla')));
    expect(s.onaylandi, 1);
    expect(s.acildi, 0);
  });
  testWidgets(
    'boş mesaj dar ekranda alana kayar, odaklanır; taslak ve seçim korunur',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await LocalDatabase.instance.close();
      databaseFactory = WindowsMemoryFactory();
      SharedPreferences.setMockInitialValues({'calisma_modu': 'bireysel'});
      final db = await LocalDatabase.instance.database;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        await LocalDatabase.instance.close();
      });
      await db.insert('OkulProfil', {
        'Id': 1,
        'OkulId': 'okul',
        'OkulAdi': 'Okul',
        'OkulKisaAdi': 'O',
        'EgitimYili': '2026-2027',
        'Donem': 1,
        'OlusturmaTarihi': 'test',
      });
      await db.insert('OgretmenProfil', {
        'AdSoyad': 'Öğretmen',
        'OkulAdi': 'Okul',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('SinifSube', {
        'SinifSubeId': 1,
        'SinifKodu': '9-C',
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('Ders', {
        'DersId': 1,
        'DersAdi': 'Ders',
        'OlusturmaTarihi': 'test',
      });
      await db.insert('DersSaati', {'DersSaatiId': 1, 'SiraNo': 1});
      await db.insert('DersProgrami', {
        'SinifSubeId': 1,
        'DersId': 1,
        'DersSaatiId': 1,
        'Gun': 'Pazartesi',
        'OgretmenProfilId': 1,
        'EgitimOgretimYili': '2026-2027',
        'OlusturmaTarihi': 'test',
      });
      for (var i = 1; i <= 60; i++) {
        await db.insert('Ogrenci', {
          'OgrenciId': i,
          'OkulNo': '$i',
          'Ad': 'Öğrenci',
          'Soyad': '$i',
          'Telefon': '05321112233',
          'OlusturmaTarihi': 'test',
        });
        await db.insert('OgrenciSinifKayit', {
          'OgrenciId': i,
          'SinifSubeId': 1,
          'EgitimOgretimYili': '2026-2027',
          'OlusturmaTarihi': 'test',
        });
      }
      final s = MesajlasmaService(
        databaseGetir: () async => db,
        modGetir: () async => CalismaModu.bireyselOgretmen,
      );
      await ac(t, s, yeni: true, text: '   ');
      final sinif = find.byType(DropdownButton<int>);
      await tikla(t, sinif);
      await tikla(t, find.text('9-C').last);
      await tikla(t, find.text('Alıcı grubu'));
      await tikla(t, find.text('Sınıf öğrencileri'));
      await tikla(t, find.text('Kendisi'));
      await tikla(t, find.text('Öğrenci listesi (0/60 seçili)'));
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tikla(t, find.byKey(const ValueKey('mesaj-aday-Ogrenci:1')));
      await tikla(t, find.text('Ön İzle ve Onayla'));
      expect(
        find.text('Lütfen göndermek istediğiniz mesajı yazın.'),
        findsOneWidget,
      );
      expect(find.textContaining('Bad state'), findsNothing);
      final alan = find.byKey(const ValueKey('mesaj-metni'));
      expect(t.widget<TextField>(alan).focusNode!.hasFocus, true);
      expect(
        alan.hitTestable(),
        findsOneWidget,
        reason: 'Mesaj alanı: ${t.getRect(alan)}',
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      final giris = find.descendant(
        of: alan,
        matching: find.byType(EditableText),
      );
      expect(
        giris.hitTestable(),
        findsOneWidget,
        reason: 'Klavye açık: ${t.getRect(alan)}, giriş: ${t.getRect(giris)}',
      );
      expect(await db.query('MesajKuyrugu'), isEmpty);
      await t.enterText(alan, 'Yeni mesaj');
      await t.pumpAndSettle();
      expect(
        find.text('Lütfen göndermek istediğiniz mesajı yazın.'),
        findsNothing,
      );
      await tikla(t, find.text('Ön İzle ve Onayla'));
      expect(find.text('Mesajı gönder'), findsOneWidget);
      expect(
        find.textContaining('1 alıcı • 1 telefon numarası'),
        findsOneWidget,
      );
      await tikla(t, find.text('Düzelt'));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'kaynak modülde boş mesaj da teknik hata yerine alan uyarısıdır',
    (t) async {
      final s = _Service();
      await ac(t, s, text: '');
      await tikla(t, find.text('Ön İzle ve Onayla'));
      expect(
        find.text('Lütfen göndermek istediğiniz mesajı yazın.'),
        findsOneWidget,
      );
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mesaj-metni')))
            .focusNode!
            .hasFocus,
        true,
      );
      expect(s.varMi, false);
    },
  );
  for (final (metin, uyari) in [
    ('{Bilinmeyen}', 'Mesajda tanınmayan veya eksik değişken var.'),
    (
      '${'a' * 3991}{Tarih}',
      'Mesajınız en fazla 4000 karakter olabilir. Lütfen kısaltın.',
    ),
  ]) {
    testWidgets('hazırlanan mesajın hatası alan içinde gösterilir: $uyari', (
      t,
    ) async {
      final s = _Service();
      await ac(t, s, text: metin);
      await tikla(t, find.text('Ön İzle ve Onayla'));
      expect(find.text(uyari), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('mesaj-metni')))
            .controller!
            .text,
        metin,
      );
      expect(s.varMi, false);
      expect(find.textContaining('Bad state'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
