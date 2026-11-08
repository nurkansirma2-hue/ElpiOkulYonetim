import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'bireysel_ana_sayfa_screen.dart';
import 'bireysel_yillik_plan_import_screen.dart';
import '../services/bireysel_ders_programi_service.dart';
import '../services/bireysel_import_service.dart';
import '../services/bireysel_profil_service.dart';
import '../models/bireysel_seflik.dart';
import '../models/ortak_import.dart';
import '../services/bireysel_belge_service.dart';
import '../services/ders_programi_import_tanimi.dart';
import 'ortak_import_screen.dart';

class BireyselDersProgramiImportScreen extends StatefulWidget {
  const BireyselDersProgramiImportScreen({super.key, this.baslangicDosyasi});
  final ImportDosya? baslangicDosyasi;

  @override
  State<BireyselDersProgramiImportScreen> createState() =>
      _BireyselDersProgramiImportScreenState();
}

class _BireyselDersProgramiImportScreenState
    extends State<BireyselDersProgramiImportScreen> {
  Map<String, dynamic>? _profil;
  PlatformFile? _seciliDosya;
  ImportDosya? _importDosyasi;
  BireyselDersProgramiOnIzleme? _onIzleme;

  final Map<String, Set<int>> _seciliDersSaatleri = <String, Set<int>>{};
  final Map<String, Map<int, String>> _baslangicSaatleri =
      <String, Map<int, String>>{};
  final Map<String, Map<int, String>> _bitisSaatleri =
      <String, Map<int, String>>{};
  final Set<String> _seciliSinifSubeler = <String>{};
  final Set<String> _seciliDersAdlari = <String>{};
  final Set<String> _seciliDerslikler = <String>{};
  final GlobalKey _sinifSubeBolumuKey = GlobalKey();
  final GlobalKey _dersAdiBolumuKey = GlobalKey();
  final GlobalKey _derslikBolumuKey = GlobalKey();

  bool _profilYukleniyor = true;
  bool _dersSaatleriOnaylandi = false;
  bool _sinifSubelerOnaylandi = false;
  bool _dersAdlariOnaylandi = false;
  bool _dersliklerOnaylandi = false;
  bool _onIzlemeHazirlaniyor = false;
  bool _kayitYapiliyor = false;
  bool _meslekPaketiAktif = false;
  bool _seflikOnaylandi = false;
  final Set<int> _seciliSeflikSaatleri = <int>{};
  DateTime? _programBaslangicTarihi;

  static const List<String> _gunSirasi = <String>[
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
  ];

  @override
  void initState() {
    super.initState();
    _profiliYukle();
  }

  Future<void> _profiliYukle() async {
    try {
      final profil = await BireyselProfilService.getir();

      if (!mounted) {
        return;
      }

      setState(() {
        _profil = profil;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      _mesajGoster(
        'Bireysel öğretmen profili okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _profilYukleniyor = false;
        });
      }
    }
    if (mounted && _profil != null && widget.baslangicDosyasi != null) {
      await _onIzlemeHazirla();
    }
  }

  Future<void> _dosyaSec() => _onIzlemeHazirla(yeniDosya: true);

  Future<void> _onIzlemeHazirla({bool yeniDosya = false}) async {
    if (_kayitYapiliyor || _onIzlemeHazirlaniyor) return;
    final profil = _profil;
    final dosya = _importDosyasi ?? widget.baslangicDosyasi;

    if (profil == null) {
      _mesajGoster(
        'Bireysel öğretmen profili bulunamadı. '
        'Önce öğretmen kurulumunu tamamlayın.',
      );
      return;
    }

    final adSoyad = (profil['AdSoyad'] ?? '').toString().trim();

    if (adSoyad.isEmpty) {
      _mesajGoster(
        'Öğretmen profilindeki Ad Soyad bilgisi boş. '
        'Önce profil bilgilerini düzeltin.',
      );
      return;
    }

    setState(() {
      _onIzlemeHazirlaniyor = true;
      _onIzleme = null;
    });

    try {
      final meslekPaketiAktif =
          await BireyselProfilService.meslekPaketiTercihiniGetir() == true;
      if (!mounted) return;
      final secim = await Navigator.of(context).push<ImportSecimi>(MaterialPageRoute(
        builder: (_) => OrtakImportScreen(
          tanim: DersProgramiImportTanimi.olustur(adSoyad, meslekPaketi: meslekPaketiAktif),
          baslangicDosyasi: yeniDosya && _seciliDosya != null ? null : dosya, secimleDon: true),
      ));
      if (!mounted || secim == null) return;
      final onIzleme = DersProgramiImportTanimi.secimiUygula(secim.onIzleme, secim.secimler);

      if (!mounted) {
        return;
      }

      setState(() {
        _onIzleme = onIzleme;
        _importDosyasi = secim.dosya;
        _seciliDosya = PlatformFile(name: secim.dosya.ad, size: secim.dosya.bytes.length, bytes: secim.dosya.bytes);
        _meslekPaketiAktif = meslekPaketiAktif;
        _seflikOnaylandi = false;
        _programBaslangicTarihi = onIzleme.baslangicTarihi;
        _seciliSeflikSaatleri
          ..clear()
          ..addAll(List.generate(onIzleme.seflikSaatleri.length, (i) => i));
        _seciliDersSaatleri.clear();
        _baslangicSaatleri.clear();
        _bitisSaatleri.clear();
        _seciliSinifSubeler
          ..clear()
          ..addAll(
            onIzleme.dersler
                .map((ders) => ders.sinif.trim())
                .where((sinif) => sinif.isNotEmpty),
          );

        for (final aday in onIzleme.gunlukDersSaatAdaylari) {
          _seciliDersSaatleri
              .putIfAbsent(aday.gun, () => <int>{})
              .add(aday.dersSaatiNo);

          _baslangicSaatleri
              .putIfAbsent(aday.gun, () => <int, String>{})[aday.dersSaatiNo] =
              aday.baslangic;

          _bitisSaatleri
              .putIfAbsent(aday.gun, () => <int, String>{})[aday.dersSaatiNo] =
              aday.bitis;
        }

        _seciliDersAdlari.clear();
        _seciliDerslikler.clear();
        _dersSaatleriOnaylandi = false;
        _sinifSubelerOnaylandi = false;
        _dersAdlariOnaylandi = false;
        _dersliklerOnaylandi = false;
        _kayitYapiliyor = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      _mesajGoster(
        'Ders programı ön izlemesi hazırlanırken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _onIzlemeHazirlaniyor = false;
        });
      }
    }
  }

  Future<void> _dersSaatiniDuzenle({
    required String gun,
    required int dersSaatiNo,
  }) async {
    final mevcutBaslangic =
        _baslangicSaatleri[gun]?[dersSaatiNo] ?? '';
    final mevcutBitis = _bitisSaatleri[gun]?[dersSaatiNo] ?? '';

    final baslangicController = TextEditingController(
      text: mevcutBaslangic,
    );
    final bitisController = TextEditingController(
      text: mevcutBitis,
    );

    final sonuc = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        String? hata;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('$gun • $dersSaatiNo. Ders'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: baslangicController,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: 'Başlangıç',
                      hintText: '08:30',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bitisController,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: 'Bitiş',
                      hintText: '09:10',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (hata != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      hata!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final baslangic =
                        _saatMetniniNormalizeEt(baslangicController.text);
                    final bitis =
                        _saatMetniniNormalizeEt(bitisController.text);

                    if (baslangic == null || bitis == null) {
                      setDialogState(() {
                        hata = 'Saatleri SS:DD biçiminde girin. Örn: 08:30';
                      });
                      return;
                    }

                    Navigator.of(context).pop(
                      <String, String>{
                        'baslangic': baslangic,
                        'bitis': bitis,
                      },
                    );
                  },
                  child: const Text('Uygula'),
                ),
              ],
            );
          },
        );
      },
    );

    baslangicController.dispose();
    bitisController.dispose();

    if (sonuc == null || !mounted) {
      return;
    }

    setState(() {
      _baslangicSaatleri
          .putIfAbsent(gun, () => <int, String>{})[dersSaatiNo] =
          sonuc['baslangic'] ?? '';

      _bitisSaatleri
          .putIfAbsent(gun, () => <int, String>{})[dersSaatiNo] =
          sonuc['bitis'] ?? '';
    });
  }

  void _gunuDigerGunlereUygula(String kaynakGun) {
    final kaynakSecimler =
        Set<int>.from(_seciliDersSaatleri[kaynakGun] ?? <int>{});
    final kaynakBaslangic =
        Map<int, String>.from(_baslangicSaatleri[kaynakGun] ?? {});
    final kaynakBitis =
        Map<int, String>.from(_bitisSaatleri[kaynakGun] ?? {});

    setState(() {
      for (final gun in _gunSirasi) {
        if (gun == kaynakGun) {
          continue;
        }

        _seciliDersSaatleri[gun] = Set<int>.from(kaynakSecimler);
        _baslangicSaatleri[gun] = Map<int, String>.from(kaynakBaslangic);
        _bitisSaatleri[gun] = Map<int, String>.from(kaynakBitis);
      }
    });

    _mesajGoster(
      '$kaynakGun ders saatleri diğer günlere uygulandı.',
    );
  }

  void _sinifSubeBolumuneKaydir() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final hedefContext = _sinifSubeBolumuKey.currentContext;

      if (hedefContext == null) {
        return;
      }

      Scrollable.ensureVisible(
        hedefContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.08,
      );
    });
  }

  void _dersSaatleriniOnayla() {
    final toplamSecili = _seciliDersSaatleri.values.fold<int>(
      0,
      (toplam, secimler) => toplam + secimler.length,
    );

    if (toplamSecili == 0) {
      _mesajGoster(
        'En az bir gün için ders saati seçmeden onay veremezsiniz.',
      );
      return;
    }

    for (final gunEntry in _seciliDersSaatleri.entries) {
      for (final dersSaatiNo in gunEntry.value) {
        final baslangic =
            _baslangicSaatleri[gunEntry.key]?[dersSaatiNo] ?? '';
        final bitis = _bitisSaatleri[gunEntry.key]?[dersSaatiNo] ?? '';

        if (_saatMetniniNormalizeEt(baslangic) == null ||
            _saatMetniniNormalizeEt(bitis) == null) {
          _mesajGoster(
            '${gunEntry.key} $dersSaatiNo. ders için başlangıç/bitiş saati geçersiz.',
          );
          return;
        }
      }
    }

    setState(() {
      _dersSaatleriOnaylandi = true;
      if (_onIzleme!.dersler.where((d) => !d.gorevMi).isEmpty &&
          (_onIzleme!.dersler.isNotEmpty || (_meslekPaketiAktif && _onIzleme!.seflikSaatleri.isNotEmpty))) {
        _sinifSubelerOnaylandi = true;
        _dersAdlariOnaylandi = true;
      }
    });

    if (_onIzleme!.dersler.where((d) => !d.gorevMi).isEmpty && _dersAdlariOnaylandi) {
      _derslikBolumuneKaydir();
      _mesajGoster('Sınıfa bağlı ders yok. Görev saatlerini ve program başlangıcını kontrol edin.');
      return;
    }

    _sinifSubeBolumuneKaydir();

    _mesajGoster(
      'Gün bazlı ders saatleri onaylandı. '
      'Sonraki adımda sınıf/şube adaylarını onaylayacağız.',
    );
  }

  List<String> _sinifSubeAdaylariniGetir(
    BireyselDersProgramiOnIzleme onIzleme,
  ) {
    final adaylar = onIzleme.dersler
        .map((ders) => ders.sinif.trim())
        .where((sinif) => sinif.isNotEmpty)
        .toSet()
        .toList()
      ..sort(_sinifSubeKarsilastir);

    return adaylar;
  }

  int _sinifSubeKarsilastir(String a, String b) {
    final aSeviye = int.tryParse(
          RegExp(r'\d{1,2}').firstMatch(a)?.group(0) ?? '',
        ) ??
        999;
    final bSeviye = int.tryParse(
          RegExp(r'\d{1,2}').firstMatch(b)?.group(0) ?? '',
        ) ??
        999;

    final seviyeKarsilastirma = aSeviye.compareTo(bSeviye);

    if (seviyeKarsilastirma != 0) {
      return seviyeKarsilastirma;
    }

    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  List<String> _dersAdiAdaylariniGetir(
    BireyselDersProgramiOnIzleme onIzleme,
  ) {
    final adaylar = onIzleme.dersler
        .where((ders) => _seciliSinifSubeler.contains(ders.sinif.trim()))
        .map((ders) => ders.dersAdi.trim())
        .where((dersAdi) => dersAdi.isNotEmpty)
        .toSet()
        .toList()
      ..sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );

    return adaylar;
  }

  List<String> _derslikAdaylariniGetir(
    BireyselDersProgramiOnIzleme onIzleme,
  ) {
    final adaylar = <String>{};

    for (final ders in onIzleme.dersler) {
      if (!_seciliSinifSubeler.contains(ders.sinif.trim()) ||
          !_seciliDersAdlari.contains(ders.dersAdi.trim())) {
        continue;
      }

      final hamDerslik = ders.derslik.trim();

      if (hamDerslik.isEmpty) {
        continue;
      }

      final parcalar = hamDerslik
          .split(RegExp(r'[,;]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);

      adaylar.addAll(parcalar);
    }

    final sonuc = adaylar.toList()
      ..sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );

    return sonuc;
  }

  String _ilkOnayliDerslikGetir(BireyselDersProgramiKaydi ders) {
    final hamDerslik = ders.derslik.trim();

    if (hamDerslik.isEmpty) {
      return '';
    }

    for (final parca in hamDerslik.split(RegExp(r'[,;]+'))) {
      final derslik = parca.trim();

      if (derslik.isNotEmpty && _seciliDerslikler.contains(derslik)) {
        return derslik;
      }
    }

    return '';
  }

  List<BireyselDersProgramiKaydi> _sonEslesmeKayitlariniGetir(
    BireyselDersProgramiOnIzleme onIzleme,
  ) {
    final sonuc = onIzleme.dersler.where((ders) {
      final seciliSaatler = _seciliDersSaatleri[ders.gun] ?? <int>{};

      if (!seciliSaatler.contains(ders.dersSaatiNo)) {
        return false;
      }

      if (ders.gorevMi) return true;

      if (!_seciliSinifSubeler.contains(ders.sinif.trim()) ||
          !_seciliDersAdlari.contains(ders.dersAdi.trim())) {
        return false;
      }

      final hamDerslik = ders.derslik.trim();

      if (hamDerslik.isEmpty) {
        return true;
      }

      final derslikler = hamDerslik
          .split(RegExp(r'[,;]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (derslikler.isEmpty) {
        return true;
      }

      return derslikler.any(_seciliDerslikler.contains);
    }).toList();

    sonuc.sort((a, b) {
      final gunKarsilastirma =
          _gunSirasi.indexOf(a.gun).compareTo(_gunSirasi.indexOf(b.gun));

      if (gunKarsilastirma != 0) {
        return gunKarsilastirma;
      }

      return a.dersSaatiNo.compareTo(b.dersSaatiNo);
    });

    return sonuc;
  }

  void _dersAdiBolumuneKaydir() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final hedefContext = _dersAdiBolumuKey.currentContext;

      if (hedefContext == null) {
        return;
      }

      Scrollable.ensureVisible(
        hedefContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.08,
      );
    });
  }

  void _derslikBolumuneKaydir() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final hedefContext = _derslikBolumuKey.currentContext;

      if (hedefContext == null) {
        return;
      }

      Scrollable.ensureVisible(
        hedefContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.08,
      );
    });
  }

  void _sinifSubeleriOnayla(BireyselDersProgramiOnIzleme onIzleme) {
    final adaylar = _sinifSubeAdaylariniGetir(onIzleme);

    if (adaylar.isEmpty) {
      _mesajGoster(
        'Excel ders kayıtlarından sınıf/şube adayı çıkarılamadı. '
        'Sınıf/şube onayı verilemez.',
      );
      return;
    }

    if (_seciliSinifSubeler.isEmpty) {
      _mesajGoster(
        'En az bir sınıf/şube seçmeden onay veremezsiniz.',
      );
      return;
    }

    final dersAdiAdaylari = _dersAdiAdaylariniGetir(onIzleme);

    if (dersAdiAdaylari.isEmpty) {
      _mesajGoster(
        'Seçili sınıf/şubelere ait ders adı adayı bulunamadı. '
        'Ders adları onayı verilemez.',
      );
      return;
    }

    setState(() {
      _sinifSubelerOnaylandi = true;
      _dersAdlariOnaylandi = false;
      _dersliklerOnaylandi = false;
      _seciliDersAdlari
        ..clear()
        ..addAll(dersAdiAdaylari);
      _seciliDerslikler.clear();
    });

    _dersAdiBolumuneKaydir();

    _mesajGoster(
      'Sınıf/şube adayları onaylandı. '
      'Sonraki adımda ders adlarını onaylayacağız.',
    );
  }

  void _dersAdlariniOnayla(BireyselDersProgramiOnIzleme onIzleme) {
    final adaylar = _dersAdiAdaylariniGetir(onIzleme);

    if (adaylar.isEmpty) {
      _mesajGoster(
        'Seçili sınıf/şubelere ait ders adı adayı bulunamadı. '
        'Ders adları onayı verilemez.',
      );
      return;
    }

    if (_seciliDersAdlari.isEmpty) {
      _mesajGoster(
        'En az bir ders adı seçmeden onay veremezsiniz.',
      );
      return;
    }

    final derslikAdaylari = _derslikAdaylariniGetir(onIzleme);

    setState(() {
      _dersAdlariOnaylandi = true;
      _dersliklerOnaylandi = false;
      _seciliDerslikler
        ..clear()
        ..addAll(derslikAdaylari);
    });

    _derslikBolumuneKaydir();

    _mesajGoster(
      'Ders adları onaylandı. '
      'Sonraki adımda derslik/laboratuvar adaylarını onaylayacağız.',
    );
  }

  Future<void> _derslikleriOnayla(
    BireyselDersProgramiOnIzleme onIzleme,
  ) async {
    if (_kayitYapiliyor || _dersliklerOnaylandi) {
      return;
    }

    final adaylar = _derslikAdaylariniGetir(onIzleme);

    if (adaylar.isNotEmpty && _seciliDerslikler.isEmpty) {
      _mesajGoster(
        'En az bir derslik/laboratuvar seçmeden kayıt yapamazsınız.',
      );
      return;
    }

    final profil = _profil;

    if (profil == null) {
      _mesajGoster(
        'Ders programı kaydedilemedi. Bireysel öğretmen profili bulunamadı.',
      );
      return;
    }

    final profilIdDeger = profil['OgretmenProfilId'];
    final egitimOgretimYili =
        (profil['EgitimOgretimYili'] ?? '').toString().trim();

    if (profilIdDeger is! int || profilIdDeger <= 0) {
      _mesajGoster(
        'Ders programı kaydedilemedi. Geçerli öğretmen profil kimliği bulunamadı.',
      );
      return;
    }

    if (egitimOgretimYili.isEmpty) {
      _mesajGoster(
        'Ders programı kaydedilemedi. Eğitim öğretim yılı bilgisi boş.',
      );
      return;
    }

    if (_programBaslangicTarihi == null) {
      _mesajGoster('Ders programının başlangıç tarihini seçin.');
      return;
    }
    final dersler = _sonEslesmeKayitlariniGetir(onIzleme);

    final seflikSecimiVar = _meslekPaketiAktif &&
        onIzleme.seflikSaatleri.isNotEmpty;
    if (seflikSecimiVar && !_seflikOnaylandi) {
      _mesajGoster('Önce şeflik saatleri seçimini onaylayın.');
      return;
    }
    if (dersler.isEmpty && (!seflikSecimiVar || _seciliSeflikSaatleri.isEmpty)) {
      _mesajGoster(
        'Onaylanan seçimlere uyan ders kaydı bulunamadı. Kayıt yapılamaz.',
      );
      return;
    }

    final kayitlar = <BireyselDersProgramiKayitGirdisi>[];

    for (final ders in dersler) {
      final baslangic =
          _baslangicSaatleri[ders.gun]?[ders.dersSaatiNo] ?? '';
      final bitis = _bitisSaatleri[ders.gun]?[ders.dersSaatiNo] ?? '';

      if (_saatMetniniNormalizeEt(baslangic) == null ||
          _saatMetniniNormalizeEt(bitis) == null) {
        _mesajGoster(
          '${ders.gun} ${ders.dersSaatiNo}. ders için başlangıç/bitiş '
          'saati geçersiz. Kayıt yapılamaz.',
        );
        return;
      }

      kayitlar.add(
        BireyselDersProgramiKayitGirdisi(
          gun: ders.gun,
          dersSaatiNo: ders.dersSaatiNo,
          baslangic: baslangic,
          bitis: bitis,
          dersAdi: ders.dersAdi,
          sinif: ders.sinif,
          derslik: _ilkOnayliDerslikGetir(ders),
        ),
      );
    }

    SeflikProgramiImportu? seflikImportu;
    if (seflikSecimiVar && _seciliSeflikSaatleri.isNotEmpty) {
      final saatler = <SeflikProgramSaatiGirdisi>[];
      for (final i in _seciliSeflikSaatleri) {
        final aday = onIzleme.seflikSaatleri[i];
        final bas = _baslangicSaatleri[aday.gun]?[aday.dersSaatiNo] ?? '';
        final son = _bitisSaatleri[aday.gun]?[aday.dersSaatiNo] ?? '';
        if (!(_seciliDersSaatleri[aday.gun]?.contains(aday.dersSaatiNo) ?? false) ||
            _saatMetniniNormalizeEt(bas) == null ||
            _saatMetniniNormalizeEt(son) == null) {
          _mesajGoster('${aday.gun} ${aday.dersSaatiNo}. şeflik saati '
              '1. adımda onaylanmamış. Dosyayı yeniden ön izleyin veya bu saati seçmeyin.');
          return;
        }
        saatler.add(SeflikProgramSaatiGirdisi(
          gun: aday.gun, dersSaatiNo: aday.dersSaatiNo, hamMetin: aday.hamMetin,
          baslangic: bas, bitis: son,
        ));
      }
      seflikImportu = SeflikProgramiImportu(
        baslangicTarihi: _programBaslangicTarihi!,
        saatler: saatler,
      );
    }

    setState(() {
      _kayitYapiliyor = true;
    });

    try {
      final kaynak = _importDosyasi?.belgeKaynagi;
      if (kaynak != null) await BireyselBelgeService.instance.importKapsaminiDogrula(kaynak);
      final kayitSayisi = await BireyselDersProgramiService.kaydet(
        ogretmenProfilId: profilIdDeger,
        egitimOgretimYili: egitimOgretimYili,
        kayitlar: kayitlar,
        baslangicTarihi: _programBaslangicTarihi!,
        seflikImportu: seflikImportu,
      );

      if (kaynak != null) {
        try {
          await BireyselBelgeService.instance.importSonucunuKaydet(kaynak, 'Ders Programı Import',
            ImportOzet(eklenen: kayitSayisi, guncellenen: 0, atlanan: 0, hatali: 0, mesaj: 'Yeni program sürümüne $kayitSayisi ders/görev kaydedildi.'));
        } catch (e) {
          if (mounted) _mesajGoster('Veriler kaydedildi; belge geçmişi yazılamadı. Orijinal hata: $e');
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _dersliklerOnaylandi = true;
      });

      _mesajGoster(
        'Ders programı başarıyla kaydedildi. '
        '$kayitSayisi ders/görev ve ${seflikImportu?.saatler.length ?? 0} şeflik saati '
        'SQLite veritabanına yazıldı.',
      );

      await _kayitSonrasiSecimSor();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _mesajGoster(
        'Ders programı kaydedilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _kayitYapiliyor = false;
        });
      }
    }
  }

  Future<void> _kayitSonrasiSecimSor() async {
    final secim = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ders Programı Kaydedildi'),
          content: const Text(
            'Ders programınız başarıyla kaydedildi.\n\n'
            'Şimdi ne yapmak istiyorsunuz?',
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop('yillikPlan');
              },
              icon: const Icon(Icons.event_note_outlined),
              label: const Text('Yıllık Plan Yükle'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop('anaSayfa');
              },
              icon: const Icon(Icons.home_outlined),
              label: const Text('Ana Sayfaya Git'),
            ),
          ],
        );
      },
    );

    if (!mounted || secim == null) {
      return;
    }

    if (secim == 'yillikPlan') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const BireyselYillikPlanImportScreen(),
        ),
        (route) => false,
      );
      return;
    }

    if (secim == 'anaSayfa') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const BireyselAnaSayfaScreen(),
        ),
        (route) => false,
      );
      return;
    }
  }

  String? _saatMetniniNormalizeEt(String deger) {
    final eslesme = RegExp(
      r'^\s*(\d{1,2}):(\d{2})\s*$',
    ).firstMatch(deger);

    if (eslesme == null) {
      return null;
    }

    final saat = int.tryParse(eslesme.group(1) ?? '');
    final dakika = int.tryParse(eslesme.group(2) ?? '');

    if (saat == null ||
        dakika == null ||
        saat < 0 ||
        saat > 23 ||
        dakika < 0 ||
        dakika > 59) {
      return null;
    }

    return '${saat.toString().padLeft(2, '0')}:'
        '${dakika.toString().padLeft(2, '0')}';
  }

  String _dosyaUzantisi(String dosyaAdi) {
    final parcalar = dosyaAdi.toLowerCase().split('.');

    if (parcalar.length < 2) {
      return '';
    }

    return parcalar.last.trim();
  }

  String _dosyaTuruEtiketi(String dosyaAdi) {
    switch (_dosyaUzantisi(dosyaAdi)) {
      case 'xls':
        return 'Excel 97-2003 (XLS)';
      case 'xlsx':
        return 'Excel (XLSX)';
      case 'csv':
        return 'CSV';
      default:
        return 'Bilinmeyen Dosya';
    }
  }

  void _mesajGoster(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mesaj),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrtakSayfa(
      appBar: const ModulUstBar(
        title: Text('Ders Programı Import'),
        centerTitle: true,
      ),
      body: _profilYukleniyor
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _profilKarti(),
                      const SizedBox(height: 16),
                      _dosyaKarti(),
                      const SizedBox(height: 16),
                      if (_onIzleme != null) _onIzlemeKarti(_onIzleme!),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _profilKarti() {
    final profil = _profil;

    if (profil == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline,
                size: 42,
                color: Colors.red,
              ),
              const SizedBox(height: 10),
              const Text(
                'Bireysel öğretmen profili bulunamadı.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final adSoyad = (profil['AdSoyad'] ?? '').toString();
    final brans = (profil['Brans'] ?? '').toString();
    final okulAdi = (profil['OkulAdi'] ?? '').toString();
    final egitimOgretimYili =
        (profil['EgitimOgretimYili'] ?? '').toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.person_outline,
                  color: Colors.indigo,
                ),
                SizedBox(width: 8),
                Text(
                  'Öğretmen Profili',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _bilgiSatiri('Ad Soyad', adSoyad),
            if (brans.trim().isNotEmpty) _bilgiSatiri('Branş', brans),
            if (okulAdi.trim().isNotEmpty) _bilgiSatiri('Okul', okulAdi),
            _bilgiSatiri('Eğitim Yılı', egitimOgretimYili),
          ],
        ),
      ),
    );
  }

  Widget _dosyaKarti() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.file_present_outlined,
                  color: Colors.indigo,
                ),
                SizedBox(width: 8),
                Text(
                  'Ders Programı Dosyası',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Okulda kullanılan ders programı Excel dosyasını seçin. '
              'Bu aşamada veritabanına kayıt yapılmaz.',
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Desteklenen dosyalar: XLS, XLSX',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _onIzlemeHazirlaniyor || _kayitYapiliyor ? null : _dosyaSec,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Excel Dosyası Seç'),
            ),
            if (_seciliDosya != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.description_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _seciliDosya!.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dosya türü: ${_dosyaTuruEtiketi(_seciliDosya!.name)}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed:
                      _onIzlemeHazirlaniyor || _kayitYapiliyor ? null : _onIzlemeHazirla,
                  icon: _onIzlemeHazirlaniyor
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(Icons.visibility_outlined),
                  label: Text(
                    _onIzlemeHazirlaniyor
                        ? 'Ön İzleme Hazırlanıyor...'
                        : 'Ön İzleme',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _onIzlemeKarti(BireyselDersProgramiOnIzleme onIzleme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  onIzleme.ogretmenBulundu
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  color: onIzleme.ogretmenBulundu
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    onIzleme.ogretmenBulundu
                        ? 'Öğretmen Eşleşmesi Bulundu'
                        : 'Öğretmen Eşleşmesi Bulunamadı',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _bilgiSatiri(
              'Sayfa sayısı',
              onIzleme.sayfaSayisi.toString(),
            ),
            _bilgiSatiri(
              'Okunan içerik',
              onIzleme.doluHucreSayisi.toString(),
            ),
            _bilgiSatiri(
              'Bulunan eşleşme',
              onIzleme.ogretmenEslesmeleri.length.toString(),
            ),
            if (onIzleme.ogretmenEslesmeleri.isNotEmpty) ...[
              const Divider(height: 28),
              const Text(
                'Dosya içinde bulunan öğretmen ifadeleri:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...onIzleme.ogretmenEslesmeleri.map(
                (eslesme) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check,
                        size: 18,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(eslesme),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (onIzleme.ogretmenBulundu) ...[
              OutlinedButton(
                onPressed: _kayitYapiliyor || _dersliklerOnaylandi ? null : _programTarihiSec,
                child: Text(_programBaslangicTarihi == null ? 'Program başlangıç tarihini seçin' :
                    'Program başlangıcı: ${seflikTarihYaz(_programBaslangicTarihi!)}'),
              ),
              const Text('Ders, koordinatörlük ve şeflik saatleri bu tarihten itibaren '
                  'geçerlidir. Yeni program yüklendiğinde önceki program bir önceki '
                  'ders gününde sona erer; geçmiş kayıtlar korunur.'),
              if (onIzleme.dersler.any((d) => d.gorevMi))
                Text('${onIzleme.dersler.where((d) => d.gorevMi).length} koordinatörlük saati '
                    'seçili gün/saatlerle birlikte aktarılacak. Sınıf ve yıllık plan gerekmez.'),
            ],
            for (final uyari in onIzleme.uyarilar)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(uyari, style: const TextStyle(color: Colors.deepOrange)),
              ),
            if (onIzleme.ogretmenBulundu) ...[
              const Divider(height: 28),
              _gunBazliDersSaatleriOnayBolumu(onIzleme),
              if (onIzleme.seflikSaatleri.isNotEmpty && !_meslekPaketiAktif)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Excel’de şeflik saatleri bulundu. Meslek paketi '
                      'kapalı olduğu için bu saatler aktarılmayacak.'),
                ),
              if (_dersSaatleriOnaylandi && onIzleme.dersler.any((d) => !d.gorevMi)) ...[
                const Divider(height: 28),
                KeyedSubtree(
                  key: _sinifSubeBolumuKey,
                  child: _sinifSubeOnayBolumu(onIzleme),
                ),
              ],
              if (_sinifSubelerOnaylandi && onIzleme.dersler.any((d) => !d.gorevMi)) ...[
                const Divider(height: 28),
                KeyedSubtree(
                  key: _dersAdiBolumuKey,
                  child: _dersAdiOnayBolumu(onIzleme),
                ),
              ],
              if (_dersAdlariOnaylandi) ...[
                const Divider(height: 28),
                KeyedSubtree(
                  key: _derslikBolumuKey,
                  child: _derslikOnayBolumu(onIzleme),
                ),
              ],
            ],
            const SizedBox(height: 14),
            Text(
              onIzleme.ogretmenBulundu
                  ? (_dersliklerOnaylandi
                      ? 'Ders programı bireysel öğretmen SQLite '
                          'veritabanına kaydedildi.'
                      : 'Bu aşama ön izleme ve adım adım onay aşamasıdır. '
                          '4. adımda Ders Programını Kaydet seçilene kadar '
                          'SQLite veritabanına kayıt yapılmaz.')
                  : 'Profildeki Ad Soyad bilgisi dosya içinde bulunamadı. '
                      'Öğretmen adı eşleştirilmeden kayıt yapılmayacak.',
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gunBazliDersSaatleriOnayBolumu(
    BireyselDersProgramiOnIzleme onIzleme,
  ) {
    final adaylar = onIzleme.gunlukDersSaatAdaylari;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 15,
              child: Text(
                '1',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Gün Bazlı Ders Saatleri Onayı',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_dersSaatleriOnaylandi)
              const Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Excel’de ortak bir saat başlığı varsa ilk değerleri tüm günlere '
          'aday olarak dağıtıyorum. Her günün saatlerini ayrı ayrı '
          'seçebilir ve düzenleyebilirsiniz.',
          style: TextStyle(
            color: Colors.grey.shade700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        if (adaylar.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Ders saati adayı bulunamadı. Excel başlık yapısını ayrıca '
              'incelememiz gerekiyor.',
            ),
          )
        else ...[
          ..._gunSirasi.map(
            (gun) => _gunDersSaatleriKarti(
              gun: gun,
              adaylar: adaylar
                  .where((aday) => aday.gun == gun)
                  .toList()
                ..sort(
                  (a, b) => a.dersSaatiNo.compareTo(b.dersSaatiNo),
                ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _dersSaatleriOnaylandi
                  ? null
                  : _dersSaatleriniOnayla,
              icon: Icon(
                _dersSaatleriOnaylandi
                    ? Icons.check_circle_outline
                    : Icons.done_all,
              ),
              label: Text(
                _dersSaatleriOnaylandi
                    ? 'Gün Bazlı Saatler Onaylandı'
                    : 'Gün Bazlı Saatleri Onayla',
              ),
            ),
          ),
          if (_dersSaatleriOnaylandi) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '1. adım tamamlandı. Her günün ders saatleri ayrı ayrı '
                'onaylandı. Sonraki adım sınıf/şube onayı olacak.',
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _sinifSubeOnayBolumu(
    BireyselDersProgramiOnIzleme onIzleme,
  ) {
    final adaylar = _sinifSubeAdaylariniGetir(onIzleme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 15,
              child: Text(
                '2',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Sınıf / Şube Onayı',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_sinifSubelerOnaylandi)
              const Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Excel’de öğretmenin ders kayıtlarında bulunan sınıf/şubeler '
          'aday olarak listelenir. Kullanmak istemediklerinizin seçimini '
          'kaldırabilirsiniz.',
          style: TextStyle(
            color: Colors.grey.shade700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        if (adaylar.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Sınıf/şube adayı bulunamadı. Excel ders hücrelerindeki '
              'sınıf bilgisini ayrıca incelememiz gerekiyor.',
            ),
          )
        else ...[
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: adaylar
                  .map(
                    (sinif) => CheckboxListTile(
                      value: _seciliSinifSubeler.contains(sinif),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        sinif,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onChanged: _sinifSubelerOnaylandi
                          ? null
                          : (deger) {
                              setState(() {
                                if (deger == true) {
                                  _seciliSinifSubeler.add(sinif);
                                } else {
                                  _seciliSinifSubeler.remove(sinif);
                                }
                              });
                            },
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _sinifSubelerOnaylandi
                  ? null
                  : () => _sinifSubeleriOnayla(onIzleme),
              icon: Icon(
                _sinifSubelerOnaylandi
                    ? Icons.check_circle_outline
                    : Icons.done_all,
              ),
              label: Text(
                _sinifSubelerOnaylandi
                    ? 'Sınıf / Şubeler Onaylandı'
                    : 'Sınıf / Şubeleri Onayla',
              ),
            ),
          ),
          if (_sinifSubelerOnaylandi) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '2. adım tamamlandı. Sınıf/şubeler onaylandı. '
                'Sonraki adım ders adları onayı olacak.',
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _dersAdiOnayBolumu(
    BireyselDersProgramiOnIzleme onIzleme,
  ) {
    final adaylar = _dersAdiAdaylariniGetir(onIzleme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 15,
              child: Text(
                '3',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Ders Adları Onayı',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_dersAdlariOnaylandi)
              const Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Seçtiğiniz sınıf/şubelere ait ders adları Excel’den aday olarak '
          'listelenir. Kullanmak istemediklerinizin seçimini '
          'kaldırabilirsiniz.',
          style: TextStyle(
            color: Colors.grey.shade700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        if (adaylar.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Ders adı adayı bulunamadı. Excel ders kayıtlarındaki ders '
              'adı bilgisini ayrıca incelememiz gerekiyor.',
            ),
          )
        else ...[
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: adaylar
                  .map(
                    (dersAdi) => CheckboxListTile(
                      value: _seciliDersAdlari.contains(dersAdi),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        dersAdi,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onChanged: _dersAdlariOnaylandi
                          ? null
                          : (deger) {
                              setState(() {
                                if (deger == true) {
                                  _seciliDersAdlari.add(dersAdi);
                                } else {
                                  _seciliDersAdlari.remove(dersAdi);
                                }
                              });
                            },
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _dersAdlariOnaylandi
                  ? null
                  : () => _dersAdlariniOnayla(onIzleme),
              icon: Icon(
                _dersAdlariOnaylandi
                    ? Icons.check_circle_outline
                    : Icons.done_all,
              ),
              label: Text(
                _dersAdlariOnaylandi
                    ? 'Ders Adları Onaylandı'
                    : 'Ders Adlarını Onayla',
              ),
            ),
          ),
          if (_dersAdlariOnaylandi) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '3. adım tamamlandı. Ders adları onaylandı. '
                'Sonraki adım derslik/laboratuvar onayı olacak.',
              ),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _programTarihiSec() async {
    final secilen = await showDatePicker(
      context: context, initialDate: _programBaslangicTarihi ?? DateTime.now(),
      firstDate: DateTime(1900), lastDate: DateTime(9999, 12, 31),
      helpText: 'Ders programı başlangıç tarihi',
    );
    if (!mounted || secilen == null) return;
    setState(() => _programBaslangicTarihi = secilen);
  }

  Widget _seflikOnayBolumu(BireyselDersProgramiOnIzleme onIzleme) {
    if (!_meslekPaketiAktif || onIzleme.seflikSaatleri.isEmpty) {
      return const SizedBox.shrink();
    }
    final kilitli = _kayitYapiliyor || _dersliklerOnaylandi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        const Text('Şeflik Saatleri',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Aktarılacak saatleri seçin. Şeflik türü veya tanımı otomatik '
            'atanmaz; Excel metni korunur. Şeflik saatleri ders programıyla aynı '
            'başlangıç tarihini kullanır. Önceki import saatleri bir önceki '
            'ders gününde biter. Manuel şeflik saatleri korunur. Hiç saat '
            'seçmezseniz yeni programda import şeflik saati bulunmaz.'),
        for (var i = 0; i < onIzleme.seflikSaatleri.length; i++)
          CheckboxListTile(
            value: _seciliSeflikSaatleri.contains(i),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('${onIzleme.seflikSaatleri[i].gun} — '
                '${onIzleme.seflikSaatleri[i].dersSaatiNo}. saat — '
                '${onIzleme.seflikSaatleri[i].hamMetin}'),
            subtitle: Text(
              '${_baslangicSaatleri[onIzleme.seflikSaatleri[i].gun]?[onIzleme.seflikSaatleri[i].dersSaatiNo] ?? "Saat eksik"}'
              ' - ${_bitisSaatleri[onIzleme.seflikSaatleri[i].gun]?[onIzleme.seflikSaatleri[i].dersSaatiNo] ?? "Saat eksik"}',
            ),
            onChanged: kilitli ? null : (secili) => setState(() {
              if (secili == true) {
                _seciliSeflikSaatleri.add(i);
              } else {
                _seciliSeflikSaatleri.remove(i);
              }
              _seflikOnaylandi = false;
            }),
          ),
        CheckboxListTile(
          value: _seflikOnaylandi,
          title: Text(_seciliSeflikSaatleri.isEmpty
              ? 'Şeflik saatlerini aktarmamayı onaylıyorum.'
              : 'Şeflik saatlerini onaylıyorum.'),
          onChanged: kilitli
              ? null : (deger) => setState(() => _seflikOnaylandi = deger == true),
        ),
      ],
    );
  }

  Widget _derslikOnayBolumu(
    BireyselDersProgramiOnIzleme onIzleme,
  ) {
    final adaylar = _derslikAdaylariniGetir(onIzleme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 15,
              child: Text(
                '4',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Derslik / Laboratuvar Onayı',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_dersliklerOnaylandi)
              const Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Seçili sınıf/şube ve ders adlarına ait derslik/laboratuvar '
          'bilgileri Excel’den aday olarak listelenir. Virgül veya noktalı '
          'virgülle gelen laboratuvarlar ayrı ve tekil adaylar olarak '
          'gösterilir. Bir ders kaydında birden fazla laboratuvar varsa '
          'Excel’deki ilk uygun seçenek otomatik kaydedilir; öğretmen '
          'sonradan manuel olarak değiştirebilir.',
          style: TextStyle(
            color: Colors.grey.shade700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        if (adaylar.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Seçili ders kayıtlarında dolu derslik/laboratuvar bilgisi '
              'bulunamadı. Boş değerlerden sahte derslik oluşturulmayacak.',
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: adaylar
                  .map(
                    (derslik) => CheckboxListTile(
                      value: _seciliDerslikler.contains(derslik),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        derslik,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onChanged: _dersliklerOnaylandi || _kayitYapiliyor
                          ? null
                          : (deger) {
                              setState(() {
                                if (deger == true) {
                                  _seciliDerslikler.add(derslik);
                                } else {
                                  _seciliDerslikler.remove(derslik);
                                }
                              });
                            },
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 12),
        _seflikOnayBolumu(onIzleme),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _dersliklerOnaylandi || _kayitYapiliyor ||
                (_meslekPaketiAktif && onIzleme.seflikSaatleri.isNotEmpty &&
                    !_seflikOnaylandi)
                ? null
                : () => _derslikleriOnayla(onIzleme),
            icon: _kayitYapiliyor
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                    ),
                  )
                : Icon(
                    _dersliklerOnaylandi
                        ? Icons.check_circle_outline
                        : Icons.save_outlined,
                  ),
            label: Text(
              _kayitYapiliyor
                  ? 'Kaydediliyor...'
                  : _dersliklerOnaylandi
                      ? 'Ders Programı Kaydedildi'
                      : 'Ders Programını Kaydet',
            ),
          ),
        ),
        if (_dersliklerOnaylandi) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '4. adım tamamlandı. Ders programı SQLite veritabanına '
              'kaydedildi. Birden fazla laboratuvar olan derslerde ilk '
              'uygun seçenek kaydedildi; daha sonra manuel düzenlenebilir.',
            ),
          ),
        ],
      ],
    );
  }

  Widget _gunDersSaatleriKarti({
    required String gun,
    required List<BireyselGunlukDersSaatiAdayi> adaylar,
  }) {
    final secili = _seciliDersSaatleri[gun] ?? <int>{};

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: OrtakGenisleyenBolum(
        initiallyExpanded: gun == 'Pazartesi',
        title: Text(
          gun,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${secili.length}/${adaylar.length} ders saati seçili',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          12,
          0,
          12,
          12,
        ),
        children: [
          if (!_dersSaatleriOnaylandi)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _gunuDigerGunlereUygula(gun),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Bu günü diğer günlere uygula'),
              ),
            ),
          ...adaylar.map(
            (aday) {
              final baslangic =
                  _baslangicSaatleri[gun]?[aday.dersSaatiNo] ??
                      aday.baslangic;
              final bitis =
                  _bitisSaatleri[gun]?[aday.dersSaatiNo] ?? aday.bitis;

              return CheckboxListTile(
                value: secili.contains(aday.dersSaatiNo),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '${aday.dersSaatiNo}. Ders',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text('$baslangic → $bitis'),
                secondary: IconButton(
                  tooltip: 'Saati düzenle',
                  onPressed: _dersSaatleriOnaylandi
                      ? null
                      : () => _dersSaatiniDuzenle(
                            gun: gun,
                            dersSaatiNo: aday.dersSaatiNo,
                          ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                onChanged: _dersSaatleriOnaylandi
                    ? null
                    : (deger) {
                        setState(() {
                          final gunSecimleri =
                              _seciliDersSaatleri.putIfAbsent(
                            gun,
                            () => <int>{},
                          );

                          if (deger == true) {
                            gunSecimleri.add(aday.dersSaatiNo);
                          } else {
                            gunSecimleri.remove(aday.dersSaatiNo);
                          }
                        });
                      },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _bilgiSatiri(String baslik, String deger) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              '$baslik:',
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              deger,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
