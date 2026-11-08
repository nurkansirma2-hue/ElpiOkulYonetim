import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/core/calisma_modu.dart';
import 'package:elpi_okul_yonetim/models/mesajlasma.dart';
import 'package:elpi_okul_yonetim/services/mesajlasma_service.dart';

// Gerçek veya bellek veritabanında silme yapmaz; yalnız verilen komutları kaydeder.
class _KomutDb implements Database {
  final sorgular = <Invocation>[];
  final degisiklikler = <Invocation>[];
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #query) {
      sorgular.add(i);
      final rows = switch (i.positionalArguments.first) {
        'OkulProfil' => [
          {'OkulId': 'okul', 'OkulAdi': 'Okul', 'EgitimYili': '2026-2027'},
        ],
        'OgretmenProfil' => [
          {
            'OgretmenProfilId': 1,
            'AdSoyad': 'Öğretmen',
            'OkulAdi': 'Okul',
            'EgitimOgretimYili': '2026-2027',
          },
        ],
        'MesajKuyrugu' => [
          {'KuyrukId': 'q1'},
        ],
        'MesajAlici' => [
          {'AliciId': 10},
        ],
        _ => <Map<String, Object?>>[],
      };
      return Future<List<Map<String, Object?>>>.value(rows);
    }
    if (i.memberName == #update || i.memberName == #delete) {
      degisiklikler.add(i);
      return Future<int>.value(1);
    }
    return super.noSuchMethod(i);
  }
}

void main() {
  final service = MesajlasmaService(
    modGetir: () async => CalismaModu.bireyselOgretmen,
  );
  test(
    'arşiv kaynakla ve sahiplikle sınırlı, mesaj durumları korunur',
    () async {
      final db = _KomutDb();
      await service.odevBildirimleriniKaldir(db, {42}, sil: false);
      expect(db.degisiklikler, hasLength(2));
      for (final i in db.degisiklikler) {
        expect(i.memberName, #update);
        expect(i.positionalArguments[1], {
          'KaynakModul': odevBildirimArsivModulu,
        });
        expect(i.namedArguments[#whereArgs], [
          '42',
          'okul',
          1,
          'Öğretmen',
          '2026-2027',
        ]);
        expect(
          i.namedArguments[#where],
          contains("KaynakModul IN ('OdevBildirim','OdevBildirimArsiv')"),
        );
      }
      final a = MesajAlicisi({
        'AliciId': 1,
        'Sira': 1,
        'Telefon': '905551234567',
        'AliciAdi': 'A',
        'Ogrenciler': '[]',
        'Durum': 'Bekliyor',
      });
      final q = MesajKuyrugu(
        {
          'KuyrukId': 'q',
          'Metin': 'Ödev',
          'KaynakModul': odevBildirimArsivModulu,
          'KaynakKayit': '42',
          'OlusturmaTarihi': 'test',
        },
        [a],
      );
      expect(q.arsivlendi, true);
      expect(q.tamamlandi, true);
      expect(q.siradaki, isNull);
      expect(a.durum, 'Bekliyor');
    },
  );
  test(
    'silme komutları FK sırasını izler ve yalnız bağlı mesajları hedefler',
    () async {
      final db = _KomutDb();
      await service.odevBildirimleriniKaldir(db, {42}, sil: true);
      expect(
        db.degisiklikler.map((i) => i.positionalArguments.first).toList(),
        [
          'MesajSms',
          'MesajAliciBag',
          'MesajAlici',
          'MesajKuyrugu',
          'MesajTekliGecmis',
        ],
      );
      for (final i in db.degisiklikler) {
        expect(i.memberName, #delete);
      }
      final q = db.sorgular.firstWhere(
        (i) => i.positionalArguments.first == 'MesajKuyrugu',
      );
      expect(q.namedArguments[#whereArgs], [
        '42',
        'okul',
        1,
        'Öğretmen',
        '2026-2027',
      ]);
      final tekli = db.degisiklikler.last;
      expect(tekli.namedArguments[#whereArgs], [
        '42',
        'okul',
        1,
        'Öğretmen',
        '2026-2027',
      ]);
    },
  );
}
