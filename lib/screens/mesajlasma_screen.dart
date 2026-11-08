import '../widgets/ortak_liste_arac_cubugu.dart';
import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import '../widgets/mesajlasma_gorunumu.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/mesajlasma.dart';
import '../models/mesaj_sablonu.dart';
import 'mesaj_sablon_ayarlar_screen.dart';
import '../services/mesajlasma_service.dart';
import '../widgets/veli_secim_dialog.dart';
import '../widgets/mesaj_telefon_dialog.dart';
import '../widgets/mesaj_alici_secim_sliver.dart';
import '../widgets/mesaj_alici_duzenleme_dialog.dart';
import '../widgets/mesaj_eksik_telefon_dialog.dart';
import 'import_merkezi_screen.dart';

/// Diğer modüller bu ortak ekranı başlangıç metni/seçimiyle açabilir.
class MesajlasmaScreen extends StatefulWidget {
  const MesajlasmaScreen({
    super.key,
    this.service,
    this.kaynakModul = 'Mesajlasma',
    this.kaynakKayit,
    this.baslangicMetni = '',
    this.baslangicOgrenciIdleri = const {},
    this.izinliOgrenciIdleri,
    this.ogrenciMesajlari,
    this.kaynakGecmisiniGoster = false,
    this.ogrenciTelefonu = false,
    this.eksikTelefonlariSor = false,
    this.gonderimOnizlemesiniAc = false,
    this.yalnizGonderimOnayi = false,
    this.takipPenceresi = false,
    this.ogretmenSinifId,
    this.baslangicOgretmenIdleri,
    this.baslangicKisiBaglari,
    this.kaynakKontrol,
  });
  final MesajlasmaService? service;
  final String kaynakModul, baslangicMetni;
  final String? kaynakKayit;
  final Set<int> baslangicOgrenciIdleri;

  /// null: genel mesajlaşma; boş küme: hiçbir öğrenciye izin yok.
  final Set<int>? izinliOgrenciIdleri;
  final Map<int, String>? ogrenciMesajlari;
  final bool kaynakGecmisiniGoster;
  final bool ogrenciTelefonu;
  final bool eksikTelefonlariSor;
  final bool gonderimOnizlemesiniAc;
  final bool yalnizGonderimOnayi;
  final bool takipPenceresi;

  /// Kaynak modülden yalnız bu sınıfın ders öğretmenlerine gönderim.
  final int? ogretmenSinifId;
  final Set<String>? baslangicOgretmenIdleri;
  final Set<String>? baslangicKisiBaglari;
  final Future<void> Function(MesajBaglami)? kaynakKontrol;
  @override
  State<MesajlasmaScreen> createState() => _MesajlasmaScreenState();
}

enum _GonderimYolu { sms, whatsapp }

