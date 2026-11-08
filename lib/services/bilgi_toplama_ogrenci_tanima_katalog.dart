part of 'bireysel_bilgi_toplama_service.dart';

/// Sınıf tanıma formu kendi soru eşleştirmeleri ve onay geçmişiyle kataloglanır.
/// Yeniden form oluşturulmaz; aynı sınıf/yılın eski atamasındaki form da bulunur.
extension BilgiToplamaOgrenciTanimaKatalog on BireyselBilgiToplamaService {
  Future<List<Map<String, Object?>>> ogrenciTanimaFormlari(
    BilgiToplamaOturumu b, {
    bool yalnizKayitli = true,
  }) => _islem(b, (tx) async {
    final bugun = DateTime.now().toIso8601String().substring(0, 10);
    final atamalar = await tx.rawQuery(
      '''SELECT a.*,s.SinifKodu,s.Aktif AS SinifAktif
      FROM RehberlikAtama a JOIN SinifSube s ON s.SinifSubeId=a.SinifSubeId
      WHERE a.OkulId=? AND a.OgretmenProfilId=? AND a.EgitimOgretimYili=? AND s.EgitimOgretimYili=?
      ORDER BY CASE WHEN a.BaslangicTarihi<=? AND (a.BitisTarihi IS NULL OR a.BitisTarihi>=?) THEN 0 ELSE 1 END,a.BaslangicTarihi DESC,a.RehberlikAtamaId DESC''',
      [b.okulId, b.profilId, b.yil, b.yil, bugun, bugun],
    );
    final siniflar = <int>{}, sonuc = <Map<String, Object?>>[];

    for (final a in atamalar) {
      final sinif = a['SinifSubeId'] as int;
      if (!siniflar.add(sinif)) continue;
      final ff = await tx.rawQuery(
        '''SELECT f.* FROM RehberlikGoogleForm f
        JOIN RehberlikAtama a ON a.RehberlikAtamaId=f.AtamaId
        WHERE a.OkulId=? AND a.OgretmenProfilId=? AND a.EgitimOgretimYili=? AND a.SinifSubeId=?''',
        [b.okulId, b.profilId, b.yil, sinif],
      );
      if (ff.length > 1) {
        throw StateError(
          'Sınıfın birden fazla tanıma formu var. Mevcut kayıtlar korunarak işlem durduruldu.',
        );
      }
      if (yalnizKayitli && ff.isEmpty) continue;
      final f = ff.firstOrNull;
      final yy = f == null
          ? <Map<String, Object?>>[]
          : await tx.query(
              'RehberlikGoogleYanit',
              where: 'FormId=?',
              whereArgs: [f['Id']],
            );
      final bitis = a['BitisTarihi'] as String?;
      sonuc.add({
        'AtamaId': a['RehberlikAtamaId'],
        'SinifSubeId': sinif,
        'SinifKodu': a['SinifKodu'],
        'FormId': f?['Id'],
        'GoogleFormId': f?['GoogleFormId'],
        'Durum': f?['Durum'] == 'Aktif' ? 'Yanıt bekleniyor' : 'Taslak',
        'Onaylanan': yy
            .where((y) => y['Durum'] == 'Onaylandi')
            .map((y) => y['GoogleYanitId'])
            .toSet()
            .length,
        'SaltOkunur':
            a['SinifAktif'] != 1 ||
            (a['BaslangicTarihi'] as String).compareTo(bugun) > 0 ||
            (bitis != null && bitis.compareTo(bugun) < 0),
      });
    }
    return sonuc;
  });
}
