import 'package:flutter/material.dart';

import '../services/bireysel_dbf_service.dart';
import '../services/bireysel_gunluk_plan_service.dart';
import '../services/bireysel_yillik_plan_service.dart';
import 'bireysel_dbf_import_screen.dart';
import 'bireysel_gunluk_plan_screen.dart';
import 'bireysel_yillik_plan_import_screen.dart';

/// Yükleme ekranından dönmek yeterli sayılmaz; her kaynak tekrar okunur.
Future<void> bireyselGunlukPlanAc(
  BuildContext context, {
  required int ogretmenProfilId,
  required String egitimOgretimYili,
  required int dersId,
  required String dersAdi,
  required int sinifSeviyesi,
  required DateTime tarih,
  required String baslangicSinifKodu,
  bool Function()? secimGecerliMi,
}) async {
  Future<bool> planVar() async {
    final plan = await BireyselYillikPlanService.icerigiGetir(
      ogretmenProfilId: ogretmenProfilId,
      egitimOgretimYili: egitimOgretimYili,
      dersId: dersId,
      sinifSeviyesi: sinifSeviyesi,
    );
    return plan.detaylar.isNotEmpty;
  }

  Future<bool> dbfVar() async =>
      await BireyselDbfService.instance.getir(
        profilId: ogretmenProfilId,
        egitimYili: egitimOgretimYili,
        dersId: dersId,
        sinifSeviyesi: sinifSeviyesi,
      ) !=
      null;
  Future<void> ac(Widget screen) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => InheritedTheme.captureAll(context, screen),
    ),
  );
  bool gecerli() => context.mounted && (secimGecerliMi?.call() ?? true);
  Future<bool> eksikBelge(String ad) async {
    if (!gecerli()) return false;
    return await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('$ad eksik'),
                content: Text(
                  '$dersAdi • $baslangicSinifKodu • $egitimOgretimYili için $ad yükleyin.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Kapat'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Yükleme alanını aç'),
                  ),
                ],
              ),
            ) ==
            true &&
        gecerli();
  }

  try {
    final kayitli = await BireyselGunlukPlanService.kayitliHaftayiGetir(
      ogretmenProfilId: ogretmenProfilId,
      egitimOgretimYili: egitimOgretimYili,
      dersId: dersId,
      sinifSeviyesi: sinifSeviyesi,
      sinifKodu: baslangicSinifKodu,
      tarih: tarih,
    );
    if (!gecerli()) return;
    if (kayitli == null && !await planVar()) {
      if (!await eksikBelge('Yıllık plan')) return;
      if (!gecerli()) return;
      await ac(
        BireyselYillikPlanImportScreen(
          baslangicDersId: dersId,
          baslangicSinifSeviyesi: sinifSeviyesi,
          kaydedinceDon: true,
        ),
      );
      if (!gecerli() || !await planVar()) return;
    }
    if (!gecerli()) return;
    if (kayitli == null && !await dbfVar()) {
      if (!await eksikBelge('Ders bilgi formu')) return;
      if (!gecerli()) return;
      await ac(
        BireyselDbfImportScreen(
          profilId: ogretmenProfilId,
          egitimYili: egitimOgretimYili,
          dersId: dersId,
          dersAdi: dersAdi,
          sinifSeviyesi: sinifSeviyesi,
          kaydedinceDon: true,
        ),
      );
      if (!gecerli() || !await dbfVar()) return;
    }
    // Yükleme sırasında öğretmen/yıl veya yıllık plan değişmiş olabilir.
    if (!gecerli() || (kayitli == null && !await planVar())) return;
    if (!gecerli()) return;
    await ac(
      BireyselGunlukPlanScreen(
        ogretmenProfilId: ogretmenProfilId,
        egitimOgretimYili: egitimOgretimYili,
        dersId: dersId,
        dersAdi: dersAdi,
        sinifSeviyesi: sinifSeviyesi,
        tarih: tarih,
        baslangicSinifKodu: baslangicSinifKodu,
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Günlük plan için belgeler kontrol edilemedi.\nOrijinal hata: $e',
          ),
        ),
      );
    }
  }
}
