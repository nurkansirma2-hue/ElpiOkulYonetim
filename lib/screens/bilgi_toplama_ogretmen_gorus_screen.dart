import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/mesajlasma.dart';
import '../services/bireysel_rehberlik_service.dart';
import '../services/mesajlasma_service.dart';
import '../services/bireysel_bilgi_toplama_service.dart';
import '../services/ogretmen_gorus_google_service.dart';
import '../services/ogretmen_gorus_fotograf.dart';
import '../services/bilgi_toplama_ogretmen_gorus_service.dart';
import '../widgets/modul_ust_bar.dart';
import '../widgets/ortak_ui.dart';
import 'mesajlasma_screen.dart';
import 'import_merkezi_screen.dart';
import '../widgets/mesaj_alici_secim_sliver.dart';

class BilgiToplamaOgretmenGorusScreen extends StatefulWidget {
  const BilgiToplamaOgretmenGorusScreen({
    super.key,
    required this.service,
    required this.baglam,
    required this.atamaId,
    required this.toplantiId,
    this.hassasOnay = false,
    this.saltOkunur = false,
    this.google,
    this.formService,
    this.mesajService,
    this.hesapBagla,
  });
  final BireyselRehberlikService service;
  final BireyselRehberlikBaglami baglam;
  final int atamaId, toplantiId;
  final bool hassasOnay, saltOkunur;
  final OgretmenGorusGoogleService? google;
  final BireyselBilgiToplamaService? formService;
  final MesajlasmaService? mesajService;
  final Future<({String token, String hesap})> Function()? hesapBagla;
  @override
  State<BilgiToplamaOgretmenGorusScreen> createState() => _GorusState();
}

