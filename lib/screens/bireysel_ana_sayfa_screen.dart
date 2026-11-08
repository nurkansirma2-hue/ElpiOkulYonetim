import '../widgets/ortak_ui.dart';
import 'dart:typed_data';
import '../core/calisma_modu.dart';
import '../services/bireysel_odev_kontrol_service.dart';
import 'performans_not_screen.dart';
import 'rapor_olustur_screen.dart';
import 'test_modulu_screen.dart';

import 'package:flutter/material.dart';
import '../widgets/ana_sayfa_gorunumu.dart';
import '../widgets/modul_ust_bar.dart';
import '../widgets/ogrenci_foto_widget.dart';

import 'bireysel_ders_programim_screen.dart';
import 'bireysel_ders_programi_import_screen.dart';
import 'bireysel_kurulum_screen.dart';
import 'bireysel_yonetim_paneli_screen.dart';
import 'okul_temel_bilgileri_screen.dart';
import 'odev_kontrol_screen.dart';
import 'bireysel_yillik_planlarim_screen.dart';
import 'bireysel_seflik_yillik_plan_screen.dart';
import 'bireysel_belgelerim_screen.dart';
import 'bireysel_gunluk_plan_akisi.dart';
import 'mesajlasma_screen.dart';
import 'import_merkezi_screen.dart';
import 'bireysel_rehberlik_screen.dart';
import 'bireysel_ogrenci_islemleri_screen.dart';
import '../database/local_database.dart';
import '../services/bireysel_ders_programi_service.dart';
import '../services/bireysel_profil_service.dart';
import '../services/bireysel_yillik_plan_service.dart';

class BireyselAnaSayfaScreen extends StatefulWidget {
  const BireyselAnaSayfaScreen({
    super.key,
    this.onDersProgrami,
    this.onYillikPlan,
  });

  final VoidCallback? onDersProgrami;
  final VoidCallback? onYillikPlan;

  @override
  State<BireyselAnaSayfaScreen> createState() => _BireyselAnaSayfaScreenState();
}

