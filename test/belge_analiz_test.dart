import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/belge_analiz_service.dart';
import 'package:elpi_okul_yonetim/services/belge_disari_aktar_service.dart';
import 'package:elpi_okul_yonetim/services/ogrenci_import_tanimi.dart';
import 'package:elpi_okul_yonetim/services/ders_programi_import_tanimi.dart';
import 'package:elpi_okul_yonetim/services/yillik_plan_import_tanimi.dart';
import 'package:elpi_okul_yonetim/services/bireysel_import_service.dart';
import 'package:elpi_okul_yonetim/services/bireysel_yillik_plan_service.dart';

void main() {
  ImportDosya text(String ad, String content) =>
      ImportDosya(ad, Uint8List.fromList(utf8.encode(content)));

  test(
    'Uzantısı Office olarak değiştirilmiş metin import biçimi değildir',
    () async {
      for (final ext in ['xls', 'xlsx', 'doc', 'docx']) {
        await expectLater(
          BelgeAnalizService.bicimiDogrulaAsync(text('liste.$ext', 'Ad;Soyad')),
          throwsFormatException,
        );
        final sonuc = await BelgeAnalizService.analizEt(
          text('liste.$ext', 'Ad;Soyad'),
        );
        expect(sonuc.tur, 'Genel belge');
        expect(sonuc.aciklama, contains('Orijinal hata'));
      }
    },
  );

  test(
    'Öğrenci CSV içeriği adından bağımsız tanınır, belirsiz aday sessiz seçilmez',
    () async {
      final sonuc = await BelgeAnalizService.analizEt(
        text('rasgele.csv', 'Okul No;Ad;Soyad;Sınıf\n101;Ali;Yılmaz;9-A'),
      );
      expect(sonuc.tur, 'Öğrenci listesi');
      final karma = await BelgeAnalizService.analizEt(
        text(
          'karma.txt',
          'Okul No Ad Soyad Sınıf\nBEP Planı Bireyselleştirilmiş Eğitim',
        ),
      );
      expect(karma.tur, 'Genel belge');
      expect(karma.adaylar, containsAll(['Öğrenci listesi', 'BEP belgesi']));
      expect(BelgeAnalizi.fromJson(sonuc.toJson())!.tur, sonuc.tur);
      expect(BelgeAnalizi.fromJson('bozuk'), isNull);
      expect(BelgeAnalizi.fromJson('{"surum":2}'), isNull);
    },
  );

  test('Çok sayfalı XLSX içerikten tanınır', () async {
    final excel = Excel.createExcel();
    excel['Kapak'].appendRow(['Okul bilgileri']);
    excel['İkinci Sayfa'].appendRow([
      'Öğrenci Numarası',
      'Adı',
      'Soyadı',
      'Sınıfı',
    ]);
    excel['İkinci Sayfa'].appendRow([101, 'Ali', 'Yılmaz', '9-A']);
    final file = ImportDosya('dosya.xlsx', Uint8List.fromList(excel.encode()!));
    final sonuc = await BelgeAnalizService.analizEt(file);
    expect(sonuc.tur, 'Öğrenci listesi');
  });

  test('DOCX gerçek kapsayıcısı ve metni kontrol edilir', () async {
    final bytes = utf8.encode(
      '<w:document xmlns:w="test"><w:body><w:p><w:r><w:t>Yıllık plan hafta kazanım</w:t></w:r></w:p></w:body></w:document>',
    );
    final archive = Archive()
      ..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
    final file = ImportDosya(
      'plan.docx',
      Uint8List.fromList(ZipEncoder().encode(archive)!),
    );
    expect((await BelgeAnalizService.analizEt(file)).tur, 'Yıllık plan');
    await expectLater(
      BelgeAnalizService.bicimiDogrulaAsync(
        ImportDosya('sahte.xlsx', file.bytes),
      ),
      throwsFormatException,
    );
  });

  test(
    'Rehber XLSX zorunlu alanları taşır, çıktı formül çalıştırmaz',
    () async {
      final bytes = await BelgeDisariAktarService.excelOlustur(
        OgrenciImportTanimi.tanim,
        [
          ImportKaydi('1', 'Kaynak', {
            'okulNo': '001',
            'ad': '=1+2',
            'soyad': 'Yılmaz',
            'sinif': '9-A',
          }),
        ],
      );
      final excel = Excel.decodeBytes(bytes);
      final rows = excel['Sheet1'].rows;
      expect(
        rows.first.map((c) => c?.value.toString()),
        containsAll(['Okul No', 'Ad', 'Soyad', 'Sınıf']),
      );
      expect(rows[1][0]!.value.toString(), '001');
      expect(rows[1][1]!.value.toString(), '=1+2');
      expect(rows[1][1]!.cellType, CellType.String);
      final sablon = Excel.decodeBytes(
        await BelgeDisariAktarService.excelOlustur(
          OgrenciImportTanimi.tanim,
          [],
          sablon: true,
        ),
      );
      expect(sablon.tables.keys, contains('Rehber'));
      expect(sablon['Sheet1'].rows, hasLength(1));
    },
  );

  test(
    'Program düzeltmesi öğretmen eşleşmesini ve başlangıç tarihini korur',
    () async {
      final definition = DersProgramiImportTanimi.olustur(
        'Ayşe',
        meslekPaketi: false,
      );
      final original = DersProgramiImportTanimi.onIzlemeyeCevir(
        BireyselDersProgramiOnIzleme(
          sayfaSayisi: 3,
          doluHucreSayisi: 50,
          ogretmenBulundu: false,
          ogretmenEslesmeleri: const [],
          gunlukDersSaatAdaylari: const [],
          baslangicTarihi: DateTime(2026, 9, 14),
          dersler: const [
            BireyselDersProgramiKaydi(
              gun: 'Pazartesi',
              dersSaatiNo: 1,
              saatAraligi: '08:00 - 08:40',
              dersAdi: 'Matematik',
              sinif: '9-A',
              derslik: '',
            ),
          ],
        ),
        meslekPaketi: false,
      );
      final rows = original.kayitlar
          .map(
            (r) => ImportKaynakSatiri(r.id, r.konum, {
              ...r.degerler,
              'dersAdi': 'Türkçe',
            }),
          )
          .toList();
      final changed = await definition.duzenlemeHazirla!(original, rows);
      final p = changed.veri as BireyselDersProgramiOnIzleme;
      expect(p.dersler.single.dersAdi, 'Türkçe');
      expect(p.sayfaSayisi, 3);
      expect(p.baslangicTarihi, DateTime(2026, 9, 14));
      expect(p.ogretmenBulundu, isFalse);
      expect(changed.engeller, isNotEmpty);
    },
  );

  test(
    'Yıllık plan düzeltmesi ders/sınıf uygunluğunu ve tatil kayıtlarını korur',
    () async {
      final definition = YillikPlanImportTanimi.olustur('2026/2027');
      final raw = BireyselYillikPlanService.eslenmisSatirlariOku([
        {
          'hafta': '1',
          'ay': 'Eylül',
          'tarih': '14-18 Eylül',
          'konu': 'Sayılar',
          'saat': '4',
        },
      ], egitimOgretimYili: '2026/2027');
      final p = BireyselYillikPlanOnIzleme(
        dosyaAdi: 'orijinal.docx',
        dosyaTuru: 'DOCX',
        baslikSatiri: 3,
        tespitEdilenDersAdi: 'Matematik',
        tespitEdilenSinifSeviyesi: 9,
        kayitlar: raw.kayitlar,
        calismaTakvimi: [
          ...raw.calismaTakvimi,
          const BireyselCalismaTakvimiAdayi(
            haftaNo: null,
            ay: 'Ekim',
            tarihAraligi: '29 Ekim',
            baslangicTarihi: '2026-10-29',
            bitisTarihi: '2026-10-29',
            kayitTuru: 'Tatil',
            calismaVarMi: false,
            aciklama: 'Cumhuriyet Bayramı',
            ozelGunAciklamasi: 'Bayram',
          ),
        ],
        hatalar: raw.hatalar,
      );
      final preview = YillikPlanImportTanimi.onIzlemeyeCevir(p);
      final rows = preview.kayitlar
          .map(
            (r) => ImportKaynakSatiri(r.id, r.konum, {
              ...r.degerler,
              if (r.degerler['tur'] == 'Plan') 'konu': 'Yeni konu',
            }),
          )
          .toList();
      final changed = await definition.duzenlemeHazirla!(preview, rows);
      final result = changed.veri as BireyselYillikPlanOnIzleme;
      expect(result.kayitlar.single.konu, 'Yeni konu');
      expect(result.tespitEdilenDersAdi, 'Matematik');
      expect(result.tespitEdilenSinifSeviyesi, 9);
      expect(
        result.calismaTakvimi.where((r) => r.kayitTuru == 'Tatil'),
        hasLength(1),
      );
      expect(p.kayitlar.single.konu, 'Sayılar');
    },
  );
}
