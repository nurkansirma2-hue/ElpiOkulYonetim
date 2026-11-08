import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:elpi_okul_yonetim/models/dbf_belgesi.dart';

/// Yalnız test belleğindeki veritabanına, ders kapsamı belirli DBF ekler.
Future<void> gunlukPlanTestDbfEkle(
  Database db, {
  int dersId = 1,
  String dersAdi = 'Matematik',
  int surum = 1,
  bool ayrintili = true,
}) async {
  final belge = DbfBelgesi(
    dosyaAdi: 'ders-$dersId.pdf',
    dersAdi: dersAdi,
    sinifSeviyesi: 9,
    icerikOzeti: 'ders-$dersId-v$surum',
    surum: surum,
    sayfalar: [
      'DERS BİLGİ FORMU DERSİN ADI $dersAdi DERSİN SINIFI 9. Sınıf '
          'ÖĞRENME KANITLARI (Ölçme ve Değerlendirme) Kontrol listesi ile değerlendirme yapılır. '
          'ÖĞRENME-ÖĞRETME YAŞANTILARI Öğrenme Öğretme Uygulamaları '
          'Denklemler: Denklem çözer ve çözüm adımlarını açıklar. '
          'ÖĞRENME ÖĞRETME ORTAM VE DONANIMI Ders kitabı ve çalışma kâğıdı. '
          'ÖĞRENME BİRİMİ / MODÜL '
          'ÖĞRENME ÇIKTISI GRUBU VE AÇIKLAMALARI İÇERİK ÇERÇEVESİ '
          'Denklem çözüm adımları açıklanır. '
          'UYGULAMA FAALİYETLERİ / TEMRİNLER Denklemler: Denklem çözüm adımlarını yazmak. '
          'DERSİN UYGULANMASINA İLİŞKİN AÇIKLAMALAR '
          'Bu etkinliklerde soru cevap gibi yöntem ve teknikler kullanılabilir.',
    ],
  );
  final kaynak = ayrintili
      ? belge
      : DbfBelgesi(
          dosyaAdi: belge.dosyaAdi,
          dersAdi: dersAdi,
          sinifSeviyesi: 9,
          icerikOzeti: belge.icerikOzeti,
          surum: surum,
          sayfalar: const ['DERS BİLGİ FORMU'],
        );
  final key = 'dbf.v1.${jsonEncode(['okul-1', 1, '2026-2027', dersId, 9])}';
  await db.delete('UygulamaAyarlari', where: 'Anahtar = ?', whereArgs: [key]);
  await db.insert('UygulamaAyarlari', {
    'Anahtar': key,
    'Deger': jsonEncode(kaynak.toJson()),
    'GuncellemeTarihi': 'test',
  });
}
