import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/ortak_google_oturum_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/bireysel_bilgi_toplama_service.dart';
import '../services/bireysel_rehberlik_service.dart';
import '../services/bilgi_toplama_google_service.dart';
import '../services/mesajlasma_service.dart';
import 'mesajlasma_screen.dart';
import 'bilgi_toplama_ogretmen_gorus_screen.dart';
import '../widgets/mesaj_alici_secim_sliver.dart';
import '../models/mesajlasma.dart';

const _alanlar = {
  'AnneAdi': 'Anne adı',
  'BabaAdi': 'Baba adı',
  'AnneTelefon': 'Anne telefon',
  'BabaTelefon': 'Baba telefon',
  'Telefon': 'Öğrenci telefon',
};
const _turler = {
  'Metin': 'Metin',
  'Sayi': 'Sayı',
  'Tarih': 'Tarih',
  'EvetHayir': 'Evet / Hayır',
  'Secenek': 'Seçenek',
};

String formIslemHatasi(Object hata) {
  if (hata is StateError) return 'İşlem tamamlanamadı. ${hata.message}';
  if (hata is FormatException) return 'Bilgileri kontrol edin. ${hata.message}';
  return 'İşlem tamamlanamadı. Bilgileriniz korundu.\nOrijinal hata: $hata';
}

String _onizlemeMetni(String alan, String? deger) => alan == 'VeliTuru'
    ? (const {'Anne': 'Anne', 'Baba': 'Baba', 'Diger': 'Diğer veli'}[deger] ??
          deger ??
          '—')
    : deger ?? '—';

// Kimlik ve iletişim alanları yukarıdaki mevcut kayıtlara bağlanır.
// Bu sorular ise mevcut ek bilgi altyapısıyla öğrenciye kaydedilir.
const _soruGruplari = <String, Map<String, String>>{
  'Öğrenci bilgileri': {
    'okul': 'Okulunuz',
    'cinsiyet': 'Cinsiyetiniz',
    'dogumYeri': 'Doğum yeriniz',
    'dogumTarihi': 'Doğum tarihiniz',
    'adres': 'Adresiniz',
    'okulOncesi': 'Okul öncesi eğitim aldınız mı?',
    'hobiler': 'Ne yapmaktan hoşlanırsınız?',
    'tasinma': 'Yakın zamanda taşındınız mı, okul değiştirdiniz mi?',
    'teknoloji':
        'Kendinize ait teknolojik aletler ve günlük/haftalık kullanım süreniz',
    'ilacCihaz':
        'Sürekli kullandığınız ilaç veya tıbbi cihaz var mı? Açıklayınız.',
    'hastalik': 'Sürekli bir hastalığınız var mı? Açıklayınız.',
    'faaliyet': 'Ders dışı faaliyetleriniz nelerdir?',
    'olay': 'Hâlâ etkisi altında olduğunuz bir olay yaşadınız mı? Açıklayınız.',
  },
  'Anne bilgileri': {
    'anneDogumYeri': 'Anne doğum yeri',
    'anneDogumTarihi': 'Anne doğum tarihi',
    'anneOz': 'Anne öz mü?',
    'anneSag': 'Anne sağ mı?',
    'anneEngel': 'Anne engel durumu',
    'anneEgitim': 'Anne eğitim durumu',
    'anneMeslek': 'Anne mesleği',
  },
  'Baba bilgileri': {
    'babaDogumYeri': 'Baba doğum yeri',
    'babaDogumTarihi': 'Baba doğum tarihi',
    'babaOz': 'Baba öz mü?',
    'babaSag': 'Baba sağ mı?',
    'babaEngel': 'Baba engel durumu',
    'babaEgitim': 'Baba eğitim durumu',
    'babaMeslek': 'Baba mesleği',
  },
  'Aile bilgileri': {
    'kardesSayisi': 'Kaç kardeşsiniz?',
    'kacinciCocuk': 'Ailenizin kaçıncı çocuğusunuz?',
    'okuyanKardesSayisi': 'Okula giden kardeş sayınız',
    'aileHastalik':
        'Aile üyelerinde sürekli hastalığı veya engeli olan var mı? Açıklayınız.',
    'birlikteYasayan':
        'Evinizde sizinle birlikte kimler yaşıyor? Yakınlık derecelerini belirtiniz.',
  },
};

BilgiToplamaSorusu _sablonSorusu(String key, String baslik) =>
    BilgiToplamaSorusu(
      anahtar: 'sablon$key',
      baslik: baslik,
      veriTuru: key.endsWith('Tarihi')
          ? 'Tarih'
          : key.endsWith('Sayisi') || key == 'kacinciCocuk'
          ? 'Sayi'
          : key.endsWith('Oz') || key.endsWith('Sag') || key == 'okulOncesi'
          ? 'EvetHayir'
          : 'Metin',
    );

Future<bool> _onay(BuildContext context, String baslik, String mesaj) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(baslik),
        content: SingleChildScrollView(child: Text(mesaj)),
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

