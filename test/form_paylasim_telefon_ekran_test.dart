import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';
import 'package:elpi_okul_yonetim/screens/mesajlasma_screen.dart';

class TelefonTestService extends MesajlasmaService {
  TelefonTestService({bool ogrenci = false}) : super(ogrenciTelefonu: ogrenci);
  final telefonlar = {1: '05321112233', 2: '', 3: ''};
  int kayit = 0;
  MesajKuyrugu? q;
  @override
  Future<List<Map<String, Object?>>> tekliGecmis(MesajBaglami b) async => [];
  @override
  Future<MesajBaglami> hazirla() async =>
      const MesajBaglami('okul', 1, 'Öğretmen', 'Okul', '2026-2027');
  @override
  Future<List<MesajOgrencisi>> ogrenciler(MesajBaglami b) async => [
    for (final id in telefonlar.keys)
      MesajOgrencisi(
        id,
        '$id',
        'Öğrenci $id',
        1,
        '9/A',
        ogrenciTelefonu ? 'Öğrenci $id' : 'Anne $id',
        telefonlar[id]!,
      ),
  ];
  @override
  Future<List<MesajKuyrugu>> kuyruklar(MesajBaglami b) async =>
      q == null ? [] : [q!];
  @override
  Future<List<Map<String, Object?>>> telefonDuzenlemeBilgileri(
    MesajBaglami b,
    Set<int> ids,
  ) async => [
    for (final id in ids)
      {
        'id': id,
        'tur': ogrenciTelefonu ? 'Ogrenci' : 'Anne',
        'telefon': telefonlar[id],
        'aciklama': 'Öğrenci $id',
      },
  ];
  @override
  Future<void> telefonlariKaydet(
    MesajBaglami b,
    Map<int, String> telefonlar, {
    required List<Map<String, Object?>> beklenen,
  }) async {
    kayit++;
    this.telefonlar.addAll(telefonlar);
  }

  @override
  Future<MesajKuyrugu> kuyrukOlustur(
    MesajBaglami b,
    MesajOnIzleme preview,
    String metin, {
    required String kaynakModul,
    String? kaynakKayit,
    Map<int, String>? ogrenciMesajlari,
  }) async {
    q = MesajKuyrugu(
      {
        'KuyrukId': 'test',
        'Metin': metin,
        'KaynakModul': kaynakModul,
        'KaynakKayit': kaynakKayit,
        'OlusturmaTarihi': '2026-10-23',
      },
      [
        for (var i = 0; i < preview.alicilar.length; i++)
          MesajAlicisi({
            'AliciId': i + 1,
            'Sira': i + 1,
            'Telefon': preview.alicilar[i].telefon,
            'AliciAdi': preview.alicilar[i].ad,
            'Durum': 'Bekliyor',
            'Ogrenciler': jsonEncode([
              for (final o in preview.alicilar[i].ogrenciler)
                {'id': o.id, 'sinifId': o.sinifId, 'aciklama': o.aciklama},
            ]),
          }),
      ],
    );
    return q!;
  }

  @override
  Future<MesajKuyrugu> kuyrukGetir(MesajBaglami b, String id) async => q!;
}

void main() {
  Future<void> ac(WidgetTester t, TelefonTestService s) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute(
                  builder: (_) => MesajlasmaScreen(
                    service: s,
                    ogrenciTelefonu: s.ogrenciTelefonu,
                    eksikTelefonlariSor: true,
                    kaynakGecmisiniGoster: true,
                    kaynakModul: s.ogrenciTelefonu
                        ? MesajlasmaService.formPaylasimOgrenciModulu
                        : MesajlasmaService.formPaylasimVeliModulu,
                    kaynakKayit: '1',
                    izinliOgrenciIdleri: const {1, 2},
                    baslangicOgrenciIdleri: const {1, 2},
                    baslangicMetni:
                        'Formu doldurunuz: https://docs.google.com/forms/d/e/test/viewform',
                  ),
                ),
              ),
              child: const Text('Paylaşımı başlat'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Paylaşımı başlat'));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
    'öğrenci telefonu isteğe bağlı girilir; doğrulama ve iki gönderim yöntemi',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = TelefonTestService(ogrenci: true);
      await ac(t, s);
      expect(find.text('Telefon numaralarını tamamla'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 500));
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('mesaj-telefon-2')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const ValueKey('mesaj-telefon-3')), findsNothing);
      await t.enterText(
        find.byKey(const ValueKey('mesaj-telefon-2')),
        'yanlış',
      );
      await t.tap(find.text('Kaydet ve devam et'));
      await t.pump();
      expect(find.textContaining('Geçerli tek telefon'), findsOneWidget);
      expect(s.kayit, 0);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('mesaj-telefon-2')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await t.enterText(
        find.byKey(const ValueKey('mesaj-telefon-2')),
        '05324445566',
      );
      await t.ensureVisible(find.text('Kaydet ve devam et'));
      await t.tap(find.text('Kaydet ve devam et'));
      await t.pumpAndSettle();
      expect(s.telefonlar[2], '05324445566');
      expect(s.telefonlar[3], '');
      await t.tap(find.text('Ön İzle ve Onayla'));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('SMS ile gönder'));
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text('Vazgeç'));
      await t.pumpAndSettle();
      expect(s.q!.alicilar, hasLength(2));
      expect(find.text('SIM Üzerinden Otomatik SMS Gönder'), findsNothing);
      expect(find.byKey(const ValueKey('whatsapp-devam')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('numarasız veli atlanır veya paylaşım tamamen sonlandırılır', (
    t,
  ) async {
    final s = TelefonTestService();
    await ac(t, s);
    await t.tap(find.text('Kaydet ve devam et'));
    await t.pumpAndSettle();
    expect(s.kayit, 0);
    await t.tap(find.text('Ön İzle ve Onayla'));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('SMS ile gönder'));
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(s.q, isNull);
    await t.pumpWidget(const SizedBox.shrink());
    final ikinci = TelefonTestService();
    await ac(t, ikinci);
    await t.tap(find.text('İşlemi sonlandır'));
    await t.pumpAndSettle();
    expect(find.text('Paylaşımı başlat'), findsOneWidget);
    expect(ikinci.q, isNull);
    expect(ikinci.kayit, 0);
    await t.pumpWidget(const SizedBox.shrink());
    final numarasiz = TelefonTestService()..telefonlar[1] = '';
    await ac(t, numarasiz);
    await t.tap(find.text('Kaydet ve devam et'));
    await t.pump();
    expect(find.textContaining('en az bir geçerli telefon'), findsOneWidget);
    expect(numarasiz.q, isNull);
    await t.tap(find.text('İşlemi sonlandır'));
    await t.pumpAndSettle();
    expect(find.text('Paylaşımı başlat'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