class _GorusState extends State<BilgiToplamaOgretmenGorusScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final _google = widget.google ?? OgretmenGorusGoogleService();
  late final _formlar = BilgiToplamaOgretmenGorusService(
    formlar: widget.formService ?? BireyselBilgiToplamaService.instance,
    kaynak: widget.service,
    baglam: widget.baglam,
    atamaId: widget.atamaId,
    toplantiId: widget.toplantiId,
    google: _google,
    hassasOnay: widget.hassasOnay,
  );
  late final _mesaj = widget.mesajService ?? MesajlasmaService.instance;
  late final _oturum = GoogleSignIn(
    serverClientId: const String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue:
          '809052042804-k51q6va9bvevktpf8hoqcs87s752n5cg.apps.googleusercontent.com',
    ),
    scopes: const ['https://www.googleapis.com/auth/forms'],
  );
  Map<String, Object?>? _durum;
  Map<String, dynamic>? _kayit, _istek;
  List<MesajKisi> _ogretmenler = [];
  final _seciliOgretmenler = <String>{};
  bool _secimYuklendi = false;
  List<Map<String, dynamic>> _yanitlar = [];
  bool _busy = false, _yanitOkundu = false, _gizli = false;
  String? _hata, _bilgi;
  int _sekme = 0;
  late final _tablar = TabController(length: 3, vsync: this);
  final _arama = TextEditingController();
  final _mesajMetni = TextEditingController();
  bool _mesajDuzenlendi = false;
  String? _mesajLinki;

  void _mesajiGuncelle(String? link) {
    if (_istek == null) return;
    final baglanti = link == null || link.isEmpty ? '{FormBaglantisi}' : link;
    if (!_mesajDuzenlendi) {
      _mesajMetni.text =
          'Değerli öğretmenim,\n${_istek!['sinif']} sınıfı için genel sınıf görüşünüzü ve öğrenciler hakkındaki açıklamalarınızı aşağıdaki forma yazmanızı rica ederim.\n$baglanti\nTeşekkür ederim.';
    } else {
      _mesajMetni.text = _mesajMetni.text.replaceAll(
        _mesajLinki ?? '{FormBaglantisi}',
        baglanti,
      );
    }
    _mesajLinki = baglanti;
  }

  final _silSecili = <String>{};
  String _asama = 'Bilgiler yükleniyor';
  void _asamaGoster(String mesaj) {
    if (mounted) setState(() => _asama = mesaj);
  }

  final _ipucu = GlobalKey<TooltipState>();
  Timer? _ipucuZamani;
  Map<String, dynamic>? get _sonuc => _kayit?['sonuc'] == null
      ? null
      : Map<String, dynamic>.from(_kayit!['sonuc'] as Map);
  List<Map> get _ogrenciler =>
      (_istek?['ogrenciler'] as List? ?? []).cast<Map>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _is(_yukle);
  }

  @override
  void dispose() {
    _tablar.dispose();
    _arama.dispose();
    _mesajMetni.dispose();
    _ipucuZamani?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.google == null) _google.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      setState(() {
        _gizli = true;
        _yanitlar = [];
        _yanitOkundu = false;
      });
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _gizli = false);
    }
  }

  Future<void> _is(Future<void> Function() f) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) {
        setState(
          () => _hata = e is StateError
              ? 'İşlem tamamlanamadı. ${e.message}'
              : 'İşlem tamamlanamadı. Bilgileriniz korundu. Bağlantınızı kontrol edip yeniden deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, Object?>> _kapsam({bool yazma = false}) =>
      widget.service.ogretmenGorusDurumu(
        widget.baglam,
        widget.atamaId,
        widget.toplantiId,
        yazma: yazma,
        hassasOnay: widget.hassasOnay,
      );

  Future<void> _mesajKapsami(MesajBaglami b) async {
    final a = await _kapsam(yazma: true);
    if (b.okulId != widget.baglam.okulId ||
        b.ogretmenId != widget.baglam.ogretmenProfilId ||
        b.yil != widget.baglam.egitimOgretimYili ||
        a['SinifSubeId'] != _durum?['SinifSubeId']) {
      throw StateError(
        'Okul, öğretmen, yıl veya sınıf değişti. Görüş formunu yeniden açın.',
      );
    }
  }

  Future<void> _yukle() async {
    final a = await _kapsam();
    final kayit = a['form'] == null
        ? null
        : Map<String, dynamic>.from(a['form'] as Map);
    Map<String, dynamic>? istek;
    if (kayit != null) {
      istek = Map<String, dynamic>.from(kayit['istek'] as Map);
    } else if (!widget.saltOkunur) {
      final rows = await widget.service.ogrencileriGetir(
        widget.baglam,
        atamaId: widget.atamaId,
      );
      final ogrenciler = <int, Map<String, dynamic>>{};
      for (final o in rows) {
        final id = o['OgrenciId'] as int;
        ogrenciler.putIfAbsent(
          id,
          () => {
            'id': id,
            'no': '${o['OkulNo'] ?? ''}',
            'ad': '${o['Ad']} ${o['Soyad']}'.trim(),
          },
        );
        ogrenciler[id]!['foto'] = await ogretmenGorusFotografi(o);
      }
      final random = Random.secure();
      istek = {
        'requestId': List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        'kapsam': widget.service.ogretmenGorusKapsamAnahtari(
          widget.baglam,
          widget.atamaId,
          widget.toplantiId,
        ),
        'baslik': '${a['SinifKodu']} • ${a['Baslik']}'.substring(
          0,
          min(200, '${a['SinifKodu']} • ${a['Baslik']}'.length),
        ),
        'sinif': '${a['SinifKodu']}',
        'yil': widget.baglam.egitimOgretimYili,
        'ogrenciler': ogrenciler.values.toList(),
      };
    }
    List<MesajKisi> ogretmenler = [];
    if (!widget.saltOkunur) {
      final b = await _mesaj.hazirla();
      if (b.okulId != widget.baglam.okulId ||
          b.ogretmenId != widget.baglam.ogretmenProfilId ||
          b.yil != widget.baglam.egitimOgretimYili) {
        throw StateError('Mesajlaşma ile rehberlik kapsamı uyuşmuyor.');
      }
      ogretmenler = await _mesaj.aliciAdaylari(
        b,
        tur: MesajKisiTuru.ogretmen,
        sinifId: a['SinifSubeId'] as int,
      );
    }
    if (kayit == null && istek != null) {
      istek['ogretmenler'] = ogretmenler
          .map((k) => k.ad.trim())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();
      istek['dersler'] = ogretmenler
          .expand(
            (k) => k.aciklama.split(' • ').skip(1).join(' • ').split(', '),
          )
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty && !v.startsWith('Ders bilgisi yok'))
          .toSet()
          .toList();
    }
    await _kapsam();
    if (mounted) {
      setState(() {
        _durum = a;
        _kayit = kayit;
        if (!_gizli && kayit?['yanitlar'] is List) {
          _yanitlar = (kayit!['yanitlar'] as List)
              .map((y) => Map<String, dynamic>.from(y as Map))
              .toList();
          _yanitOkundu = true;
        }
        _silSecili.retainAll(_yanitlar.map((y) => '${y['responseId']}'));
        _istek = istek;
        _mesajiGuncelle(_sonuc?['responderUrl']?.toString());
        _ogretmenler = ogretmenler;
        if (!_secimYuklendi) {
          _seciliOgretmenler.addAll(
            (kayit?['aliciIdleri'] as List?)?.cast<String>() ??
                ogretmenler.map((k) => k.kisiId),
          );
          _secimYuklendi = true;
        }
        _seciliOgretmenler.retainAll(ogretmenler.map((k) => k.kisiId));
      });
    }
  }

  Future<({String token, String hesap})> _yetki() async {
    if (widget.google == null) {
      await _formlar.baglantiyiHazirla();
    }
    final ({String token, String hesap}) v;
    if (widget.hesapBagla != null) {
      v = await widget.hesapBagla!();
    } else {
      final account =
          _oturum.currentUser ??
          await _oturum.signInSilently() ??
          await _oturum.signIn();
      if (account == null) {
        throw StateError('Google hesap seçimi iptal edildi.');
      }
      if (!await _oturum.requestScopes([
        'https://www.googleapis.com/auth/forms',
      ])) {
        throw StateError('Google Forms izni verilmedi.');
      }
      final token = (await account.authentication).accessToken;
      if (token == null) throw StateError('Google hesap izni yenilenmeli.');
      v = (token: token, hesap: account.email);
    }
    if (_kayit != null && _kayit!['hesap'] != v.hesap) {
      throw StateError(
        'Bu form ${_kayit!['hesap']} hesabıyla hazırlandı. Aynı hesabı seçin.',
      );
    }
    return v;
  }

  Future<void> _hazirla() => _is(() async {
    await _kapsam(yazma: true);
    if (_istek == null || _ogrenciler.isEmpty) {
      throw StateError('Sınıfta aktif öğrenci yok.');
    }
    _asamaGoster('Google hesabına bağlanılıyor…');
    final v = await _yetki().timeout(const Duration(seconds: 60));
    _asamaGoster('Google Form bağlantısı kontrol ediliyor…');
    _asamaGoster('Fotoğraflı öğretmen görüşü formu hazırlanıyor…');
    await _formlar.hazirla(v.token, v.hesap, _istek!);
    await _yukle();
    if (mounted) _ipucuGoster();
  });

  Future<void> _gonder({bool hatirlat = false}) => _is(() async {
    await _kapsam(yazma: true);
    final mb = await _mesaj.hazirla();
    await _mesajKapsami(mb);
    final kisiler = await _mesaj.aliciAdaylari(
      mb,
      tur: MesajKisiTuru.ogretmen,
      sinifId: _durum!['SinifSubeId'] as int,
    );
    if (kisiler.isEmpty ||
        (!hatirlat &&
            !kisiler.any((k) => _seciliOgretmenler.contains(k.kisiId)))) {
      throw StateError(
        'Sınıfta derse giren öğretmen kaydı yok. Mesajlaşma / Import Merkezi’nden öğretmen ders programını aktarın.',
      );
    }
    final hazir = _sonuc;
    if (hazir == null) {
      throw StateError(
        'Google Form hazır değil. Mesajlaşma açılmadı; yeniden deneyin.',
      );
    }
    final v = await _yetki();
    _asamaGoster('Form bağlantısı doğrulanıyor…');
    final r = await _formlar.yayinaHazirla(
      v.token,
      v.hesap,
      '${_istek!['requestId']}',
      '${hazir['formId']}',
    );
    final hedefler = hatirlat
        ? kisiler.map((k) => k.kisiId).toSet()
        : Set<String>.of(_seciliOgretmenler);
    Future<void> yanitlariYenile() async {
      _asamaGoster('Yanıtlayan öğretmenler kontrol ediliyor…');
      final yanitlar = await _formlar.yanitlar(
        v.token,
        '${_istek!['requestId']}',
        '${r['formId']}',
      );
      await _mesajKapsami(mb);
      if (mounted && !_gizli) {
        setState(() {
          _yanitlar = yanitlar;
          _yanitOkundu = true;
        });
      }
      hedefler.removeAll(
        BilgiToplamaOgretmenGorusService.yanitlayanOgretmenIdleri(
          kisiler,
          yanitlar,
        ),
      );
    }

    if (hatirlat) {
      await yanitlariYenile();
      if (!mounted) return;
      if (hedefler.isEmpty) {
        setState(
          () => _bilgi =
              'Tüm öğretmenler yanıtladı. Hatırlatma gönderilecek öğretmen yok.',
        );
        return;
      }
    }
    await _mesajKapsami(mb);
    await widget.service.ogretmenGorusYonet(
      widget.baglam,
      widget.atamaId,
      widget.toplantiId,
      requestId: '${_istek!['requestId']}',
      formId: '${r['formId']}',
      hassasOnay: widget.hassasOnay,
      aliciIdleri: hedefler.toList(),
    );
    if (!mounted) return;
    _mesajiGuncelle(r['responderUrl']?.toString());
    final guncelLink = r['responderUrl'].toString();
    if (!_mesajMetni.text.contains(guncelLink)) {
      _mesajMetni.text = '${_mesajMetni.text.trim()}\n$guncelLink';
    }
    if (_mesajMetni.text.trim().isEmpty || _mesajMetni.text.length > 4000) {
      throw StateError('Mesaj metni 1–4000 karakter olmalıdır.');
    }
    final onayHedefleri = Set<String>.of(hedefler);
    _asamaGoster('Seçili öğretmenlerle gönderim onayı açılıyor…');
    setState(() => _busy = false);
    await Navigator.push(
      context,
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, _, _) => MesajlasmaScreen(
          service: _mesaj,
          gonderimOnizlemesiniAc: true,
          yalnizGonderimOnayi: true,
          takipPenceresi: true,
          baslangicOgretmenIdleri: Set.of(hedefler),
          kaynakModul: 'OgretmenGorusFormu',
          kaynakKayit:
              'atama:${widget.atamaId}:toplanti:${widget.toplantiId}:form:${r['formId']}',
          ogretmenSinifId: _durum!['SinifSubeId'] as int,
          kaynakKontrol: !hatirlat
              ? _mesajKapsami
              : (b) async {
                  await _mesajKapsami(b);
                  await yanitlariYenile();
                  if (!hedefler.containsAll(onayHedefleri)) {
                    throw StateError(
                      'Yeni yanıt geldi. Yanıtlayan öğretmene mesaj gönderilmedi; '
                      'geri dönüp Hatırlat ile güncel listeyi yeniden açın.',
                    );
                  }
                },
          baslangicMetni:
              '${hatirlat ? 'Hatırlatma: ' : ''}${_mesajMetni.text.trim()}',
        ),
      ),
    );
    if (mounted) await _yukle();
  });

  Future<void> _mesajlasmayaGit({bool hatirlat = false}) async {
    if ((_kayit?['yonetim'] as Map?)?['acik'] == false ||
        (_kayit?['yonetim'] as Map?)?['arsiv'] == true) {
      setState(
        () => _hata = 'Form yanıt alımına kapalı. Önce Özet bölümünden açın.',
      );
      return;
    }
    if (!hatirlat && _seciliOgretmenler.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir öğretmen seçin.')),
      );
      return;
    }
    if (_sonuc == null) await _hazirla();
    if (!mounted) return;
    if (_sonuc == null) return;
    await _gonder(hatirlat: hatirlat);
  }

  Future<void> _yanitOku() => _is(() async {
    await _kapsam();
    final v = await _yetki();
    final yanitlar = await _formlar.yanitlar(
      v.token,
      '${_istek!['requestId']}',
      '${_sonuc!['formId']}',
    );
    await _kapsam();
    if (mounted && !_gizli) {
      setState(() {
        _yanitlar = yanitlar;
        _yanitOkundu = true;
        _sekme = 1;
        _tablar.index = 1;
      });
    }
  });

  Future<void> _formAc() => _is(() async {
    await _kapsam();
    final u = OgretmenGorusGoogleService.baglanti(
      '${_sonuc!['editUrl']}',
      duzenle: true,
    );
    await const MethodChannel(
      'elpi_okul_yonetim/google_form',
    ).invokeMethod<void>('ac', {'adres': u.toString()});
  });

  Future<void> _programAktar() => _is(() async {
    await _kapsam(yazma: true);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ImportMerkeziScreen(
          mesajService: _mesaj,
          sinifId: _durum!['SinifSubeId'] as int,
        ),
      ),
    );
    if (mounted) await _yukle();
  });

  void _ipucuGoster() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _gizli) return;
      _ipucu.currentState?.ensureTooltipVisible();
      _ipucuZamani?.cancel();
      _ipucuZamani = Timer(const Duration(seconds: 4), () {
        if (mounted) Tooltip.dismissAllToolTips();
      });
    });
  }

  Future<void> _onizlemeAc() async {
    if (_busy || _sonuc == null) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Form ön izlemesi'),
        content: SizedBox(
          width: 500,
          height: MediaQuery.sizeOf(c).height * .6,
          child: ListView(
            children: [
              for (final alan in ['ogretmenler', 'dersler'])
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: alan == 'ogretmenler'
                          ? 'Öğretmen adı'
                          : 'Girdiğiniz ders / dersler',
                    ),
                    hint: const Text('Seçiniz'),
                    items: [
                      for (final v in (_istek?[alan] as List? ?? []))
                        DropdownMenuItem(
                          value: '$v',
                          child: Text('$v', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              const ListTile(
                title: Text('Sınıfın genel durumu hakkındaki görüşünüz'),
                subtitle: Text('Zorunlu • Uzun açıklama'),
              ),
              for (final o in _ogrenciler)
                ListTile(
                  leading: o['foto'] == null
                      ? const Icon(Icons.person_outline)
                      : Image.memory(
                          base64Decode('${(o['foto'] as Map)['base64']}'),
                          width: 48,
                          height: 64,
                          fit: BoxFit.contain,
                        ),
                  title: Text('${o['no']} • ${o['ad']}'),
                  subtitle: Text(
                    o['foto'] == null
                        ? 'Fotoğraf yok • Öğrenci hakkında açıklama'
                        : 'Öğrenci hakkında açıklama',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _gorunenYanitlar => _yanitlar.where((y) {
    final ara = _arama.text.trim().toLowerCase();
    final adlar = _ogrenciler
        .where((o) => (y['ogrenciler'] as Map).containsKey('${o['id']}'))
        .map((o) => o['ad'])
        .join(' ');
    return ara.isEmpty ||
        '${y['ogretmen']} ${y['ders']} ${y['sinifGorusu']} $adlar'
            .toLowerCase()
            .contains(ara);
  }).toList();

  Future<bool> _onay(String baslik, String metin) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(baslik),
          content: SingleChildScrollView(child: Text(metin)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Onayla'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _durumAyarla(String islem) => _is(() async {
    if (_sonuc == null || widget.saltOkunur) return;
    if (!await _onay(
      islem,
      '$islem işlemi uygulansın mı? Form ve yanıtlar silinmez.',
    )) {
      return;
    }
    if (!mounted || _gizli) return;
    final v = await _yetki();
    await _formlar.durumAyarla(
      v.token,
      '${_istek!['requestId']}',
      '${_sonuc!['formId']}',
      islem,
    );
    await _yukle();
  });

  Future<void> _yanitSil({String? tek}) => _is(() async {
    if (widget.saltOkunur || _sonuc == null) return;
    final ids = tek == null ? Set<String>.of(_silSecili) : <String>{tek};
    if (ids.isEmpty) return;
    if (!await _onay(
      'Google Forms ve uygulamadan sil',
      '${ids.length} yanıt kalıcı olarak silinecek. Önce Google’dan silindiği doğrulanır. Başarısız yanıtlar korunur. Öğrenci kayıtları değişmez. Bağlı E-Tablo kopyaları ve eski yedekler silinmez.',
    )) {
      return;
    }
    if (!mounted || _gizli) return;
    final v = await _yetki();
    final hatalar = await _formlar.yanitlariSil(
      v.token,
      '${_istek!['requestId']}',
      '${_sonuc!['formId']}',
      ids,
      devamEt: () => mounted && !_gizli,
    );
    await _yukle();
    if (mounted) {
      setState(
        () => _bilgi = hatalar.isEmpty
            ? '${ids.length} yanıt silindi.'
            : hatalar.join('\n'),
      );
    }
  });

  Widget _aliciSecimi() => CustomScrollView(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    slivers: [
      MesajAliciSecimSliver(
        adaylar: _ogretmenler,
        siniflar: {_durum!['SinifSubeId'] as int: '${_durum!['SinifKodu']}'},
        secilenler: {
          for (final k in _ogretmenler.where(
            (k) => _seciliOgretmenler.contains(k.kisiId),
          ))
            k.secimAnahtari: k,
        },
        degistir: (kisiler) => setState(() {
          _seciliOgretmenler.clear();
          _seciliOgretmenler.addAll(kisiler.map((k) => k.kisiId));
        }),
        veliDuzenle: (_) async {},
        ogretmenDuzenle: (_, __) async {},
        kisiDuzenle: (_) async {},
        sadeceOgretmen: true,
        iletisimDuzenleme: false,
        kilitli: _busy,
      ),
    ],
  );

  Widget _yanitListesi() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _arama,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Öğretmen, ders veya öğrenci ara',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      if (!_yanitOkundu) const Text('Henüz yanıtlar alınmadı.'),
      if (_yanitOkundu && _yanitlar.isEmpty) const Text('Henüz yanıt gelmedi.'),
      for (final y in _gorunenYanitlar)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: widget.saltOkunur
                      ? null
                      : Checkbox(
                          value: _silSecili.contains(y['responseId']),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    _silSecili.add('${y['responseId']}');
                                  } else {
                                    _silSecili.remove(y['responseId']);
                                  }
                                }),
                        ),
                  title: Text('${y['ogretmen']} • ${y['ders']}'),
                ),
                Text('Sınıf görüşü: ${y['sinifGorusu'] ?? ''}'),
                for (final o in _ogrenciler)
                  if ((y['ogrenciler'] as Map)['${o['id']}'] != null)
                    Text(
                      '${o['ad']}: ${(y['ogrenciler'] as Map)['${o['id']}']}',
                    ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _degerlendirme() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final o in _ogrenciler)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${o['no']} • ${o['ad']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final y in _yanitlar)
                  if ((y['ogrenciler'] as Map)['${o['id']}'] != null)
                    Text(
                      '${y['ogretmen']} (${y['ders']}): ${(y['ogrenciler'] as Map)['${o['id']}']}',
                    ),
              ],
            ),
          ),
        ),
      const Text(
        'Görüşler öğrenci kimlik ve iletişim bilgilerini değiştirmez.',
      ),
    ],
  );

  void _tumYanitlariSec() => setState(() {
    final hepsi =
        _gorunenYanitlar.isNotEmpty &&
        _gorunenYanitlar.every((y) => _silSecili.contains(y['responseId']));
    for (final y in _gorunenYanitlar) {
      if (hepsi) {
        _silSecili.remove(y['responseId']);
      } else {
        _silSecili.add('${y['responseId']}');
      }
    }
  });

  Widget _altIslemler() {
    final hazir = _sonuc != null;
    final tumuSecili =
        _gorunenYanitlar.isNotEmpty &&
        _gorunenYanitlar.every((y) => _silSecili.contains(y['responseId']));
    final yazabilir = !widget.saltOkunur && _durum != null;
    Widget eylem(
      String text,
      IconData icon,
      VoidCallback? action, {
      String? hint,
      Key? key,
    }) => Expanded(
      child: Tooltip(
        message: hint ?? text,
        child: TextButton(
          key: key,
          onPressed: _busy ? null : action,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 56),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 4),
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
    return Row(
      key: const ValueKey('gorus-alt-islemler'),
      children: [
        if (_durum == null)
          eylem(
            'Yenile',
            Icons.refresh,
            () => _is(_yukle),
            hint: 'Yeniden dene',
          )
        else if (_sekme == 0 && yazabilir)
          eylem('Mesaj at', Icons.send_outlined, _mesajlasmayaGit)
        else
          eylem(
            'Yenile',
            Icons.sync,
            hazir ? _yanitOku : null,
            hint: 'Yanıtları yenile',
          ),
        Expanded(
          child: Tooltip(
            key: _ipucu,
            message: 'Ön izleme',
            showDuration: const Duration(seconds: 4),
            child: TextButton(
              key: const ValueKey('gorus-form-onizleme'),
              onPressed: _busy || !hazir ? null : _onizlemeAc,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 56),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.preview_outlined, size: 22),
                  SizedBox(height: 4),
                  Text(
                    'Ön izle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_sekme == 0 && yazabilir) ...[
          eylem(
            'Hatırlat',
            Icons.notifications_active_outlined,
            hazir ? () => _mesajlasmayaGit(hatirlat: true) : null,
            hint: 'Seçililere hatırlat',
          ),
          eylem(
            'Yanıtlar',
            Icons.sync,
            hazir ? _yanitOku : null,
            hint: 'Gelen görüşler',
          ),
        ] else if (_sekme == 1 && yazabilir) ...[
          eylem(
            tumuSecili ? 'Kaldır' : 'Tümünü seç',
            Icons.select_all,
            _gorunenYanitlar.isEmpty ? null : _tumYanitlariSec,
            hint: 'Görünen yanıtların seçimini değiştir',
          ),
          eylem(
            'Sil (${_silSecili.length})',
            Icons.delete_outline,
            _silSecili.isEmpty ? null : () => _yanitSil(),
            hint: 'Seçilen ${_silSecili.length} yanıtı sil',
          ),
        ] else if (_sekme == 2 && yazabilir)
          eylem('Mesaj at', Icons.send_outlined, _mesajlasmayaGit),
        Expanded(
          child: PopupMenuButton<String>(
            tooltip: 'Form işlemleri',
            enabled: !_busy,
            onSelected: (v) {
              switch (v) {
                case 'form':
                  _formAc();
                case 'gorus':
                  _yanitOku();
                case 'hatirlat':
                  _mesajlasmayaGit(hatirlat: true);
                case 'import':
                  _programAktar();
                case 'yenile':
                  _is(_yukle);
                default:
                  _durumAyarla(v);
              }
            },
            itemBuilder: (_) => [
              if (hazir)
                const PopupMenuItem(
                  value: 'form',
                  child: Text('Google Formu görüntüle'),
                ),
              if (hazir)
                const PopupMenuItem(
                  value: 'gorus',
                  child: Text('Gelen görüşler'),
                ),
              if (yazabilir && hazir) ...[
                const PopupMenuItem(
                  value: 'hatirlat',
                  child: Text('Seçililere hatırlat'),
                ),
                const PopupMenuItem(
                  value: 'Kapat',
                  child: Text('Yanıt alımını kapat'),
                ),
                const PopupMenuItem(
                  value: 'Aç',
                  child: Text('Yanıt alımını aç'),
                ),
                const PopupMenuItem(
                  value: 'Tamamla',
                  child: Text('Tamamlandı olarak işaretle'),
                ),
                PopupMenuItem(
                  value: (_kayit?['yonetim'] as Map?)?['arsiv'] == true
                      ? 'Arşivden çıkar'
                      : 'Arşivle',
                  child: Text(
                    (_kayit?['yonetim'] as Map?)?['arsiv'] == true
                        ? 'Arşivden çıkar'
                        : 'Arşivle',
                  ),
                ),
              ],
              if (yazabilir && _ogretmenler.isEmpty)
                const PopupMenuItem(
                  value: 'import',
                  child: Text('Öğretmen ders programını aktar'),
                ),
              const PopupMenuItem(value: 'yenile', child: Text('Yeniden dene')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.more_vert, size: 22),
                  SizedBox(height: 4),
                  Text('Diğer', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: const ModulUstBar(title: Text('Öğretmen görüş formu')),
    bottomNavigationBar: _gizli ? null : _altIslemler(),
    body: _gizli
        ? const Center(child: Text('Görüşler gizlendi.'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) ...[
                const LinearProgressIndicator(),
                Text(_asama, key: const ValueKey('gorus-islem-asamasi')),
              ],
              if (_hata != null) ...[
                Text(
                  _hata!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_bilgi != null) Text(_bilgi!),
              if (_durum != null) ...[
                Text(
                  '${_durum!['SinifKodu']} • ${_durum!['Baslik']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TabBar(
                  controller: _tablar,
                  onTap: (i) => setState(() => _sekme = i),
                  tabs: const [
                    Tab(text: 'Özet'),
                    Tab(text: 'Yanıtlar'),
                    Tab(text: 'Değerlendirme'),
                  ],
                ),
                if (_sekme == 0) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_ogrenciler.length} öğrenci • ${_ogretmenler.length} ders öğretmeni',
                          ),
                          Text(
                            'Yanıt alımı: ${(_kayit?['yonetim'] as Map?)?['acik'] == false
                                ? 'Kapalı'
                                : _sonuc?['acceptingResponses'] == true
                                ? 'Açık'
                                : 'Henüz doğrulanmadı'}',
                          ),
                          Text(
                            '${_yanitlar.length} yanıt • ${BilgiToplamaOgretmenGorusService.yanitlayanOgretmenIdleri(_ogretmenler, _yanitlar).length} öğretmen yanıtladı',
                          ),
                          if (widget.saltOkunur)
                            const Text('Geçmiş toplantı salt okunur.'),
                        ],
                      ),
                    ),
                  ),
                  if (!widget.saltOkunur) _aliciSecimi(),
                  if (!widget.saltOkunur)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: TextField(
                        key: const ValueKey('ogretmen-gorus-mesaj'),
                        controller: _mesajMetni,
                        enabled: !_busy,
                        minLines: 5,
                        maxLines: 10,
                        maxLength: 4000,
                        decoration: const InputDecoration(
                          labelText: 'Mesajınız',
                          border: OutlineInputBorder(),
                          helperText:
                              'Form bağlantısı hazırlandığında mesaja eklenir.',
                          helperMaxLines: 2,
                        ),
                        onChanged: (_) => _mesajDuzenlendi = true,
                      ),
                    ),
                  if (!widget.saltOkunur && _sonuc != null) ...[
                    const Text(
                      'Hatırlat, güncel form yanıtlarını kontrol ederek yalnızca yanıtlamayan öğretmenleri seçer.',
                    ),
                  ],
                ],
                if (_sekme == 1) _yanitListesi(),
                if (_sekme == 2) _degerlendirme(),
              ],
            ],
          ),
  );
}