/// Ayrılmış alt alanda durur; içerik üzerinde yüzmez ve son satırı kapatmaz.
class _FormAnaIslem extends StatelessWidget {
  const _FormAnaIslem({
    required this.metin,
    required this.ipucu,
    required this.onPressed,
    this.geri,
    this.busy = false,
    this.icon = Icons.cloud_upload_outlined,
  });
  final String metin, ipucu;
  final VoidCallback? onPressed, geri;
  final bool busy;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      12,
      8,
      12,
      8 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Row(
      children: [
        if (geri != null)
          IconButton(
            tooltip: 'Geri',
            onPressed: busy ? null : geri,
            icon: const Icon(Icons.arrow_back),
          ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: ipucu,
              showDuration: const Duration(seconds: 4),
              child: FilledButton.icon(
                key: const ValueKey('form-sabit-ana-islem'),
                onPressed: busy ? null : onPressed,
                style: FilledButton.styleFrom(
                  elevation: 2,
                  minimumSize: const Size(0, 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Icon(icon),
                label: Text(
                  busy ? 'Hazırlanıyor…' : metin,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class BireyselBilgiToplamaScreen extends StatefulWidget {
  const BireyselBilgiToplamaScreen({
    super.key,
    this.service,
    this.google,
    this.hesapBagla,
    this.sekmeIcinde = false,
  });
  final bool sekmeIcinde;
  final BireyselBilgiToplamaService? service;
  final BilgiToplamaGoogleService? google;
  final Future<String> Function()? hesapBagla;
  @override
  State<BireyselBilgiToplamaScreen> createState() => _FormlarState();
}

class _FormlarState extends State<BireyselBilgiToplamaScreen> {
  late final _service = widget.service ?? BireyselBilgiToplamaService.instance;
  BilgiToplamaOturumu? _b;
  List<Map<String, Object?>> _formlar = [];
  Map<int, List<String>> _formOzetleri = {};
  List<Map<String, Object?>> _gorusFormlari = [];
  Map<int, Map<String, dynamic>> _yonetim = {};
  String _durumFiltresi = 'Tümü';
  String? _hata;
  bool _busy = true;
  bool _secimModu = false;
  final _secilenFormlar = <int>{};
  String? _silmeDurumu;
  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      final b = await _service.hazirla();
      final f = await _service.formlar(b);
      final gorusler = await _service.ogretmenGorusFormlari(b);
      final ozetler = <int, List<String>>{};
      final yonetim = <int, Map<String, dynamic>>{};
      for (final form in f) {
        final id = form['Id'] as int;
        final m = await _service.formOzeti(b, id);
        yonetim[id] = m;
        final hedef = await _service.hedefOgrenciler(b, id);
        final sorular = await _service.sorular(b, id);
        final siniflar =
            hedef.map((o) => o['SinifKodu'].toString()).toSet().toList()
              ..sort();
        final bilgiler = sorular
            .where(
              (q) =>
                  !BireyselBilgiToplamaService.kimlikAlani(q['AlanAnahtari']),
            )
            .map((q) => q['Baslik'].toString())
            .toList();
        final tarih = DateTime.tryParse(
          form['OlusturmaTarihi'].toString(),
        )?.toLocal();
        final tarihMetni = tarih == null
            ? ''
            : '${tarih.day.toString().padLeft(2, '0')}.${tarih.month.toString().padLeft(2, '0')}.${tarih.year} • ';
        ozetler[id] = [
          '${siniflar.isEmpty ? 'Hedef sınıf bulunamadı' : siniflar.join(', ')} • '
              '${hedef.map((o) => o['OgrenciId']).toSet().length} öğrenci'
              '${form['HedefTuru'] == 'OgrenciSec' ? ' (seçilenler)' : ''}',
          'Bilgiler: ${bilgiler.take(3).join(', ')}'
              '${bilgiler.length > 3 ? ' (+${bilgiler.length - 3})' : ''}',
          '${tarihMetni}Form #$id',
          '${bilgiFormSablonlari[m['sablon']] ?? 'Bilgi formu'} • ${m['aliciGrubu']}',
          m['yanitlayan'] == null
              ? '${m['yanitSayisi']} yanıt • Kişi eşleştirmesi belirsiz'
              : '${m['yanitlayan']} / ${m['beklenen']} öğrenci için yanıt eşleşti',
          'Yanıt alımı: ${m['yayinAcik'] == true
              ? 'Açık'
              : m['yayinAcik'] == false
              ? 'Kapalı'
              : 'Henüz doğrulanmadı'}',
          if (m['sonYanit'] != null)
            'Son yanıt: ${DateTime.parse(m['sonYanit'] as String).toLocal()}',
        ];
      }
      if (mounted) {
        setState(() {
          _b = b;
          _formlar = f;
          _gorusFormlari = gorusler;
          _formOzetleri = ozetler;
          _yonetim = yonetim;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Formlar yüklenemedi. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _formOzetKutusu(
    IconData icon, String label, int value, Color background,
  ) => Expanded(child: Container(
    constraints: const BoxConstraints(minHeight: 104),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(OrtakUi.radius),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 5),
      Text('$value', maxLines: 1,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown, child: Text(label,
        maxLines: 1, style: Theme.of(context).textTheme.labelMedium)),
    ]),
  ));

  Future<void> _ac(int id, {bool hazirla = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BireyselBilgiFormDetayScreen(
          service: _service,
          baglam: _b!,
          formId: id,
          hazirlayarakAc: hazirla,
          google: widget.google,
          hesapBagla: widget.hesapBagla,
        ),
      ),
    );
    if (mounted) await _yukle();
  }

  void _formSec(int id) => setState(() {
    _secimModu = true;
    if (!_secilenFormlar.add(id)) _secilenFormlar.remove(id);
  });

  void _secimiKapat() => setState(() {
    _secimModu = false;
    _secilenFormlar.clear();
  });

  Future<void> _seciliFormlariArsivle() async {
    final b = _b;
    final ids = _secilenFormlar.toList();
    if (b == null || _busy || ids.isEmpty) return;
    if (!await _onay(context, 'Seçili formları arşivle',
        '${ids.length} formun Google yanıt alımı otomatik kapatılacak ve '
        'kapatma doğrulanınca arşivlenecek. Mevcut yanıtlar korunacak. Devam edilsin mi?')) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final hatalar = <String>[];
    var basarili = 0;
    final google = widget.google ?? BilgiToplamaGoogleService();
    String? token;
    try {
      for (final id in ids) {
        try {
          final form = await _service.formGetir(b, id);
          final googleId = form['GoogleFormId'];
          if (googleId != null) {
            token ??= widget.hesapBagla != null
                ? await widget.hesapBagla!()
                : await OrtakGoogleOturumService.token();
            // Uzak durum doğrulanmadan yerel arşiv işareti yazılmaz.
            await google.yanitAliminiAyarla(_service, b, id, token!, false);
          } else {
            // Henüz Google'da oluşturulmamış taslak için yanıt alımı yok.
            // Mevcut yerel arşiv güvenlik koşulu korunur.
          }
          await _service.isaretle(b, id, 'Arşivle');
          _secilenFormlar.remove(id);
          basarili++;
        } catch (e) {
          hatalar.add('Form #$id: $e');
        }
      }
    } finally {
      if (widget.google == null) google.dispose();
      if (mounted) {
        await _yukle();
        if (mounted) setState(() => _secimModu = _secilenFormlar.isNotEmpty);
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Arşivleme sonucu'),
        content: SingleChildScrollView(child: Text(
          '$basarili form arşive gönderildi. '
          '${hatalar.length} form arşivlenemedi.'
          '${hatalar.isEmpty ? '' : '\n\n${hatalar.join('\n')}'}',
        )),
        actions: [TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Tamam'),
        )],
      ),
    );
  }



  Future<String> _duzenlemeToken() async {
    if (widget.hesapBagla != null) return widget.hesapBagla!();
    return OrtakGoogleOturumService.token();
  }

  Future<void> _formDuzenle() async {
    if (_busy || _secilenFormlar.length != 1 || _b == null) return;
    final id = _secilenFormlar.single, b = _b!;
    final google = widget.google ?? BilgiToplamaGoogleService();
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      var bilgi = await _service.formDuzenlemeBilgileri(b, id);
      String token = '';
      if ((bilgi['form'] as Map)['GoogleFormId'] != null) {
        token = await _duzenlemeToken();
      }
      if (await _service.bekleyenFormDuzenlemesi(b, id) != null) {
        await google.formDuzenlemeyiSurdur(_service, b, id, token);
        bilgi = await _service.formDuzenlemeBilgileri(b, id);
      }
      final sadeceAd = await google.formdaYanitVar(_service, b, id, token);
      if (!mounted) return;
      setState(() => _busy = false);
      final form = Map<String, Object?>.from(bilgi['form'] as Map);
      await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (_) => _YeniForm(
            service: _service,
            b: b,
            mevcutForm: form,
            mevcutSorular: (bilgi['sorular'] as List)
                .map((s) => Map<String, Object?>.from(s as Map))
                .toList(),
            mevcutHedefler: (bilgi['hedefler'] as List)
                .map((s) => Map<String, Object?>.from(s as Map))
                .toList(),
            yalnizAd: sadeceAd,
            duzenlemeyiKaydet: (ad, hedef, sorular, secim) async {
              await google.formDuzenle(
                _service,
                b,
                id,
                token,
                beklenenForm: form,
                baslik: ad,
                sorular: sadeceAd ? null : sorular,
                hedefTuru: sadeceAd ? null : hedef,
                ogrenciIdleri: !sadeceAd && hedef == 'OgrenciSec' ? secim : {},
                sinifIdleri: !sadeceAd && hedef == 'SinifSec' ? secim : {},
              );
            },
          ),
        ),
      );
      if (!mounted) return;
      _secilenFormlar.clear();
      _secimModu = false;
      await _yukle();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Düzenleme açılamadı. Orijinal hata: $e');
      }
    } finally {
      if (widget.google == null) google.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _formlariSil() async {
    final ids = _secilenFormlar.toList();
    if (_busy || ids.isEmpty || _b == null) return;
    if (!await _onay(
      context,
      'Seçilen formları sil',
      '${ids.length} form uygulama listesinden kaldırılacak. '
          'Google formları yanıtlara kapatılacak ve henüz alınmamış olanlar dahil tüm yanıtları kalıcı olarak silinecek. '
          'Öğrenciye kaydedilmiş bilgiler korunur. Google’daki boş form şablonu ve varsa bağlı E-Tablolar kopyası kalır. '
          'Kaydedilmemiş yanıtlar kaybolur. Devam edilsin mi?',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    final google = widget.google ?? BilgiToplamaGoogleService();
    final hatalar = <String>[];
    var silinen = 0;
    String? token;
    try {
      for (final id in ids) {
        if (!mounted) break;
        setState(
          () => _silmeDurumu =
              'Form siliniyor: ${silinen + hatalar.length + 1} / ${ids.length}',
        );
        try {
          final form = await _service.formGetir(_b!, id);
          if (form['GoogleFormId'] == null) {
            await _service.formuSil(
              _b!,
              id,
              googleTemizle: (_) async {
                throw StateError('Google bağlantısı değişti; yeniden deneyin.');
              },
            );
          } else {
            if (token == null) {
              if (widget.hesapBagla != null) {
                token = await widget.hesapBagla!();
              } else {
                token = await OrtakGoogleOturumService.token(
                  ekIzin: BilgiToplamaGoogleService.silmeScope);
              }
            }
            await google.formuSil(_service, _b!, id, token);
          }
          silinen++;
          _secilenFormlar.remove(id);
        } catch (e) {
          hatalar.add('Form #$id: $e');
        }
      }
    } finally {
      if (widget.google == null) google.dispose();
      if (mounted) {
        await _yukle();
        if (mounted) {
          setState(() {
            _silmeDurumu = null;
            _secimModu = _secilenFormlar.isNotEmpty;
            _hata = hatalar.isEmpty ? null : hatalar.join('\n');
          });
        }
      }
    }
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Form silme sonucu'),
          content: SingleChildScrollView(
            child: Text(
              '$silinen form silindi. '
              '${hatalar.length} form silinemedi.${hatalar.isEmpty ? '' : '\n\n${hatalar.join('\n')}'}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _gorusAc(Map<String, Object?> form) async {
    final kaynak = _service.gorusKaynakService;
    final baglam = await kaynak.hazirla();
    if (baglam.okulId != _b!.okulId ||
        baglam.ogretmenProfilId != _b!.profilId ||
        baglam.egitimOgretimYili != _b!.yil) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Okul veya öğretmen değişti. Formları yenileyin.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BilgiToplamaOgretmenGorusScreen(
          service: kaynak,
          formService: _service,
          baglam: baglam,
          atamaId: form['AtamaId'] as int,
          toplantiId: form['ToplantiId'] as int,
          saltOkunur: form['SaltOkunur'] == true,
        ),
      ),
    );
    if (mounted) await _yukle();
  }

  Future<void> _tanimaAc(Map<String, Object?> form) async {
    final kaynak = _service.gorusKaynakService;
    final b = await kaynak.hazirla();
    if (b.okulId != _b!.okulId ||
        b.ogretmenProfilId != _b!.profilId ||
        b.egitimOgretimYili != _b!.yil) {
      throw StateError('Form kapsamı değişti. Yenileyin.');
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RehberlikBilgiFormScreen(
          service: kaynak,
          formService: _service,
          baglam: b,
          atamaId: form['AtamaId'] as int,
          sinifId: form['SinifSubeId'] as int,
          hesapBagla: widget.hesapBagla,
        ),
      ),
    );
    if (mounted) await _yukle();
  }

  Future<void> _tanimaSec() async {
    try {
      final siniflar = await _service.ogrenciTanimaFormlari(
        _b!,
        yalnizKayitli: false,
      );
      if (!mounted) return;
      if (siniflar.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Önce Sınıf Rehberliğim bölümünde sınıf ataması oluşturun.',
            ),
          ),
        );
        return;
      }
      final secilen = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Tanıma formunun sınıfını seç'),
          children: [
            for (final a in siniflar)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, a),
                child: Text('${a['SinifKodu']} • Öğrenci tanıma formu'),
              ),
          ],
        ),
      );
      if (secilen != null && mounted) await _tanimaAc(secilen);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formIslemHatasi(e))));
      }
    }
  }

  Future<void> _sablonSec() async {
    final tur = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Form şablonu'),
        children: [
          for (final e in bilgiFormSablonlari.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, e.key),
              child: Text(e.value),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'tanima'),
            child: const Text('Öğrenci tanıma formu'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'gorus'),
            child: const Text('Fotoğraflı öğretmen görüşü'),
          ),
        ],
      ),
    );
    if (!mounted || tur == null) return;
    if (tur == 'tanima') {
      await _tanimaSec();
      return;
    }
    if (tur != 'gorus') {
      await _yeni(tur);
      return;
    }
    try {
      final toplantilar = await _service.ogretmenGorusFormlari(
        _b!,
        yalnizKayitli: false,
      );
      if (!mounted) return;
      if (toplantilar.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Önce Sınıf Rehberliğim bölümünde bir toplantı oluşturun. Kilitli toplantıları kendi ekranından açın.',
            ),
          ),
        );
        return;
      }
      final secilen = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Toplantıyı seç'),
          children: [
            for (final t in toplantilar)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, t),
                child: Text('${t['SinifKodu']} • ${t['Baslik']}'),
              ),
          ],
        ),
      );
      if (mounted && secilen != null) await _gorusAc(secilen);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Form açılamadı. $e')));
      }
    }
  }

  Future<void> _yeni([String sablon = 'Bilgi']) async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => _YeniForm(service: _service, b: _b!, sablon: sablon),
      ),
    );
    if (!mounted) return;
    await _yukle();
    if (id != null && mounted) await _ac(id, hazirla: true);
  }

  @override
  Widget build(BuildContext context) {
    final normal = _formlar
        .where(
          (f) => _durumFiltresi == 'Tümü'
              ? true
              : (_yonetim[f['Id']]?['durum'] == _durumFiltresi),
        )
        .toList();
    final gorusler = _gorusFormlari
        .where(
          (f) => _durumFiltresi == 'Tümü' ? true : f['Durum'] == _durumFiltresi,
        )
        .toList();
    final durumlar = <String, int>{};
    for (final f in _formlar) {
      final durum = (_yonetim[f['Id']]?['durum'] ?? 'Taslak').toString();
      durumlar.update(durum, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final g in _gorusFormlari) {
      final durum = (g['Durum'] ?? 'Taslak').toString();
      durumlar.update(durum, (n) => n + 1, ifAbsent: () => 1);
    }
    final toplam = _formlar.length + _gorusFormlari.length;
    final bekleyen = durumlar['Yanıt bekleniyor'] ?? 0;
    final tamamlanan = durumlar['Tamamlandı'] ?? 0;
    return OrtakSayfa(
      appBar: widget.sekmeIcinde ? null : ModulUstBar(
        title: Text(
          _secimModu
              ? '${_secilenFormlar.length} form seçili'
              : 'Formlarla Bilgi Toplama',
        ),
        actions: [
          if (_secimModu) ...[
            IconButton(
              tooltip: 'Formu düzenle',
              onPressed: _busy || _secilenFormlar.length != 1
                  ? null
                  : _formDuzenle,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Tümünü seç',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      if (_secilenFormlar.length == normal.length) {
                        _secilenFormlar.clear();
                      } else {
                        _secilenFormlar.addAll(
                          normal.map((f) => f['Id'] as int),
                        );
                      }
                    }),
              icon: const Icon(Icons.select_all),
            ),
            IconButton(
              tooltip: 'Seçimi kapat',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _secimModu = false;
                      _secilenFormlar.clear();
                    }),
              icon: const Icon(Icons.close),
            ),
          ],
          IconButton(
            tooltip: 'Formları sil',
            onPressed: _busy || _formlar.isEmpty
                ? null
                : () {
                    if (!_secimModu || _secilenFormlar.isEmpty) {
                      setState(() => _secimModu = true);
                    } else {
                      _formlariSil();
                    }
                  },
            icon: const Icon(Icons.delete_outline),
          ),
          if (!_secimModu)
            IconButton(
              onPressed: _busy ? null : _yukle,
              icon: const Icon(Icons.refresh),
              tooltip: 'Yenile',
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
          child: _secimModu
              ? Row(children: [
                  Expanded(flex: 3, child: FilledButton.icon(
                    onPressed: _busy || _secilenFormlar.isEmpty
                        ? null : _seciliFormlariArsivle,
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Arşive Gönder',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  )),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: OutlinedButton.icon(
                    onPressed: _busy || _secilenFormlar.isEmpty
                        ? null : _formlariSil,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Sil'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  )),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: OutlinedButton(
                    onPressed: _busy ? null : _secimiKapat,
                    child: const Text('Vazgeç'),
                  )),
                ])
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 164, maxWidth: 240),
                    child: FilledButton.icon(
                      onPressed: _b == null || _busy ? null : _sablonSec,
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Form'),
                    ),
                  ),
                ),
        ),
      ),
      body: Column(
        children: [
          if (_secimModu) Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const SizedBox(width: 12),
                Icon(Icons.check_box,
                  color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('${_secilenFormlar.length} form seçildi',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
                TextButton.icon(
                  onPressed: _busy ? null : _secimiKapat,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Seçimi temizle'),
                ),
              ]),
            ),
          ),
          if (!_secimModu) Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [
              _formOzetKutusu(Icons.description_outlined,
                'Toplam form', toplam, Theme.of(context).colorScheme.primaryContainer),
              const SizedBox(width: 6),
              _formOzetKutusu(Icons.hourglass_bottom_outlined,
                'Bekleyen', bekleyen, const Color(0xFFFFEBD0)),
              const SizedBox(width: 6),
              _formOzetKutusu(Icons.task_alt_outlined,
                'Tamamlanan', tamamlanan, const Color(0xFFDEF5E7)),
            ]),
          ),
          if (!_secimModu)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  for (final d in [
                    'Tümü',
                    'Taslak',
                    'Yanıt bekleniyor',
                    'Tamamlandı',
                    'Arşiv',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(d),
                        selected: _durumFiltresi == d,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _durumFiltresi = d),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _busy
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        if (_silmeDurumu != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_silmeDurumu!),
                          ),
                      ],
                    ),
                  )
                : _hata != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_hata!),
                          TextButton(
                            onPressed: _yukle,
                            child: const Text('Yeniden dene'),
                          ),
                        ],
                      ),
                    ),
                  )
                : normal.isEmpty && gorusler.isEmpty
                ? const Center(
                    child: Text(
                      'Bu görünümde form yok. Yeni form ile başlayın.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount:
                        normal.length + (_secimModu ? 0 : gorusler.length),
                    itemBuilder: (c, i) {
                      if (i >= normal.length) {
                        final g = gorusler[i - normal.length];
                        return Card(
                          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          elevation: 1,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Icon(Icons.forum_outlined,
                                color: Theme.of(context).colorScheme.primary),
                            ),
                            title: Text('${g['SinifKodu']} • ${g['Baslik']}'),
                            subtitle: Text(
                              'Öğretmen görüşü • ${g['Durum']}\n${g['YanitSayisi'] ?? 'Henüz alınmadı'} yanıt • Kişi eşleştirmesi belirsiz\nYanıt alımı: ${g['YayinAcik'] == true
                                  ? 'Açık'
                                  : g['YayinAcik'] == false
                                  ? 'Kapalı'
                                  : 'Henüz doğrulanmadı'}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              try {
                                await _gorusAc(g);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text('Form açılamadı. $e'),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        );
                      }
                      final f = normal[i];
                      final secili = _secilenFormlar.contains(f['Id']);
                      return Card(
                        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        elevation: 1,
                        color: secili ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: secili ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          leading: _secimModu
                              ? Checkbox(
                                  value: _secilenFormlar.contains(f['Id']),
                                  onChanged: (_) => _formSec(f['Id'] as int),
                                )
                              : CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  child: Icon(Icons.assignment_outlined,
                                    color: Theme.of(context).colorScheme.primary),
                                ),
                          title: Text(f['Baslik'] as String,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${f['EgitimOgretimYili']} • ${_yonetim[f['Id']]?['durum']}',
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Builder(builder: (context) {
                                final m = _yonetim[f['Id']];
                                final yanit = (m?['yanitlayan'] as num?)?.toInt();
                                final hedef = (m?['beklenen'] as num?)?.toInt();
                                if (yanit == null || hedef == null || hedef <= 0) {
                                  return Text('${m?['yanitSayisi'] ?? 0} yanıt • Eşleşme doğrulanmadı');
                                }
                                final oran = (yanit / hedef).clamp(0.0, 1.0);
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$yanit / $hedef yanıt eşleşti • %${(oran * 100).round()}',
                                      style: Theme.of(context).textTheme.bodySmall),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(value: oran, minHeight: 7),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onLongPress: () => _formSec(f['Id'] as int),
                          onTap: () => _secimModu
                              ? _formSec(f['Id'] as int)
                              : _ac(f['Id'] as int),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Rehberlik kartı doğrudan ortak üç adımlı bilgi formunu açar.
class RehberlikBilgiFormScreen extends StatefulWidget {
  const RehberlikBilgiFormScreen({
    super.key,
    required this.service,
    required this.baglam,
    required this.atamaId,
    required this.sinifId,
    this.formService,
    this.hesapBagla,
    this.google,
  });
  final BireyselRehberlikService service;
  final BireyselRehberlikBaglami baglam;
  final int atamaId, sinifId;
  final BireyselBilgiToplamaService? formService;
  final Future<String> Function()? hesapBagla;
  final BilgiToplamaGoogleService? google;
  @override
  State<RehberlikBilgiFormScreen> createState() => _RehberlikBilgiFormState();
}

class _RehberlikBilgiFormState extends State<RehberlikBilgiFormScreen> {
  late final _service =
      widget.formService ?? BireyselBilgiToplamaService.instance;
  late final _oturum = _hazirla();
  Future<BilgiToplamaOturumu> _hazirla() async {
    await _kontrol();
    final b = await _service.hazirla();
    if (b.okulId != widget.baglam.okulId ||
        b.profilId != widget.baglam.ogretmenProfilId ||
        b.yil != widget.baglam.egitimOgretimYili) {
      throw StateError('Rehberlik ve form kapsamı değişti.');
    }
    return b;
  }

  Future<void> _kontrol() async {
    await widget.service.googleYazmaYetkisiniKontrol(
      widget.baglam,
      widget.atamaId,
    );
    final b = await _service.hazirla();
    final atamalar = await _service.ogrenciTanimaFormlari(
      b,
      yalnizKayitli: false,
    );
    if (!atamalar.any(
      (a) =>
          a['AtamaId'] == widget.atamaId &&
          a['SinifSubeId'] == widget.sinifId &&
          a['SaltOkunur'] != true,
    )) {
      throw StateError('Rehberlik sınıfı değişti veya salt okunur.');
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BilgiToplamaOturumu>(
    future: _oturum,
    builder: (c, snapshot) {
      if (snapshot.hasData) {
        return _YeniForm(
          service: _service,
          b: snapshot.data!,
          baslangicSinifId: widget.sinifId,
          baslangicFormAdi: 'Öğrenci Bilgi Formu',
          kaynakKontrol: _kontrol,
          tamamlandi: (id) async {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => BireyselBilgiFormDetayScreen(
                  service: _service,
                  baglam: snapshot.data!,
                  formId: id,
                  hazirlayarakAc: true,
                  google: widget.google,
                  hesapBagla: widget.hesapBagla,
                ),
              ),
            );
          },
        );
      }
      return OrtakSayfa(
        appBar: const ModulUstBar(title: Text('Yeni bilgi formu')),
        body: Center(
          child: snapshot.hasError
              ? Text(formIslemHatasi(snapshot.error!))
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

class _YeniForm extends StatefulWidget {
  const _YeniForm({
    required this.service,
    required this.b,
    this.mevcutForm,
    this.mevcutSorular = const [],
    this.mevcutHedefler = const [],
    this.yalnizAd = false,
    this.sablon = 'Bilgi',
    this.duzenlemeyiKaydet,
    this.baslangicSinifId,
    this.baslangicFormAdi,
    this.kaynakKontrol,
    this.tamamlandi,
  });
  final BireyselBilgiToplamaService service;
  final BilgiToplamaOturumu b;
  final Map<String, Object?>? mevcutForm;
  final List<Map<String, Object?>> mevcutSorular, mevcutHedefler;
  final bool yalnizAd;
  final String sablon;
  final int? baslangicSinifId;
  final String? baslangicFormAdi;
  final Future<void> Function()? kaynakKontrol;
  final Future<void> Function(int id)? tamamlandi;
  final Future<void> Function(
    String ad,
    String hedef,
    List<BilgiToplamaSorusu> sorular,
    Set<int> secim,
  )?
  duzenlemeyiKaydet;
  @override
  State<_YeniForm> createState() => _YeniFormState();
}

class _YeniFormState extends State<_YeniForm> {
  final _ad = TextEditingController();
  List<MesajKisi> _aliciAdaylari = [];
  final _alicilar = <String, MesajKisi>{};
  List<Map<String, Object?>> _adaylar = [];
  final _hazir = _alanlar.keys.toSet();
  final _sablon = <String>{};
  final _ek = <BilgiToplamaSorusu>[];
  bool get _ogrenciListeli => widget.mevcutForm == null
      ? widget.sablon == 'Bilgi'
      : widget.mevcutSorular.any((q) => q['AlanAnahtari'] == 'ogrenciSecimi');
  bool _veliSorusu = true;
  Set<int> _secim = {};
  String _hedef = 'OgrenciSec';
  int _adim = 0, _sira = 0;
  bool _busy = true;
  String? _hata;
  final _taslakIstegi = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final _soruSirasi = <String>[];
  final _zorunlu = <String, bool>{};
  @override
  void initState() {
    super.initState();
    if (widget.baslangicFormAdi != null) _ad.text = widget.baslangicFormAdi!;
    if (widget.mevcutForm == null && widget.sablon != 'Bilgi') {
      _hazir.clear();
      _veliSorusu = false;
      _ad.text = bilgiFormSablonlari[widget.sablon] ?? '';
      if (widget.sablon == 'Katilim') {
        _ek.add(
          BilgiToplamaSorusu(
            anahtar: 'ek1',
            baslik: 'Toplantıya katılacak mısınız?',
            veriTuru: 'Secenek',
            zorunlu: true,
            secenekler: ['Katılacağım', 'Katılamayacağım', 'Henüz belli değil'],
          ),
        );
        _ek.add(BilgiToplamaSorusu(anahtar: 'ek2', baslik: 'Notunuz'));
        _sira = 2;
      } else if (widget.sablon == 'Anket') {
        _ek.add(
          BilgiToplamaSorusu(
            anahtar: 'ek1',
            baslik: 'Genel değerlendirmeniz',
            veriTuru: 'Secenek',
            zorunlu: true,
            secenekler: ['Çok iyi', 'İyi', 'Orta', 'Geliştirilmeli'],
          ),
        );
        _ek.add(
          BilgiToplamaSorusu(anahtar: 'ek2', baslik: 'Görüş ve önerileriniz'),
        );
        _sira = 2;
      }
    }
    _yukle();
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      await widget.kaynakKontrol?.call();
      final rows = await widget.service.hedefAdaylari(widget.b);
      final ms = MesajlasmaService.instance;
      final mb = await ms.hazirla();
      if (mb.okulId != widget.b.okulId ||
          mb.ogretmenId != widget.b.profilId ||
          mb.yil != widget.b.yil) {
        throw StateError('Alıcı kapsamı değişti.');
      }
      final adaylar = await ms.aliciAdaylari(mb);
      final eskiAlicilar = widget.mevcutForm == null
          ? <String>{}
          : await widget.service.formAliciBaglari(
              widget.b,
              widget.mevcutForm!['Id'] as int,
            );
      if (mounted) {
        setState(() {
          _adaylar = rows;
          _aliciAdaylari = adaylar;
          _alicilar.addEntries(
            adaylar
                .where((k) => eskiAlicilar.contains(k.bagAnahtari))
                .map((k) => MapEntry(k.secimAnahtari, k)),
          );
          if (widget.mevcutForm == null && widget.baslangicSinifId != null) {
            final sinif = widget.baslangicSinifId!;
            final ids = rows
                .where((o) => o['SinifSubeId'] == sinif)
                .map((o) => o['OgrenciId'] as int)
                .toSet();
            if (ids.isEmpty) {
              throw StateError(
                'Rehberlik sınıfınızda ders kapsamınızda aktif öğrenci bulunamadı.',
              );
            }
            _secim = ids;
            _alicilar.addEntries(
              adaylar
                  .where(
                    (k) =>
                        k.sinifId == sinif &&
                        k.tur == MesajKisiTuru.veli &&
                        ids.contains(int.tryParse(k.kisiId)),
                  )
                  .map((k) => MapEntry(k.secimAnahtari, k)),
            );
          }
          if (widget.mevcutForm != null) {
            _soruSirasi.addAll(
              widget.mevcutSorular
                  .where(
                    (q) => !BireyselBilgiToplamaService.kimlikAlani(
                      q['AlanAnahtari'],
                    ),
                  )
                  .map((q) => q['AlanAnahtari'] as String),
            );
            for (final q in widget.mevcutSorular) {
              _zorunlu[q['AlanAnahtari'] as String] = q['Zorunlu'] == 1;
            }
            _ad.text = widget.mevcutForm!['Baslik'] as String;
            _hedef = widget.mevcutForm!['HedefTuru'] as String;
            final ids = widget.mevcutHedefler
                .map((h) => h['OgrenciId'])
                .toSet();
            _secim = _hedef == 'SinifSec'
                ? rows
                      .where((o) => ids.contains(o['OgrenciId']))
                      .map((o) => o['SinifSubeId'] as int)
                      .toSet()
                : ids.cast<int>();
            if (eskiAlicilar.isEmpty) {
              _alicilar.addEntries(
                adaylar
                    .where(
                      (k) =>
                          k.tur == MesajKisiTuru.ogrenci &&
                          ids.contains(int.tryParse(k.kisiId)),
                    )
                    .map((k) => MapEntry(k.secimAnahtari, k)),
              );
            }
            _hazir.clear();
            _veliSorusu = widget.mevcutSorular.any(
              (q) => q['AlanAnahtari'] == 'veliSecimi',
            );
            for (final q in widget.mevcutSorular) {
              final key = q['AlanAnahtari'] as String;
              if (BireyselBilgiToplamaService.veliSorulari.any(
                (s) => s.anahtar == key,
              )) {
                continue;
              }
              if (BireyselBilgiToplamaService.kimlikAlani(key)) {
                continue;
              }
              final hedef = q['HedefAlan'] as String?;
              if (hedef != null && _alanlar.containsKey(hedef)) {
                _hazir.add(hedef);
                continue;
              }
              final katalog = key.startsWith('sablon') ? key.substring(6) : '';
              if (_soruGruplari.values.any((g) => g[katalog] == q['Baslik'])) {
                _sablon.add(katalog);
                continue;
              }
              _ek.add(
                BilgiToplamaSorusu(
                  anahtar: key,
                  baslik: q['Baslik'] as String,
                  veriTuru: q['VeriTuru'] as String,
                  zorunlu: q['Zorunlu'] == 1,
                  secenekler: (jsonDecode(q['Secenekler'] as String) as List)
                      .cast<String>(),
                ),
              );
              final sira =
                  int.tryParse(key.startsWith('ek') ? key.substring(2) : '') ??
                  0;
              if (sira > _sira) _sira = sira;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Öğrenciler yüklenemedi. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int get _hedefOgrenciSayisi => _adaylar
      .where(
        (o) =>
            _hedef == 'Siniflarim' ||
            (_hedef == 'SinifSec'
                ? _secim.contains(o['SinifSubeId'])
                : _secim.contains(o['OgrenciId'])),
      )
      .map((o) => o['OgrenciId'])
      .toSet()
      .length;

  Widget _ortakHedefSecimi() {
    final kisiler = _aliciAdaylari;
    final secili = _alicilar;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '1 / 3 • Hedefi seç',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_hata != null)
                  Text(
                    _hata!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ad,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Form adı',
                    hintText: 'Başlığı girin',
                  ),
                ),
                Text('$_hedefOgrenciSayisi öğrenci seçili.'),
              ],
            ),
          ),
        ),
        MesajAliciSecimSliver(
          baslangicSinifId: widget.baslangicSinifId,
          baslangicAliciTuru: widget.baslangicSinifId == null
              ? null
              : MesajKisiTuru.veli,
          ogrenciKapsami: false,
          iletisimDuzenleme: false,
          adaylar: kisiler,
          siniflar: {
            for (final o in _adaylar)
              o['SinifSubeId'] as int: '${o['SinifKodu']}',
          },
          secilenler: secili,
          kilitli: _busy,
          degistir: (ks) => setState(() {
            _hedef = 'OgrenciSec';
            _alicilar
              ..clear()
              ..addEntries(ks.map((k) => MapEntry(k.secimAnahtari, k)));
            final siniflar = ks
                .where((k) => k.tur == MesajKisiTuru.ogretmen)
                .map((k) => k.sinifId)
                .toSet();
            _secim = {
              for (final k in ks.where((k) => k.tur != MesajKisiTuru.ogretmen))
                int.parse(k.kisiId),
              for (final o in _adaylar.where(
                (o) => siniflar.contains(o['SinifSubeId']),
              ))
                o['OgrenciId'] as int,
            };
            _hata = null;
          }),
          veliDuzenle: (_) async {},
          ogretmenDuzenle: (_, _) async {},
          kisiDuzenle: (_) async {},
        ),
      ],
    );
  }

  Future<void> _soru([int? index]) async {
    final eski = index == null ? null : _ek[index];
    final baslik = TextEditingController(text: eski?.baslik ?? '');
    final secenek = TextEditingController(
      text: eski?.secenekler.join('\n') ?? '',
    );
    var tur = eski?.veriTuru ?? 'Metin', zorunlu = eski?.zorunlu ?? false;
    String? hata;
    final s = await showDialog<BilgiToplamaSorusu>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: Text(eski == null ? 'Serbest soru ekle' : 'Soruyu düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: baslik,
                  decoration: const InputDecoration(labelText: 'Soru başlığı'),
                  maxLength: 300,
                ),
                DropdownButtonFormField<String>(
                  initialValue: tur,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cevap türü'),
                  items: [
                    for (final e in _turler.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => ss(() => tur = v!),
                ),
                if (tur == 'Secenek')
                  TextField(
                    controller: secenek,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Her satıra bir seçenek',
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Zorunlu'),
                  value: zorunlu,
                  onChanged: (v) => ss(() => zorunlu = v!),
                ),
                if (hata != null)
                  Text(
                    hata!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final opts = tur == 'Secenek'
                    ? secenek.text
                          .split('\n')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList()
                    : <String>[];
                if (baslik.text.trim().isEmpty ||
                    (tur == 'Secenek' &&
                        (opts.isEmpty || opts.toSet().length != opts.length))) {
                  ss(() => hata = 'Başlığı ve seçenekleri kontrol edin.');
                  return;
                }
                Navigator.pop(
                  c,
                  BilgiToplamaSorusu(
                    anahtar: eski?.anahtar ?? 'ek${++_sira}',
                    baslik: baslik.text.trim(),
                    veriTuru: tur,
                    zorunlu: zorunlu,
                    secenekler: opts,
                  ),
                );
              },
              child: const Text('Soruyu kaydet'),
            ),
          ],
        ),
      ),
    );
    // Dialog kapanış animasyonunda controller hâlâ kullanılabilir.
    if (s != null && mounted) {
      setState(() {
        if (index == null) {
          _ek.add(s);
        } else {
          _ek[index] = s;
        }
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    baslik.dispose();
    secenek.dispose();
  }

  List<BilgiToplamaSorusu> _duzenSorular() {
    final sorular = [
      if (_veliSorusu) ...BireyselBilgiToplamaService.veliSorulari,
      for (final a in _hazir)
        BilgiToplamaSorusu(
          anahtar: 'hazir$a',
          baslik: _alanlar[a]!,
          hedefAlan: a,
          veriTuru: a.contains('Telefon') ? 'Telefon' : 'Metin',
        ),
      for (final grup in _soruGruplari.values)
        for (final soru in grup.entries)
          if (_sablon.contains(soru.key)) _sablonSorusu(soru.key, soru.value),
      ..._ek,
    ];
    for (final q in sorular) {
      if (!_soruSirasi.contains(q.anahtar)) _soruSirasi.add(q.anahtar);
    }
    sorular.sort(
      (a, b) => _soruSirasi
          .indexOf(a.anahtar)
          .compareTo(_soruSirasi.indexOf(b.anahtar)),
    );
    return sorular
        .map(
          (q) => BilgiToplamaSorusu(
            anahtar: q.anahtar,
            baslik: q.baslik,
            veriTuru: q.veriTuru,
            hedefAlan: q.hedefAlan,
            secenekler: q.secenekler,
            zorunlu:
                BireyselBilgiToplamaService.veliSorulari.any(
                  (v) => v.anahtar == q.anahtar,
                )
                ? q.zorunlu
                : (_zorunlu[q.anahtar] ?? q.zorunlu),
          ),
        )
        .toList();
  }

  Widget _soruSirasiDuzenle() {
    final qs = _duzenSorular();
    return Column(
      children: [
        const ListTile(
          title: Text('Soru sırası ve zorunluluk'),
          subtitle: Text('Kimlik alanları sabittir.'),
        ),
        for (var i = 0; i < qs.length; i++)
          Card(
            child: Column(
              children: [
                CheckboxListTile(
                  title: Text(qs[i].baslik),
                  subtitle: const Text('Zorunlu'),
                  value: qs[i].zorunlu,
                  onChanged:
                      BireyselBilgiToplamaService.veliSorulari.any(
                        (v) => v.anahtar == qs[i].anahtar,
                      )
                      ? null
                      : (v) => setState(
                          () => _zorunlu[qs[i].anahtar] = v ?? false,
                        ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Yukarı taşı',
                      onPressed: i == 0
                          ? null
                          : () => setState(() {
                              _soruSirasi.clear();
                              _soruSirasi.addAll(qs.map((q) => q.anahtar));
                              final x = _soruSirasi.removeAt(i);
                              _soruSirasi.insert(i - 1, x);
                            }),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Aşağı taşı',
                      onPressed: i == qs.length - 1
                          ? null
                          : () => setState(() {
                              _soruSirasi.clear();
                              _soruSirasi.addAll(qs.map((q) => q.anahtar));
                              final x = _soruSirasi.removeAt(i);
                              _soruSirasi.insert(i + 1, x);
                            }),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _devam() async {
    if (_busy) return;
    if (_adim == 0 &&
        (_ad.text.trim().isEmpty ||
            (!widget.yalnizAd && _hedefOgrenciSayisi == 0))) {
      setState(() => _hata = 'Form adını ve hedef öğrencileri seçin.');
      return;
    }
    if (_adim == 1 &&
        _hazir.isEmpty &&
        _sablon.isEmpty &&
        _ek.isEmpty &&
        !_veliSorusu) {
      setState(
        () => _hata = 'En az bir bilgi alanı veya serbest soru ekleyin.',
      );
      return;
    }
    if (_adim < 2 && !widget.yalnizAd) {
      setState(() {
        _adim++;
        _hata = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      await widget.kaynakKontrol?.call();
      final sorular = _duzenSorular();
      int id;
      if (widget.duzenlemeyiKaydet != null) {
        await widget.duzenlemeyiKaydet!(_ad.text, _hedef, sorular, _secim);
        id = widget.mevcutForm!['Id'] as int;
      } else {
        id = await widget.service.formOlustur(
          widget.b,
          baslik: _ad.text,
          istekKimligi: _taslakIstegi,
          ogrenciListesi: _ogrenciListeli,
          hedefTuru: _hedef,
          ogrenciIdleri: _hedef == 'OgrenciSec' ? _secim : {},
          sinifIdleri: _hedef == 'SinifSec' ? _secim : {},
          sorular: sorular,
        );
      }
      if (widget.mevcutForm == null) {
        await widget.service.sablonKaydet(widget.b, id, widget.sablon);
      }
      if (!widget.yalnizAd && _alicilar.isNotEmpty) {
        await widget.service.formAlicilariniKaydet(
          widget.b,
          id,
          _alicilar.values.map((k) => k.bagAnahtari).toSet(),
        );
      }
      if (mounted) {
        if (widget.tamamlandi != null) {
          await widget.tamamlandi!(id);
        } else {
          Navigator.pop(context, id);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _hata =
              'Form kaydedilemedi. '
              '${widget.duzenlemeyiKaydet == null ? '' : 'Düzenleme yarım kaldıysa ekrandan çıkıp listeden Düzenle ile yeniden açın. '}'
              'Orijinal hata: $e',
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formIslemHatasi(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: OrtakSayfa(
      appBar: ModulUstBar(
        title: Text(
          widget.mevcutForm == null ? 'Yeni bilgi formu' : 'Formu düzenle',
        ),
      ),
      bottomNavigationBar: _FormAnaIslem(
        metin: widget.yalnizAd || _adim == 2
            ? widget.mevcutForm == null
                  ? 'Google Formu Hazırla'
                  : 'Değişiklikleri kaydet'
            : 'Devam',
        ipucu: _adim == 2 && widget.mevcutForm == null
            ? 'Bilgileri arka planda kaydeder ve Google Formu hazırlar.'
            : 'Formun sonraki adımına geçin.',
        busy: _busy,
        onPressed: _devam,
        geri: _adim > 0 ? () => setState(() => _adim--) : null,
        icon: _adim == 2
            ? widget.mevcutForm == null
                  ? Icons.cloud_upload_outlined
                  : Icons.save_outlined
            : Icons.arrow_forward,
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _adim == 0 && !widget.yalnizAd
          ? _ortakHedefSecimi()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.yalnizAd
                      ? 'Forma yanıt gelmiş. Yalnız form adını değiştirebilirsiniz.'
                      : '${_adim + 1} / 3 • ${['Hedefi seç', 'Soruları hazırla', 'Kontrol et'][_adim]}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (_hata != null)
                  Text(
                    _hata!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_adim == 0) ...[
                  TextField(
                    controller: _ad,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Form adı',
                      hintText: 'Başlığı girin',
                    ),
                  ),
                ],
                if (_adim == 1) ...[
                  Text(
                    'Formda olacak alanları seçin',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${(_ogrenciListeli ? 1 : 3) + _hazir.length + _sablon.length + _ek.length + (_veliSorusu ? 4 : 0)} soru • ${_ogrenciListeli ? 'Öğrenci seçimi zorunlu' : '3 kimlik alanı zorunlu'}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          _hazir
                            ..clear()
                            ..addAll(_alanlar.keys);
                          _sablon.clear();
                          _veliSorusu = true;
                        }),
                        child: const Text('Kısa form alanları'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _hazir.addAll(_alanlar.keys);
                          _veliSorusu = true;
                          _sablon.addAll(
                            _soruGruplari.values.expand((g) => g.keys),
                          );
                        }),
                        child: const Text('Tüm hazır alanları seç'),
                      ),
                    ],
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _ogrenciListeli
                            ? 'Öğrenci, sınıfı ve okul numarasıyla tek açılır listeden seçilir.'
                            : 'Okul numarası, ad soyad ve sınıf zorunludur. Ad soyad ve sınıf yalnız kontrol amacıyla alınır.',
                      ),
                    ),
                  ),
                  for (final a in _alanlar.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.value),
                      subtitle: const Text(
                        'Mevcut öğrenci bilgisine kaydedilir',
                      ),
                      value: _hazir.contains(a.key),
                      onChanged: (v) => setState(() {
                        if (v!) {
                          _hazir.add(a.key);
                        } else {
                          _hazir.remove(a.key);
                        }
                      }),
                    ),
                  CheckboxListTile(
                    key: const ValueKey('veli-sorulari'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Veliniz kim?'),
                    subtitle: const Text(
                      'Annem / Babam / Diğer. Diğer veli için ad, yakınlık ve telefon soruları da eklenir. Veli ilişkisi onayınızla kaydedilir.',
                    ),
                    value: _veliSorusu,
                    onChanged: (v) => setState(() => _veliSorusu = v ?? false),
                  ),
                  const Text(
                    'Ek alanlar',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Başlığa dokunup istediğiniz soruları işaretleyin. Seçilmeyen alanlar forma eklenmez.',
                  ),
                  for (final grup in _soruGruplari.entries)
                    OrtakGenisleyenBolum(
                      key: PageStorageKey('soruGrubu${grup.key}'),
                      title: Text(grup.key),
                      subtitle: Text(
                        '${grup.value.keys.where(_sablon.contains).length} / ${grup.value.length} seçili',
                      ),
                      children: [
                        for (final soru in grup.value.entries)
                          CheckboxListTile(
                            title: Text(soru.value),
                            value: _sablon.contains(soru.key),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _sablon.add(soru.key);
                              } else {
                                _sablon.remove(soru.key);
                              }
                            }),
                          ),
                      ],
                    ),
                  for (var i = 0; i < _ek.length; i++)
                    Card(
                      child: ListTile(
                        title: Text(_ek[i].baslik),
                        subtitle: Text(
                          'Serbest ek bilgi • ${_turler[_ek[i].veriTuru]}${_ek[i].zorunlu ? ' • Zorunlu' : ''}',
                        ),
                        onTap: () => _soru(i),
                        trailing: IconButton(
                          tooltip: 'Soruyu kaldır',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _ek.removeAt(i)),
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _soru(),
                    icon: const Icon(Icons.add),
                    label: const Text('Serbest soru ekle'),
                  ),
                  _soruSirasiDuzenle(),
                ],
                if (_adim == 2) ...[
                  Text(
                    _ad.text,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _hedef == 'Siniflarim'
                        ? 'Tüm sınıflarım'
                        : '${_secim.length} ${_hedef == 'SinifSec' ? 'sınıf' : 'öğrenci'} seçildi',
                  ),
                  Text('$_hedefOgrenciSayisi öğrenci seçili.'),
                  const SizedBox(height: 12),
                  Text(
                    _ogrenciListeli
                        ? 'Öğrenciyi seçin → Seçili öğrencilerden zorunlu açılır liste'
                        : 'Okul numarası → Öğrenciyi eşleştir\nAd soyad ve sınıf → Yalnız kontrol',
                  ),
                  for (final a in _hazir)
                    ListTile(
                      title: Text(_alanlar[a]!),
                      subtitle: const Text(
                        'Öğrencinin mevcut bilgisine bağlanır',
                      ),
                    ),
                  for (final s in [
                    if (_veliSorusu)
                      ...BireyselBilgiToplamaService.veliSorulari,
                    for (final grup in _soruGruplari.values)
                      for (final soru in grup.entries)
                        if (_sablon.contains(soru.key))
                          _sablonSorusu(soru.key, soru.value),
                    ..._ek,
                  ])
                    ListTile(
                      title: Text(s.baslik),
                      subtitle: Text(
                        BireyselBilgiToplamaService.veliSorulari.any(
                              (q) => q.anahtar == s.anahtar,
                            )
                            ? 'Veli ilişkisi onayınızla kaydedilir'
                            : 'Serbest ek bilgi olarak saklanır',
                      ),
                    ),
                  Text(
                    widget.mevcutForm == null
                        ? 'Google Form hazırlanırken bilgileriniz uygulamada korunur.'
                        : 'Değişiklikler mevcut forma kaydedilecek. Google form bağlantısı korunur.',
                  ),
                ],
              ],
            ),
    ),
  );
}

class _SecimScreen extends StatefulWidget {
  const _SecimScreen({
    required this.baslik,
    required this.liste,
    required this.secili,
    this.tek = false,
  });
  final String baslik;
  final Map<int, String> liste;
  final Set<int> secili;
  final bool tek;
  @override
  State<_SecimScreen> createState() => _SecimState();
}

class _SecimState extends State<_SecimScreen> {
  late final _ids = Set<int>.of(widget.secili);
  String _arama = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.liste.entries
        .where((e) => e.value.toLowerCase().contains(_arama.toLowerCase()))
        .toList();
    return OrtakSayfa(
      appBar: ModulUstBar(title: Text(widget.baslik)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Ara',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _arama = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (c, i) {
                final e = rows[i];
                return CheckboxListTile(
                  title: Text(e.value),
                  value: _ids.contains(e.key),
                  onChanged: (v) => setState(() {
                    if (widget.tek) _ids.clear();
                    if (v!) {
                      _ids.add(e.key);
                    } else {
                      _ids.remove(e.key);
                    }
                  }),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _ids),
                child: Text('Seçimi tamamla (${_ids.length})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BireyselBilgiFormDetayScreen extends StatefulWidget {
  const BireyselBilgiFormDetayScreen({
    super.key,
    required this.service,
    required this.baglam,
    required this.formId,
    this.google,
    this.hesapBagla,
    this.hazirlayarakAc = false,
  });
  final BireyselBilgiToplamaService service;
  final BilgiToplamaOturumu baglam;
  final int formId;
  final bool hazirlayarakAc;
  final BilgiToplamaGoogleService? google;
  final Future<String> Function()? hesapBagla;
  @override
  State<BireyselBilgiFormDetayScreen> createState() => _DetayState();
}

class _DetayState extends State<BireyselBilgiFormDetayScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _webId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '809052042804-k51q6va9bvevktpf8hoqcs87s752n5cg.apps.googleusercontent.com',
  );
  late final _google = widget.google ?? BilgiToplamaGoogleService();
  final _hesap = OrtakGoogleOturumService.hesap;
  final _kurtar = TextEditingController();
  Map<String, Object?>? _form;
  Map<String, dynamic> _ozet = {};
  Map<String, Map<String, int>> _sayilar = {};
  late final _tablar = TabController(length: 3, vsync: this);
  int _sekme = 0;
  final _silSecili = <int>{};
  List<Map<String, Object?>> _sorular = [], _yanitlar = [];
  BilgiToplamaOnizleme? _p;
  String? _hata, _sonuc, _email;
  String? _formMesaji;
  bool _busy = false, _gizli = false, _paylasildi = false;
  final _arama = TextEditingController();
  final Map<int, BilgiToplamaOnizleme> _topluUygun = {};
  final Set<int> _topluSecili = {};
  final Map<int, String> _topluSorun = {};
  bool _topluTarandi = false;
  String _filtre = 'Tümü';
  String? _silmeIlerleme;
  bool _silmeDurdur = false;
  BireyselBilgiToplamaService get s => widget.service;
  BilgiToplamaOturumu get b => widget.baglam;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _is(() async {
      await _yerel();
      if (widget.hazirlayarakAc) {
        await _googleFormunuHazirla();
        return;
      }
      if (widget.hesapBagla == null) {
        try {
          final hesap = _hesap.currentUser ?? await _hesap.signInSilently();
          if (mounted) setState(() => _email = hesap?.email);
        } catch (_) {
          // Sessiz oturum bulunamazsa kullanıcı bağlama düğmesini kullanır.
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tablar.dispose();
    _kurtar.dispose();
    _arama.dispose();
    if (widget.google == null) _google.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      setState(() => _gizli = false);
      if (!_busy) _is(_yerel);
    } else {
      setState(() {
        _gizli = true;
        _p = null;
        _yanitlar = [];
        _topluUygun.clear();
        _topluSecili.clear();
        _topluSorun.clear();
        _topluTarandi = false;
      });
    }
  }

  Future<void> _yerel() async {
    final f = await s.formGetir(b, widget.formId);
    final ss = await s.sorular(b, widget.formId);
    final yy = await s.yanitlar(b, widget.formId);
    final ozet = await s.formOzeti(b, widget.formId);
    final sayilar = await s.sayisalOzet(b, widget.formId);
    final paylasildi = await s.formPaylasildiMi(b, widget.formId);
    _topluUygun.clear();
    _topluSecili.clear();
    _topluSorun.clear();
    _topluTarandi = false;
    if (mounted) {
      setState(() {
        _form = f;
        _ozet = ozet;
        _sayilar = sayilar;
        _silSecili.clear();
        _paylasildi = paylasildi;
        _sorular = ss;
        if (!_gizli) _yanitlar = yy;
      });
    }
  }

  Future<void> _is(Future<void> Function() f) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _hata = null;
      _sonuc = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = formIslemHatasi(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _token({bool silme = false}) async {
    if (widget.hesapBagla != null) return widget.hesapBagla!();
    if (_webId.isEmpty) {
      throw StateError(
        'Google bağlantısı bu uygulama sürümünde yapılandırılmamış.',
      );
    }
    final a = await OrtakGoogleOturumService.hesapGetir();
    final t = await OrtakGoogleOturumService.token(
      ekIzin: silme ? BilgiToplamaGoogleService.silmeScope : null);
    if (mounted) setState(() => _email = a.email);
    return t;
  }

  Future<void> _hesapDegistir() => _is(() async {
    if (widget.hesapBagla == null) await OrtakGoogleOturumService.hesapDegistir();
    if (mounted) setState(() => _email = null);
    await _token();
  });

  Future<void> _hazirla({bool kurtar = false}) =>
      _is(() => _googleFormunuHazirla(kurtar: kurtar));
  Future<void> _googleFormunuHazirla({bool kurtar = false}) async {
    try {
      await _google.hazirla(
        s,
        b,
        widget.formId,
        await _token(),
        kurtarilacakId: kurtar ? _kurtar.text.trim() : null,
      );
    } finally {
      // Google kimliği kaydedildikten sonra istek yarıda kalmış olabilir.
      try {
        await _yerel();
      } catch (_) {
        /* Asıl hata korunur. */
      }
    }
    if ((await s.formAliciBaglari(b, widget.formId)).isEmpty) {
      if (mounted) {
        setState(
          () => _sonuc =
              'Google Form hazır. Paylaşmak için Alıcılar düğmesinden alıcı seçin.',
        );
      }
      return;
    }
    await _paylasIcerigi(yayinla: true, onizle: true);
  }

  Future<void> _paylas({
    bool yayinla = false,
    bool ac = false,
    bool onizle = true,
    Set<int>? yalnizOgrenciler,
  }) => _is(
    () => _paylasIcerigi(
      yayinla: yayinla,
      ac: ac,
      onizle: onizle,
      yalnizOgrenciler: yalnizOgrenciler,
    ),
  );

  Future<void> _paylasIcerigi({
    bool yayinla = false,
    bool ac = false,
    bool onizle = true,
    Set<int>? yalnizOgrenciler,
  }) async {
    final kaynakFormId = _form?['GoogleFormId'];
    var aliciBaglari = await s.formAliciBaglari(b, widget.formId);
    if (yalnizOgrenciler != null) {
      aliciBaglari = aliciBaglari
          .where(
            (bag) => yalnizOgrenciler.contains(int.tryParse(bag.split(':')[1])),
          )
          .toSet();
      if (aliciBaglari.isEmpty) {
        throw StateError(
          'Hatırlatma için formun kayıtlı alıcılarını seçmeniz gerekiyor.',
        );
      }
    }
    if (!mounted || _gizli) return;
    if (yayinla && aliciBaglari.isEmpty) {
      await _alicilariDuzenle();
      aliciBaglari = await s.formAliciBaglari(b, widget.formId);
      if (aliciBaglari.isEmpty || !mounted || _gizli) return;
    }
    final token = await _token();
    final link = yayinla
        ? await _google.yayinla(s, b, widget.formId, token)
        : BilgiToplamaGoogleService.paylasimBaglantisi(
            await _google.kontrolEt(s, b, widget.formId, token),
          );
    _formMesaji = _paylasimMesaji(link);
    if (ac) {
      await const MethodChannel(
        'elpi_okul_yonetim/google_form',
      ).invokeMethod<void>('ac', {'adres': link});
    } else {
      await Clipboard.setData(ClipboardData(text: link));
      if (yayinla) {
        await s.formPaylasildiIsaretle(
          b,
          widget.formId,
          _form!['GoogleFormId'] as String,
        );
      }
    }
    if (mounted) {
      setState(() {
        if (yayinla) _paylasildi = true;
        _sonuc = ac
            ? 'Form açıldı.'
            : 'Yanıtlama bağlantısı kopyalandı. Google Forms’taki yanıtlayıcı erişimini de kontrol edin.';
      });
    }
    if (yayinla && mounted && !_gizli) {
      setState(() => _busy = false);
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: !onizle,
          pageBuilder: (_, _, _) => MesajlasmaScreen(
            yalnizGonderimOnayi: onizle,
            kaynakKontrol: (mb) async {
              if (mb.okulId != b.okulId ||
                  mb.ogretmenId != b.profilId ||
                  mb.yil != b.yil) {
                throw StateError('Form alıcı kapsamı değişti.');
              }
              final kaynak = await s.formGetir(b, widget.formId);
              final m = await s.yonetim(b, widget.formId);
              if (kaynak['GoogleFormId'] != kaynakFormId ||
                  kaynak['Durum'] != 'Aktif' ||
                  m['arsiv'] == true) {
                throw StateError('Form kapandı veya bağlantısı değişti.');
              }
              final guncel = await s.formAliciBaglari(b, widget.formId);
              if (!aliciBaglari.every(guncel.contains)) {
                throw StateError('Formun alıcıları değişti. Yeniden açın.');
              }
            },
            baslangicKisiBaglari: aliciBaglari,
            kaynakModul: 'BilgiFormOrtakPaylasim',
            kaynakKayit: widget.formId.toString(),
            kaynakGecmisiniGoster: false,
            gonderimOnizlemesiniAc: onizle,
            baslangicMetni: _paylasimMesaji(link),
          ),
        ),
      );
      if (mounted && !_gizli) {
        await _yerel();
        if (mounted) {
          setState(
            () => _sonuc =
                'Form yayımlandı. Mesajlaşma ekranındaki gönderim onayları esas alınır.',
          );
        }
      }
    }
  }

  Future<void> _al() => _is(() async {
    _p = null;
    final ids = await _google.yanitlariAl(s, b, widget.formId, await _token());
    await _yerel();
    if (mounted) {
      _sekme = 1;
      _tablar.index = 1;
      setState(
        () => _sonuc =
            '${ids.length} yanıt kontrol edildi. Önceden alınan aynı yanıtlar tekrar eklenmedi.',
      );
    }
  });
  Future<void> _incele(int id) => _is(() async {
    final p = await s.onizle(b, id);
    if (mounted && !_gizli) {
      setState(() {
        _p = p;
        _sekme = 2;
        _tablar.index = 2;
      });
    }
  });
  Future<void> _yanitDuzenle() => _is(() async {
    final p = _p!;
    final cevaplar = await s.duzenlenecekCevaplar(b, p);
    if (!mounted || _gizli || !identical(_p, p)) return;
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => _YanitDuzenleScreen(
          sorular: _sorular,
          cevaplar: cevaplar,
          kaydet: (v) => s.yanitiDuzenle(b, p, v),
        ),
      ),
    );
    if (id == null || !mounted || _gizli) return;
    await _yerel();
    final yeni = await s.onizle(b, id);
    if (mounted && !_gizli) {
      setState(() {
        _p = yeni;
        _sonuc =
            'Düzeltmeler ön izlemeye alındı. Öğrenciye işlemek için onaylayın.';
      });
    }
  });
  Future<void> _duzelt() => _is(() async {
    final p = _p!;
    final rows = await s.hedefOgrenciler(b, widget.formId);
    if (!mounted) return;
    final ids = await Navigator.of(context).push<Set<int>>(
      MaterialPageRoute(
        builder: (_) => _SecimScreen(
          baslik: 'Doğru öğrenciyi seç',
          tek: true,
          secili: const {},
          liste: {
            for (final o in rows)
              o['OgrenciId'] as int:
                  '${o['OkulNo']} • ${o['Ad']} ${o['Soyad']} • ${o['SinifKodu']}',
          },
        ),
      ),
    );
    if (ids == null || ids.length != 1 || !mounted) return;
    if (!await _onay(
      context,
      'Eşleştirmeyi düzelt',
      'Seçilen öğrenciye bağlansın mı? Öğrencinin okul numarası, adı ve sınıfı değişmeyecek.',
    )) {
      return;
    }
    if (!mounted) return;
    await s.eslemeyiDuzelt(
      b,
      p,
      ogrenciId: ids.single,
      aciklama:
          'Öğretmen, form kimlik bilgilerini kontrol ederek doğru öğrenciyi seçti.',
    );
    final yeni = await s.onizle(b, p.yanitId);
    if (mounted && !_gizli) setState(() => _p = yeni);
  });
  Future<void> _ogrenciyeDuzelttir() => _is(() async {
    final p = _p!;
    final hedef = await s.duzeltmeHedefi(b, p);
    final link = await _google.duzeltmeBaglantisi(
      s,
      b,
      p,
      await _token(silme: true),
    );
    if (!mounted || _gizli || !identical(_p, p)) return;
    final id = hedef['ogrenciId'] as int;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MesajlasmaScreen(
          kaynakModul: MesajlasmaService.formDuzeltmeOgrenciModulu,
          kaynakKayit: '${widget.formId}:${hedef['responseId']}',
          ogrenciTelefonu: true,
          baslangicOgrenciIdleri: {id},
          izinliOgrenciIdleri: {id},
          baslangicMetni:
              '${p.ogrenci!['Ad']} ${p.ogrenci!['Soyad']}, '
              '“${hedef['baslik']}” formundaki eksik veya yanlış bilgilerinizi '
              'aşağıdaki bağlantıdan düzeltip yeniden gönderiniz. '
              'Bu bağlantı yalnız sizin cevabınız içindir; başkalarıyla paylaşmayınız.\n$link',
        ),
      ),
    );
    if (mounted && !_gizli) {
      _p = null;
      await _yerel();
      if (mounted) {
        setState(
          () => _sonuc =
              'Düzeltmeler gönderildikten sonra “Yanıtları getir” ile güncel cevabı alıp yeniden onaylayın.',
        );
      }
    }
  });
  Future<void> _kaydet() => _is(() async {
    final p = _p!;
    if (!await _onay(
      context,
      'Bilgileri kaydet',
      '${p.uyarilar.join('\n')}\nÖn izlemedeki yeni bilgiler seçilen öğrenciye kaydedilsin mi? Boş cevaplar mevcut bilgileri silmez.',
    )) {
      return;
    }
    if (!mounted || _gizli || !identical(_p, p)) return;
    await s.onayla(b, p, uyarilariKabulEt: p.uyarilar.isNotEmpty);
    _p = null;
    await _yerel();
    if (mounted) setState(() => _sonuc = 'Öğrenci bilgileri kaydedildi.');
  });
  bool _bekleyen(Map<String, Object?> y) =>
      y['Durum'] != 'Onaylandi' && y['Durum'] != 'Reddedildi';

  Future<void> _uygunlariTara() => _is(() async {
    final uygun = <int, BilgiToplamaOnizleme>{};
    final sorun = <int, String>{};
    for (final y in _yanitlar.where(_bekleyen)) {
      final id = y['Id'] as int;
      try {
        final p = await s.onizle(b, id);
        if (p.kaydedilebilir && p.uyarilar.isEmpty) {
          uygun[id] = p;
        } else {
          sorun[id] = [...p.hatalar, ...p.uyarilar].join('; ');
        }
      } catch (e) {
        sorun[id] = 'Kontrol edilemedi: $e';
      }
    }
    if (!mounted || _gizli) return;
    setState(() {
      _topluUygun
        ..clear()
        ..addAll(uygun);
      _topluSorun
        ..clear()
        ..addAll(sorun);
      _topluSecili
        ..clear()
        ..addAll(uygun.keys);
      _topluTarandi = true;
      _sonuc =
          '${uygun.length} uygun yanıt seçildi. '
          '${sorun.length} yanıt ayrıca kontrol edilmeli.';
    });
  });

  // Gelen yanıtlar sekmesinden tek dokunuşla güvenli uygunluk
  // taraması ve ardından mevcut onay akışını başlatır.
  Future<void> _tumunuOnayla() async {
    if (_busy || !_yanitlar.any(_bekleyen)) return;
    await _uygunlariTara();
    if (!mounted || _gizli || _topluSecili.isEmpty) {
      if (mounted && !_gizli && _topluSorun.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Toplu onaya uygun yanıt bulunamadı. Kontrol gerektiren yanıtları inceleyin.'),
        ));
      }
      return;
    }
    await _topluOnayla();
  }

  Future<void> _topluOnayla() => _is(() async {
    final ids = _topluSecili.toList()..sort();
    if (ids.isEmpty) return;
    final kabul = await _onay(
      context,
      'Toplu Onay',
      '${ids.length} uygun yanıt, öğrenci bilgilerine kaydedilecek. '
          'Kimlik uyuşmazlığı, tekrar yanıtı veya başka uyarısı olanlar '
          'toplu onaya dahil edilmez. Boş cevaplar mevcut bilgileri silmez. '
          'İşlemi onaylıyor musunuz?',
    );
    if (!kabul || !mounted || _gizli) return;
    var basarili = 0;
    final hatalar = <String>[];
    for (final id in ids) {
      if (!mounted || _gizli) break;
      try {
        // Her kayıt için anlık durum ve önceki ön izleme imzası
        // mevcut onayla() içinde yeniden denetlenir.
        await s.onayla(b, _topluUygun[id]!);
        basarili++;
      } catch (e) {
        hatalar.add('Yanıt #$id: $e');
      }
    }
    await _yerel();
    if (!mounted) return;
    final ozet =
        '$basarili yanıt kaydedildi, '
        '${hatalar.length} yanıt kaydedilemedi.';
    setState(() => _sonuc = ozet);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Toplu Onay Sonucu'),
        content: SingleChildScrollView(
          child: Text(
            hatalar.isEmpty
                ? ozet
                : '$ozet\n\nKontrol gerektirenler:\n${hatalar.join('\n')}',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  });

  Widget _topluListe() {
    final tamam = _yanitlar.where((y) => y['Durum'] == 'Onaylandi').length;
    final bekleyen = _yanitlar.where(_bekleyen).length;
    final uygun = _topluTarandi ? _topluUygun.length : 0;
    final sorun = _topluTarandi ? _topluSorun.length : 0;
    final ara = _arama.text.trim().toLowerCase();
    final gorunen = _yanitlar.where((y) {
      final metin =
          "${y['GirilenOkulNo']} ${y['GirilenAdSoyad']} "
                  "${y['GirilenSinif']}"
              .toLowerCase();
      if (ara.isNotEmpty && !metin.contains(ara)) return false;
      final id = y['Id'] as int;
      switch (_filtre) {
        case 'Uygun':
          return _topluUygun.containsKey(id);
        case 'Kontrol':
          return _topluSorun.containsKey(id);
        case 'Kaydedilen':
          return y['Durum'] == 'Onaylandi';
        default:
          return true;
      }
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '2. Gelen yanıtlar',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          '${_yanitlar.length} toplam • $tamam kaydedildi • $bekleyen bekliyor',
        ),
        if (_sekme == 1)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: FilledButton.icon(
              onPressed: _busy || bekleyen == 0 ? null : _tumunuOnayla,
              icon: const Icon(Icons.done_all),
              label: const Text('Tümünü Onayla'),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _busy || _form?['GoogleFormId'] == null
              ? null
              : () => _topluSil(),
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Toplu sil'),
        ),
        if (_sekme == 1)
          OutlinedButton.icon(
            onPressed: _busy || _silSecili.isEmpty
                ? null
                : () => _topluSil(secilen: true),
            icon: const Icon(Icons.delete_outline),
            label: Text('Seçilen ${_silSecili.length} yanıtı sil'),
          ),
        if (_sekme == 1 && gorunen.isNotEmpty)
          CheckboxListTile(
            title: const Text('Görünen yanıtların tümünü seç'),
            value: gorunen.every((y) => _silSecili.contains(y['Id'])),
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    for (final y in gorunen) {
                      if (v == true) {
                        _silSecili.add(y['Id'] as int);
                      } else {
                        _silSecili.remove(y['Id']);
                      }
                    }
                  }),
          ),
        if (_silmeIlerleme != null) ...[
          Text(_silmeIlerleme!),
          TextButton(
            onPressed: _silmeDurdur
                ? null
                : () => setState(() => _silmeDurdur = true),
            child: Text(
              _silmeDurdur
                  ? 'Mevcut işlemden sonra duracak'
                  : 'Toplu silmeyi durdur',
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in ['Tümü', 'Uygun', 'Kontrol', 'Kaydedilen'])
              ChoiceChip(
                label: Text(
                  f == 'Uygun'
                      ? 'Uygun ($uygun)'
                      : f == 'Kontrol'
                      ? 'Kontrol ($sorun)'
                      : f,
                ),
                selected: _filtre == f,
                onSelected: _busy ? null : (_) => setState(() => _filtre = f),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _arama,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Öğrenci ara (ad, soyad, okul no, sınıf)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (_sekme == 2)
          OutlinedButton.icon(
            onPressed: _busy || bekleyen == 0 ? null : _uygunlariTara,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
              _topluTarandi
                  ? 'Uygunluk kontrolünü yenile'
                  : 'Uygun olanları kontrol et ve seç',
            ),
          ),
        if (_topluTarandi)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Uygun olanların tümünü seç ($uygun)'),
            value: uygun > 0 && _topluSecili.length == uygun,
            onChanged: _busy || uygun == 0
                ? null
                : (v) => setState(() {
                    _topluSecili.clear();
                    if (v == true) _topluSecili.addAll(_topluUygun.keys);
                  }),
          ),
        if (_yanitlar.isEmpty) const Text('Henüz yanıt alınmadı.'),
        for (final y in gorunen)
          Card(
            child: ListTile(
              leading: _sekme == 1
                  ? Checkbox(
                      value: _silSecili.contains(y['Id']),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                _silSecili.add(y['Id'] as int);
                              } else {
                                _silSecili.remove(y['Id']);
                              }
                            }),
                    )
                  : _topluUygun.containsKey(y['Id'])
                  ? Checkbox(
                      value: _topluSecili.contains(y['Id']),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              final id = y['Id'] as int;
                              if (v == true) {
                                _topluSecili.add(id);
                              } else {
                                _topluSecili.remove(id);
                              }
                            }),
                    )
                  : const Icon(Icons.assignment_outlined),
              title: Text("${y['GirilenOkulNo']} • ${y['GirilenAdSoyad']}"),
              subtitle: Text(
                "${y['GirilenSinif']} • "
                "${_topluUygun.containsKey(y['Id'])
                    ? 'Uygun'
                    : _topluSorun.containsKey(y['Id'])
                    ? 'Kontrol gerekli'
                    : y['Durum']}\n"
                "${_topluSorun[y['Id']] ?? ''}",
              ),
              isThreeLine: _topluSorun.containsKey(y['Id']),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _incele(y['Id'] as int),
            ),
          ),
        if (_topluTarandi)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 20),
            child: FilledButton.icon(
              onPressed: _busy || _topluSecili.isEmpty ? null : _topluOnayla,
              icon: const Icon(Icons.done_all),
              label: Text('Seçili ${_topluSecili.length} yanıtı toplu onayla'),
            ),
          ),
      ],
    );
  }

  Future<void> _reddet() => _is(() async {
    final p = _p!;
    if (!await _onay(
      context,
      'Yanıtı reddet',
      'Bu yanıt öğrenciye işlenmeden kapatılsın mı?',
    )) {
      return;
    }
    if (!mounted || _gizli || !identical(_p, p)) return;
    await s.reddet(b, p);
    _p = null;
    await _yerel();
  });
  Future<void> _topluSil({bool secilen = false}) => _is(() async {
    final secilenIds = Set<int>.of(_silSecili);
    if (secilen && secilenIds.isEmpty) {
      throw StateError('Silinecek yanıtları seçin.');
    }
    final sadeceKaydedilenler = secilen
        ? false
        : await showDialog<bool>(
            context: context,
            builder: (c) => SimpleDialog(
              title: const Text('Toplu sil'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Kaydedilen yanıtları sil'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Tüm yanıtları sil'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('İptal'),
                ),
              ],
            ),
          );
    if (sadeceKaydedilenler == null || !mounted || _gizli) return;
    final token = await _token(silme: true);
    if (!mounted || _gizli) return;
    // Google'da henüz alınmamış yanıtları da onay sayısına dahil et.
    await _google.yanitlariAl(s, b, widget.formId, token);
    await _yerel();
    final plan = await s.topluSilmePlani(
      b,
      widget.formId,
      sadeceKaydedilenler: sadeceKaydedilenler,
      seciliYanitIdleri: secilen ? secilenIds : null,
    );
    if (!mounted || _gizli) return;
    if (plan.toplam == 0) {
      setState(() => _sonuc = 'Seçilen kapsamda silinecek yanıt yok.');
      return;
    }
    if (!await _onay(
      context,
      'Toplu silmeyi onayla',
      '${_form?['Baslik']}\n${plan.toplam} yanıt silinecek.\n'
          '${plan.kaydedilmemisSayisi} yanıt henüz öğrenciye kaydedilmemiş.\n\n'
          'Google Forms yanıtları ve bunların uygulamadaki ham cevapları kalıcı olarak temizlenecek; geri alınamaz. '
          'Öğrenciye kaydedilmiş bilgiler korunur. Form yeni yanıt almaya devam eder. '
          'Onaydan sonra gelen yeni yanıtlar silinmez. Google E-Tablolar kopyaları ve eski yedekler bu işleme dahil değildir.',
    )) {
      return;
    }
    if (!mounted || _gizli) return;
    _silmeDurdur = false;
    setState(() => _silmeIlerleme = 'Siliniyor: 0 / ${plan.toplam}');
    try {
      final sonuc = await _google.yanitlariTopluSil(
        s,
        b,
        plan,
        token,
        devamEt: () => mounted && !_gizli && !_silmeDurdur,
        ilerleme: (n, toplam) {
          if (mounted) {
            setState(() => _silmeIlerleme = 'Kontrol edildi: $n / $toplam');
          }
        },
      );
      await _yerel();
      if (!mounted) return;
      final ozet =
          '${sonuc.basarili} yanıt silindi ve ham kopyaları temizlendi. '
          '${sonuc.kalan} yanıt tamamlanamadı veya işleme alınmadı.';
      setState(() => _sonuc = ozet);
      if (!_gizli) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Toplu silme sonucu'),
            content: SingleChildScrollView(
              child: Text([ozet, ...sonuc.hatalar].join('\n\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _silmeIlerleme = null);
    }
  });

  Future<void> _sil() => _is(() async {
    final p = _p!;
    if ((await s.silmeBaglantisi(b)).isEmpty) {
      throw StateError(
        'Google bağlantısı kurulumu eksik. Uygulamanın Google bağlantı yapılandırmasını kontrol edin.',
      );
    }
    if (!mounted || _gizli || !identical(_p, p)) return;
    if (!await _onay(
      context,
      'Google Forms ve uygulamadan sil',
      'Bu yanıt Google Forms’tan kalıcı olarak silinecek; geri alınamaz. '
          'Yanıt ve önceki düzenlemelerinin ham cevapları uygulamadan temizlenecek. '
          'Öğrenciye kaydedilmiş bilgiler korunur. '
          'Forma bağlı Google E-Tablolar kopyası varsa oradan silinmez. Devam edilsin mi?',
    )) {
      return;
    }
    if (!mounted || _gizli || !identical(_p, p)) return;
    final token = await _token(silme: true);
    if (!mounted || _gizli) return;
    await _google.yanitiSil(s, b, p, token);
    _p = null;
    await _yerel();
    if (mounted) {
      setState(
        () => _sonuc =
            'Yanıt Google Forms’tan silindi ve uygulama listesinden kaldırıldı.',
      );
    }
  });
  Future<void> _alicilariDuzenle() async {
    final hedefKayitlari = await s.hedefOgrenciler(b, widget.formId);
    final hedefler = hedefKayitlari.map((o) => o['OgrenciId'] as int).toSet();
    final siniflar = hedefKayitlari.map((o) => o['SinifSubeId']).toSet();
    final ms = MesajlasmaService.instance;
    final mb = await ms.hazirla();
    if (mb.okulId != b.okulId ||
        mb.ogretmenId != b.profilId ||
        mb.yil != b.yil) {
      throw StateError('Alıcı kapsamı değişti.');
    }
    final adaylar = (await ms.aliciAdaylari(mb))
        .where(
          (k) => k.tur == MesajKisiTuru.ogretmen
              ? siniflar.contains(k.sinifId)
              : hedefler.contains(int.tryParse(k.kisiId)),
        )
        .toList();
    if (!mounted || _gizli) return;
    final onceki = await s.formAliciBaglari(b, widget.formId);
    if (!mounted || _gizli) return;
    final sonuc = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => _FormAliciSecScreen(adaylar: adaylar, onceki: onceki),
      ),
    );
    if (sonuc != null) await s.formAlicilariniKaydet(b, widget.formId, sonuc);
  }

  Future<void> _durumIslemi(String islem) => _is(() async {
    if (!await _onay(
      context,
      islem,
      islem == 'Kapat'
          ? 'Google Form yeni yanıt kabul etmeyecek. Mevcut yanıtlar korunacak.'
          : '$islem işlemi uygulansın mı? Form ve yanıtlar silinmez.',
    )) {
      return;
    }
    if (!mounted || _gizli) return;
    if (islem == 'Kapat' || islem == 'Aç') {
      await _google.yanitAliminiAyarla(
        s,
        b,
        widget.formId,
        await _token(),
        islem == 'Aç',
      );
    } else {
      await s.isaretle(b, widget.formId, islem);
    }
    await _yerel();
  });

  Future<void> _hatirlat() async {
    Set<int>? bekleyen;
    await _is(() async {
      await _google.yanitlariAl(s, b, widget.formId, await _token());
      await _yerel();
      if (_ozet['yanitlayan'] == null || _ozet['eslesmeyen'] != 0) {
        throw StateError(
          'Bazı yanıtların kişisi belirsiz. Yanlış kişiye hatırlatma göndermemek için önce yanıtları eşleştirin.',
        );
      }
      bekleyen = (_ozet['beklenenIds'] as List).cast<int>().toSet().difference(
        (_ozet['yanitlayanIds'] as List).cast<int>().toSet(),
      );
      if (bekleyen!.isEmpty) {
        throw StateError('Yanıt beklenen öğrenci kalmadı.');
      }
    });
    if (mounted && bekleyen != null && bekleyen!.isNotEmpty) {
      await _paylas(yayinla: true, yalnizOgrenciler: bekleyen);
    }
  }

  String _paylasimMesaji(String link) =>
      'Merhaba, “${_form!['Baslik']}” formunu aşağıdaki bağlantıdan doldurmanızı rica ederiz.\n$link';

  Future<void> _mesajMetniniYukle() => _is(() async {
    final remote = await _google.kontrolEt(s, b, widget.formId, await _token());
    final link = remote['responderUri']?.toString() ?? '';
    final uri = Uri.tryParse(link);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'docs.google.com' ||
        !uri.path.startsWith('/forms/')) {
      throw StateError('Formun yanıtlama bağlantısı henüz alınamadı.');
    }
    if (mounted) setState(() => _formMesaji = _paylasimMesaji(link));
  });

  Widget _mesajMetniKutusu() => Card(
    child: OrtakGenisleyenBolum(
      key: const PageStorageKey('form-mesaj-metni'),
      initiallyExpanded: false,
      leading: const Icon(Icons.message_outlined),
      title: const Text('Mesaj metni'),
      onExpansionChanged: (acik) {
        if (!acik) return;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              _busy ||
              _formMesaji != null ||
              _form?['GoogleFormId'] == null) {
            return;
          }

          _mesajMetniniYukle();
        });
      },
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Builder(builder: (context) {
            final mesaj = _formMesaji;
            if (mesaj == null) {
              return SelectableText(
                _busy ? 'Mesaj yükleniyor…' : 'Form bağlantısı henüz hazırlanmadı.');
            }
            final eslesme = RegExp(r'https://[^\s]+').firstMatch(mesaj);
            if (eslesme == null) return SelectableText(mesaj);
            final baglanti = eslesme.group(0)!;
            final uri = Uri.tryParse(baglanti);
            final guvenli = uri != null &&
                uri.scheme == 'https' &&
                uri.host == 'docs.google.com' &&
                uri.path.startsWith('/forms/');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(mesaj.substring(0, eslesme.start)),
                if (guvenli)
                  InkWell(
                    onTap: () async {
                      try {
                        if (!await launchUrl(uri!, mode: LaunchMode.externalApplication)) {
                          throw StateError('Form bağlantısı açılamadı.');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Form açılamadı. Orijinal hata: $e')));
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        baglanti,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline),
                      ),
                    ),
                  )
                else SelectableText(baglanti),
                if (eslesme.end < mesaj.length)
                  SelectableText(mesaj.substring(eslesme.end)),
              ],
            );
          }),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _formMesaji == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _formMesaji!));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mesaj metni kopyalandı.'),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Metni kopyala'),
          ),
        ),
      ],
    ),
  );

  Widget _yonetimOzeti() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${bilgiFormSablonlari[_ozet['sablon']] ?? 'Bilgi formu'} • ${_form?['Durum'] == 'Aktif' && _ozet['durum'] == 'Taslak' ? 'Google Form hazır, yayımlanmayı bekliyor' : _ozet['durum']}',
              ),
              Text('Yanıtlayacak grup: ${_ozet['aliciGrubu']}'),
              Text(
                _ozet['yanitlayan'] == null
                    ? '${_ozet['yanitSayisi']} yanıt • Kişi eşleştirmesi belirsiz'
                    : '${_ozet['yanitlayan']} / ${_ozet['beklenen']} öğrenci için yanıt eşleşti',
              ),
              Text(
                'Yanıt alımı: ${_ozet['yayinAcik'] == true
                    ? 'Açık'
                    : _ozet['yayinAcik'] == false
                    ? 'Kapalı'
                    : 'Henüz doğrulanmadı'}',
              ),
              Text(
                'Paylaşım: ${_ozet['paylasimBaslatildi'] == true ? 'Başlatıldı; gönderim onayı Mesajlaşma’da' : 'Uygulamada paylaşım kaydı yok'}',
              ),
              if (_ozet['sonYanit'] != null)
                Text(
                  'Son yanıt: ${DateTime.parse(_ozet['sonYanit'] as String).toLocal()}',
                ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _sayisalDegerlendirme() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final e in _sayilar.entries)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.key, style: Theme.of(context).textTheme.titleMedium),
                if (e.value.isEmpty) const Text('Henüz yanıt yok.'),
                for (final v in e.value.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${v.key}: ${v.value}'),
                        LinearProgressIndicator(
                          value:
                              v.value /
                              e.value.values.fold<int>(0, (a, b) => a + b),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _formIslemCubugu() {
    final taslak = _form!['Durum'] == 'Taslak';
    final aktif = _form!['Durum'] == 'Aktif';
    final kapali = _form!['Durum'] == 'Kapali';
    Widget eylem(
      IconData icon,
      String label,
      String hint,
      VoidCallback? action,
    ) => Expanded(
      child: Tooltip(
        message: hint,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            minimumSize: const Size(0, 56),
          ),
          onPressed: _busy ? null : action,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (taslak || aktif)
          _FormAnaIslem(
            metin: taslak ? 'Google Formu Hazırla' : 'Ön İzle ve Onayla',
            ipucu:
                'Seçili alıcılarla mesaj ön izlemesini açar. Gönderim sizin onayınızla yapılır.',
            busy: _busy,
            icon: taslak ? Icons.description_outlined : Icons.preview_outlined,
            onPressed: () => taslak ? _hazirla() : _paylas(yayinla: true),
          ),
        Row(
          children: [
            eylem(
              Icons.people_outline,
              'Alıcılar',
              'Alıcıları düzenle',
              () => _is(_alicilariDuzenle),
            ),
            eylem(
              kapali ? Icons.play_circle_outline : Icons.pause_circle_outline,
              kapali ? 'Yanıt aç' : 'Yanıt kapat',
              kapali ? 'Yanıt alımını aç' : 'Yanıt alımını kapat',
              aktif || kapali
                  ? () => _durumIslemi(kapali ? 'Aç' : 'Kapat')
                  : null,
            ),
            eylem(
              Icons.notifications_active_outlined,
              'Hatırlat',
              'Yanıt vermeyenlere hatırlat',
              aktif ? _hatirlat : null,
            ),
            Expanded(
              child: PopupMenuButton<String>(
                tooltip: 'Diğer işlemler',
                enabled: !_busy,
                onSelected: (v) {
                  if (v == 'hesap') {
                    _hesapDegistir();
                  } else {
                    _durumIslemi(v);
                  }
                },
                itemBuilder: (_) => [
                  if (_email != null)
                    const PopupMenuItem(
                      value: 'hesap',
                      child: Text('Hesabı değiştir'),
                    ),
                  if (kapali)
                    const PopupMenuItem(
                      value: 'Tamamla',
                      child: Text('Tamamlandı olarak işaretle'),
                    ),
                  if (kapali)
                    PopupMenuItem(
                      value: _ozet['arsiv'] == true
                          ? 'Arşivden çıkar'
                          : 'Arşivle',
                      child: Text(
                        _ozet['arsiv'] == true ? 'Arşivden çıkar' : 'Arşivle',
                      ),
                    ),
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
        ),
      ],
    );
  }

  Widget _btn(String text, VoidCallback f) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: OutlinedButton(onPressed: _busy ? null : f, child: Text(text)),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: OrtakSayfa(
      appBar: ModulUstBar(
        title: Text(_form?['Baslik']?.toString() ?? 'Bilgi formu'),
      ),
      bottomNavigationBar: _form == null || _gizli ? null : _formIslemCubugu(),
      body: _gizli
          ? const Center(child: Text('Bilgiler gizlendi.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_hata != null)
                  SelectableText(
                    _hata!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_hata != null) _btn('Yeniden dene', () => _is(_yerel)),
                if (_sonuc != null)
                  Text(
                    _sonuc!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                if (_form == null && !_busy)
                  _btn('Yeniden dene', () => _is(_yerel)),
                if (_form != null)
                  TabBar(
                    isScrollable: true,
                    controller: _tablar,
                    onTap: (i) => setState(() {
                      _sekme = i;
                      if (i != 2) _p = null;
                    }),
                    tabs: const [
                      Tab(text: 'Özet'),
                      Tab(text: 'Yanıtlar'),
                      Tab(text: 'Değerlendirme'),
                    ],
                  ),
                if (_sekme == 0 && _form != null) ...[
                  _yonetimOzeti(),
                  _mesajMetniKutusu(),
                ],
                if (_sekme == 2 && _p != null) _onizleme(),
                if (_sekme == 2 && _p == null) _sayisalDegerlendirme(),
                if (_form != null && _p == null) ...[
                  if (_sekme == 0) ...[
                    const Text(
                      '1. Formu hazırla ve paylaş',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_email != null) Text(_email!),
                    if (_email == null)
                      _btn(
                        'Google hesabını bağla',
                        () => _is(() async {
                          await _token();
                        }),
                      ),
                    if (_form!['Durum'] == 'Taslak') ...[
                      if (_form!['GoogleFormId'] == null)
                        OrtakGenisleyenBolum(
                          title: const Text('Yarım kalan Google formunu bağla'),
                          children: [
                            const Text(
                              'Google Forms düzenleme adresindeki /d/ ile /edit arasındaki kimliği girin. Farklı sorular içeren formlar bağlanmaz.',
                            ),
                            TextField(
                              controller: _kurtar,
                              decoration: const InputDecoration(
                                labelText: 'Google form kimliği',
                              ),
                            ),
                            _btn(
                              'Mevcut formu bağla',
                              () => _hazirla(kurtar: true),
                            ),
                            _btn(
                              'Form oluşmadığını kontrol ettim',
                              () => _is(() async {
                                if (!await _onay(
                                  context,
                                  'Yeniden oluşturma izni',
                                  'Google Forms hesabınızda bu formun oluşmadığını kontrol ettiniz mi? Bu işlem yalnız yeniden deneme kilidini kaldırır.',
                                )) {
                                  return;
                                }
                                await s.googleTekrarDenemeyeIzinVer(
                                  b,
                                  widget.formId,
                                );
                                if (mounted) {
                                  setState(
                                    () => _sonuc =
                                        'Yeniden hazırlama izni verildi.',
                                  );
                                }
                              }),
                            ),
                          ],
                        ),
                    ] else ...[
                      if (_paylasildi) ...[
                        _btn('Formu aç', () => _paylas(ac: true)),
                        _btn('Yanıtları getir', _al),
                      ],
                    ],
                  ],
                  const SizedBox(height: 16),
                  if (_sekme != 0) _topluListe(),
                ],
              ],
            ),
    ),
  );
  Widget _onizleme() {
    final p = _p!, o = p.ogrenci;
    final kapali = _yanitlar.any(
      (y) =>
          y['Id'] == p.yanitId &&
          (y['Durum'] == 'Onaylandi' || y['Durum'] == 'Reddedildi'),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '3. Kontrol et ve kaydet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'Formda: ${p.girilen['okulNo']} • ${p.girilen['adSoyad']} • ${p.girilen['sinif']}',
            ),
            Text(
              o == null
                  ? 'Eşleşen öğrenci yok.'
                  : 'Kayıtta: ${o['OkulNo']} • ${o['Ad']} ${o['Soyad']} • ${o['SinifKodu']}',
            ),
            const Text('Ad soyad ve sınıf öğrenci kaydına yazılmaz.'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: FilledButton.icon(
                onPressed: _busy ? null : _yanitDuzenle,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Yanıtları Düzenle'),
              ),
            ),
            for (final e in p.hatalar)
              Text(
                e,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            for (final e in p.uyarilar)
              Text(
                e,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            for (final e in p.degisiklikler.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _alanlar[e.key] ??
                      BireyselBilgiToplamaService.veliAlanBasliklari[e.key] ??
                      e.key,
                ),
                subtitle: Text(
                  'Eski: ${_onizlemeMetni(e.key, e.value['eski'])}\nYeni: ${_onizlemeMetni(e.key, e.value['yeni'])}',
                ),
              ),
            for (final e in p.serbestDegerler.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _sorular.firstWhere((q) => q['Id'] == e.key)['Baslik']
                      as String,
                ),
                subtitle: Text(
                  'Eski: ${p.serbestOncekiDegerler[e.key] ?? '—'}\nYeni: ${e.value}',
                ),
              ),
            if (!kapali) _btn('Doğru öğrenciyi seç', _duzelt),
            if (_form?['Durum'] == 'Aktif' && o != null)
              _btn('Öğrenciye düzeltme bağlantısı gönder', _ogrenciyeDuzelttir),
            FilledButton(
              onPressed: _busy || !p.kaydedilebilir ? null : _kaydet,
              child: const Text('Onayla ve kaydet'),
            ),
            if (!kapali) _btn('Yanıtı reddet', _reddet),
            _btn('Google Forms ve uygulamadan sil', _sil),
            _btn('Ön izlemeyi kapat', () => setState(() => _p = null)),
          ],
        ),
      ),
    );
  }
}

