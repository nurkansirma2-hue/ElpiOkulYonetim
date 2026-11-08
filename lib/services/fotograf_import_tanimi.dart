import 'package:flutter/material.dart';
import '../models/ortak_import.dart';
import '../screens/fotograf_import_hucre_secim_screen.dart';
import 'bireysel_import_service.dart';

class FotografImportTanimi {
  static const tanim = ImportTanimi(
    id: 'bireysel_fotograf',
    ad: 'Fotoğraf Import',
    aciklama:
        'Önce Öğrenci Import ile öğrencilerinizi yükleyin. Fotoğraflı e-Okul XLS dosyasındaki okul numarası ve ad soyad mevcut öğrencilerinizle eşleştirilir. Yalnız seçilen fotoğraflar eklenir veya güncellenir; öğrenci bilgileri korunur.',
    alanlar: [
      ImportAlan('okulNo', 'Okul No'),
      ImportAlan('adSoyad', 'Ad Soyad'),
      ImportAlan('sinif', 'Sınıf', filtrelenebilir: true, gruplanabilir: true),
    ],
    uzantilar: {'xls'},
    yalnizOzelOkuyucu: true,
    ozelOkuyucuAdi: 'Okul numarası ve ad soyad ile otomatik fotoğraf eşleştirme',
    ozelOku: BireyselImportService.ortakFotoOzelOku,
    hazirla: _kolonlariReddet,
    aktar: BireyselImportService.ortakFotograflariKaydet,
  );

  static Future<ImportOnIzleme> _kolonlariReddet(
    List<ImportKaynakSatiri> _,
  ) async => throw StateError('Fotoğraflı XLS okuyucusunu kullanın.');

  static Future<ImportOnIzleme?> onIzlemeyiHazirla(
    BuildContext context,
    ImportDosya dosya,
  ) => BireyselImportService.ortakFotoOzelOku(dosya);

  static Future<ImportOnIzleme?> hucrelerdenOnIzlemeyiHazirla(
    BuildContext context,
    ImportDosya dosya,
  ) async {
    final excel = await BireyselImportService.fotoExcelOku(dosya.bytes);
    final siniflar = await BireyselImportService.fotoImportSiniflariniGetir();
    if (!context.mounted) return null;
    return Navigator.of(context).push<ImportOnIzleme>(
      MaterialPageRoute(
        builder: (_) => FotografImportHucreSecimScreen(
          dosya: excel,
          siniflar: siniflar,
          onIzlemeyiHazirla: (sinifHucreleri) =>
              BireyselImportService.ortakFotoOzelOku(
                dosya,
                sinifHucreleri: sinifHucreleri,
              ),
        ),
      ),
    );
  }

  static Widget? gorsel(ImportOnIzleme preview, ImportKaydi row) {
    final data = preview.veri;
    if (data is! BireyselFotoOnIzleme) return null;
    final photos = data.kayitlar.where((p) => p.okulNo == row.id);
    if (photos.isEmpty) return null;
    return Image.memory(
      photos.first.fotoVerisi,
      width: 48,
      height: 64,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
    );
  }
}
