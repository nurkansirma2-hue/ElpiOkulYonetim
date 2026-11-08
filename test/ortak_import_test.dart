import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/models/ortak_import.dart';
import 'package:elpi_okul_yonetim/services/bireysel_import_service.dart';
import 'package:elpi_okul_yonetim/services/ogrenci_import_tanimi.dart';
import 'package:elpi_okul_yonetim/services/ortak_import_service.dart';

void main() {
  ImportTanimi karmaTanim() => ImportTanimi(
    id: 'yeni_kart',
    ad: 'Yeni Kart',
    aciklama: '',
    alanlar: const [
      ImportAlan('konu', 'Konu', zorunlu: true),
      ImportAlan(
        'gun',
        'Gün',
        zorunlu: true,
        kolonDisiKapsam: ImportBilgiKapsami.blok,
      ),
      ImportAlan(
        'sorumlu',
        'Sorumlu',
        alternatifler: ['Görevli'],
        kolonDisiKapsam: ImportBilgiKapsami.blok,
      ),
      ImportAlan(
        'yil',
        'Yıl',
        kolondan: false,
        kolonDisiKapsam: ImportBilgiKapsami.dosya,
      ),
      ImportAlan(
        'yer',
        'Yer',
        kolondan: false,
        kolonDisiKapsam: ImportBilgiKapsami.sayfa,
      ),
    ],
    blokBaslangici: (r) =>
        r.first.startsWith('Bölüm:') ? <String, String>{} : null,
    kartKayitlariniOku: (r) => r.first.startsWith('Kart:')
        ? [
            {'konu': r.first.substring(5).trim()},
            {'konu': r[1]},
          ]
        : null,
    hazirla: (rows) async => ImportOnIzleme(
      rows
          .map(
            (r) => ImportKaydi(
              r.id,
              r.konum,
              r.degerler,
              durum: (r.degerler['gun'] ?? '').isEmpty
                  ? ImportDurumu.hatali
                  : ImportDurumu.uygun,
            ),
          )
          .toList(),
    ),
    aktar: (p, s) async => ImportOzet(
      eklenen: s.length,
      guncellenen: 0,
      atlanan: 0,
      hatali: 0,
      mesaj: '',
    ),
  );
  test(
    'Yeni kart kolon/blok/sayfa/dosya bilgilerini ortak motorla birleştirir',
    () async {
      final def = karmaTanim();
      final tables = [
        ImportTablosu('Bir', [
          ['Yıl: 2026'],
          ['Yer', 'Salon'],
          ['Bölüm: 1'],
          ['Gün: Pazartesi'],
          ['Görevli', 'Ali'],
          ['Konu', 'Gün'],
          ['Toplantı', ''],
          ['Gezi', 'Salı'],
          ['Bölüm: 2'],
          ['Gün', 'Çarşamba'],
          ['Konu'],
          ['Seminer'],
        ]),
        ImportTablosu('İki', [
          ['Kart: Etkinlik', 'Konser'],
        ]),
      ];
      final rows = OrtakImportService.kaynaklariOku(def, tables);
      expect(rows.length, 5);
      expect(rows[0].degerler['gun'], 'Pazartesi');
      expect(rows[1].degerler['gun'], 'Salı');
      expect(rows[0].degerler['sorumlu'], 'Ali');
      expect(rows[2].degerler.containsKey('sorumlu'), isFalse);
      expect(rows[2].degerler['gun'], 'Çarşamba');
      expect(rows[3].degerler.containsKey('gun'), isFalse);
      expect(rows[3].degerler.containsKey('yer'), isFalse);
      expect(rows.every((r) => r.degerler['yil'] == '2026'), isTrue);
      expect(rows.map((r) => r.id).toSet().length, 5);
      final preview = await def.hazirla(rows);
      expect(
        preview.kayitlar.where((r) => r.durum == ImportDurumu.hatali).length,
        2,
      );
      final session = ImportOturumu(preview)..topluSec(preview.kayitlar, true);
      expect(session.secimler.length, 3);
      expect((await def.aktar(preview, session.secimler)).eklenen, 3);
    },
  );
  test('Ortak bilgi çelişkisi yeni blok olmadan sessizce üzerine yazılmaz', () {
    expect(
      () => OrtakImportService.kaynaklariOku(karmaTanim(), [
        ImportTablosu('Bir', [
          ['Gün: Pazartesi'],
          ['Gün: Salı'],
        ]),
      ]),
      throwsFormatException,
    );
  });
  test(
    'Zorunlu alan kolon dışında bulunabilir ve profil kolon şartı koymaz',
    () {
      final def = karmaTanim();
      final table = ImportTablosu('Bir', [
        ['Konu'],
        ['Toplantı'],
      ]);
      expect(table.eslemeHatalari(def, 0, {'konu': 0}), isEmpty);
      final p = ImportProfili(
        ad: 'P',
        modul: def.id,
        surum: 1,
        basliklar: ['konu'],
        esleme: {'konu': 'konu'},
      );
      expect(p.uygula(def, ['Konu']), {'konu': 0});
    },
  );
  const definition = OgrenciImportTanimi.tanim;
  final classes = <String, Map<String, Object?>>{
    '9a': {'SinifSubeId': 1, 'SinifKodu': '9-A'},
    '10b': {'SinifSubeId': 2, 'SinifKodu': '10-B'},
  };
  test('Sınıfa ait alan ve rehber bilgisi çelişirse son satır kazanmaz', () {
    final rows = BireyselImportService.ortakOgrenciSatirlariniDogrula([
      ImportKaynakSatiri('1', 'Satır 1', {
        'okulNo': '101',
        'ad': 'Ayşe',
        'soyad': 'Yılmaz',
        'sinif': '9-A',
        'alan': 'Bilişim',
        'rehberOgretmen': 'Ali',
      }),
      ImportKaynakSatiri('2', 'Satır 2', {
        'okulNo': '102',
        'ad': 'Veli',
        'soyad': 'Yılmaz',
        'sinif': '9-A',
        'alan': 'Bilişim',
        'rehberOgretmen': 'Başka Öğretmen',
      }),
    ], classes);
    expect(rows.every((r) => r.durum == ImportDurumu.hatali), isTrue);
  });
  ImportKaynakSatiri source(
    String id,
    String no, {
    String name = 'Ayşe',
    String surname = 'Yılmaz',
    String classroom = '9-A',
    String gender = 'Kız',
  }) => ImportKaynakSatiri(id, 'Satır $id', {
    'okulNo': no,
    'ad': name,
    'soyad': surname,
    'sinif': classroom,
    'cinsiyet': gender,
  });

  test('Türkçe alternatif başlıklar ve kolon sırası otomatik eşleşir', () {
    final table = ImportTablosu('Liste', [
      [],
      [
        'ÖĞRENCİ SOYADI',
        'ÖĞRETMEN AD SOYAD',
        'Okul Numarası',
        'Öğrenci Adı',
        'Sınıf/Şube',
      ],
      ['Yılmaz', 'Ali Öğretmen', '101', 'Ayşe', '9-A'],
    ]);
    expect(table.baslikBul(definition), 1);
    final mapping = table.otomatikEsle(definition, 1);
    expect(mapping, {
      'soyad': 0,
      'rehberOgretmen': 1,
      'okulNo': 2,
      'ad': 3,
      'sinif': 4,
    });
    expect(table.eslemeHatalari(definition, 1, mapping), isEmpty);
    expect(
      table.esle(1, mapping).single.degerler['rehberOgretmen'],
      'Ali Öğretmen',
    );
  });
  test(
    'Belirsiz başlık ve bir kolona iki alan atanması sessizce kabul edilmez',
    () {
      final table = ImportTablosu('Liste', [
        ['Okul No', 'Öğrenci No', 'Ad', 'Soyad', 'Sınıf'],
      ]);
      expect(table.otomatikEsle(definition, 0).containsKey('okulNo'), isFalse);
      expect(
        table.eslemeHatalari(definition, 0, {
          'okulNo': 0,
          'ad': 2,
          'soyad': 2,
          'sinif': 4,
        }),
        isNotEmpty,
      );
    },
  );
  test('Başlıksız, boş ve sınır dışı satır manuel karara bırakılır', () {
    final table = ImportTablosu('Liste', [
      ['101', 'Ayşe'],
    ]);
    expect(table.baslikBul(definition), -1);
    expect(table.eslemeHatalari(definition, -1, {}), isNotEmpty);
    expect(table.eslemeHatalari(definition, 0, {'okulNo': 99}), isNotEmpty);
  });
  test('Boş satırlar ve tekrarlanan başlıklar veri kaydı yapılmaz', () {
    final table = ImportTablosu('Liste', [
      ['Okul No', 'Ad'],
      ['101', 'Ayşe'],
      [],
      ['Okul No', 'Ad'],
      ['102', 'Ali'],
    ]);
    expect(table.esle(0, {'okulNo': 0, 'ad': 1}).map((r) => r.id), [
      'Liste:1',
      'Liste:4',
    ]);
  });
  test('CSV ayraçları, tırnaklı ayraç, kaçış ve çok satırlı hücre okunur', () {
    expect(
      OrtakImportService.csvOku(
        'No;Ad;Not\r\n101;"Ayşe; Nur";"İlk\nİkinci ""satır"""\r\n',
      ),
      [
        ['No', 'Ad', 'Not'],
        ['101', 'Ayşe; Nur', 'İlk\nİkinci "satır"'],
      ],
    );
    expect(OrtakImportService.csvOku('No,Ad\n1,"Ali, Veli"'), [
      ['No', 'Ad'],
      ['1', 'Ali, Veli'],
    ]);
    expect(OrtakImportService.csvOku('No\tAd\n1\tAli'), [
      ['No', 'Ad'],
      ['1', 'Ali'],
    ]);
    expect(OrtakImportService.csvOku('No,Ad\n1,'), [
      ['No', 'Ad'],
      ['1', ''],
    ]);
  });
  test('Bozuk CSV tırnakları ve geçersiz UTF-8 açık hata verir', () {
    for (final text in ['No,Ad\n1,"Ali', 'No,Ad\n1,"Ali"x', 'No,Ad\n1,Al"i']) {
      expect(() => OrtakImportService.csvOku(text), throwsFormatException);
    }
    expect(
      () => OrtakImportService.tablolariOku(
        ImportDosya('a.csv', Uint8List.fromList([255])),
      ),
      throwsFormatException,
    );
  });
  test('UTF-8 BOM ve XLSX hücre tipi/sayfa adı korunur', () {
    final csv = OrtakImportService.tablolariOku(
      ImportDosya(
        'a.csv',
        Uint8List.fromList(utf8.encode('\uFEFFNo;Ad\n1;Ali')),
      ),
    );
    expect(csv.single.satirlar.first.first, 'No');
    final excel = Excel.createExcel();
    excel['Liste'].appendRow(['Okul No', 'Ad']);
    excel['Liste'].appendRow([101, 'Ayşe']);
    final tables = OrtakImportService.tablolariOku(
      ImportDosya('a.xlsx', Uint8List.fromList(excel.encode()!)),
    );
    expect(tables.singleWhere((t) => t.ad == 'Liste').satirlar[1], [
      '101',
      'Ayşe',
    ]);
  });
  test(
    'Profil kolon sırasından bağımsız uygulanır ve farklı modüle taşınmaz',
    () {
      final profile = ImportProfili(
        ad: 'Liste',
        modul: definition.id,
        surum: 1,
        basliklar: ['numara', 'adi', 'soyadi', 'sinif'],
        esleme: {
          'okulNo': 'numara',
          'ad': 'adi',
          'soyad': 'soyadi',
          'sinif': 'sinif',
        },
      );
      expect(profile.uygula(definition, ['Sınıf', 'Soyadı', 'Numara', 'Adı']), {
        'okulNo': 2,
        'ad': 3,
        'soyad': 1,
        'sinif': 0,
      });
      expect(
        profile.uygula(definition, ['Numara', 'Adı', 'Soyadı', 'Sınıf', 'Not']),
        isNull,
      );
      expect(
        profile.uygula(definition, [
          'Numara',
          'Adı',
          'Soyadı',
          'Sınıf',
          'Not',
        ], benzer: true),
        isNotNull,
      );
      expect(
        profile.uygula(definition, [
          'Numara',
          'Adı',
          'Adı',
          'Soyadı',
          'Sınıf',
        ], benzer: true),
        isNull,
      );
      expect(ImportProfili.fromJson(profile.toJson()).esleme, profile.esleme);
      final different = ImportTanimi(
        id: 'yeni',
        ad: 'Yeni',
        alanlar: definition.alanlar,
        hazirla: definition.hazirla,
        aktar: definition.aktar,
        aciklama: '',
      );
      expect(
        profile.uygula(different, ['Numara', 'Adı', 'Soyadı', 'Sınıf']),
        isNull,
      );
      final upgraded = ImportTanimi(
        id: definition.id,
        surum: 2,
        ad: 'Yeni',
        alanlar: definition.alanlar,
        hazirla: definition.hazirla,
        aktar: definition.aktar,
        aciklama: '',
      );
      expect(
        profile.uygula(upgraded, ['Numara', 'Adı', 'Soyadı', 'Sınıf']),
        isNull,
      );
    },
  );
  test(
    'Filtre, grup ve tümünü seçme seçimleri korur; hatalı satır seçilemez',
    () {
      final rows = BireyselImportService.ortakOgrenciSatirlariniDogrula([
        source('1', '101'),
        source('2', '102', classroom: '10-B'),
        source('3', 'x'),
      ], classes);
      final session = ImportOturumu(ImportOnIzleme(rows));
      session.topluSec(rows, true);
      expect(session.secimler, {'101', '102'});
      session.filtreler['sinif'] = '9-A';
      session.topluSec(session.gorunen, false);
      expect(session.secimler, {'102'});
      session.filtreler.clear();
      session.durumFiltresi = ImportDurumu.hatali;
      session.topluSec(session.gorunen, true);
      expect(session.secimler, {'102'});
      session.secimiKaldir();
      expect(session.secimler, isEmpty);
    },
  );
  test('Dosya engeli tüm seçim yollarında uygulanır', () {
    final row = ImportKaydi('1', 'satır', {});
    final session = ImportOturumu(
      ImportOnIzleme([row], engeller: ['Belirsiz dosya']),
    );
    session.sec(row, true);
    session.topluSec([row], true);
    expect(session.secimler, isEmpty);
  });
  test(
    'Kapsam dışı, hatalı ve uyarılı kayıtlar ayrılır; baştaki sıfırlar normalleşir',
    () {
      final rows = BireyselImportService.ortakOgrenciSatirlariniDogrula([
        source('1', '00101'),
        source('2', '102', classroom: '11-C'),
        source('3', '103', name: ''),
        source('4', '104', gender: ''),
      ], classes);
      expect(rows.map((r) => r.durum), [
        ImportDurumu.uygun,
        ImportDurumu.atlanan,
        ImportDurumu.hatali,
        ImportDurumu.uyarili,
      ]);
      expect(rows.first.id, '101');
      expect(rows.first.degerler['okulNo'], '101');
    },
  );
  test('Çelişkili okul numarasının tüm geçerli adayları aktarım dışıdır', () {
    final rows = BireyselImportService.ortakOgrenciSatirlariniDogrula([
      source('1', '101'),
      source('2', '00101', classroom: '10-B'),
      source('3', '101'),
    ], classes);
    expect(rows.every((r) => r.durum == ImportDurumu.hatali), isTrue);
  });
  test('Aynı öğrencinin tekrarı bir kez aktarılır', () {
    final rows = BireyselImportService.ortakOgrenciSatirlariniDogrula([
      source('1', '101'),
      source('2', '00101'),
    ], classes);
    expect(rows.map((r) => r.durum), [
      ImportDurumu.uygun,
      ImportDurumu.atlanan,
    ]);
  });
  test('Yüksek kayıt sayısında filtre değişimi kimlikleri karıştırmaz', () {
    final rows = [
      for (var i = 1; i <= 5000; i++)
        ImportKaydi('$i', 'Satır $i', {'sinif': i.isEven ? '9-A' : '10-B'}),
    ];
    final session = ImportOturumu(ImportOnIzleme(rows));
    session.filtreler['sinif'] = '9-A';
    session.topluSec(session.gorunen, true);
    session.filtreler['sinif'] = '10-B';
    expect(session.secimler.length, 2500);
    expect(
      session.gorunen.any((r) => session.secimler.contains(r.id)),
      isFalse,
    );
    session.filtreler.clear();
    expect(session.secimler.contains('5000'), isTrue);
  });
  test(
    'Başka kart yalnız kendi tanımıyla eşleştirme ve seçim kullanır',
    () async {
      final other = ImportTanimi(
        id: 'etkinlik',
        ad: 'Etkinlik',
        aciklama: '',
        alanlar: const [
          ImportAlan(
            'gun',
            'Gün',
            zorunlu: true,
            alternatifler: ['Etkinlik Günü'],
            filtrelenebilir: true,
          ),
          ImportAlan('konu', 'Konu', zorunlu: true),
        ],
        hazirla: (rows) async => ImportOnIzleme(
          rows.map((r) => ImportKaydi(r.id, r.konum, r.degerler)).toList(),
        ),
        aktar: (preview, selected) async => ImportOzet(
          eklenen: selected.length,
          guncellenen: 0,
          atlanan: preview.kayitlar.length - selected.length,
          hatali: 0,
          mesaj: 'Tamam',
        ),
      );
      final table = ImportTablosu('Yeni', [
        ['Konu', 'Etkinlik Günü'],
        ['Toplantı', 'Pazartesi'],
      ]);
      final mapping = table.otomatikEsle(other, 0);
      expect(table.eslemeHatalari(other, 0, mapping), isEmpty);
      final session = ImportOturumu(
        await other.hazirla(table.esle(0, mapping)),
      );
      session.topluSec(session.gorunen, true);
      expect(
        (await other.aktar(session.onIzleme, session.secimler)).eklenen,
        1,
      );
    },
  );
}