class _MesajlasmaScreenState extends State<MesajlasmaScreen>
    with WidgetsBindingObserver {
  late final _service =
      widget.service ??
      (widget.ogrenciTelefonu
          ? MesajlasmaService(ogrenciTelefonu: true)
          : MesajlasmaService.instance);
  late final _metin = TextEditingController(text: widget.baslangicMetni);
  final _arama = TextEditingController();
  final _gecmisArama = TextEditingController();
  List<Map<String, Object?>> _tekliKayitlar = [];
  final _gecmisSecili = <String>{};
  String? _gecmisSinif;
  int? _gecmisOgrenci;
  bool _gecmisAramaAcik = false, _gecmisFiltreAcik = false;
  String? _gecmisKanal, _gecmisDurum;
  DateTimeRange? _gecmisTarih;
  int _gecmisSiralama = 0;
  final _mesajOdak = FocusNode();
  final _mesajAlani = GlobalKey();
  final _hazirlamaKaydirma = ScrollController();
  String? _mesajHatasi;
  bool _mesajOdakIsteniyor = false;
  MesajKuyrugu? _tekliOnay;
  bool _tekliDondu = false;
  late final Set<int> _secili = {...widget.baslangicOgrenciIdleri};
  late final Set<int>? _izinli;
  List<MesajOgrencisi> _kapsamdakiler(List<MesajOgrencisi> students) =>
      students.where((o) => _izinli == null || _izinli.contains(o.id)).toList();
  void _kapsamKontrol(Iterable<int> ids) {
    if (_izinli != null && ids.any((id) => !_izinli.contains(id))) {
      throw StateError('Alıcılar görüş talebinin öğrenci kapsamı dışında.');
    }
  }

  MesajSablonListesi? _sablonListesi;
  MesajKisiTuru? _hazirMesajTuru;
  MesajKisiTuru? get _sablonTuru => _yeniSecim
      ? _hazirMesajTuru
      : widget.ogrenciTelefonu
      ? MesajKisiTuru.ogrenci
      : MesajKisiTuru.veli;
  List<MesajSablonu> get _uygunSablonlar =>
      _sablonListesi?.sablonlar.where((s) => s.tur == _sablonTuru).toList() ??
      [];
  int _sablonSurumu = 0;
  MesajBaglami? _baglam;
  List<MesajOgrencisi> _ogrenciler = [];
  List<MesajKuyrugu> _kuyruklar = [];
  MesajKuyrugu? _aktif;
  bool _gonderimBasliyor = false, _whatsappDisarida = false;
  String? _hata;
  bool _busy = false, _gecmis = false;
  bool _duzenlendi = false, _cikisOnaylandi = false;
  int? _sinif;
  // Kaynak modüllerin hazır/kısıtlı alıcı akışları sonraki uyarlamaya kadar korunur.
  bool get _yeniSecim =>
      widget.baslangicKisiBaglari != null ||
      widget.ogretmenSinifId != null ||
      (widget.kaynakModul == 'Mesajlasma' &&
          widget.kaynakKayit == null &&
          widget.baslangicOgrenciIdleri.isEmpty &&
          _izinli == null &&
          widget.ogrenciMesajlari == null &&
          !widget.ogrenciTelefonu &&
          !widget.eksikTelefonlariSor);
  List<MesajKisi> _kisiler = [];
  Map<int, String> _siniflar = {};
  final _seciliKisiler = <String, MesajKisi>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _izinli = widget.izinliOgrenciIdleri == null
        ? null
        : Set<int>.unmodifiable(widget.izinliOgrenciIdleri!);
    _ilkYukle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _metin.dispose();
    _arama.dispose();
    _gecmisArama.dispose();
    _mesajOdak.dispose();
    _hazirlamaKaydirma.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      if (_whatsappDisarida) setState(() => _whatsappDisarida = false);
      if (_tekliOnay != null) {
        _tekliDondu = true;
        if (!_busy) _islem(_tekliOnayiSor);
      }
    } else if (_aktif != null &&
        _gonderimBasliyor &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused)) {
      setState(() => _whatsappDisarida = true);
    }
  }

  @override
  void didChangeMetrics() {
    if (!_mesajOdak.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final alan = _mesajAlani.currentContext;
      if (alan != null) {
        Scrollable.ensureVisible(
          alan,
          alignment: .15,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  void _mesajUyarisi(String metin) {
    setState(() {
      _hata = null;
      _mesajHatasi = metin;
      _mesajOdakIsteniyor = true;
    });
  }

  bool _metniDogrula(String metin) {
    if (metin.trim().isEmpty) {
      _mesajUyarisi('Lütfen göndermek istediğiniz mesajı yazın.');
      return false;
    }
    if (metin.trim().length > 4000) {
      _mesajUyarisi(
        'Mesajınız en fazla 4000 karakter olabilir. Lütfen kısaltın.',
      );
      return false;
    }
    if (_mesajHatasi != null) setState(() => _mesajHatasi = null);
    return true;
  }

  String? _dogrulanmisMesaj({Iterable<MesajKisi>? alicilar}) {
    try {
      final text = _mesajiHazirla(_metin.text, alicilar: alicilar);
      return _metniDogrula(text) ? text : null;
    } on StateError catch (e) {
      _mesajUyarisi(e.message.toString());
      return null;
    }
  }

  Future<void> _mesajaGit() async {
    if (!mounted) return;
    // Sliver listesi kayarken tahmini uzunluk kesinleşir; yeni sonu da izle.
    if (_yeniSecim && _hazirlamaKaydirma.hasClients) {
      for (var i = 0; i < 3; i++) {
        if (!mounted || !_hazirlamaKaydirma.hasClients) return;
        await _hazirlamaKaydirma.animateTo(
          _hazirlamaKaydirma.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_hazirlamaKaydirma.hasClients) return;
        final konum = _hazirlamaKaydirma.position;
        if ((konum.maxScrollExtent - konum.pixels).abs() < 1) break;
      }
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _mesajAlani.currentContext == null) return;
    if (widget.ogrenciMesajlari == null) _mesajOdak.requestFocus();
    await Scrollable.ensureVisible(
      _mesajAlani.currentContext!,
      alignment: .15,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _tekliOnayiSor() async {
    final bekleyen = _tekliOnay;
    if (bekleyen == null || !mounted) return;
    _tekliOnay = null;
    _tekliDondu = false;
    final q = await _service.kuyrukGetir(_baglam!, bekleyen.id);
    final a = q.siradaki;
    if (!mounted || a == null || a.durum != 'Acildi') {
      if (widget.takipPenceresi) _kaynagaDon();
      return;
    }
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Mesajı gönderdiniz mi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MesajTakipAliciOzeti(alici: a),
            const SizedBox(height: 12),
            const Text(
              'WhatsApp mesajını gönderdiyseniz onaylayın. '
              'WhatsApp gönderim bilgisini uygulamaya bildirmez.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Daha sonra'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Evet, gönderdim'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) {
      if (widget.takipPenceresi) _kaynagaDon();
      return;
    }
    await _service.aliciyiSonuclandir(_baglam!, q.id, a.id, gonderdim: true);
    await _yenile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gönderim onayınız kaydedildi.')),
      );
    }
    if (widget.takipPenceresi) _kaynagaDon();
  }

  Future<void> _islem(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'İşlem tamamlanamadı. Orijinal hata: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _gonderimBasliyor = false;
        });
        if (_mesajOdakIsteniyor) {
          _mesajOdakIsteniyor = false;
          await _mesajaGit();
        }
        if (mounted && _tekliDondu && _tekliOnay != null) {
          await _islem(_tekliOnayiSor);
        }
      }
    }
  }

  bool _kaynakDonusu = false;
  void _kaynagaDon() {
    if (!mounted || _kaynakDonusu) return;
    _kaynakDonusu = true;
    Navigator.of(context).pop();
  }

  Future<void> _ilkYukle() async {
    await _islem(() async {
      final b = await _service.hazirla();
      await widget.kaynakKontrol?.call(b);
      final sablonlar = await _service.hazirMesajlariGetir(b);
      final students = _kapsamdakiler(await _service.ogrenciler(b));
      final queues = await _kapsamKuyruklari(b);
      final tekli = await _tekliGecmisi(b);
      var kisiler = _yeniSecim
          ? await _service.aliciAdaylari(
              b,
              tur: widget.ogretmenSinifId == null
                  ? null
                  : MesajKisiTuru.ogretmen,
              sinifId: widget.ogretmenSinifId,
            )
          : <MesajKisi>[];
      if (widget.baslangicKisiBaglari != null) {
        kisiler = kisiler
            .where((k) => widget.baslangicKisiBaglari!.contains(k.bagAnahtari))
            .toList();
      }
      final siniflar = _yeniSecim
          ? await _service.mesajSiniflari(b)
          : <Map<String, Object?>>[];
      if (!mounted) return;
      setState(() {
        _baglam = b;
        if (_sablonListesi?.kayit != sablonlar.kayit) _sablonSurumu++;
        _sablonListesi = sablonlar;
        _ogrenciler = students;
        _kuyruklar = queues;
        _tekliKayitlar = tekli;
        _gecmisSecili.retainAll(_secilebilirGecmis);
        _kisiler = kisiler;
        if (widget.baslangicKisiBaglari != null) {
          _seciliKisiler.addEntries(
            kisiler.map((k) => MapEntry(k.secimAnahtari, k)),
          );
          _hazirMesajTuru = kisiler.isEmpty ? null : kisiler.first.tur;
        }
        if (widget.ogretmenSinifId != null) {
          _hazirMesajTuru = MesajKisiTuru.ogretmen;
          _seciliKisiler.addEntries(
            kisiler
                .where(
                  (k) =>
                      widget.baslangicOgretmenIdleri == null ||
                      widget.baslangicOgretmenIdleri!.contains(k.kisiId),
                )
                .map((k) => MapEntry(k.secimAnahtari, k)),
          );
        }
        _siniflar = {
          for (final s in siniflar)
            s['SinifSubeId'] as int: s['SinifKodu'] as String,
        };
        _secili.removeWhere((id) => !students.any((o) => o.id == id));
        if (widget.ogrenciMesajlari != null) {
          _secili.removeWhere(_dahaOnceKuyrukta);
          _gecmis = (queues.isNotEmpty || tekli.isNotEmpty) && _secili.isEmpty;
        }
        if (widget.kaynakGecmisiniGoster &&
            (queues.isNotEmpty || tekli.isNotEmpty)) {
          _gecmis = true;
        }
      });
      if (widget.gonderimOnizlemesiniAc &&
          _yeniSecim &&
          !_gecmis &&
          _seciliKisiler.isNotEmpty) {
        setState(() => _busy = false);
        await _yeniOnayIcerigi();
      }
      if (widget.eksikTelefonlariSor &&
          !_gecmis &&
          _preview.gecersizler.isNotEmpty) {
        await _telefonlariTamamla(_preview.gecersizler, sonlandir: true);
      }
    });
    if (widget.yalnizGonderimOnayi &&
        mounted &&
        _aktif == null &&
        _tekliOnay == null) {
      if (_hata != null) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Gönderim başlatılamadı'),
            content: Text(_hata!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
      _kaynagaDon();
    }
  }

  Future<void> _yenile() async {
    final b = _baglam!;
    await widget.kaynakKontrol?.call(b);
    final sablonlar = await _service.hazirMesajlariGetir(b);
    final students = _kapsamdakiler(await _service.ogrenciler(b));
    final queues = await _kapsamKuyruklari(b);
    final tekli = await _tekliGecmisi(b);
    var kisiler = _yeniSecim
        ? await _service.aliciAdaylari(
            b,
            tur: widget.ogretmenSinifId == null ? null : MesajKisiTuru.ogretmen,
            sinifId: widget.ogretmenSinifId,
          )
        : <MesajKisi>[];
    if (widget.baslangicKisiBaglari != null) {
      kisiler = kisiler
          .where((k) => widget.baslangicKisiBaglari!.contains(k.bagAnahtari))
          .toList();
    }
    final siniflar = _yeniSecim
        ? await _service.mesajSiniflari(b)
        : <Map<String, Object?>>[];
    final active = _aktif == null
        ? null
        : await _service.kuyrukGetir(b, _aktif!.id);
    if (!mounted) return;
    setState(() {
      if (_sablonListesi?.kayit != sablonlar.kayit) _sablonSurumu++;
      _sablonListesi = sablonlar;
      _ogrenciler = students;
      _kuyruklar = queues;
      _tekliKayitlar = tekli;
      _gecmisSecili.retainAll(_secilebilirGecmis);
      if (_yeniSecim) {
        _kisiler = kisiler;
        _siniflar = {
          for (final s in siniflar)
            s['SinifSubeId'] as int: s['SinifKodu'] as String,
        };
        final guncel = {for (final k in kisiler) k.bagAnahtari: k};
        final onceki = _seciliKisiler.values.toList();
        _seciliKisiler.clear();
        for (final k in onceki) {
          final yeni = guncel[k.bagAnahtari];
          if (yeni != null) _seciliKisiler[yeni.secimAnahtari] = yeni;
        }
        if (_seciliKisiler.length != onceki.length) {
          _hata =
              '${onceki.length - _seciliKisiler.length} alıcı güncel ders kapsamından çıktığı için seçimden çıkarıldı.';
        }
      }
      _aktif = active;
      if (!students.any((o) => o.sinifId == _sinif)) _sinif = null;
      _secili.removeWhere((id) => !students.any((o) => o.id == id));
      if (!_gecmisSinifSecenekleri.contains(_gecmisSinif)) _gecmisSinif = null;
      if (!_gecmisOgrenciSecenekleri.containsKey(_gecmisOgrenci)) {
        _gecmisOgrenci = null;
      }
      _gecmisSecili.retainAll(_secilebilirGecmis);
    });
  }

  List<MesajOgrencisi> get _gorunen {
    final search = _arama.text.trim().toLowerCase();
    return _ogrenciler
        .where(
          (o) =>
              (_sinif == null || o.sinifId == _sinif) &&
              '${o.aciklama} ${o.veliAdi} ${o.telefon}'.toLowerCase().contains(
                search,
              ),
        )
        .toList();
  }

  Future<List<MesajKuyrugu>> _kapsamKuyruklari(MesajBaglami b) async {
    if (_izinli != null &&
        widget.ogrenciMesajlari == null &&
        !widget.kaynakGecmisiniGoster) {
      return [];
    }
    final rows = (await _service.kuyruklar(b)).where((q) =>
      widget.kaynakModul != 'Mesajlasma' || q.kaynakModul == 'Mesajlasma').toList();
    if (widget.ogretmenSinifId != null || widget.baslangicKisiBaglari != null) {
      return rows
          .where(
            (q) =>
                q.kaynakModul == widget.kaynakModul &&
                q.kaynakKayit == widget.kaynakKayit,
          )
          .toList();
    }
    if (_izinli == null) return rows;
    return rows
        .where(
          (q) =>
              q.kaynakModul == widget.kaynakModul &&
              q.kaynakKayit == widget.kaynakKayit &&
              q.alicilar.every(
                (a) =>
                    _gecmisEkFiltre(
                      q.tarih,
                      a.smsDurumu == null ? 'WhatsApp' : 'SMS',
                      a.smsDurumu ?? a.durum,
                    ) &&
                    (jsonDecode(a.ogrenciler) as List).every(
                      (o) => _izinli.contains(o['id']),
                    ),
              ),
        )
        .toList();
  }

  Future<List<Map<String, Object?>>> _tekliGecmisi(MesajBaglami b) async {
    if (_izinli != null &&
        widget.ogrenciMesajlari == null &&
        !widget.kaynakGecmisiniGoster) {
      return [];
    }
    final rows = (await _service.tekliGecmis(b)).where((r) =>
      widget.kaynakModul != 'Mesajlasma' || r['KaynakModul'] == 'Mesajlasma').toList();
    if (widget.ogretmenSinifId != null || widget.baslangicKisiBaglari != null) {
      return rows
          .where(
            (r) =>
                r['KaynakModul'] == widget.kaynakModul &&
                r['KaynakKayit'] == widget.kaynakKayit,
          )
          .toList();
    }
    return rows
        .where(
          (r) =>
              _izinli == null ||
              (r['KaynakModul'] == widget.kaynakModul &&
                  r['KaynakKayit'] == widget.kaynakKayit &&
                  _izinli.contains(r['OgrenciId'])),
        )
        .toList();
  }

  bool _dahaOnceKuyrukta(int id) =>
      _tekliKayitlar.any(
        (r) => r['OgrenciId'] == id && r['Durum'] != 'Acilamadi',
      ) ||
      _kuyruklar.any(
        (q) => q.alicilar.any(
          (a) =>
              _gecmisEkFiltre(
                q.tarih,
                a.smsDurumu == null ? 'WhatsApp' : 'SMS',
                a.smsDurumu ?? a.durum,
              ) &&
              (jsonDecode(a.ogrenciler) as List).any((o) => o['id'] == id),
        ),
      );

  MesajOnIzleme get _preview {
    final unique = <int, MesajOgrencisi>{};
    for (final o in _ogrenciler.where((o) => _secili.contains(o.id))) {
      unique.putIfAbsent(o.id, () => o);
    }
    return MesajOnIzleme(unique.values.toList());
  }

  Future<void> _iletisim(MesajOgrencisi o) => _islem(() async {
    final bilgiler = await _service.veliBilgileri(_baglam!, o.id);
    if (!mounted) return;
    final secim = await showDialog<VeliSecimi>(
      context: context,
      builder: (_) => VeliSecimDialog(ogrenci: bilgiler),
    );
    if (secim == null || !mounted) return;
    await _service.iletisimKaydet(
      _baglam!,
      o.id,
      secim.ad,
      secim.telefon,
      veliTuru: secim.tur,
      onceki: secim.onceki,
    );
    await _yenile();
  });

  Future<bool> _telefonlariTamamla(
    List<MesajOgrencisi> kisiler, {
    required bool sonlandir,
  }) async {
    final ids = kisiler.map((o) => o.id).toSet();
    _kapsamKontrol(ids);
    final bilgiler = await _service.telefonDuzenlemeBilgileri(_baglam!, ids);
    if (!mounted) return false;
    final degerler = await showDialog<Map<int, String>>(
      context: context,
      builder: (_) => MesajTelefonDialog(
        bilgiler: bilgiler,
        gecerliAliciVar: _preview.alicilar.isNotEmpty,
        islemiSonlandir: sonlandir,
      ),
    );
    if (!mounted) return false;
    if (degerler == null) {
      if (sonlandir) Navigator.of(context).pop();
      return false;
    }
    if (degerler.isNotEmpty) {
      await _service.telefonlariKaydet(_baglam!, degerler, beklenen: bilgiler);
    }
    await _yenile();
    if (!mounted) return false;
    // Boş bırakılanlar açıkça kapsam dışında; kuyrukta geçersiz alıcı oluşmaz.
    setState(
      () => _secili.removeWhere(
        (id) =>
            !_ogrenciler.any((o) => o.id == id && o.normalizeTelefon != null),
      ),
    );
    return true;
  }

  Future<void> _sablonAyarlari() => _islem(() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MesajSablonAyarlarScreen(
          service: _service,
          baglam: _baglam!,
          baslangicTuru: _sablonTuru ?? MesajKisiTuru.veli,
        ),
      ),
    );
    if (!mounted) return;
    final liste = await _service.hazirMesajlariGetir(_baglam!);
    if (mounted) {
      setState(() {
        _sablonListesi = liste;
        _sablonSurumu++;
      });
    }
  });

  String _mesajiHazirla(String ham, {Iterable<MesajKisi>? alicilar}) {
    final kisiler = alicilar ?? _seciliKisiler.values;
    final ids = kisiler
        .where((k) => k.tur != MesajKisiTuru.ogretmen)
        .map((k) => k.kisiId)
        .toSet();
    final secilen = _yeniSecim
        ? {
            for (final o in _ogrenciler.where((o) => ids.contains('${o.id}')))
              o.id: o,
          }.values.toList()
        : _preview.secilenler;
    final siniflar = _yeniSecim
        ? kisiler.map((k) => _siniflar[k.sinifId]).whereType<String>().toSet()
        : secilen.map((o) => o.sinif).toSet();
    var sonuc = ham.trim();
    if (sonuc.contains('{OgrenciAdi}')) {
      if (secilen.length != 1 ||
          (_yeniSecim && kisiler.any((k) => k.tur == MesajKisiTuru.ogretmen))) {
        throw StateError(
          'Öğrenci adı değişkeni için yalnız bir öğrenci seçin.',
        );
      }
      sonuc = sonuc.replaceAll('{OgrenciAdi}', secilen.single.ad);
    }
    if (sonuc.contains('{Sinif}')) {
      if (siniflar.length != 1) {
        throw StateError('Sınıf değişkeni için aynı sınıftan öğrenci seçin.');
      }
      sonuc = sonuc.replaceAll('{Sinif}', siniflar.single);
    }
    final simdi = DateTime.now();
    final tarih =
        '${simdi.day.toString().padLeft(2, '0')}.'
        '${simdi.month.toString().padLeft(2, '0')}.${simdi.year}';
    sonuc = sonuc.replaceAll('{Tarih}', tarih);
    if (RegExp(r'\{[^{}]+\}').hasMatch(sonuc)) {
      throw StateError('Mesajda tanınmayan veya eksik değişken var.');
    }
    return sonuc;
  }

  String _veliBasligi(String? tur) => switch (tur) {
    'Anne' => 'Veli (Anne)',
    'Baba' => 'Veli (Baba)',
    'Diger' => 'Veli (Diğer veli)',
    _ => 'Veli (türü belirtilmemiş)',
  };

  String _kisiBasligi(MesajKisi k) =>
      k.tur == MesajKisiTuru.veli ? _veliBasligi(k.veliTuru) : k.tur.baslik;

  MesajKisi _kaynakAlicisi(MesajOgrencisi o) => MesajKisi(
    tur: widget.ogrenciTelefonu ? MesajKisiTuru.ogrenci : MesajKisiTuru.veli,
    kisiId: '${o.id}',
    sinifId: o.sinifId,
    ad: o.veliAdi,
    telefon: o.telefon,
    aciklama: o.aciklama,
    veliTuru: widget.ogrenciTelefonu ? null : o.veliTuru,
    telefonAciklamasi: o.telefonAciklamasi,
  );

  Widget _onizlemeAlici(
    MesajKisi k,
    ValueChanged<MesajKisi> duzenle,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '+${k.normalizeTelefon}\n${_kisiBasligi(k)} • ${k.tur == MesajKisiTuru.veli && ['', 'Babası', 'Annesi'].contains(k.ad.trim()) ? 'Adı kaydedilmemiş' : k.ad}\n${k.aciklama}'
            '${k.telefonAciklamasi == null ? '' : '\n${k.telefonAciklamasi}'}',
          ),
        ),
        IconButton(
          key: ValueKey('onizleme-telefon-${k.bagAnahtari}'),
          tooltip: 'Telefonu düzenle',
          onPressed: () => duzenle(k),
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    ),
  );

  Future<void> _onizlemeTelefonDuzenle(MesajKisi k) async {
    final veli = k.tur == MesajKisiTuru.veli && k.veliTuru != null;
    final bilgiler = veli
        ? await _service.veliBilgileri(_baglam!, int.parse(k.kisiId))
        : null;
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => MesajKisiTelefonDialog(
        kisi: k,
        veliAdi: veli
            ? (bilgiler![k.veliTuru == 'Diger'
                          ? 'DigerVeliAdi'
                          : '${k.veliTuru}Adi'] ??
                      '')
                  .toString()
            : null,
        veliKaydet: veli
            ? (ad, tel) => _service.kisiTelefonlariniKaydet(
                _baglam!,
                {k.secimAnahtari: tel},
                beklenen: [k],
                adlar: {k.secimAnahtari: ad},
              )
            : null,
        kaydet: (tel) => _service.kisiTelefonlariniKaydet(
          _baglam!,
          {k.secimAnahtari: tel},
          beklenen: [k],
        ),
      ),
    );
    if (saved == true && mounted) await _yenile();
  }

  Future<void> _onayla() => _islem(_onayIcerigi);

  Future<void> _onayIcerigi() async {
    if (!_metniDogrula(_metin.text)) return;
    _kapsamKontrol(_secili);
    if (widget.eksikTelefonlariSor &&
        _preview.gecersizler.isNotEmpty &&
        !await _telefonlariTamamla(_preview.gecersizler, sonlandir: true)) {
      return;
    }
    if (!mounted) return;
    if (widget.ogrenciMesajlari != null && _secili.any(_dahaOnceKuyrukta)) {
      throw StateError(
        'Bu sınıfın kayıtlı davet gönderimi var. Gönderim Geçmişi bölümünden devam edin.',
      );
    }
    final p = _preview, text = _dogrulanmisMesaj();
    if (text == null) return;
    if (p.alicilar.isEmpty) {
      throw StateError(
        'En az bir geçerli alıcı seçin ve mesajınızı yazın (en fazla 4000 karakter).',
      );
    }
    MesajKisi? duzenlenecek;
    final confirm = await showDialog<_GonderimYolu>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mesajı gönder'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text),
                if (widget.ogrenciMesajlari != null)
                  for (final o in p.secilenler)
                    Text(
                      '${o.aciklama}\n${widget.ogrenciMesajlari![o.id] ?? "Mesaj eksik"}',
                    ),
                const Divider(),
                Text(
                  '${p.alicilar.length} tekil telefon • ${p.birlestirilen} tekrar birleştirildi',
                ),
                for (final a in p.alicilar)
                  for (final o in a.ogrenciler)
                    _onizlemeAlici(_kaynakAlicisi(o), (k) {
                      duzenlenecek = k;
                      Navigator.pop(ctx);
                    }),
                if (p.gecersizler.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    '${p.gecersizler.length} eksik/geçersiz telefon gönderim dışında kalacak:',
                  ),
                  for (final o in p.gecersizler) Text(o.aciklama),
                ],
                const Divider(),
                const Text(
                  'WhatsApp içinde mesajı kendiniz gönderirsiniz. Toplu gönderimde uygulamaya dönünce “Gönderdim, sıradakine geç” ile devam edin.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Düzelt'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, _GonderimYolu.sms),
            icon: const Icon(Icons.sms_outlined),
            label: const Text('SMS ile gönder'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, _GonderimYolu.whatsapp),
            icon: const Icon(Icons.open_in_new),
            label: const Text('WhatsApp ile gönder'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (duzenlenecek != null) {
      await _onizlemeTelefonDuzenle(duzenlenecek!);
      if (mounted) await _onayIcerigi();
      return;
    }
    if (confirm == null) return;
    _kapsamKontrol(p.secilenler.map((o) => o.id));
    if (p.secilenler.length == 1) {
      if (await _tekKisiyeGonder(confirm, text, ogrenciler: p) && mounted) {
        setState(() {
          _metin.clear();
          _duzenlendi = false;
          _secili.clear();
        });
      }
      return;
    }
    final q = await _service.kuyrukOlustur(
      _baglam!,
      p,
      text,
      kaynakModul: widget.kaynakModul,
      kaynakKayit: widget.kaynakKayit,
      ogrenciMesajlari: widget.ogrenciMesajlari,
    );
    if (!mounted) return;
    setState(() {
      _aktif = q;
      _gonderimBasliyor = true;
      _gecmis = false;
      _metin.clear();
      _duzenlendi = false;
      _secili.clear();
    });
    await _yenile();
    await _gonderimiBaslat(confirm);
  }

  Future<bool> _tekKisiyeGonder(
    _GonderimYolu yol,
    String text, {
    MesajOnIzleme? ogrenciler,
    MesajKisiOnIzleme? kisiler,
  }) async {
    if (yol == _GonderimYolu.sms) {
      final onay = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('SMS gönderimi'),
          content: const Text(
            'Mesaj SIM hattınızdan gönderilecek. Operatörünüz ücret alabilir. Devam edilsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('SMS Gönderimini Başlat'),
            ),
          ],
        ),
      );
      if (onay != true || !mounted) return false;
    }
    try {
      await _service.tekliGonder(
        _baglam!,
        text,
        ogrenciler: ogrenciler,
        kisiler: kisiler,
        sms: yol == _GonderimYolu.sms,
        kaynakModul: widget.kaynakModul,
        kaynakKayit: widget.kaynakKayit,
        ogrenciMesajlari: widget.ogrenciMesajlari,
        izinliOgrenciIdleri: _izinli,
      );
    } finally {
      await _yenile();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            yol == _GonderimYolu.sms
                ? 'SMS gönderim isteği iletildi. Bu, teslim edildiği anlamına gelmez.'
                : 'WhatsApp açıldı. Mesajı WhatsApp içinde gönderin.',
          ),
        ),
      );
    }
    return true;
  }

  void _takibiKapat() {
    if (!mounted) return;
    setState(() {
      _aktif = null;
      _gonderimBasliyor = false;
      _whatsappDisarida = false;
      _gecmis = false;
    });
    if (widget.takipPenceresi && _tekliOnay == null) _kaynagaDon();
  }

  Future<void> _gonderimiBaslat(_GonderimYolu yol) async {
    if (!mounted) return;
    setState(() => _gonderimBasliyor = true);
    try {
      if (yol == _GonderimYolu.sms) {
        try {
          await _smsTopluBaslat();
        } finally {
          // İptal/hata halinde de kayıt geçmişte kalır; takip ekranı açılmaz.
          _takibiKapat();
        }
      } else {
        final q = _aktif!;
        final siradaki = q.siradaki;
        if (q.alicilar.length == 1 && siradaki != null) {
          _tekliOnay = q;
          _tekliDondu = false;
        }
        try {
          if (siradaki != null) await _whatsappBaslat(siradaki);
        } catch (_) {
          if (_tekliOnay?.id == q.id) _tekliOnay = null;
          rethrow;
        }
        if (mounted && q.alicilar.length == 1) _takibiKapat();
      }
    } finally {
      if (mounted) setState(() => _gonderimBasliyor = false);
    }
  }

  Future<void> _ac(MesajAlicisi a) =>
      _islem(() => _gonderimiBaslat(_GonderimYolu.whatsapp));
  Future<void> _whatsappBaslat(MesajAlicisi a) async {
    try {
      await _service.aliciyiAc(
        _baglam!,
        _aktif!.id,
        a.id,
        tekrar: a.durum == 'Acildi',
      );
    } finally {
      await _yenile();
    }
  }

  Future<void> _sonuc(MesajAlicisi a, bool sent) => _islem(() async {
    await _service.aliciyiSonuclandir(
      _baglam!,
      _aktif!.id,
      a.id,
      gonderdim: sent,
    );
    await _yenile();
    if (!mounted) return;
    if (_aktif!.siradaki != null) {
      await _gonderimiBaslat(_GonderimYolu.whatsapp);
    } else {
      _takibiKapat();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp işlemi tamamlandı.')),
      );
    }
  });

  Future<void> _smsTopluBaslat() async {
    final q = _aktif!;
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Otomatik SMS gönderimi'),
        content: Text(
          '${q.alicilar.length} tekil numaraya telefonunuzun SIM hattından '
          'SMS uygulaması açılmadan gönderim yapılacak. Operatörünüz her SMS '
          'parçası için ücret alabilir. Önceden başlatılan SMS kayıtları '
          'tekrar gönderilmeyecek. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SMS Gönderimini Başlat'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    final sonuc = await _service.smsTopluGonder(_baglam!, q.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SMS gönderim istekleri tamamlandı'),
        content: Text(
          'Operatöre iletilmek üzere istenen: ${sonuc['istenen']}\n'
          'Sonucu belirsiz: ${sonuc['belirsiz']}\n'
          'Önceden işlenmiş, tekrar gönderilmeyen: ${sonuc['atlanan']}\n\n'
          'Bu sonuç SMS teslim edildi anlamına gelmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.takipPenceresi
      ? (_aktif == null || _gonderimBasliyor || _whatsappDisarida
            ? const SizedBox.expand()
            : Dialog(
                child: SizedBox(width: 520, height: 380, child: _kuyruk()),
              ))
      : widget.yalnizGonderimOnayi && _aktif == null && _tekliOnay == null
      ? const SizedBox.expand()
      : MesajlasmaGorunumu(child: Builder(builder: _ekran));

  Widget _ekran(BuildContext context) => PopScope(
    canPop: !_busy && !_gonderimBasliyor && (!_duzenlendi || _cikisOnaylandi),
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _busy || _gonderimBasliyor || _cikisOnaylandi) return;
      final cik = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Mesaj taslağından çıkılsın mı?'),
          content: const Text(
            'Seçimleriniz ve yazdığınız mesaj bu ekrandan çıkınca silinir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Düzenlemeye devam et'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Vazgeç ve çık'),
            ),
          ],
        ),
      );
      if (cik != true || !mounted) return;
      setState(() => _cikisOnaylandi = true);
      await WidgetsBinding.instance.endOfFrame;
      if (context.mounted) Navigator.pop(context);
    },
    child: OrtakSayfa(
      bottomNavigationBar: _gecmis && _aktif == null
          ? _gecmisAracCubugu()
          : null,
      appBar: ModulUstBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.eksikTelefonlariSor
                  ? 'Form paylaşımı • ${widget.ogrenciTelefonu ? 'Öğrenci' : 'Veli'}'
                  : 'Mesajlaşma',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_baglam != null)
              Text(
                '${_baglam!.ogretmenAdi} • ${_baglam!.yil}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          if ((!_gecmis || _aktif != null) && (!_yeniSecim || _aktif != null)) ...[
            IconButton(
              key: const ValueKey('hazir-mesaj-ayarlari'),
              tooltip: 'Hazır mesaj ayarları',
              onPressed: _busy || _baglam == null ? null : _sablonAyarlari,
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              tooltip: 'Yenile',
              onPressed: _busy
                  ? null
                  : () => _baglam == null ? _ilkYukle() : _islem(_yenile),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_hata != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _hata!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_aktif == null && !_gecmis && _baglam != null &&
                !widget.eksikTelefonlariSor)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primaryContainer,
                        Theme.of(context).colorScheme.primaryContainer
                            .withValues(alpha: .70),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(OrtakUi.radius),
                  ),
                  padding: const EdgeInsets.all(OrtakUi.bosluk),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        child: Icon(Icons.chat_bubble_outline,
                          color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Mesaj Hazırla',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('Alıcıları belirleyin, mesajı hazırlayın ve '
                              'gönderimden önce kontrol edin.',
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_aktif == null &&
                (_izinli == null ||
                    widget.ogrenciMesajlari != null ||
                    widget.kaynakGecmisiniGoster))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                      selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.edit_outlined),
                        label: Text('Mesaj Hazırla'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.history),
                        label: Text('Geçmiş'),
                      ),
                    ],
                    selected: {_gecmis},
                    onSelectionChanged: (values) =>
                        setState(() => _gecmis = values.first),
                  ),
                ),
              ),
            if (_aktif == null && _gecmis && _baglam != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.history,
                          color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        const Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Gönderim Geçmişi',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text('Alıcıları, kanalları ve gönderim durumlarını '
                              'mevcut kayıtlarınızdan inceleyin.'),
                          ],
                        )),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _baglam == null
                  ? Center(
                      child: Text(
                        _busy ? 'Yükleniyor…' : 'Mesajlaşma açılamadı.',
                      ),
                    )
                  : _aktif != null
                  ? (_gonderimBasliyor || _whatsappDisarida
                        ? const Center(child: Text('Gönderim açılıyor…'))
                        : _kuyruk())
                  : IndexedStack(
                      index: _gecmis ? 1 : 0,
                      children: [_hazirlama(), _gecmisListesi()],
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sekme(
    BuildContext context,
    String baslik,
    IconData icon,
    bool secili,
    VoidCallback sec,
  ) => Semantics(
    button: true,
    selected: secili,
    child: Material(
      color: secili
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : sec,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18,
                color: secili
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 7),
              Flexible(child: Text(
                baslik,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: secili
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              )),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _hazirlama() {
    if (_yeniSecim) return _yeniHazirlama();
    final classes = <int, String>{
      for (final o in _ogrenciler) o.sinifId: o.sinif,
    };
    final visible = _gorunen, p = _preview;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            controller: _hazirlamaKaydirma,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _sinif,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Sınıf'),
                        items: [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('Tüm sınıflarım'),
                          ),
                          for (final e in classes.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _sinif = v),
                      ),
                      TextField(
                        controller: _arama,
                        enabled: !_busy,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: widget.ogrenciTelefonu
                              ? 'Öğrenci veya telefon ara'
                              : 'Öğrenci, veli veya telefon ara',
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _secili.addAll(
                                      visible
                                          .where(
                                            (o) =>
                                                widget.ogrenciMesajlari ==
                                                    null ||
                                                widget.ogrenciMesajlari!
                                                    .containsKey(o.id),
                                          )
                                          .map((o) => o.id),
                                    ),
                                  ),
                            child: const Text('Görünenleri Seç'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(_secili.clear),
                            child: const Text('Seçimi Temizle'),
                          ),
                        ],
                      ),
                      Text(
                        '${_secili.length} öğrenci seçili • ${p.alicilar.length} tekil telefon\n'
                        '${p.gecersizler.length} eksik/geçersiz • ${p.birlestirilen} tekrar\n'
                        '${widget.eksikTelefonlariSor
                            ? 'Seçilen alıcının telefonunu kalemden düzenleyebilirsiniz.'
                            : widget.ogrenciTelefonu
                            ? 'Öğrencinin kayıtlı telefonu kullanılır. Telefonu Öğrencilerim ekranından düzenleyebilirsiniz.'
                            : 'Filtre değişince seçimler korunur. Kalemden veli bilgilerini düzenleyin.'}',
                      ),
                    ],
                  ),
                ),
              ),
              for (final alan in _mesajAlanlari())
                SliverToBoxAdapter(child: alan),
              if (visible.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Öğrenci bulunamadı. '
                      'Önce ders programınızı ve öğrencilerinizi yükleyin.',
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) {
                    final o = visible[i];
                    return CheckboxListTile(
                      value: _secili.contains(o.id),
                      title: Text(o.aciklama),
                      subtitle: Text(
                        '${o.veliAdi.isEmpty ? "Veli adı yok" : o.veliAdi}\n'
                        '${o.telefon.isEmpty ? "Telefon yok" : o.telefon}'
                        '${o.telefon.isNotEmpty && o.normalizeTelefon == null ? " — Geçersiz" : ""}',
                      ),
                      secondary: widget.eksikTelefonlariSor
                          ? IconButton(
                              key: ValueKey('telefon-duzenle-${o.id}'),
                              tooltip: 'Telefonu düzenle',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: _busy
                                  ? null
                                  : () => _islem(() async {
                                      await _telefonlariTamamla([
                                        o,
                                      ], sonlandir: false);
                                    }),
                            )
                          : widget.ogrenciTelefonu
                          ? null
                          : IconButton(
                              key: ValueKey('veli-duzenle-${o.id}'),
                              tooltip: 'Veli bilgilerini düzenle',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: _busy ? null : () => _iletisim(o),
                            ),
                      onChanged:
                          _busy ||
                              (widget.ogrenciMesajlari != null &&
                                  !widget.ogrenciMesajlari!.containsKey(o.id))
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                _secili.add(o.id);
                              } else {
                                _secili.remove(o.id);
                              }
                            }),
                    );
                  },
                ),
            ],
          ),
        ),
        MesajOnizlemeButonu(
          onPressed:
              _busy ||
                  (p.alicilar.isEmpty &&
                      (!widget.eksikTelefonlariSor || p.gecersizler.isEmpty))
              ? null
              : _onayla,
        ),
      ],
    );
  }

  Future<void> _programdanOgretmenAktar(int sinifId) => _islem(() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ImportMerkeziScreen(mesajService: _service, sinifId: sinifId),
      ),
    );
    if (mounted) {
      await _yenile();
    }
  });

  Future<void> _ogretmenDuzenle(String? kisiId, int? sinifId) =>
      _islem(() async {
        var id = kisiId;
        if (id == null) {
          final kayitlar = await _service.ogretmenIletisimKayitlari(_baglam!);
          if (!mounted) return;
          if (kayitlar.isNotEmpty) {
            final secim = await showDialog<String>(
              context: context,
              builder: (c) => SimpleDialog(
                title: const Text('Öğretmen seç veya ekle'),
                children: [
                  for (final k in kayitlar)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(c, k['KisiId'] as String),
                      child: Text(k['AdSoyad'] as String),
                    ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, 'yeni'),
                    child: const Text('Yeni öğretmen ekle'),
                  ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Vazgeç'),
                  ),
                ],
              ),
            );
            if (secim == null || !mounted) return;
            if (secim != 'yeni') id = secim;
          }
        }
        final onceki = id == null
            ? null
            : await _service.ogretmenIletisimBilgisi(_baglam!, id);
        final kisi = onceki?['kisi'] as Map?;
        final siniflar = <int>{
          if (sinifId != null) sinifId,
          if (onceki != null)
            for (final s in onceki['siniflar'] as List)
              if (s['EgitimOgretimYili'] == _baglam!.yil &&
                  _siniflar.containsKey(s['SinifSubeId']))
                s['SinifSubeId'] as int,
        };
        if (!mounted) return;
        final saved = await showDialog<bool>(
          context: context,
          builder: (_) => MesajOgretmenDialog(
            sinifIliskileriKayitli: onceki != null,
            siniflar: _siniflar,
            seciliSiniflar: siniflar,
            ad: (kisi?['AdSoyad'] ?? '') as String,
            telefon: (kisi?['Telefon'] ?? '') as String,
            kaydet: (ad, tel, siniflar) async {
              await _service.ogretmenIletisimKaydet(
                _baglam!,
                id: id,
                ad: ad,
                telefon: tel,
                sinifIdleri: siniflar,
                sinifIliskileriniDogruladim: true,
                onceki: onceki,
              );
            },
          ),
        );
        if (saved == true) await _yenile();
      });

  Future<void> _kisiDuzenle(MesajKisi k) {
    if (k.tur == MesajKisiTuru.ogretmen) {
      return _ogretmenDuzenle(k.kisiId, null);
    }
    if (k.tur == MesajKisiTuru.veli && k.veliTuru == null) {
      return _iletisim(_ogrenciler.firstWhere((o) => '${o.id}' == k.kisiId));
    }
    return _islem(() async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => MesajKisiTelefonDialog(
          kisi: k,
          kaydet: (tel) => _service.kisiTelefonlariniKaydet(
            _baglam!,
            {k.secimAnahtari: tel},
            beklenen: [k],
          ),
        ),
      );
      if (saved == true) await _yenile();
    });
  }

  Future<void> _yeniOnayla() => _islem(_yeniOnayIcerigi);

  Future<void> _yeniOnayIcerigi() async {
    if (!_metniDogrula(_metin.text)) return;
    await _yenile();
    if (!mounted) return;
    var p = MesajKisiOnIzleme(_seciliKisiler.values);
    final atlanan = <MesajKisi>[];
    if (p.gecersizler.isNotEmpty) {
      final eksikler = <String, MesajKisi>{
        for (final k in p.gecersizler) k.secimAnahtari: k,
      }.values.toList();
      final veliBilgileri = <String, Map<String, Object?>>{};
      for (final k in eksikler.where((k) => k.tur == MesajKisiTuru.veli)) {
        veliBilgileri[k.secimAnahtari] = await _service.veliBilgileri(
          _baglam!,
          int.parse(k.kisiId),
        );
      }
      if (!mounted) return;
      final sonuc = await showDialog<Set<String>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => MesajEksikTelefonDialog(
          kisiler: eksikler,
          kaydet: (telefonlar, beklenen) => _service.kisiTelefonlariniKaydet(
            _baglam!,
            telefonlar,
            beklenen: beklenen,
          ),
          veliBilgileri: veliBilgileri,
          veliTelefonKaydet: (k, tur, ad, telefon, bilgiler) async {
            await _service.iletisimKaydet(
              _baglam!,
              int.parse(k.kisiId),
              ad,
              telefon,
              veliTuru: tur,
              onceki: bilgiler,
            );
            final adaylar = await _service.aliciAdaylari(_baglam!);
            final veli = adaylar.firstWhere(
              (c) =>
                  c.tur == MesajKisiTuru.veli &&
                  c.kisiId == k.kisiId &&
                  c.sinifId == k.sinifId,
            );
            if (!mounted) return;
            setState(() {
              _seciliKisiler.removeWhere(
                (key, c) =>
                    c.kisiId == k.kisiId &&
                    c.tur == MesajKisiTuru.veli &&
                    c.normalizeTelefon == null,
              );
              _seciliKisiler[veli.secimAnahtari] = veli;
            });
          },
        ),
      );
      if (!mounted) return;
      // Açıkça kaydedilen telefonlar iptalde de korunur; seçim/taslak silinmez.
      final oncekiAnahtarlar = _seciliKisiler.keys.toSet();
      await _yenile();
      if (!mounted || sonuc == null) return;
      if (!oncekiAnahtarlar.every(_seciliKisiler.containsKey)) {
        throw StateError(
          'Alıcı kapsamı değişti. Kalan seçimleri kontrol edip ön izlemeyi yeniden açın.',
        );
      }
      atlanan.addAll(
        _seciliKisiler.values.where((k) => sonuc.contains(k.secimAnahtari)),
      );
      p = MesajKisiOnIzleme(
        _seciliKisiler.values.where((k) => !sonuc.contains(k.secimAnahtari)),
      );
      if (p.gecersizler.isNotEmpty) {
        throw StateError(
          'Telefon veya veli ilişkisi değişti. Alıcıları yeniden kontrol edin.',
        );
      }
    }
    final text = _dogrulanmisMesaj(alicilar: p.secilenler);
    if (text == null) return;
    if (p.telefonGruplari.isEmpty) {
      throw StateError(
        'Gönderim için en az bir geçerli alıcı ve 1–4000 karakterlik mesaj gerekli. Gönderim başlatılmadı.',
      );
    }
    MesajKisi? duzenlenecek;
    final onay = await showDialog<_GonderimYolu>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Mesajı gönder'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mesajınız', style: Theme.of(context).textTheme.titleSmall),
              Text(text),
              const Divider(),
              Text(
                '${p.kisiSayisi} alıcı • ${p.telefonGruplari.length} telefon numarası',
              ),
              if (p.kisiSayisi > p.telefonGruplari.length)
                const Text(
                  'Aynı numarayı kullanan alıcılara tek mesaj hazırlanır.',
                ),
              if (atlanan.isNotEmpty) Text('Atlanan alıcı: ${atlanan.length}'),
              for (final k in atlanan)
                Text(
                  'Atlandı: ${_kisiBasligi(k)} • ${k.ad}\n${k.aciklama}\n'
                  '${k.tur == MesajKisiTuru.veli && k.veliTuru == null
                      ? 'Veli ilişkisi tanımlı değil'
                      : k.telefon.trim().isEmpty
                      ? 'Telefon eksik'
                      : 'Telefon geçersiz'}',
                ),
              for (final e in p.telefonGruplari.entries)
                for (final k in e.value)
                  _onizlemeAlici(k, (k) {
                    duzenlenecek = k;
                    Navigator.pop(c);
                  }),
              const Text(
                'SMS veya sıralı WhatsApp gönderimini seçin. WhatsApp içinde mesajı kendiniz gönderirsiniz.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Düzelt'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, _GonderimYolu.sms),
            icon: const Icon(Icons.sms_outlined),
            label: const Text('SMS ile gönder'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, _GonderimYolu.whatsapp),
            icon: const Icon(Icons.open_in_new),
            label: const Text('WhatsApp ile gönder'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (duzenlenecek != null) {
      await _onizlemeTelefonDuzenle(duzenlenecek!);
      if (mounted) await _yeniOnayIcerigi();
      return;
    }
    if (onay == null) return;
    setState(() => _busy = true);
    await widget.kaynakKontrol?.call(_baglam!);
    if (p.kisiSayisi == 1) {
      if (await _tekKisiyeGonder(onay, text, kisiler: p) && mounted) {
        setState(() {
          _metin.clear();
          _duzenlendi = false;
          _seciliKisiler.clear();
        });
      }
      return;
    }
    final q = await _service.kisilerleKuyrukOlustur(
      _baglam!,
      p,
      text,
      kaynakModul: widget.kaynakModul,
      kaynakKayit: widget.kaynakKayit,
      izinliOgrenciIdleri: _izinli,
    );
    if (!mounted) return;
    setState(() {
      _aktif = q;
      _gonderimBasliyor = true;
      _gecmis = false;
      _metin.clear();
      _duzenlendi = false;
      _seciliKisiler.clear();
    });
    await _yenile();
    await _gonderimiBaslat(onay);
  }

  Widget _dersOgretmenleri() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MesajAdimBasligi(
            adim: 1,
            baslik: 'Ders öğretmenleri',
            aciklama:
                '${_siniflar[widget.ogretmenSinifId] ?? ''} sınıfında derse giren öğretmenler.',
          ),
          MesajAciliKarti(
            renk: mesajListeRengi,
            margin: const EdgeInsets.only(top: 12),
            child: OrtakGenisleyenBolum(
              title: Text(
                'Öğretmen listesi (${_seciliKisiler.length}/${_kisiler.length} seçili)',
              ),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _seciliKisiler.addEntries(
                                _kisiler.map(
                                  (k) => MapEntry(k.secimAnahtari, k),
                                ),
                              );
                              _duzenlendi = true;
                            }),
                      child: const Text('Tümünü seç'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _seciliKisiler.clear();
                              _duzenlendi = true;
                            }),
                      child: const Text('Seçimi kaldır'),
                    ),
                  ],
                ),
                for (final k in _kisiler)
                  CheckboxListTile(
                    key: ValueKey('gorus-ogretmen-${k.kisiId}'),
                    title: Text(k.ad),
                    subtitle: Text(
                      '${k.aciklama}\n${k.telefon.isEmpty ? 'Telefon eksik' : k.telefon}',
                    ),
                    value: _seciliKisiler.containsKey(k.secimAnahtari),
                    secondary: IconButton(
                      tooltip: 'Telefonu düzenle',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _busy
                          ? null
                          : () => _islem(() => _onizlemeTelefonDuzenle(k)),
                    ),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              _seciliKisiler[k.secimAnahtari] = k;
                            } else {
                              _seciliKisiler.remove(k.secimAnahtari);
                            }
                            _duzenlendi = true;
                          }),
                  ),
              ],
            ),
          ),
          if (_kisiler.isEmpty)
            const Text('Bu sınıfta ders öğretmeni bulunamadı.'),
        ],
      ),
    ),
  );

  Widget _yeniHazirlama() => Column(
    children: [
      Expanded(
        child: CustomScrollView(
          controller: _hazirlamaKaydirma,
          slivers: [
            if (widget.ogretmenSinifId != null)
              _dersOgretmenleri()
            else
              MesajAliciSecimSliver(
                key: const ValueKey('mesaj-alici-secimi'),
                adaylar: _kisiler,
                aliciTuruDegisti: (tur) => setState(() {
                  _duzenlendi = true;
                  _hazirMesajTuru = tur;
                }),
                siniflar: _siniflar,
                secilenler: _seciliKisiler,
                kilitli: _busy,
                degistir: (ks) => setState(() {
                  _duzenlendi = true;
                  _hata = null;
                  _seciliKisiler
                    ..clear()
                    ..addEntries(ks.map((k) => MapEntry(k.secimAnahtari, k)));
                }),
                veliDuzenle: (id) =>
                    _iletisim(_ogrenciler.firstWhere((o) => o.id == id)),
                ogretmenDuzenle: _ogretmenDuzenle,
                kisiDuzenle: _kisiDuzenle,
                programdanAktar: _programdanOgretmenAktar,
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: MesajAdimBasligi(
                  adim: 2,
                  baslik: 'Mesajı hazırla',
                  aciklama:
                      'Göndereceğiniz mesajın türünü ve içeriğini belirleyin.',
                ),
              ),
            ),
            for (final alan in _mesajAlanlari())
              SliverToBoxAdapter(child: alan),
          ],
        ),
      ),
      MesajOnizlemeButonu(
        onPressed: _busy || _seciliKisiler.isEmpty ? null : _yeniOnayla,
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Hazır mesaj ayarları',
              onPressed: _busy || _baglam == null ? null : _sablonAyarlari,
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: 'Yenile',
              onPressed: _busy
                  ? null
                  : () => _baglam == null ? _ilkYukle() : _islem(_yenile),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    ],
  );

  List<Widget> _mesajAlanlari() => [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MesajSecimYuzeyi(
        icon: Icons.chat_outlined,
        renk: mesajSablonRengi,
        child: DropdownButtonFormField<String>(
          key: ValueKey('hazir-mesaj-${_sablonTuru?.name}-$_sablonSurumu'),
          initialValue: '',
          isExpanded: true,
          menuMaxHeight: 320,
          decoration: InputDecoration(
            labelText: _sablonTuru == null
                ? 'Önce alıcı grubunu seçin'
                : 'Hazır mesaj • ${_sablonTuru!.baslik}',
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Hazır mesaj seçin')),
            for (final s in _uygunSablonlar)
              DropdownMenuItem(
                value: s.id,
                child: Text(s.baslik, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged:
              _busy ||
                  widget.ogrenciMesajlari != null ||
                  _uygunSablonlar.isEmpty
              ? null
              : (v) {
                  final bulunan = _uygunSablonlar.where((s) => s.id == v);
                  if (bulunan.isNotEmpty) {
                    setState(() {
                      _duzenlendi = true;
                      _metin.text = bulunan.single.metin;
                      _mesajHatasi = null;
                    });
                  }
                },
        ),
      ),
    ),
    Padding(
      key: _mesajAlani,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        key: const ValueKey('mesaj-metni'),
        controller: _metin,
        focusNode: _mesajOdak,
        onChanged: (_) {
          setState(() {
            _duzenlendi = true;
            _mesajHatasi = null;
          });
        },
        readOnly: widget.ogrenciMesajlari != null,
        enabled: !_busy,
        minLines: 3,
        maxLines: 6,
        maxLength: 4000,
        decoration: InputDecoration(
          labelText: 'Mesajınız',
          hintText: 'Mesajınızı buraya yazın…',
          alignLabelWithHint: true,
          error: _mesajHatasi == null
              ? null
              : Semantics(
                  liveRegion: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_mesajHatasi!)),
                    ],
                  ),
                ),
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer
              .withValues(alpha: .65),
          borderRadius: BorderRadius.circular(OrtakUi.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Değişkenler: {Tarih}, {Sinif}, {OgrenciAdi}. Öğrenci adı yalnız tek öğrenci veya velisi seçiliyken kullanılır.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ),
  ];

  bool get _gecmisFiltreli =>
      _gecmisSinif != null ||
      _gecmisOgrenci != null ||
      _gecmisKanal != null ||
      _gecmisDurum != null ||
      _gecmisTarih != null;

  String _tekliDurum(Map<String, Object?> r) => r['Durum'] == 'Istendi'
      ? (r['Kanal'] == 'WhatsApp' ? 'Onaylandi' : 'Istendi')
      : '${r['Durum']}';

  bool _gecmisEkFiltre(String tarih, String kanal, String durum) {
    if (_gecmisKanal != null && kanal != _gecmisKanal) {
      return false;
    }
    if (_gecmisDurum != null && durum != _gecmisDurum) {
      return false;
    }
    final aralik = _gecmisTarih;
    if (aralik == null) return true;
    final t = DateTime.tryParse(tarih)?.toLocal();
    if (t == null) return false;
    final gun = DateUtils.dateOnly(t);
    return !gun.isBefore(aralik.start) && !gun.isAfter(aralik.end);
  }

  Future<void> _gecmisTarihSec() async {
    final aralik = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(9999),
      initialDateRange: _gecmisTarih,
      helpText: 'Gönderim tarih aralığı',
      cancelText: 'Vazgeç',
      saveText: 'Uygula',
      confirmText: 'Uygula',
      fieldStartLabelText: 'Başlangıç',
      fieldEndLabelText: 'Bitiş',
    );
    if (aralik != null && mounted) {
      setState(() {
        _gecmisTarih = aralik;
        _gecmisSecili.clear();
      });
    }
  }

  Widget _gecmisEkFiltreler() => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        _gecmisFiltreSatiri(
          DropdownButtonFormField<String>(
            key: ValueKey('gecmis-kanal-$_gecmisKanal'),
            initialValue: _gecmisKanal,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kanal'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Tüm kanallar')),
              DropdownMenuItem(value: 'WhatsApp', child: Text('WhatsApp')),
              DropdownMenuItem(value: 'SMS', child: Text('SMS')),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _gecmisKanal = v;
                    _gecmisSecili.clear();
                  }),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('gecmis-durum-$_gecmisDurum'),
            initialValue: _gecmisDurum,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Durum'),
            items: const [
              DropdownMenuItem(
                value: null,
                child: Text('Tüm durumlar', overflow: TextOverflow.ellipsis),
              ),
              DropdownMenuItem(value: 'Onaylandi', child: Text('Onaylandı')),
              DropdownMenuItem(
                value: 'Acildi',
                child: Text('Onay bekliyor', overflow: TextOverflow.ellipsis),
              ),
              DropdownMenuItem(value: 'Bekliyor', child: Text('Bekliyor')),
              DropdownMenuItem(value: 'Atlandi', child: Text('Atlandı')),
              DropdownMenuItem(value: 'Acilamadi', child: Text('Açılamadı')),
              DropdownMenuItem(
                value: 'Istendi',
                child: Text(
                  'SMS isteği iletildi',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: 'Gonderildi',
                child: Text('SMS gönderildi', overflow: TextOverflow.ellipsis),
              ),
              DropdownMenuItem(
                value: 'Basarisiz',
                child: Text('SMS başarısız', overflow: TextOverflow.ellipsis),
              ),
              DropdownMenuItem(
                value: 'Belirsiz',
                child: Text('Sonuç belirsiz', overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _gecmisDurum = v;
                    _gecmisSecili.clear();
                  }),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('gecmis-tarih'),
              onPressed: _busy ? null : _gecmisTarihSec,
              icon: const Icon(Icons.date_range),
              label: Text(
                _gecmisTarih == null
                    ? 'Tarih aralığı'
                    : '${_gecmisTarih!.start.day}.${_gecmisTarih!.start.month}.${_gecmisTarih!.start.year} – '
                          '${_gecmisTarih!.end.day}.${_gecmisTarih!.end.month}.${_gecmisTarih!.end.year}',
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _gecmisSinif = null;
                      _gecmisOgrenci = null;
                      _gecmisKanal = null;
                      _gecmisDurum = null;
                      _gecmisTarih = null;
                      _gecmisSecili.clear();
                    }),
              child: const Text('Filtreleri temizle'),
            ),
          ],
        ),
      ],
    ),
  );

  bool _gecmisteEslesir(String metin) =>
      listeAramaMetni(metin).contains(listeAramaMetni(_gecmisArama.text));

  String? _kayitSinifi(String aciklama) =>
      aciklama.contains(' • ') ? aciklama.split(' • ').first.trim() : null;

  int? _kayitOgrencisi(Map r) =>
      r['tur'] == 'Ogretmen' ? null : int.tryParse('${r['id']}');

  bool _gecmisKapsaminda(String aciklama, int? ogrenciId) =>
      (_gecmisSinif == null || _kayitSinifi(aciklama) == _gecmisSinif) &&
      (_gecmisOgrenci == null || ogrenciId == _gecmisOgrenci);

  Iterable<Map<String, Object?>> get _gecmisOgrenciKayitlari sync* {
    for (final o in _ogrenciler) {
      yield {'id': o.id, 'aciklama': o.aciklama};
    }
    for (final q in _kuyruklar) {
      for (final a in q.alicilar) {
        for (final r in (jsonDecode(a.ogrenciler) as List).whereType<Map>()) {
          yield {
            'id': _kayitOgrencisi(r),
            'aciklama': '${r['aciklama'] ?? a.ad}',
          };
        }
      }
    }
    for (final r in _tekliKayitlar) {
      yield {'id': r['OgrenciId'], 'aciklama': '${r['Aciklama']}'};
    }
  }

  List<String> get _gecmisSinifSecenekleri {
    final siniflar = {
      ..._siniflar.values,
      for (final r in _gecmisOgrenciKayitlari)
        if (_kayitSinifi('${r['aciklama']}') != null)
          _kayitSinifi('${r['aciklama']}')!,
    }.toList();
    siniflar.sort((a, b) {
      final sayi = RegExp(r'^\s*(\d+)');
      final sonuc = (int.tryParse(sayi.firstMatch(b)?.group(1) ?? '') ?? 0)
          .compareTo(int.tryParse(sayi.firstMatch(a)?.group(1) ?? '') ?? 0);
      return sonuc == 0 ? b.compareTo(a) : sonuc;
    });
    return siniflar;
  }

  Map<int, String> get _gecmisOgrenciSecenekleri {
    final ogrenciler = <int, String>{};
    for (final r in _gecmisOgrenciKayitlari) {
      final id = r['id'] as int?;
      final aciklama = '${r['aciklama']}';
      if (id == null ||
          (_gecmisSinif != null && _kayitSinifi(aciklama) != _gecmisSinif)) {
        continue;
      }
      final parcalar = aciklama.split(' • ');
      final ad = parcalar.length >= 3
          ? '${parcalar.skip(2).join(' • ')} • ${parcalar[1]}'
          : aciklama;
      ogrenciler.putIfAbsent(id, () => ad);
    }
    final sirali = ogrenciler.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Map.fromEntries(sirali);
  }

  Iterable<Map> _gecmisAliciKayitlari(MesajAlicisi a) {
    final kayitlar = (jsonDecode(a.ogrenciler) as List)
        .whereType<Map>()
        .toList();
    return kayitlar.isEmpty
        ? [
            {'aciklama': a.ad},
          ]
        : kayitlar;
  }

  bool _gecmisteKuyrukGorunur(MesajKuyrugu q) => q.alicilar.any(
    (a) =>
        _gecmisEkFiltre(
          q.tarih,
          a.smsDurumu == null ? 'WhatsApp' : 'SMS',
          a.smsDurumu ?? a.durum,
        ) &&
        _gecmisAliciKayitlari(a).any(
          (r) =>
              _gecmisKapsaminda(
                '${r['aciklama'] ?? a.ad}',
                _kayitOgrencisi(r),
              ) &&
              _gecmisteEslesir(
                '${r['aciklama'] ?? a.ad} ${a.ad} ${a.telefon} ${q.metin}',
              ),
        ),
  );

  Set<String> get _secilebilirGecmis => {
    for (final q in _kuyruklar)
      for (final a in q.alicilar)
        if (_gecmisEkFiltre(
              q.tarih,
              a.smsDurumu == null ? 'WhatsApp' : 'SMS',
              a.smsDurumu ?? a.durum,
            ) &&
            _gecmisAliciKayitlari(a).any(
              (r) =>
                  _gecmisKapsaminda(
                    '${r['aciklama'] ?? a.ad}',
                    _kayitOgrencisi(r),
                  ) &&
                  _gecmisteEslesir(
                    '${r['aciklama'] ?? a.ad} ${a.ad} ${a.telefon} ${q.metin}',
                  ),
            ))
          'q/${q.id}/${a.id}',
    for (final r in _tekliKayitlar)
      if (_gecmisEkFiltre('${r['Tarih']}', '${r['Kanal']}', _tekliDurum(r)) &&
          _gecmisKapsaminda('${r['Aciklama']}', r['OgrenciId'] as int?) &&
          _gecmisteEslesir(
            '${r['Aciklama']} ${r['Tur']}: ${r['AliciAdi']} ${r['Telefon']} ${r['Metin']}',
          ))
        't/${r['KayitId']}',
  };

  Set<String> get _onaylanabilirGecmis => {
    for (final q in _kuyruklar)
      for (final a in q.alicilar)
        if (_gecmisEkFiltre(
              q.tarih,
              a.smsDurumu == null ? 'WhatsApp' : 'SMS',
              a.smsDurumu ?? a.durum,
            ) &&
            a.durum == 'Acildi' &&
            a.smsDurumu == null &&
            _gecmisAliciKayitlari(a).any(
              (r) =>
                  _gecmisKapsaminda(
                    '${r['aciklama'] ?? a.ad}',
                    _kayitOgrencisi(r),
                  ) &&
                  _gecmisteEslesir(
                    '${r['aciklama'] ?? a.ad} ${a.ad} ${a.telefon} ${q.metin}',
                  ),
            ))
          'q/${q.id}/${a.id}',
    for (final r in _tekliKayitlar)
      if (_gecmisEkFiltre('${r['Tarih']}', '${r['Kanal']}', _tekliDurum(r)) &&
          r['Kanal'] == 'WhatsApp' &&
          r['Durum'] == 'Acildi' &&
          _gecmisKapsaminda('${r['Aciklama']}', r['OgrenciId'] as int?) &&
          _gecmisteEslesir(
            '${r['Aciklama']} ${r['Tur']}: ${r['AliciAdi']} ${r['Telefon']} ${r['Metin']}',
          ))
        't/${r['KayitId']}',
  };

  void _gecmisSec(String key) => setState(() {
    if (!_gecmisSecili.remove(key)) _gecmisSecili.add(key);
  });

  Future<void> _gecmisiOnayla() => _islem(() async {
    final secilen = _gecmisSecili.intersection(_onaylanabilirGecmis);
    if (secilen.isEmpty) return;
    final kuyruklar = <String, Set<int>>{}, tekliler = <String>{};
    for (final key in secilen) {
      final parcalar = key.split('/');
      if (parcalar.first == 't') {
        tekliler.add(parcalar[1]);
      } else {
        (kuyruklar[parcalar[1]] ??= {}).add(int.parse(parcalar[2]));
      }
    }
    await _service.gecmisiOnayla(
      _baglam!,
      kuyrukAlicilari: kuyruklar,
      tekliKayitlar: tekliler,
    );
    _gecmisSecili.clear();
    await _yenile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seçili mesajlar gönderim beyanınız olarak onaylandı.'),
        ),
      );
    }
  });

  Future<void> _gecmisiSil() => _islem(() async {
    final secilen = _gecmisSecili.intersection(_secilebilirGecmis);
    if (secilen.isEmpty) return;
    final kuyruklar = <String, Set<int>>{}, tekliler = <String>{};
    final bilgiler = <String>[];
    for (final key in secilen) {
      final parcalar = key.split('/');
      if (parcalar.first == 't') {
        tekliler.add(parcalar[1]);
        final r = _tekliKayitlar.firstWhere((r) => r['KayitId'] == parcalar[1]);
        bilgiler.add('${r['Aciklama']} • ${r['AliciAdi']}');
      } else {
        final id = int.parse(parcalar[2]);
        (kuyruklar[parcalar[1]] ??= {}).add(id);
        final a = _kuyruklar
            .firstWhere((q) => q.id == parcalar[1])
            .alicilar
            .firstWhere((a) => a.id == id);
        bilgiler.add('${_ogrenciAciklamasi(a)} • ${a.ad}');
      }
    }
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Seçili mesaj geçmişini sil'),
        content: Text(
          '${secilen.length} gönderim kaydı kalıcı olarak silinecek. Öğrenci ve iletişim kayıtları korunur. Aynı gönderime bağlı öğrencilerin ortak mesaj kaydı birlikte silinir.\n\n${bilgiler.join('\n')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    await _service.gecmisiSil(
      _baglam!,
      kuyrukAlicilari: kuyruklar,
      tekliKayitlar: tekliler,
      onayMetni: 'SİL',
    );
    _gecmisSecili.clear();
    await _yenile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçili geçmiş kayıtları silindi.')),
      );
    }
  });

  Future<void> _gecmistenDevam(String id) => _islem(() async {
    final fresh = await _service.kuyrukGetir(_baglam!, id);
    if (!mounted || fresh.tamamlandi) return;
    setState(() {
      _aktif = fresh;
      _gecmisSecili.clear();
    });
    if (fresh.smsBaslatildi) {
      await _gonderimiBaslat(_GonderimYolu.sms);
    } else if (fresh.siradaki?.durum != 'Acildi') {
      await _gonderimiBaslat(_GonderimYolu.whatsapp);
    }
  });

  String _gecmisKonusu(String kaynak, String metin) {
    if (kaynak == odevBildirimArsivModulu) return 'Ödev bildirimi • Arşiv';
    if (kaynak == 'OgretmenGorusFormu') return 'Öğretmen görüş formu';
    if (kaynak == MesajlasmaService.formDuzeltmeOgrenciModulu) {
      return 'Bilgi formu düzeltme talebi';
    }
    if (kaynak == MesajlasmaService.formPaylasimOgrenciModulu ||
        kaynak == MesajlasmaService.formPaylasimVeliModulu ||
        metin.contains('docs.google.com/forms/') ||
        metin.contains('forms.gle/')) {
      return 'Bilgi formu daveti';
    }
    final konu = metin
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceFirst(
          RegExp(
            r'^\s*(Sayın velimiz|Sayın velim|Merhaba)[,\s:]*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (konu.isEmpty) return 'Bilgilendirme mesajı';
    return konu.length <= 70 ? konu : '${konu.substring(0, 70).trimRight()}…';
  }

  Widget _gecmisFiltreSatiri(Widget ilk, Widget ikinci) => LayoutBuilder(
    builder: (context, c) =>
        c.maxWidth >= 320 && MediaQuery.textScalerOf(context).scale(1) <= 1.2
        ? Row(
            children: [
              Expanded(child: ilk),
              const SizedBox(width: OrtakUi.bosluk),
              Expanded(child: ikinci),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ilk,
              const SizedBox(height: OrtakUi.bosluk),
              ikinci,
            ],
          ),
  );

  Widget _gecmisDigerIslemler() => PopupMenuButton<String>(
    tooltip: 'Geçmiş işlemleri',
    enabled: !_busy,
    onSelected: (v) async {
      if (v == 'sil') {
        await _gecmisiSil();
      } else if (v == 'yenile') {
        await _islem(_yenile);
      } else if (v == 'sablon') {
        await _sablonAyarlari();
      } else {
        await _gecmistenDevam(v);
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        key: const ValueKey('gecmisi-sil'),
        value: 'sil',
        enabled: _gecmisSecili.intersection(_secilebilirGecmis).isNotEmpty,
        child: const Text('Seçili kayıtları sil'),
      ),
      const PopupMenuItem(value: 'yenile', child: Text('Yenile')),
      const PopupMenuItem(value: 'sablon', child: Text('Hazır mesaj ayarları')),
      for (final q in _kuyruklar.where(
        (q) => !q.tamamlandi && _gecmisteKuyrukGorunur(q),
      ))
        PopupMenuItem(
          value: q.id,
          child: Text(
            'Devam et: ${q.metin}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    child: const Padding(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.more_vert, size: 21),
          SizedBox(height: 4),
          Text('Diğer', maxLines: 1, style: TextStyle(fontSize: 10)),
        ],
      ),
    ),
  );

  Widget _gecmisAracCubugu() => OrtakListeAracCubugu<int>(
    etkin: !_busy,
    aramaAktif: _gecmisAramaAcik || _gecmisArama.text.isNotEmpty,
    filtreAktif: _gecmisFiltreAcik || _gecmisFiltreli,
    ara: () => setState(() => _gecmisAramaAcik = !_gecmisAramaAcik),
    filtrele: () => setState(() => _gecmisFiltreAcik = !_gecmisFiltreAcik),
    siralama: _gecmisSiralama,
    siralamaSecenekleri: const {
      0: 'Tarih: yeniden eskiye',
      1: 'Tarih: eskiden yeniye',
      2: 'Öğrenci / alıcı adı (A–Z)',
      3: 'Öğrenci / alıcı adı (Z–A)',
    },
    sirala: (v) => setState(() => _gecmisSiralama = v),
    ekIslemler: [
      IconButton(
        key: const ValueKey('gecmisi-onayla'),
        tooltip: 'Onayla',
        onPressed:
            _busy || _gecmisSecili.intersection(_onaylanabilirGecmis).isEmpty
            ? null
            : _gecmisiOnayla,
        icon: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 21),
            SizedBox(height: 4),
            Text('Onayla', maxLines: 1, style: TextStyle(fontSize: 10)),
          ],
        ),
      ),
      _gecmisDigerIslemler(),
    ],
  );

  Widget _gecmisListesi() {
    final sinifSecenekleri = _gecmisSinifSecenekleri;
    final ogrenciSecenekleri = _gecmisOgrenciSecenekleri;
    final arama = listeAramaMetni(_gecmisArama.text);
    final satirlar =
        <({String tarih, String ad, String arama, Widget Function() satir})>[];
    for (final q in _kuyruklar) {
      for (final a in q.alicilar) {
        if (!_gecmisEkFiltre(
          q.tarih,
          a.smsDurumu == null ? 'WhatsApp' : 'SMS',
          a.smsDurumu ?? a.durum,
        )) {
          continue;
        }
        final bilgiler = _gecmisAliciKayitlari(a);
        final kayitlar = bilgiler.toList();
        final gorulen = <String>{};
        for (final r in kayitlar) {
          final aciklama = '${r['aciklama'] ?? a.ad}';
          if (!_gecmisKapsaminda(aciklama, _kayitOgrencisi(r)) ||
              !gorulen.add(aciklama)) {
            continue;
          }
          satirlar.add((
            tarih: q.tarih,
            ad: aciklama,
            arama: listeAramaMetni('$aciklama ${a.ad} ${a.telefon} ${q.metin}'),
            satir: () => _topluGecmisSatiri(q, a, aciklama),
          ));
        }
      }
    }
    for (final r in _tekliKayitlar) {
      if (!_gecmisEkFiltre('${r['Tarih']}', '${r['Kanal']}', _tekliDurum(r)) ||
          !_gecmisKapsaminda('${r['Aciklama']}', r['OgrenciId'] as int?)) {
        continue;
      }
      final durum = r['Durum'] == 'Istendi'
          ? (r['Kanal'] == 'WhatsApp'
                ? 'Onaylandı'
                : 'SMS gönderim isteği iletildi')
          : r['Durum'] == 'Acildi'
          ? 'Onay bekliyor'
          : r['Durum'] == 'Acilamadi'
          ? 'WhatsApp açılamadı'
          : 'Gönderim sonucu belirsiz';
      final bilgi = '${r['Aciklama']} • ${r['Tur']}: ${r['AliciAdi']}';
      satirlar.add((
        tarih: '${r['Tarih']}',
        ad: '${r['Aciklama']}',
        arama: listeAramaMetni('$bilgi ${r['Telefon']} ${r['Metin']}'),
        satir: () => MesajGecmisKarti(
          tarih: '${r['Tarih']}',
          kanal: '${r['Kanal']}',
          durum: durum,
          tamMetin: '${r['Aciklama']}\n${r['Tur']}: ${r['AliciAdi']}',
          child: ListTile(
            title: Text(
              '${r['Aciklama']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${r['Tur']}: ${r['AliciAdi']} • ${_gecmisKonusu('${r['KaynakModul']}', '${r['Metin']}')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            leading: Checkbox(
              key: ValueKey('gecmis-sec-t/${r['KayitId']}'),
              value: _gecmisSecili.contains('t/${r['KayitId']}'),
              onChanged:
                  _busy || !_secilebilirGecmis.contains('t/${r['KayitId']}')
                  ? null
                  : (_) => _gecmisSec('t/${r['KayitId']}'),
            ),
            selected: _gecmisSecili.contains('t/${r['KayitId']}'),
            onTap: _busy || !_secilebilirGecmis.contains('t/${r['KayitId']}')
                ? null
                : () => _gecmisSec('t/${r['KayitId']}'),
          ),
        ),
      ));
    }
    satirlar.sort((a, b) {
      final ta = DateTime.tryParse(a.tarih), tb = DateTime.tryParse(b.tarih);
      final tarih = ta != null && tb != null
          ? ta.compareTo(tb)
          : a.tarih.compareTo(b.tarih);
      String ad(String s) =>
          s.split(' • ').length >= 3 ? s.split(' • ').skip(2).join(' • ') : s;
      final isim = listeTurkceKarsilastir(ad(a.ad), ad(b.ad));
      return switch (_gecmisSiralama) {
        1 => tarih != 0 ? tarih : isim,
        2 => isim != 0 ? isim : -tarih,
        3 => isim != 0 ? -isim : -tarih,
        _ => tarih != 0 ? -tarih : isim,
      };
    });
    final gorunen = satirlar
        .where((s) => arama.isEmpty || s.arama.contains(arama))
        .toList();
    return CustomScrollView(
      key: const ValueKey('gonderim-gecmisi-liste'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(OrtakUi.bosluk),
          sliver: SliverList.list(
            children: [
              if (_gecmisFiltreAcik)
                Card(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: OrtakUi.bosluk),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Filtreler',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Filtreleri kapat',
                              onPressed: () =>
                                  setState(() => _gecmisFiltreAcik = false),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: _gecmisFiltreSatiri(
                          DropdownButtonFormField<String>(
                            key: ValueKey('gecmis-sinif-$_gecmisSinif'),
                            initialValue: _gecmisSinif,
                            isExpanded: true,
                            menuMaxHeight: 320,
                            decoration: const InputDecoration(
                              labelText: 'Sınıf',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  'Tüm sınıflar',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                              for (final s in sinifSecenekleri)
                                DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                    _gecmisSinif = v;
                                    _gecmisOgrenci = null;
                                    _gecmisSecili.clear();
                                  }),
                          ),
                          DropdownButtonFormField<int>(
                            key: ValueKey(
                              'gecmis-ogrenci-$_gecmisSinif-$_gecmisOgrenci',
                            ),
                            initialValue: _gecmisOgrenci,
                            isExpanded: true,
                            menuMaxHeight: 320,
                            decoration: const InputDecoration(
                              labelText: 'Öğrenci',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text(
                                  'Tüm öğrenciler',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                              for (final e in ogrenciSecenekleri.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                    _gecmisOgrenci = v;
                                    _gecmisSecili.clear();
                                  }),
                          ),
                        ),
                      ),
                      _gecmisEkFiltreler(),
                    ],
                  ),
                ),
              if (_gecmisAramaAcik)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    key: const ValueKey('gonderim-gecmisi-arama'),
                    controller: _gecmisArama,
                    enabled: !_busy,
                    onChanged: (_) => setState(_gecmisSecili.clear),
                    decoration: InputDecoration(
                      suffixIcon: IconButton(
                        tooltip: 'Aramayı temizle',
                        icon: const Icon(Icons.clear),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _gecmisArama.clear();
                                _gecmisSecili.clear();
                              }),
                      ),
                      labelText: 'Öğrenci / alıcı geçmişi ara',
                      hintText: 'Ad, okul numarası veya telefon',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${gorunen.length} kayıt${_gecmisFiltreli ? ' • Filtre uygulanıyor' : ''}',
                    ),
                    TextButton.icon(
                      key: const ValueKey('gecmis-tumunu-sec'),
                      onPressed: _busy || _secilebilirGecmis.isEmpty
                          ? null
                          : () => setState(() {
                              final hepsi = _secilebilirGecmis;
                              if (hepsi.every(_gecmisSecili.contains)) {
                                _gecmisSecili.clear();
                              } else {
                                _gecmisSecili
                                  ..clear()
                                  ..addAll(hepsi);
                              }
                            }),
                      icon: const Icon(Icons.select_all),
                      label: Text(
                        _secilebilirGecmis.isNotEmpty &&
                                _secilebilirGecmis.every(_gecmisSecili.contains)
                            ? 'Seçimi kaldır'
                            : 'Tümünü seç',
                      ),
                    ),
                    Text(
                      '${_gecmisSecili.intersection(_secilebilirGecmis).length} seçili',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (gorunen.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 40,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: OrtakUi.bosluk),
                    Text(
                      'Gönderim kaydı bulunamadı.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _gecmisFiltreli || arama.isNotEmpty
                          ? 'Aramayı veya filtreleri değiştirerek tekrar deneyin.'
                          : 'Gönderim işlemleriniz burada listelenir.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              OrtakUi.bosluk,
              0,
              OrtakUi.bosluk,
              OrtakUi.bosluk,
            ),
            sliver: SliverList.builder(
              itemCount: gorunen.length,
              itemBuilder: (_, i) => gorunen[i].satir(),
            ),
          ),
      ],
    );
  }

  Widget _topluGecmisSatiri(MesajKuyrugu q, MesajAlicisi a, String aciklama) {
    final key = 'q/${q.id}/${a.id}';
    final secilebilir = !_busy && _secilebilirGecmis.contains(key);
    return MesajGecmisKarti(
      tarih: q.tarih,
      kanal: a.smsDurumu == null ? 'WhatsApp' : 'SMS',
      tamMetin: '$aciklama\n${a.ad}',
      durum: a.smsDurumu == null
          ? _durum(a)
          : a.smsDurumu == 'Istendi'
          ? 'SMS isteği iletildi'
          : 'SMS sonucu belirsiz',
      child: ListTile(
        title: Text(aciklama, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${a.ad} • ${_gecmisKonusu(q.kaynakModul, MesajlasmaService.aliciMetni(q, a))}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        leading: Checkbox(
          key: ValueKey('gecmis-sec-$key'),
          value: _gecmisSecili.contains(key),
          onChanged: secilebilir ? (_) => _gecmisSec(key) : null,
        ),
        selected: _gecmisSecili.contains(key),
        onTap: secilebilir ? () => _gecmisSec(key) : null,
      ),
    );
  }

  Widget _kuyruk() {
    final q = _aktif!, next = q.siradaki;
    return ListView(
      key: const ValueKey('whatsapp-devam'),
      padding: const EdgeInsets.all(16),
      children: [
        if (next != null) ...[
          MesajTakipAliciOzeti(
            alici: next,
            sira: '${next.sira} / ${q.alicilar.length}',
          ),
          const SizedBox(height: 16),
          if (next.durum == 'Acildi') ...[
            const Text('Mesajı WhatsApp içinde gönderdiyseniz devam edin.'),
            FilledButton(
              onPressed: _busy ? null : () => _sonuc(next, true),
              child: const Text('Gönderdim, sıradakine geç'),
            ),
          ] else ...[
            if (next.hata != null) Text('WhatsApp açılamadı. ${next.hata}'),
            FilledButton(
              onPressed: _busy ? null : () => _ac(next),
              child: const Text('WhatsApp’ı yeniden aç'),
            ),
          ],
          TextButton(
            onPressed: _busy ? null : () => _sonuc(next, false),
            child: const Text('Atla'),
          ),
        ],
        OutlinedButton(
          onPressed: _busy ? null : _takibiKapat,
          child: const Text('Daha sonra devam et'),
        ),
      ],
    );
  }

  String _ogrenciAciklamasi(MesajAlicisi a) =>
      (jsonDecode(a.ogrenciler) as List).map((o) => o['aciklama']).join('\n');
  String _durum(MesajAlicisi a) => switch (a.durum) {
    'Onaylandi' => 'Onaylandı',
    'Atlandi' => 'Atlandı',
    'Acildi' => 'Onay bekliyor',
    'Acilamadi' => 'WhatsApp açılamadı',
    _ => 'Bekliyor',
  };
}
