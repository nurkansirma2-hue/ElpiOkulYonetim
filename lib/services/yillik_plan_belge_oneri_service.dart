import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/local_database.dart';
import '../models/ortak_import.dart';
import 'belge_analiz_service.dart';
import 'belge_eslestirme_service.dart';
import 'bireysel_profil_service.dart';
import 'drive_belge_service.dart';
import 'ortak_import_service.dart';

class YillikPlanBelgeAdayi {
  const YillikPlanBelgeAdayi(this.dosya, this.uyarilar);
  final ImportDosya dosya;
  final List<String> uyarilar;
}

/// Hesap bağlantısı okul/öğretmen kapsamındadır; token kalıcı tutulmaz.
class YillikPlanBelgeOneriService {
  YillikPlanBelgeOneriService({DriveBelgeService? drive})
    : _drive = drive ?? DriveBelgeService();
  final DriveBelgeService _drive;

  Future<String> _kapsam(int profilId) async {
    await OrtakImportService.bireyselModuDogrula();
    final okul = await BireyselProfilService.okulProfiliniGetir();
    final profil = await BireyselProfilService.getir();
    if (okul == null ||
        okul['AktifMi'] != 1 ||
        '${okul['OkulId'] ?? ''}'.isEmpty ||
        profil?['OgretmenProfilId'] != profilId ||
        okul['OkulAdi'] != profil?['OkulAdi']) {
      throw StateError(
        'Aktif okul veya öğretmen değişti. Ekranı yeniden açın.',
      );
    }
    return 'drive.hesap.v1.${jsonEncode([okul['OkulId'], profilId])}';
  }

  Future<ImportDosya?> sec(int profilId, Set<String> uzantilar) async {
    final key = await _kapsam(profilId);
    return _drive.sec(
      uzantilar,
      hesapSecildi: (hesap) async {
        if (await _kapsam(profilId) != key) {
          throw StateError('Dosya seçilirken okul değişti. Yeniden seçin.');
        }
        final db = await LocalDatabase.instance.database;
        await db.insert('UygulamaAyarlari', {
          'Anahtar': key,
          'Deger': hesap,
          'GuncellemeTarihi': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      },
    );
  }

  Future<List<YillikPlanBelgeAdayi>> ara({
    required int profilId,
    required String ders,
    required int seviye,
    required String yil,
    required String okul,
  }) async {
    final key = await _kapsam(profilId);
    final db = await LocalDatabase.instance.database;
    final ayar = await db.query(
      'UygulamaAyarlari',
      columns: ['Deger'],
      where: 'Anahtar = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (ayar.isEmpty) return [];
    final token = await _drive.erisim(ayar.single['Deger'] as String);
    if (token == null) return [];
    final liste = await _drive.adaylariListele(token);
    // Adı dersle eşleşen yakın adaylar önce; toplu içerik indirilmez.
    int puan(Map<String, dynamic> m) {
      final ad = '${m['name']}';
      return (BelgeEslestirmeService.dersGeciyor(ad, ders) ? 2 : 0) +
          (importNormalize(ad).contains('plan') ? 1 : 0);
    }

    final uygun =
        liste
            .where(
              (m) =>
                  puan(m) > 0 &&
                  (m['capabilities'] as Map?)?['canDownload'] == true &&
                  (int.tryParse('${m['size']}') ?? 1) <= 5 * 1024 * 1024,
            )
            .toList()
          ..sort((a, b) => puan(b).compareTo(puan(a)));
    final sonuc = <YillikPlanBelgeAdayi>[];
    for (final m in uygun.take(3)) {
      try {
        final dosya = await _drive.indir(
          token: token,
          dosyaId: m['id'] as String,
          uzantilar: {'xls', 'xlsx', 'docx'},
          beklenenSurum: m['version'] as String?,
          boyutSiniri: 5 * 1024 * 1024,
        );
        await BelgeAnalizService.bicimiDogrulaAsync(dosya);
        final metin = dosya.uzanti == 'docx'
            ? await BelgeAnalizService.docxMetni(dosya.bytes)
            : (await OrtakImportService.oku(dosya))
                  .map((t) => t.satirlar.map((r) => r.join(' ')).join('\n'))
                  .join('\n');
        final eslesme = BelgeEslestirmeService.yillikPlan(
          ad: dosya.ad,
          metin: metin,
          ders: ders,
          seviye: seviye,
          yil: yil,
          okul: okul,
        );
        if (eslesme != null) {
          sonuc.add(YillikPlanBelgeAdayi(dosya, eslesme.uyarilar));
        }
      } on FormatException {
        // Bozuk veya desteklenmeyen aday manuel seçimi engellemez.
      }
    }
    if (await _kapsam(profilId) != key) {
      throw StateError('Arama kapsamı değişti.');
    }
    return sonuc;
  }

  void dispose() => _drive.dispose();
}