class _BireyselAnaSayfaScreenState extends State<BireyselAnaSayfaScreen>
    with AnaSayfaGorunumTercihi<BireyselAnaSayfaScreen> {
  final TextEditingController _aramaController = TextEditingController();
  final ScrollController _anaSayfaScroll = ScrollController();
  final FocusNode _aramaOdak = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );

  Map<String, dynamic>? _profil;
  List<Map<String, dynamic>> _tumOgrenciler = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _filtreliOgrenciler = <Map<String, dynamic>>[];

  bool _yukleniyor = true;
  bool _gunlukDersYukleniyor = false;
  bool _gunlukPlanAciliyor = false;
  bool _aramaYapiliyor = false;
  bool _aramaAcik = false;
  bool _aramaElleOdak = false;
  bool _notHesaplamaAciliyor = false;
  bool _rehberGoster = true;
  int _kurulumAdimi = 0;
  int _eksikPlanSayisi = 0;

  DateTime _seciliTarih = DateTime.now();
  BireyselBugunDersDurumu? _gunlukDurum;
  int _aktifDersIndex = 0;
  String _dersDurumMesaji = '';
  IconData _dersDurumIcon = Icons.menu_book;

  @override
  void initState() {
    super.initState();
    _aramaOdak.addListener(_aramaOdagiDegisti);
    gorunumTercihiniYukle();
    ModulUstBarBaglantisi.aktif = ModulUstBarBaglantisi(
      sahip: this,
      renk: () => anaSayfaTema.colorScheme.primary,
      tema: () => anaSayfaTema,
      ayarlar: () => ayarlariAc(
        onOkulBilgileri: _okulBilgileriniAc,
        onYonetimBakim: _yonetimPaneliniAc,
      ),
      profil: _profilimiAc,
      bildirimler: _bildirimleriAc,
    );
    _sayfayiYukle();
  }

  @override
  void dispose() {
    if (identical(ModulUstBarBaglantisi.aktif?.sahip, this)) {
      ModulUstBarBaglantisi.aktif = null;
    }
    _aramaOdak.removeListener(_aramaOdagiDegisti);
    _aramaOdak.dispose();
    _aramaController.dispose();
    _anaSayfaScroll.dispose();
    super.dispose();
  }

  Future<void> _sayfayiYukle() async {
    if (mounted) {
      setState(() {
        _yukleniyor = true;
      });
    }

    try {
      final profil = await BireyselProfilService.getir();

      if (!mounted) {
        return;
      }

      setState(() {
        _profil = profil;
      });

      await _kurulumDurumunuGetir();
      await _ogrencileriYukle();
      await _gunlukDurumuGetir();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _mesajGoster(
        'Bireysel öğretmen ana sayfası yüklenirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _yukleniyor = false;
        });
      }
    }
  }

  Future<void> _kurulumDurumunuGetir() async {
    // Tamamlanma bilgisi tutulmaz; sıfırlama sonrası kayıtlar yeniden kontrol edilir.
    _kurulumAdimi = 0;
    _eksikPlanSayisi = 0;
    final profilId = _profil?['OgretmenProfilId'] as int?;
    final yil = (_profil?['EgitimOgretimYili'] ?? '').toString().trim();
    if (profilId == null || profilId <= 0 || yil.isEmpty) return;

    final program = await BireyselDersProgramiService.haftalikProgramiGetir(
      ogretmenProfilId: profilId,
      egitimOgretimYili: yil,
    );
    if (!mounted) return;
    if (program.isEmpty) {
      _kurulumAdimi = 1;
      return;
    }

    final db = await LocalDatabase.instance.database;
    final eksikler = await db.rawQuery(
      '''
      SELECT DISTINCT d.DersId, s.SinifSeviyesi
      FROM GecerliDersProgrami dp
      INNER JOIN Ders d ON d.DersId = dp.DersId
      INNER JOIN SinifSube s ON s.SinifSubeId = dp.SinifSubeId
      WHERE dp.OgretmenProfilId = ? AND dp.EgitimOgretimYili = ?
        AND dp.Aktif = 1 AND d.Aktif = 1 AND s.Aktif = 1
        AND s.SinifSeviyesi > 0
        AND NOT EXISTS (
          SELECT 1 FROM YillikPlan yp
          WHERE yp.YillikPlanId = (
            SELECT MAX(yp2.YillikPlanId) FROM YillikPlan yp2
            WHERE yp2.OgretmenProfilId = dp.OgretmenProfilId
              AND yp2.EgitimOgretimYili IN (?, ?)
              AND yp2.DersId = d.DersId
              AND yp2.SinifSeviyesi = s.SinifSeviyesi AND yp2.Aktif = 1
          )
          AND EXISTS (
            SELECT 1 FROM YillikPlanDetay ypd
            WHERE ypd.YillikPlanId = yp.YillikPlanId AND ypd.Aktif = 1
          )
        )
      ''',
      [
        profilId,
        yil,
        yil,
        BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(yil),
      ],
    );
    if (!mounted) return;
    _eksikPlanSayisi = eksikler.length;
    _kurulumAdimi = eksikler.isEmpty ? 0 : 2;
  }

  Future<void> _ogrencileriYukle() async {
    final profil = _profil;

    if (profil == null) {
      if (mounted) {
        setState(() {
          _tumOgrenciler = <Map<String, dynamic>>[];
          _filtreliOgrenciler = <Map<String, dynamic>>[];
        });
      }
      return;
    }

    final yil = (profil['EgitimOgretimYili'] ?? '').toString().trim();

    if (yil.isEmpty) {
      return;
    }

    try {
      final db = await LocalDatabase.instance.database;

      final sonuc = await db.rawQuery(
        '''
        SELECT
          o.OgrenciId,
          o.OkulNo,
          o.Ad,
          o.Soyad,
          s.SinifKodu,
          s.Alan,
          f.FotoVerisi,
          f.DosyaYolu
        FROM Ogrenci o
        LEFT JOIN OgrenciFotograf f ON f.OgrenciId = o.OgrenciId AND f.Aktif = 1
        INNER JOIN OgrenciSinifKayit osk
          ON osk.OgrenciId = o.OgrenciId
          AND osk.EgitimOgretimYili = ?
          AND osk.Aktif = 1
        INNER JOIN SinifSube s
          ON s.SinifSubeId = osk.SinifSubeId
          AND s.Aktif = 1
        WHERE o.Aktif = 1 AND s.EgitimOgretimYili = ?
          AND EXISTS (
            SELECT 1 FROM GecerliDersProgrami dp
            WHERE dp.SinifSubeId = s.SinifSubeId AND dp.OgretmenProfilId = ?
              AND dp.EgitimOgretimYili = ? AND dp.Aktif = 1
          )
        ORDER BY o.Ad, o.Soyad
        ''',
        [yil, yil, profil['OgretmenProfilId'], yil],
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _tumOgrenciler = sonuc
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _filtreliOgrenciler = <Map<String, dynamic>>[];
      });
    } catch (e) {
      throw Exception(
        'Bireysel öğrenci listesi SQLite veritabanından okunurken '
        'hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  Future<void> _gunlukDurumuGetir() async {
    final profil = _profil;

    if (profil == null) {
      if (mounted) {
        setState(() {
          _gunlukDurum = null;
          _aktifDersIndex = 0;
          _gunlukDersYukleniyor = false;
        });
      }
      return;
    }

    final profilId = profil['OgretmenProfilId'] as int?;
    final yil = (profil['EgitimOgretimYili'] ?? '').toString().trim();

    if (profilId == null || profilId <= 0 || yil.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _gunlukDersYukleniyor = true;
      });
    }

    final istenenTarih = _seciliTarih;
    try {
      final durum = await BireyselDersProgramiService.bugununDurumunuGetir(
        ogretmenProfilId: profilId,
        egitimOgretimYili: yil,
        tarih: istenenTarih,
      );

      if (!mounted || !DateUtils.isSameDay(istenenTarih, _seciliTarih)) {
        return;
      }

      setState(() {
        _gunlukDurum = durum;
        _aktifDersIndex = _aktifDersiBul(durum);
        _gunlukDersYukleniyor = false;
      });
    } catch (e) {
      if (!mounted || !DateUtils.isSameDay(istenenTarih, _seciliTarih)) {
        return;
      }

      setState(() {
        _gunlukDurum = null;
        _aktifDersIndex = 0;
        _gunlukDersYukleniyor = false;
      });

      _mesajGoster(
        'Günlük ders akışı yüklenirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  int _aktifDersiBul(BireyselBugunDersDurumu durum) {
    final dersler = durum.dersler;

    if (dersler.isEmpty) {
      _dersDurumMesaji = '';

      _dersDurumIcon = Icons.info_outline;
      return 0;
    }

    if (!_bugunMu(_seciliTarih)) {
      _dersDurumMesaji = 'Seçili günün ders akışı';

      _dersDurumIcon = Icons.calendar_month;
      return 0;
    }

    final now = TimeOfDay.now();
    final simdiDakika = _saatDakika(now);

    for (int i = 0; i < dersler.length; i++) {
      final baslangic = _saatParse(dersler[i].baslangic);
      final bitis = _saatParse(dersler[i].bitis);

      if (baslangic == null || bitis == null) {
        continue;
      }

      final basDakika = _saatDakika(baslangic);
      final bitDakika = _saatDakika(bitis);

      if (simdiDakika >= basDakika && simdiDakika < bitDakika) {
        _dersDurumMesaji = dersler[i].gorevMi
            ? dersler[i].seflikMi
                  ? 'Şu an şeflik görevin var'
                  : 'Şu an koordinatörlük görevin var'
            : 'Şu an dersin var';

        _dersDurumIcon = Icons.play_circle_fill;
        return i;
      }
    }

    for (int i = 0; i < dersler.length; i++) {
      final baslangic = _saatParse(dersler[i].baslangic);

      if (baslangic == null) {
        continue;
      }

      if (_saatDakika(baslangic) > simdiDakika) {
        _dersDurumMesaji = 'Şu an ders yok • Sıradaki ders';

        _dersDurumIcon = Icons.schedule;
        return i;
      }
    }

    _dersDurumMesaji = 'Bugünkü derslerin tamamlandı';

    _dersDurumIcon = Icons.check_circle;
    return dersler.length - 1;
  }

  Future<void> _oncekiGuneGit() async {
    setState(() {
      _seciliTarih = _seciliTarih.subtract(const Duration(days: 1));
      _aktifDersIndex = 0;
    });

    await _gunlukDurumuGetir();
  }

  Future<void> _sonrakiGuneGit() async {
    setState(() {
      _seciliTarih = _seciliTarih.add(const Duration(days: 1));
      _aktifDersIndex = 0;
    });

    await _gunlukDurumuGetir();
  }

  Future<void> _buguneDon() async {
    setState(() {
      _seciliTarih = DateTime.now();
      _aktifDersIndex = 0;
    });

    await _gunlukDurumuGetir();
  }

  Future<void> _tarihSec() async {
    final tarih = await showDatePicker(
      context: context,
      initialDate: _seciliTarih,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (tarih == null || !mounted ||
        DateUtils.isSameDay(tarih, _seciliTarih)) return;
    setState(() {
      _seciliTarih = tarih;
      _aktifDersIndex = 0;
    });
    await _gunlukDurumuGetir();
  }

  Future<void> _dersPrograminiAc() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _kurulumAdimi == 1
            ? const BireyselDersProgramiImportScreen()
            : const BireyselDersProgramimScreen(),
      ),
    );

    if (mounted) {
      await _sayfayiYukle();
    }
  }

  Future<void> _yillikPlanlariAc() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BireyselYillikPlanlarimScreen()),
    );

    if (mounted) {
      await _sayfayiYukle();
    }
  }

  Future<void> _ogrencileriAc() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BireyselOgrenciIslemleriScreen()),
    );
    if (mounted) {
      await _sayfayiYukle();
      if (mounted) _filtrele(_aramaController.text);
    }
  }

  Future<void> _yonetimPaneliniAc() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BireyselYonetimPaneliScreen(
          onSifirlandi: () {
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (kurulumContext) => PopScope(
                  canPop: false,
                  child: BireyselKurulumScreen(
                    onTamamlandi: () async {
                      if (!kurulumContext.mounted) return;
                      Navigator.of(kurulumContext).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const BireyselAnaSayfaScreen(),
                        ),
                        (_) => false,
                      );
                    },
                  ),
                ),
              ),
              (_) => false,
            );
          },
        ),
      ),
    );
    if (mounted) {
      await _sayfayiYukle();
      if (mounted) _filtrele(_aramaController.text);
    }
  }

  Future<void> _okulBilgileriniAc() async {
    final kaydedildi = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            Theme(data: anaSayfaTema, child: const OkulTemelBilgileriScreen()),
      ),
    );
    if (mounted && kaydedildi == true) {
      await _sayfayiYukle();
      if (mounted) _filtrele(_aramaController.text);
    }
  }

  void _filtrele(String arama) {
    final metin = arama.trim();

    if (metin.isEmpty) {
      setState(() {
        _aramaYapiliyor = false;
        _filtreliOgrenciler = <Map<String, dynamic>>[];
      });
      return;
    }

    final sorgu = _normalize(metin);

    final sonuc = _tumOgrenciler
        .where((ogrenci) {
          final ad = _normalize((ogrenci['Ad'] ?? '').toString());
          final soyad = _normalize((ogrenci['Soyad'] ?? '').toString());
          final adSoyad = _normalize('$ad $soyad');
          final okulNo = _normalize((ogrenci['OkulNo'] ?? '').toString());
          final sinif = _normalize((ogrenci['SinifKodu'] ?? '').toString());
          final alan = _normalize((ogrenci['Alan'] ?? '').toString());

          return ad.contains(sorgu) ||
              soyad.contains(sorgu) ||
              adSoyad.contains(sorgu) ||
              okulNo.contains(sorgu) ||
              sinif.contains(sorgu) ||
              alan.contains(sorgu);
        })
        .toList(growable: false);

    setState(() {
      _aramaYapiliyor = true;
      _filtreliOgrenciler = sonuc;
    });
  }

  void _mesajGoster(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj)));
  }

  Future<void> _profilimiAc() async {
    final kaydedildi = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (profilContext) => Theme(
          data: anaSayfaTema,
          child: BireyselKurulumScreen(
            duzenleme: true,
            onTamamlandi: () async {
              if (profilContext.mounted) Navigator.of(profilContext).pop(true);
            },
          ),
        ),
      ),
    );
    if (mounted && kaydedildi == true) await _sayfayiYukle();
  }

  Future<void> _notHesaplamayiAc() async {
    if (_notHesaplamaAciliyor || _yukleniyor) return;
    setState(() => _notHesaplamaAciliyor = true);
    try {
      final oturum = await BireyselOdevKontrolService.hazirla();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PerformansNotScreen(oturum: oturum)),
      );
    } catch (e) {
      if (mounted) _mesajGoster('Not hesaplama açılamadı. Orijinal hata: $e');
    } finally {
      if (mounted) setState(() => _notHesaplamaAciliyor = false);
    }
  }

  void _aramaOdagiDegisti() {
    if (!_aramaOdak.hasFocus && _aramaElleOdak) {
      _aramaOdak.canRequestFocus = false;
      if (mounted) setState(() => _aramaElleOdak = false);
    }
  }

  void _aramayiAc() {
    _aramaOdak.canRequestFocus = true;
    _aramaOdak.requestFocus();
    setState(() {
      _aramaAcik = true;
      _aramaElleOdak = true;
    });
  }

  void _aramayiKapat() {
    FocusScope.of(context).unfocus();
    _aramaController.clear();
    _filtrele('');
    setState(() => _aramaAcik = false);
    if (_anaSayfaScroll.hasClients) _anaSayfaScroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_aramaAcik && _anaSayfaScroll.hasClients) {
        _anaSayfaScroll.jumpTo(0);
      }
    });
  }

  Future<void> _bildirimleriAc() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (c) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Bildirimler',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Icon(Icons.notifications_none, size: 40),
          const SizedBox(height: 12),
          const Text('Henüz bildirim yok.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => temaIleGoster(
    (context) => PopScope(
      canPop: !_aramaAcik,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _aramaAcik) _aramayiKapat();
      },
      child: OrtakSayfa(
        backgroundColor: this.anaSayfaZemin,
        appBar: AnaSayfaUstBar(
          context: context,
          modAdi: '${CalismaModu.bireyselOgretmen.baslik} Modu',
          geri: _aramaAcik
              ? IconButton(
                  tooltip: 'Ana sayfaya dön',
                  onPressed: _aramayiKapat,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          islemler: [
            AnaSayfaBildirimSimgesi(onPressed: _bildirimleriAc),
            PopupMenuButton<String>(
              tooltip: 'Diğer işlemler',
              onSelected: (v) async {
                switch (v) {
                  case 'ayarlar':
                    await ayarlariAc(
                      onOkulBilgileri: _okulBilgileriniAc,
                      onYonetimBakim: _yonetimPaneliniAc,
                    );
                  case 'profil':
                    await _profilimiAc();
                  case 'arama':
                    _aramayiAc();
                  case 'yenile':
                    await _sayfayiYukle();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'ayarlar',
                  enabled: !_yukleniyor,
                  child: const ListTile(
                    dense: true,
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Ayarlar'),
                  ),
                ),
                PopupMenuItem(
                  value: 'profil',
                  enabled: !_yukleniyor,
                  child: const ListTile(
                    dense: true,
                    leading: Icon(Icons.person_outline),
                    title: Text('Profilim'),
                  ),
                ),
              ],
            ),
          ],
        ),
        bottomNavigationBar: _aramaAcik ? null : _anaGezinmeCubugu(),
        body: _yukleniyor
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                top: false,
                child: Column(
                  children: [
                    if (_aramaAcik) ...[
                      if (_aramaYapiliyor)
                        _aramaSonuclari()
                      else
                        const Expanded(
                          child: Center(
                            child: Text(
                              'Öğrenci adı, okul numarası veya sınıf arayın.',
                            ),
                          ),
                        ),
                    ] else
                      Expanded(
                        child: ListView(
                          controller: _anaSayfaScroll,
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            _profilVeTarihKarti(),
                            _gunlukDersKarti(context),
                            _aramaKutusu(),
                            _menu(context),
                            _duyuruKarti(),
                          ],
                        ),
                      ),
                    if (_aramaAcik) _aramaKutusu(),
                  ],
                ),
              ),
      ),
    ),
  );

  Widget _gunlukDersKarti(BuildContext context) {
    if (_gunlukDersYukleniyor) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: this.anaSayfaPastel,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Ders akışı yükleniyor...'),
          ],
        ),
      );
    }

    final durum = _gunlukDurum;

    if (durum == null) {
      return _bosGunKarti(mesaj: 'Ders ve çalışma takvimi bilgisi okunamadı.');
    }

    if (durum.haftaSonu) {
      return _bosGunKarti(mesaj: 'Hafta sonu. Bu tarihte ders yok.');
    }

    if (durum.calismaTakvimiVarMi &&
        durum.tarihTakvimdeVarMi &&
        !durum.calismaVarMi) {
      final aciklama = durum.takvimAciklamasi.isNotEmpty
          ? durum.takvimAciklamasi
          : 'Çalışma takvimine göre bu tarihte ders yok.';

      return _bosGunKarti(mesaj: aciklama, ekAciklama: durum.ozelGunAciklamasi);
    }

    if (durum.dersler.isEmpty) {
      String mesaj;

      if (!durum.calismaTakvimiVarMi) {
        mesaj =
            'Çalışma takvimi yüklenmemiş ve bu tarihte ders programı '
            'bulunamadı.';
      } else if (!durum.tarihTakvimdeVarMi) {
        mesaj =
            'Bu tarih çalışma takviminde bulunamadı ve ders programı '
            'kaydı yok.';
      } else {
        mesaj = 'Bu tarihte ders programı bulunamadı.';
      }

      return _bosGunKarti(mesaj: mesaj);
    }

    if (_aktifDersIndex < 0 || _aktifDersIndex >= durum.dersler.length) {
      _aktifDersIndex = 0;
    }

    final ders = durum.dersler[_aktifDersIndex];
    final baslangic = _saatKisalt(ders.baslangic);
    final bitis = _saatKisalt(ders.bitis);
    final adSoyad = (_profil?['AdSoyad'] ?? '').toString().trim();

    String takvimUyarisi = '';

    if (!durum.calismaTakvimiVarMi) {
      takvimUyarisi = 'Çalışma takvimi yüklenmemiş';
    } else if (!durum.tarihTakvimdeVarMi) {
      takvimUyarisi = 'Seçili tarih çalışma takviminde bulunamadı';
    }

    final profilId = _profil?['OgretmenProfilId'] as int?;
    final yil = (_profil?['EgitimOgretimYili'] ?? '').toString().trim();
    final sinifSeviyesi = ders.sinifSeviyesi;
    final kartAcilabilir =
        !ders.gorevMi &&
        ders.dersId > 0 &&
        sinifSeviyesi != null &&
        sinifSeviyesi > 0 &&
        profilId != null &&
        profilId > 0 &&
        yil.isNotEmpty;

    return GunlukDersGorunumu(
      acik: derslerAcik,
      onToggle: dersleriDaraltGenislet,
      tarih: _tarihYazi(_seciliTarih),
      bugun: _bugunMu(_seciliTarih),
      oncekiGun: _oncekiGuneGit,
      sonrakiGun: _sonrakiGuneGit,
      buguneDon: _buguneDon,
      onTarihSec: _tarihSec,
      dersAdi: ders.dersAdi,
      sinif: ders.sinif,
      konu: ders.konu,
      konuGoster: true,
      onYillikPlan: widget.onYillikPlan ?? _yillikPlanlariAc,
      gunlukPlanYukleniyor: _gunlukPlanAciliyor,
      gorevMi: ders.gorevMi,
      gunlukPlanMenusu: true,
      onGunlukPlan: kartAcilabilir && !_gunlukPlanAciliyor
          ? () async {
              if (_gunlukPlanAciliyor) return;
              setState(() => _gunlukPlanAciliyor = true);
              try {
                await bireyselGunlukPlanAc(
                  context,
                  ogretmenProfilId: profilId,
                  egitimOgretimYili: yil,
                  dersId: ders.dersId,
                  dersAdi: ders.dersAdi,
                  sinifSeviyesi: sinifSeviyesi,
                  tarih: durum.tarih,
                  baslangicSinifKodu: ders.sinif,
                  secimGecerliMi: () =>
                      mounted &&
                      _gunlukDurum == durum &&
                      _aktifDersIndex < durum.dersler.length &&
                      identical(durum.dersler[_aktifDersIndex], ders) &&
                      DateUtils.isSameDay(_seciliTarih, durum.tarih),
                );
              } finally {
                if (mounted) setState(() => _gunlukPlanAciliyor = false);
              }
            }
          : null,
      ogretmen: adSoyad,
      derslik: ders.derslik,
      uyari: takvimUyarisi,
      saat: '$baslangic - $bitis',
      durum: _dersDurumMesaji,
      durumIcon: _dersDurumIcon,
      sira: '${_aktifDersIndex + 1}/${durum.dersler.length}',
      oncekiDers: _aktifDersIndex > 0
          ? () => setState(() => _aktifDersIndex--)
          : null,
      sonrakiDers: _aktifDersIndex < durum.dersler.length - 1
          ? () => setState(() => _aktifDersIndex++)
          : null,
    );
  }

  Widget _sonrakiDersKarti(BuildContext context) {
    final durum = _gunlukDurum;
    if (durum == null || durum.dersler.isEmpty ||
        _aktifDersIndex >= durum.dersler.length - 1) {
      return const SizedBox.shrink();
    }
    final sonraki = durum.dersler[_aktifDersIndex + 1];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.skip_next_outlined),
          title: const Text('Sonraki Dersim'),
          subtitle: Text(
            '${sonraki.dersAdi} • ${sonraki.sinif}\n'
            '${_saatKisalt(sonraki.baslangic)}–${_saatKisalt(sonraki.bitis)}'
            '${sonraki.konu.isEmpty ? '' : ' • ${sonraki.konu}'}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _aktifDersIndex++),
        ),
      ),
    );
  }

  Widget _bosGunKarti({required String mesaj, String ekAciklama = ''}) =>
      GunlukDersGorunumu(
        acik: derslerAcik,
        onToggle: dersleriDaraltGenislet,
        tarih: _tarihYazi(_seciliTarih),
        bugun: _bugunMu(_seciliTarih),
        oncekiGun: _oncekiGuneGit,
        sonrakiGun: _sonrakiGuneGit,
        buguneDon: _buguneDon,
        onTarihSec: _tarihSec,
        dersAdi: '',
        sinif: '',
        saat: '',
        konu: '',
        durum: '',
        durumIcon: Icons.event_busy,
        sira: '',
        bosMesaji: mesaj,
        uyari: ekAciklama,
      );

  Widget _aramaKutusu() => OrtakIslemCubugu(
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('sabit-ogrenci-arama'),
            controller: _aramaController,
            focusNode: _aramaOdak,
            canRequestFocus: _aramaElleOdak,
            onTapOutside: (_) => _aramaOdak.unfocus(),
            onTap: _aramayiAc,
            onChanged: _filtrele,
            decoration: InputDecoration(
              hintText: 'Öğrenci ara',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _aramaController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Temizle',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _aramaController.clear();
                        _filtrele('');
                      },
                    )
                  : null,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Yenile',
          onPressed: _yukleniyor ? null : _sayfayiYukle,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
  );

  Widget _aramaSonuclari() {
    if (!_aramaYapiliyor) {
      return const SizedBox();
    }

    if (_filtreliOgrenciler.isEmpty) {
      return const Expanded(child: Center(child: Text('Sonuç bulunamadı')));
    }

    return Expanded(
      child: ListView.builder(
        itemCount: _filtreliOgrenciler.length,
        itemBuilder: (context, index) {
          final ogrenci = _filtreliOgrenciler[index];
          final ad = (ogrenci['Ad'] ?? '').toString().trim();
          final soyad = (ogrenci['Soyad'] ?? '').toString().trim();
          final okulNo = (ogrenci['OkulNo'] ?? '').toString().trim();
          final sinif = (ogrenci['SinifKodu'] ?? '').toString().trim();
          final alan = (ogrenci['Alan'] ?? '').toString().trim();

          final altBilgi = <String>[
            if (okulNo.isNotEmpty) 'No: $okulNo',
            if (sinif.isNotEmpty) sinif,
            if (alan.isNotEmpty) alan,
          ].join(' • ');

          return ListTile(
            leading: OgrenciFotoWidget(
              fotoYolu: ogrenci['DosyaYolu'] as String?,
              fotoVerisi: ogrenci['FotoVerisi'] as Uint8List?,
              yerel: true,
              width: 40,
              height: 40,
            ),
            title: Text('$ad $soyad'.trim()),
            subtitle: altBilgi.isEmpty ? null : Text(altBilgi),
          );
        },
      ),
    );
  }

  Widget _duyuruKarti() {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: colors.primaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(Icons.campaign_outlined, color: colors.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Duyurular / Bilgilendirmeler',
              style: TextStyle(fontWeight: FontWeight.bold))),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.all(14),
          child: Text('Henüz gösterilecek duyuru bulunmuyor.'),
        ),
      ]),
    );
  }

  Widget _anaGezinmeCubugu() => NavigationBar(
    selectedIndex: 0,
    height: 70,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    onDestinationSelected: (index) async {
      switch (index) {
        case 0:
          if (_anaSayfaScroll.hasClients) {
            await _anaSayfaScroll.animateTo(0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut);
          }
        case 1:
          if (_anaSayfaScroll.hasClients) {
            await _anaSayfaScroll.animateTo(
              _anaSayfaScroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut);
          }
        case 2:
          final tarih = await showDatePicker(
            context: context,
            initialDate: _seciliTarih,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (tarih != null && mounted) {
            setState(() => _seciliTarih = tarih);
            await _sayfayiYukle();
          }
        case 3:
          await _bildirimleriAc();
        case 4:
          await _profilimiAc();
      }
    },
    destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home), label: 'Ana Sayfa'),
      NavigationDestination(icon: Icon(Icons.grid_view_outlined),
        label: 'Modüller'),
      NavigationDestination(icon: Icon(Icons.calendar_month_outlined),
        label: 'Takvim'),
      NavigationDestination(icon: Icon(Icons.notifications_none),
        label: 'Bildirimler'),
      NavigationDestination(icon: Icon(Icons.person_outline),
        label: 'Profil'),
    ],
  );

  Widget _profilVeTarihKarti() {
    final ad = (_profil?['AdSoyad'] ?? '').toString().trim();
    final okul = (_profil?['OkulAdi'] ?? _profil?['Okul'] ?? '').toString().trim();
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          colors.primaryContainer,
          colors.primaryContainer.withValues(alpha: .65),
        ], begin: Alignment.centerLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(OrtakUi.radius),
      ),
      child: Row(children: [
        CircleAvatar(backgroundColor: colors.surface,
          child: Icon(Icons.person_outline, color: colors.primary)),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ad.isEmpty ? 'Öğretmen' : ad,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
            Text(okul.isEmpty ? 'Bireysel Öğretmen' : 'Öğretmen | $okul',
              maxLines: 3, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
          ],
        )),
      ]),
    );
  }

  Widget _menu(BuildContext context) {
    if (_aramaYapiliyor) return const SizedBox.shrink();
    Widget kart(IconData icon, String title, Color renk, VoidCallback tap) =>
        AnaMenuKart(
          key: ValueKey('modul-$title'),
          icon: icon, baslik: title, renk: renk,
          onTap: tap,
        );
    final ana = <Widget>[
      _dersProgramiKarti(),
      kart(Icons.people_alt_outlined, 'Öğrenci İşlemleri',
          const Color(0xFF1371DF), _ogrencileriAc),
      kart(Icons.assignment_outlined, 'Ödev Kontrol',
          const Color(0xFFF1A000), () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OdevKontrolScreen()))),
      kart(Icons.mail_outline, 'Mesajlaşma',
          const Color(0xFF0C86CF), () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MesajlasmaScreen()))),
      kart(Icons.contact_page_outlined, 'Rehberlik Dosyam',
          const Color(0xFF7920CC), () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BireyselRehberlikScreen()))),
      kart(Icons.menu_book_outlined, 'Yıllık Planlarım',
          const Color(0xFF009348), widget.onYillikPlan ?? _yillikPlanlariAc),
      kart(Icons.handyman_outlined, 'Atölye Şefliği',
          const Color(0xFF126CC8), () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BireyselSeflikYillikPlanScreen()))),
      kart(Icons.folder_open_outlined, 'Belgelerim',
          const Color(0xFFF28A00), () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BireyselBelgelerimScreen()))),
      kart(Icons.file_upload_outlined, 'Import / Export',
          const Color(0xFF008D6B), () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportMerkeziScreen()));
            if (mounted) await _sayfayiYukle();
          }),
      kart(Icons.settings_outlined, 'Okul Bilgileri',
          const Color(0xFF263A60), _okulBilgileriniAc),
      kart(Icons.grid_view_outlined, 'Diğer Modüller',
          const Color(0xFF6B26C5), () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (c) => SafeArea(child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('Diğer Modüller')),
                ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: const Text('Raporlar'),
                  onTap: () { Navigator.pop(c); Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RaporOlusturScreen())); },
                ),
                ListTile(
                  leading: const Icon(Icons.assignment_turned_in),
                  title: const Text('Not Hesaplama'),
                  onTap: () { Navigator.pop(c); _notHesaplamayiAc(); },
                ),
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Test Modülü'),
                  onTap: () { Navigator.pop(c); Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TestModuluScreen())); },
                ),
              ],
            )),
          )),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            const Icon(Icons.bolt, color: Colors.white),
            const SizedBox(width: 8),
            const Expanded(child: Text('Hızlı Erişim',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            Icon(Icons.grid_view, size: 18,
              color: Theme.of(context).colorScheme.onPrimary),
          ]),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, constraints) {
          final kolon = constraints.maxWidth >= 340 ? 4 :
              constraints.maxWidth >= 270 ? 3 : 2;
          const bosluk = 6.0;
          final genislik = (constraints.maxWidth - bosluk * (kolon - 1)) / kolon;
          return AnaMenuStili(
            kompakt: false, yatay: true, kutucuk: true, dar: true,
            child: Wrap(spacing: bosluk, runSpacing: bosluk,
              children: [for (final item in ana)
                SizedBox(width: genislik, child: item)]),
          );
        }),
      ]),
    );
  }

  bool get _kurulumRehberiOnde => _rehberGoster && _kurulumAdimi == 1;

  Widget _rehberDugmesi() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () {
          setState(() {
            _rehberGoster = !_rehberGoster;
          });
        },
        icon: Icon(_rehberGoster ? Icons.close : Icons.help_outline),
        label: Text(_rehberGoster ? 'Açıklamayı kapat' : 'Rehberi göster'),
      ),
    );
  }

  Widget _dersProgramiKarti() {
    return _rehberliKart(
      adim: 1,
      child: AnaMenuKart(
        key: const ValueKey('modul-Ders Programım'),
        icon: Icons.calendar_month,
        baslik: 'Ders Programım',
        aciklama: 'Haftalık ders programı',
        renk: const Color(0xFF8A2CEC),
        onTap: widget.onDersProgrami ?? _dersPrograminiAc,
      ),
    );
  }

  Widget _rehberliKart({required int adim, required Widget child}) {
    if (!_rehberGoster || _kurulumAdimi != adim) return child;
    return _KurulumRehberi(
      key: ValueKey(adim),
      adim: adim,
      aciklama: adim == 1
          ? 'Önce ders programınızı yükleyin. Aşağıdaki karta dokunun; '
                'Excel dosyanızı seçip ön izlemeyi kontrol ederek kaydedin.'
          : 'Ders programınız hazır. $_eksikPlanSayisi ders / sınıf için '
                'yıllık plan eksik. Aşağıdaki karttan planlarınızı yükleyin.',
      child: child,
    );
  }

  bool _bugunMu(DateTime tarih) {
    final now = DateTime.now();

    return tarih.year == now.year &&
        tarih.month == now.month &&
        tarih.day == now.day;
  }

  TimeOfDay? _saatParse(String? saat) {
    if (saat == null || saat.trim().isEmpty) {
      return null;
    }

    final parcalar = saat.split(':');

    if (parcalar.length < 2) {
      return null;
    }

    final saatInt = int.tryParse(parcalar[0]);
    final dakikaInt = int.tryParse(parcalar[1]);

    if (saatInt == null || dakikaInt == null) {
      return null;
    }

    return TimeOfDay(hour: saatInt, minute: dakikaInt);
  }

  int _saatDakika(TimeOfDay saat) {
    return saat.hour * 60 + saat.minute;
  }

  String _saatKisalt(String? saat) {
    if (saat == null || saat.trim().isEmpty) {
      return '';
    }

    final parcalar = saat.split(':');

    if (parcalar.length < 2) {
      return saat;
    }

    return '${parcalar[0]}:${parcalar[1]}';
  }

  String _tarihYazi(DateTime tarih) {
    const gunler = <String>[
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    final gunAdi = gunler[tarih.weekday - 1];

    return '${tarih.day.toString().padLeft(2, '0')}.'
        '${tarih.month.toString().padLeft(2, '0')}.'
        '${tarih.year} $gunAdi';
  }

  String _normalize(String? text) {
    if (text == null) {
      return '';
    }

    return text
        .trim()
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');
  }
}

