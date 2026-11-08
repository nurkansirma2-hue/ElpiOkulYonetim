import 'package:flutter/material.dart';
import '../models/mesajlasma.dart';
import '../models/ortak_import.dart';
import '../models/import_ilerleme.dart';
import '../services/mesajlasma_service.dart';
import '../services/program_belgesi_okuyucu.dart';

class ProgramImportKapsamDialog {
  static Future<ImportOnIzleme?> hazirla(
    BuildContext context,
    MesajlasmaService service,
    MesajBaglami baglam,
    int sinifId,
    ImportDosya dosya, {
    Future<List<ImportKaynakSatiri>> Function(ImportDosya)? oku,
    void Function(ImportIlerleme?)? ilerleme,
  }) async {
    final rows = oku != null
        ? await oku(dosya)
        : await ProgramBelgesiOkuyucu.oku(dosya, ilerleme: ilerleme);
    ilerleme?.call(
      ImportIlerleme(
        '${rows.length} öğretmen-sınıf kaydı bulundu; sınıf kapsamı kontrol ediliyor…',
      ),
    );
    final siniflar = await service.mesajSiniflari(baglam);
    final hedef = siniflar.where((s) => s['SinifSubeId'] == sinifId).toList();
    if (hedef.length != 1) {
      throw StateError('Seçili sınıf güncel ders kapsamınızda değil.');
    }
    final kod = hedef.single['SinifKodu'] as String;
    final diger = rows
        .map((r) => r.degerler['sinif'] ?? '')
        .where(
          (s) => s.isNotEmpty && importNormalize(s) != importNormalize(kod),
        )
        .toSet();
    var tumu = false;
    if (diger.isNotEmpty) {
      if (!context.mounted) return null;
      ilerleme?.call(null);
      final secim = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: const Text('Diğer sınıflar da aktarılsın mı?'),
          content: Text(
            'Belge türü: ${rows.map((r) => r.degerler['tur'] ?? 'Program').toSet().join(', ')}\n'
            'Seçili sınıf: $kod\nBelgede ${diger.length} başka sınıf da var.\n\n'
            'Diğer sınıfları ve bu sınıfların ders öğretmenlerini de ön izlemeye dahil edeyim mi? '
            'Yalnız mevcut eğitim yılında ders kapsamınızdaki sınıflara ilişki eklenir. '
            'Yeni sınıf oluşturulmaz; ders saatleri değiştirilmez. Sonraki ekranda kayıtları seçip onaylayacaksınız.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('Yalnız $kod'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Diğer sınıfları da dahil et'),
            ),
          ],
        ),
      );
      if (secim == null || !context.mounted) return null;
      tumu = secim;
    }
    ilerleme?.call(
      ImportIlerleme(
        '${rows.length} kayıt doğrulanıyor; tekrarlar ve eğitim yılı kontrol ediliyor…',
      ),
    );
    return service.ogretmenProgramiOnIzleme(
      baglam,
      rows,
      sinifId: sinifId,
      digerSiniflar: tumu,
    );
  }
}
