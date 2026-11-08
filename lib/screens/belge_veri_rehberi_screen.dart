import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';

import '../core/calisma_modu.dart';
import '../database/local_database.dart';
import '../services/calisma_modu_service.dart';
import '../services/bireysel_profil_service.dart';
import '../services/ogrenci_import_tanimi.dart';
import 'bireysel_ders_programi_import_screen.dart';
import 'bireysel_yillik_plan_import_screen.dart';
import 'ortak_import_screen.dart';

class BelgeVeriRehberiScreen extends StatefulWidget {
  const BelgeVeriRehberiScreen({super.key});
  @override
  State<BelgeVeriRehberiScreen> createState() => _BelgeVeriRehberiScreenState();
}

class _BelgeVeriRehberiScreenState extends State<BelgeVeriRehberiScreen> {
  Map<String, int>? _sayilar;
  String? _okul, _hata;
  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
        throw StateError('Rehber yalnız bireysel modda kullanılabilir.');
      }
      final profil = await BireyselProfilService.getir();
      if (profil == null) throw StateError('Öğretmen profilini tamamlayın.');
      final id = profil['OgretmenProfilId'], yil = profil['EgitimOgretimYili'];
      final db = await LocalDatabase.instance.database;
      final program = await db.rawQuery(
        '''SELECT COUNT(*) AS N FROM GecerliDersProgrami
        WHERE OgretmenProfilId = ? AND EgitimOgretimYili = ? AND Aktif = 1''',
        [id, yil],
      );
      final sinif = await db.rawQuery(
        '''SELECT COUNT(DISTINCT SinifSubeId) AS N FROM GecerliDersProgrami
        WHERE OgretmenProfilId = ? AND EgitimOgretimYili = ? AND Aktif = 1 AND SinifSubeId IS NOT NULL''',
        [id, yil],
      );
      final ogrenci = await db.rawQuery(
        '''SELECT COUNT(DISTINCT k.OgrenciId) AS N
        FROM OgrenciSinifKayit k JOIN Ogrenci o ON o.OgrenciId = k.OgrenciId
        WHERE k.Aktif = 1 AND o.Aktif = 1 AND k.EgitimOgretimYili = ?
        AND k.SinifSubeId IN (SELECT SinifSubeId FROM GecerliDersProgrami
          WHERE OgretmenProfilId = ? AND EgitimOgretimYili = ? AND Aktif = 1)''',
        [yil, id, yil],
      );
      final bos = await db.rawQuery(
        '''SELECT COUNT(DISTINCT p.SinifSubeId) AS N FROM GecerliDersProgrami p
        WHERE p.OgretmenProfilId = ? AND p.EgitimOgretimYili = ? AND p.Aktif = 1
        AND p.SinifSubeId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM OgrenciSinifKayit k
          JOIN Ogrenci o ON o.OgrenciId = k.OgrenciId WHERE k.SinifSubeId = p.SinifSubeId
          AND k.EgitimOgretimYili = p.EgitimOgretimYili AND k.Aktif = 1 AND o.Aktif = 1)''',
        [id, yil],
      );
      final plan = await db.rawQuery(
        '''SELECT COUNT(*) AS N FROM YillikPlan p
        WHERE p.OgretmenProfilId = ? AND p.EgitimOgretimYili = ? AND p.Aktif = 1
        AND EXISTS (SELECT 1 FROM YillikPlanDetay d WHERE d.YillikPlanId = p.YillikPlanId AND d.Aktif = 1)''',
        [id, yil],
      );
      if (!mounted) return;
      setState(() {
        _okul = '${profil['OkulAdi']} • $yil';
        _sayilar = {
          'program': program.single['N'] as int,
          'sinif': sinif.single['N'] as int,
          'ogrenci': ogrenci.single['N'] as int,
          'bos': bos.single['N'] as int,
          'plan': plan.single['N'] as int,
        };
        _hata = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Rehber hazırlanamadı.\nOrijinal hata: $e');
      }
    }
  }

  Future<void> _ac(Widget ekran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));
    if (mounted) _yukle();
  }

  Widget _bolum(String ad, String bilgi, {VoidCallback? onTap}) => Card(
    child: ListTile(
      title: Text(ad),
      subtitle: Text(bilgi),
      isThreeLine: false,
      trailing: onTap == null
          ? null
          : const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    ),
  );

  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: const ModulUstBar(title: Text('Veri Hazırlama Rehberi')),
    body: _hata != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_hata!),
            ),
          )
        : _sayilar == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(_okul!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text(
                'İstediğiniz bölümden başlayabilirsiniz. Sayılar cihazdaki gerçek kayıtlardan okunur; import geçmişi tamamlanmış veri anlamına gelmez.',
              ),
              _bolum(
                'Okul ve Öğretmen Bilgileri',
                'Aktif okul ve öğretmen profili var. Bu bilgiler arşivin veri ayrımını belirler.',
              ),
              _bolum(
                'Öğretmen, Ders ve Sınıflar',
                'Bireysel mod yalnız kendi profilinizi tutar. Dersler ve sınıflar ders programı aktarımıyla hazırlanır.',
              ),
              _bolum(
                'Ders Programı',
                '${_sayilar!['program']} aktif ders saati, ${_sayilar!['sinif']} sınıf. Gün, saat, ders, sınıf ve başlangıç tarihi kontrol edilir.',
                onTap: () => _ac(const BireyselDersProgramiImportScreen()),
              ),
              _bolum(
                'Öğrenci Listeleri',
                '${_sayilar!['ogrenci']} kayıtlı öğrenci. Öğrencisi bulunmayan ${_sayilar!['bos']} ders sınıfı var. Sınıf başına kişi sayısını ayrıca kontrol edin.',
                onTap: () => _ac(
                  const OrtakImportScreen(tanim: OgrenciImportTanimi.tanim),
                ),
              ),
              _bolum(
                'Yıllık Planlar',
                '${_sayilar!['plan']} planın en az bir detay kaydı var. Bu sayı bütün haftaların eksiksiz olduğu anlamına gelmez; ders ve hafta kapsamını kontrol edin.',
                onTap: () => _ac(const BireyselYillikPlanImportScreen()),
              ),
              _bolum(
                'BEP Belgeleri',
                'Belgelerim içinde BEP türüyle arşivleyebilirsiniz. BEP belgeleri doğrudan veritabanına aktarılmaz.',
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Import ekranında cihazdan veya Belgelerimden dosya seçebilir, gerekli alanları ve rehber Excel şablonunu görebilirsiniz.',
                ),
              ),
            ],
          ),
  );
}
