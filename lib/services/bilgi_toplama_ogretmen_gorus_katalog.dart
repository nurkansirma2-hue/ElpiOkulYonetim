part of 'bireysel_bilgi_toplama_service.dart';

/// Öğretmen görüşü ortak form kataloğunun bir şablonudur. Eski toplantı kayıtları
/// aynı yerde kalır; ikinci bir Google Form veya yanıt kopyası oluşturulmaz.
extension BilgiToplamaOgretmenGorusKatalog on BireyselBilgiToplamaService {
  BireyselRehberlikService get gorusKaynakService =>
      BireyselRehberlikService(databaseGetir: _db, modGetir: _mod);

  Future<List<Map<String, Object?>>> ogretmenGorusFormlari(
    BilgiToplamaOturumu b, {
    bool yalnizKayitli = true,
  }) => _islem(b, (tx) async {
    final rows = await tx.rawQuery(
      '''SELECT a.RehberlikAtamaId AS AtamaId,
      k.Id AS ToplantiId, k.Baslik, a.BaslangicTarihi, a.BitisTarihi,
      s.SinifKodu, s.Aktif AS SinifAktif
      FROM RehberlikAtama a JOIN RehberlikKayit k ON k.AtamaId=a.RehberlikAtamaId
      JOIN SinifSube s ON s.SinifSubeId=a.SinifSubeId
      WHERE a.OkulId=? AND a.OgretmenProfilId=? AND a.EgitimOgretimYili=?
      AND s.EgitimOgretimYili=? AND k.Tur='Toplanti' AND k.Hassas=0
      ORDER BY k.Id DESC''',
      [b.okulId, b.profilId, b.yil, b.yil],
    );
    final sonuc = <Map<String, Object?>>[];
    final bugun = DateTime.now().toIso8601String().substring(0, 10);
    for (final r in rows) {
      final key =
          'ogretmen_gorus_v1:${jsonEncode([b.okulId, b.profilId, b.yil, r['AtamaId'], r['ToplantiId']])}';
      final kayit = await tx.query(
        'UygulamaAyarlari',
        where: 'Anahtar=?',
        whereArgs: [key],
      );
      if (yalnizKayitli && kayit.isEmpty) continue;
      final form = kayit.isEmpty
          ? null
          : jsonDecode(kayit.single['Deger'] as String) as Map;
      final bitis = r['BitisTarihi'] as String?;
      sonuc.add({
        ...r,
        'Hazir': form?['sonuc'] != null,
        'Durum': (form?['yonetim'] as Map?)?['arsiv'] == true
            ? 'Arşiv'
            : (form?['yonetim'] as Map?)?['tamam'] == true
            ? 'Tamamlandı'
            : ((form?['sonuc'] as Map?)?['published'] != true &&
                  (form?['yonetim'] as Map?)?['acik'] != true)
            ? 'Taslak'
            : 'Yanıt bekleniyor',
        'YanitSayisi': (form?['yanitlar'] as List?)?.length,
        'YayinAcik':
            (form?['yonetim'] as Map?)?['acik'] ??
            (form?['sonuc'] as Map?)?['acceptingResponses'],
        'SonEsitleme': form?['sonEsitleme'],
        'SaltOkunur':
            r['SinifAktif'] != 1 ||
            (r['BaslangicTarihi'] as String).compareTo(bugun) > 0 ||
            (bitis != null && bitis.compareTo(bugun) < 0),
      });
    }
    return sonuc;
  });
}
