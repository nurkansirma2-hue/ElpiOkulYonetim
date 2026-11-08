import 'package:flutter_test/flutter_test.dart';
import 'package:elpi_okul_yonetim/database/veli_iliskisi.dart';
import 'support/windows_memory_database.dart';

void main() {
  late WindowsMemoryDatabase db;
  setUp(() async {
    db = WindowsMemoryDatabase();
    await db.execute('''CREATE TABLE Ogrenci(OgrenciId INTEGER PRIMARY KEY,
      AnneAdi TEXT,AnneTelefon TEXT,BabaAdi TEXT,BabaTelefon TEXT,
      VeliAdi TEXT,VeliTelefonu TEXT,GuncellemeTarihi TEXT)''');
    for (var id = 1; id <= 5; id++) {
      await db.insert('Ogrenci', {
        'OgrenciId': id,
        'AnneAdi': 'Ayşe',
        'AnneTelefon': '05321112233',
        'BabaAdi': 'Ali',
        'BabaTelefon': '05324445566',
        'VeliAdi': switch (id) {
          1 => 'Ayşe',
          2 => 'Teyze',
          4 => 'Ali',
          5 => 'Farklı kişi',
          _ => null,
        },
        'VeliTelefonu': switch (id) {
          1 => '+905321112233',
          2 => '05327778899',
          4 => '05324445566',
          5 => '05321112233',
          _ => null,
        },
      });
    }
  });
  tearDown(() async => db.close());
  Future<Map<String, Object?>> oku(int id) async => (await db.rawQuery(
    '''
    SELECT o.*,${VeliIliskisi.adSql('o')} AS EtkinAd,
      ${VeliIliskisi.telefonSql('o')} AS EtkinTelefon FROM Ogrenci o WHERE OgrenciId=?
  ''',
    [id],
  )).single;
  test(
    'v21 geçişi anne baba diğer ayrımını yapar ve eski veriyi korur',
    () async {
      final once = await db.query('Ogrenci');
      await VeliIliskisi.hazirla(db);
      final sonra = await db.query('Ogrenci');
      expect(sonra.map((o) => o['VeliTuru']), [
        'Anne',
        'Diger',
        'Anne',
        'Baba',
        'Diger',
      ]);
      for (var i = 0; i < once.length; i++) {
        for (final e in once[i].entries) {
          expect(sonra[i][e.key], e.value);
        }
      }
      expect((await oku(1))['EtkinTelefon'], '05321112233');
    },
  );
  test('veli anne veya baba kaydını izler; telefon kopyalanmaz', () async {
    await VeliIliskisi.hazirla(db);
    await VeliIliskisi.kaydet(db, 3, 'Baba');
    expect((await oku(3))['EtkinTelefon'], '05324445566');
    expect((await oku(3))['VeliTelefonu'], isNull);
    await db.update('Ogrenci', {
      'BabaTelefon': '05323334455',
    }, where: 'OgrenciId=3');
    expect((await oku(3))['EtkinTelefon'], '05323334455');
    await VeliIliskisi.kaydet(db, 3, 'Anne');
    await db.update('Ogrenci', {
      'AnneAdi': 'Yeni Anne',
      'AnneTelefon': null,
    }, where: 'OgrenciId=3');
    expect((await oku(3))['EtkinTelefon'], isNull);
    expect((await oku(3))['EtkinAd'], 'Yeni Anne');
  });
  test('diğer velinin telefonu korunur; geçersiz seçim yazılmaz', () async {
    await VeliIliskisi.hazirla(db);
    await VeliIliskisi.kaydet(db, 2, 'Anne');
    expect((await oku(2))['VeliTelefonu'], '05327778899');
    await VeliIliskisi.kaydet(
      db,
      2,
      'Diger',
      ad: 'Teyze',
      telefon: '05327778899',
    );
    expect((await oku(2))['EtkinTelefon'], '05327778899');
    await expectLater(
      VeliIliskisi.kaydet(db, 2, 'Yanlis'),
      throwsFormatException,
    );
    await expectLater(
      VeliIliskisi.kaydet(db, 2, 'Diger', telefon: 'abc'),
      throwsFormatException,
    );
    expect((await oku(2))['EtkinTelefon'], '05327778899');
  });

  for (final tur in ['Anne', 'Baba']) {
    test(
      '$tur adı ve telefonu kendi alanına yazılır; diğer bilgiler korunur',
      () async {
        await VeliIliskisi.hazirla(db);
        final once = await oku(3);
        await VeliIliskisi.kaydet(
          db,
          3,
          tur,
          ad: 'Yeni $tur',
          telefon: '05329990000',
          onceki: VeliIliskisi.gorunum(once),
        );
        final sonra = await oku(3);
        expect(sonra['VeliTuru'], tur);
        expect(sonra['${tur}Adi'], 'Yeni $tur');
        expect(sonra['${tur}Telefon'], '05329990000');
        final diger = tur == 'Anne' ? 'Baba' : 'Anne';
        for (final key in [
          '${diger}Adi',
          '${diger}Telefon',
          'VeliAdi',
          'VeliTelefonu',
        ]) {
          expect(sonra[key], once[key]);
        }
        await expectLater(
          VeliIliskisi.kaydet(db, 3, tur, telefon: 'abc'),
          throwsFormatException,
        );
        expect((await oku(3))['${tur}Telefon'], '05329990000');
        await expectLater(
          VeliIliskisi.kaydet(
            db,
            3,
            tur,
            ad: 'Eski ekrandaki değer',
            telefon: '05320000000',
            onceki: VeliIliskisi.gorunum(once),
          ),
          throwsStateError,
        );
        expect((await oku(3))['${tur}Telefon'], '05329990000');
      },
    );
  }
}