class _YanitDuzenleScreen extends StatefulWidget {
  const _YanitDuzenleScreen({
    required this.sorular,
    required this.cevaplar,
    required this.kaydet,
  });
  final List<Map<String, Object?>> sorular;
  final Map<String, String> cevaplar;
  final Future<int> Function(Map<String, String>) kaydet;
  @override
  State<_YanitDuzenleScreen> createState() => _YanitDuzenleState();
}

class _YanitDuzenleState extends State<_YanitDuzenleScreen>
    with WidgetsBindingObserver {
  late final _controllers = {
    for (final q in widget.sorular)
      q['AlanAnahtari'] as String: TextEditingController(
        text: widget.cevaplar[q['AlanAnahtari']] ?? '',
      ),
  };
  bool _busy = false, _gizli = false;
  String? _hata;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _gizli = state != AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      final id = await widget.kaydet({
        for (final e in _controllers.entries) e.key: e.value.text,
      });
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Düzeltme kaydedilemedi. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _alan(Map<String, Object?> q) {
    final c = _controllers[q['AlanAnahtari']]!;
    final tur = q['VeriTuru'];
    final secenekler = tur == 'EvetHayir'
        ? ['Evet', 'Hayır']
        : tur == 'Secenek'
        ? (jsonDecode(q['Secenekler'] as String) as List)
              .map((v) => v is Map ? v['etiket'] as String : v as String)
              .toList()
        : <String>[];
    final label = '${q['Baslik']}${q['Zorunlu'] == 1 ? ' *' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: secenekler.isNotEmpty
          ? DropdownButtonFormField<String>(
              initialValue: c.text,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Yanıt yok')),
                for (final v in {...secenekler, if (c.text.isNotEmpty) c.text})
                  DropdownMenuItem(value: v, child: Text(v)),
              ],
              onChanged: _busy ? null : (v) => c.text = v ?? '',
            )
          : TextField(
              controller: c,
              enabled: !_busy,
              minLines: 1,
              maxLines: tur == 'Metin' ? 4 : 1,
              keyboardType: tur == 'Telefon'
                  ? TextInputType.phone
                  : tur == 'Sayi'
                  ? const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    )
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: label,
                helperText: tur == 'Tarih' ? 'YYYY-AA-GG' : null,
                border: const OutlineInputBorder(),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: OrtakSayfa(
      appBar: const ModulUstBar(title: Text('Yanıtları düzenle')),
      body: _gizli
          ? const Center(child: Text('Bilgiler gizlendi.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Düzeltmeler uygulamada yeni bir kontrol kaydı olarak saklanır. Google yanıtı korunur. Öğrenci bilgileri ayrıca onayladığınızda güncellenir. Boş cevaplar mevcut bilgileri silmez.',
                ),
                if (_hata != null)
                  Text(
                    _hata!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                for (final q in widget.sorular) _alan(q),
                FilledButton(
                  onPressed: _busy ? null : _kaydet,
                  child: const Text('Düzeltmeleri ön izle'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
              ],
            ),
    ),
  );
}

class _FormAliciSecScreen extends StatefulWidget {
  const _FormAliciSecScreen({required this.adaylar, required this.onceki});
  final List<MesajKisi> adaylar;
  final Set<String> onceki;
  @override
  State<_FormAliciSecScreen> createState() => _FormAliciSecState();
}

class _FormAliciSecState extends State<_FormAliciSecScreen> {
  late final _secilen = {
    for (final k in widget.adaylar.where(
      (k) => widget.onceki.contains(k.bagAnahtari),
    ))
      k.secimAnahtari: k,
  };
  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: const ModulUstBar(title: Text('Form alıcıları')),
    body: CustomScrollView(
      slivers: [
        MesajAliciSecimSliver(
          adaylar: widget.adaylar,
          siniflar: {
            for (final k in widget.adaylar)
              k.sinifId: k.aciklama.split(' • ').first,
          },
          secilenler: _secilen,
          degistir: (k) => setState(() {
            _secilen.clear();
            _secilen.addEntries(k.map((v) => MapEntry(v.secimAnahtari, v)));
          }),
          veliDuzenle: (_) async {},
          ogretmenDuzenle: (_, __) async {},
          kisiDuzenle: (_) async {},
          iletisimDuzenleme: false,
        ),
      ],
    ),
    bottomNavigationBar: Padding(
      padding: const EdgeInsets.all(12),
      child: FilledButton(
        onPressed: _secilen.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                _secilen.values.map((k) => k.bagAnahtari).toSet(),
              ),
        child: Text('Seçimi kaydet (${_secilen.length})'),
      ),
    ),
  );
}