class _KurulumRehberi extends StatefulWidget {
  const _KurulumRehberi({
    super.key,
    required this.adim,
    required this.aciklama,
    required this.child,
  });

  final int adim;
  final String aciklama;
  final Widget child;

  @override
  State<_KurulumRehberi> createState() => _KurulumRehberiState();
}

class _KurulumRehberiState extends State<_KurulumRehberi>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animasyon = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animasyon.stop();
      _animasyon.value = 0;
    } else if (!_animasyon.isAnimating) {
      _animasyon.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _animasyon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animasyon,
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        final ilerleme = Curves.easeInOut.transform(_animasyon.value);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Color.lerp(
                scheme.outlineVariant,
                scheme.primary,
                ilerleme,
              )!,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withAlpha((12 + ilerleme * 20).round()),
                blurRadius: 8 + ilerleme * 8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.adim == 1
                    ? '1 / 2 • Ders programınızı yükleyin'
                    : '2 / 2 • Yıllık planlarınızı yükleyin',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.aciklama,
                style: TextStyle(color: scheme.onPrimaryContainer, height: 1.4),
              ),
              if (widget.adim == 1) ...[
                const SizedBox(height: 8),
                Text(
                  'Sonraki adım: Yıllık planları yükleme',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 12,
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Transform.translate(
                  offset: Offset(0, ilerleme * 5),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    color: scheme.primary,
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}
