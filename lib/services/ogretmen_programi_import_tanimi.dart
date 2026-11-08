import '../models/mesajlasma.dart';
import '../models/ortak_import.dart';
import 'mesajlasma_service.dart';
import 'program_belgesi_okuyucu.dart';

class OgretmenProgramiImportTanimi {
  static ImportTanimi olustur(
    MesajlasmaService service,
    MesajBaglami baglam,
    int sinifId, {
    Future<List<ImportKaynakSatiri>> Function(ImportDosya)? pdfOku,
  }) => ImportTanimi(
    id: 'mesaj_ogretmen_programi',
    ad: 'Programdan öğretmen aktar',
    aciklama:
        'PDF, Word veya Excel içindeki öğretmen ya da sınıf programını otomatik tanıyıp aktarın. '
        'Ön izlemede adları, sınıfı ve eğitim yılını doğrulayın. Aynı adlı farklı kişileri ayırt edin. '
        'Bu işlem ders saatlerinizi değiştirmez; öğretmen-sınıf ilişkilerini kaydeder.',
    uzantilar: ProgramBelgesiOkuyucu.uzantilar,
    yalnizOzelOkuyucu: true,
    ozelOkuyucuAdi:
        'Otomatik program tanıma • öğretmen / sınıf • bütün sayfalar',
    alanlar: const [
      ImportAlan(
        'ogretmen',
        'Öğretmen',
        zorunlu: true,
        filtrelenebilir: true,
        gruplanabilir: true,
      ),
      ImportAlan('sinif', 'Sınıf', zorunlu: true, filtrelenebilir: true),
      ImportAlan('dersler', 'Dersler (her satıra bir ders)'),
      ImportAlan('yil', 'Eğitim yılı', kolondan: false),
      ImportAlan('tur', 'Belge türü', kolondan: false),
    ],
    hazirla: (rows) =>
        service.ogretmenProgramiOnIzleme(baglam, rows, sinifId: sinifId),
    ozelOku: (dosya) async => service.ogretmenProgramiOnIzleme(
      baglam,
      await (pdfOku ?? ProgramBelgesiOkuyucu.oku)(dosya),
      sinifId: sinifId,
    ),
    duzenlemeHazirla: (onceki, rows) =>
        service.ogretmenProgramiDuzenle(baglam, onceki, rows),
    aktar: (p, secimler) => service.ogretmenProgramiAktar(baglam, p, secimler),
  );
}
