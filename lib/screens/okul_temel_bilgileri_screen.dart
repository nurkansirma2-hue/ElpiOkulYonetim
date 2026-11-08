import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';

import '../core/calisma_modu.dart';
import '../models/okul_bilgi_model.dart';
import '../services/bireysel_okul_bilgi_service.dart';
import '../services/calisma_modu_service.dart';

class OkulTemelBilgileriScreen extends StatefulWidget {
  const OkulTemelBilgileriScreen({super.key});

  @override
  State<OkulTemelBilgileriScreen> createState() =>
      _OkulTemelBilgileriScreenState();
}

class _OkulTemelBilgileriScreenState extends State<OkulTemelBilgileriScreen> {
  final _formKey = GlobalKey<FormState>();
  final _alanlar = <String, TextEditingController>{
    for (final ad in [
      'okulAdi',
      'mudurAdi',
      'mudurYardimcilari',
      'telefon',
      'email',
      'webSitesi',
      'adres',
      'konum',
    ])
      ad: TextEditingController(),
  };
  Map<String, String> _ilkDegerler = {};
  OkulBilgiModel? _okul;
  BireyselOkulBilgiOturumu? _bireyselOturum;
  bool _yukleniyor = true;
  bool _kaydediliyor = false;
  bool _cikisSoruluyor = false;
  bool _cikisaIzinVer = false;
  String? _hata;
  String? _kayitHatasi;

  bool get _kirli =>
      _ilkDegerler.isNotEmpty &&
      _alanlar.entries.any(
        (alan) => alan.value.text.trim() != _ilkDegerler[alan.key],
      );

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    for (final controller in _alanlar.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _moduDogrula() async {
    const beklenen = CalismaModu.bireyselOgretmen;
    if (await CalismaModuService.getir() != beklenen) {
      throw StateError(
        'Çalışma modu değişti. Okul Bilgileri ekranını yeniden açın.',
      );
    }
  }

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      await _moduDogrula();
      final oturum = await BireyselOkulBilgiService.getir();
      _bireyselOturum = oturum;
      final okul = oturum.okul;
      await _moduDogrula();
      if (!mounted) return;
      final veriler = okul.toMap();
      for (final alan in _alanlar.entries) {
        alan.value.text = (veriler[alan.key] ?? '').toString();
      }
      setState(() {
        _okul = okul;
        _ilkDegerler = {
          for (final alan in _alanlar.entries) alan.key: alan.value.text.trim(),
        };
        _kayitHatasi = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hata = 'Okul bilgileri yüklenemedi.\nOrijinal hata: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  OkulBilgiModel _duzenlenmisModel(OkulBilgiModel temel) => temel.copyWith(
    okulAdi: _alanlar['okulAdi']!.text.trim(),
    mudurAdi: _alanlar['mudurAdi']!.text.trim(),
    mudurYardimcilari: _alanlar['mudurYardimcilari']!.text.trim(),
    telefon: _alanlar['telefon']!.text.trim(),
    email: _alanlar['email']!.text.trim(),
    webSitesi: _alanlar['webSitesi']!.text.trim(),
    adres: _alanlar['adres']!.text.trim(),
    konum: _alanlar['konum']!.text.trim(),
  );

  Future<void> _kaydet() async {
    if (_kaydediliyor || _okul == null) return;
    final gecersizAlanlar = _formKey.currentState!.validateGranularly();
    if (gecersizAlanlar.isNotEmpty) {
      await Scrollable.ensureVisible(
        gecersizAlanlar.first.context,
        duration: const Duration(milliseconds: 200),
        alignment: 0.1,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _kaydediliyor = true;
      _kayitHatasi = null;
    });
    try {
      await _moduDogrula();
      await BireyselOkulBilgiService.kaydet(
        _bireyselOturum!,
        _duzenlenmisModel(_okul!),
      );
      if (!mounted) return;
      setState(() {
        _ilkDegerler = {
          for (final alan in _alanlar.entries) alan.key: alan.value.text.trim(),
        };
        _kaydediliyor = false;
        _cikisaIzinVer = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Okul bilgileri kaydedildi.')),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        _cikisaIzinVer = false;
        await _yukle();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _kayitHatasi = 'Okul bilgileri kaydedilemedi.\nOrijinal hata: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  Future<void> _geriDon() async {
    if (_kaydediliyor || _cikisSoruluyor || !_kirli) return;
    _cikisSoruluyor = true;
    final cik = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Değişiklikler kaydedilmedi'),
        content: const Text(
          'Girdiğiniz değişiklikleri kaydetmeden çıkılsın mı?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Düzenlemeye Dön'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaydetmeden Çık'),
          ),
        ],
      ),
    );
    _cikisSoruluyor = false;
    if (!mounted || cik != true) return;
    setState(() => _cikisaIzinVer = true);
    Navigator.of(context).pop();
  }

  String? _baglantiDogrula(String? value) {
    final metin = value?.trim() ?? '';
    if (metin.isEmpty) return null;
    final uri = Uri.tryParse(metin.contains('://') ? metin : 'https://$metin');
    if (RegExp(r'\s').hasMatch(metin) ||
        uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        !uri.host.contains('.') ||
        uri.host.startsWith('.') ||
        uri.host.endsWith('.') ||
        uri.host.contains('..') ||
        uri.userInfo.isNotEmpty) {
      return 'Geçerli bir web veya harita bağlantısı girin.';
    }
    return null;
  }

  Widget _alan(
    String ad,
    String etiket, {
    int? maxLength,
    int maxLines = 1,
    TextInputType? klavye,
    String? yardim,
    String? Function(String?)? dogrula,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('okul_$ad'),
      controller: _alanlar[ad],
      enabled: !_kaydediliyor,
      maxLength: maxLength,
      minLines: maxLines > 1 ? 2 : 1,
      maxLines: maxLines,
      keyboardType: klavye,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      decoration: InputDecoration(
        labelText: etiket,
        border: const OutlineInputBorder(),
        helperText: yardim,
        helperMaxLines: 3,
        errorMaxLines: 3,
        counterText: '',
      ),
      validator: dogrula,
      onChanged: (_) => setState(() => _kayitHatasi = null),
    ),
  );

  Widget _bolum(String baslik) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 16),
    child: Text(baslik, style: Theme.of(context).textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_kaydediliyor && (_cikisaIzinVer || !_kirli),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _geriDon();
    },
    child: OrtakSayfa(
      appBar: const ModulUstBar(title: Text('Okul Bilgileri')),
      body: SafeArea(
        child: _yukleniyor
            ? const Center(child: CircularProgressIndicator())
            : _hata != null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_hata!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _yukle,
                        child: const Text('Tekrar Dene'),
                      ),
                    ],
                  ),
                ),
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Okul adı zorunludur. Diğer bilgileri daha sonra tamamlayabilirsiniz.',
                          ),
                          _bolum('Okul ve Yönetim'),
                          _alan(
                            'okulAdi',
                            'Okul Adı',
                            maxLength: 200,
                            dogrula: (v) => (v?.trim().isEmpty ?? true)
                                ? 'Okul adı zorunludur.'
                                : null,
                          ),
                          _alan('mudurAdi', 'Okul Müdürü', maxLength: 160),
                          _alan(
                            'mudurYardimcilari',
                            'Müdür Yardımcıları',
                            maxLength: 1000,
                            maxLines: 4,
                            yardim:
                                'Her müdür yardımcısını ayrı satıra yazabilirsiniz.',
                          ),
                          _bolum('İletişim ve Adres'),
                          _alan(
                            'telefon',
                            'Telefon',
                            maxLength: 50,
                            klavye: TextInputType.phone,
                          ),
                          _alan(
                            'email',
                            'E-posta',
                            maxLength: 254,
                            klavye: TextInputType.emailAddress,
                            dogrula: (v) =>
                                (v?.trim().isEmpty ?? true) ||
                                    RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(v!.trim())
                                ? null
                                : 'Geçerli bir e-posta adresi girin.',
                          ),
                          _alan(
                            'webSitesi',
                            'Web Sitesi',
                            maxLength: 2048,
                            klavye: TextInputType.url,
                            dogrula: _baglantiDogrula,
                          ),
                          _alan(
                            'adres',
                            'Adres',
                            maxLength: 2000,
                            maxLines: 4,
                            klavye: TextInputType.streetAddress,
                          ),
                          _alan(
                            'konum',
                            'Konum / Harita Bağlantısı',
                            maxLength: 2048,
                            klavye: TextInputType.url,
                            dogrula: _baglantiDogrula,
                          ),
                          if (_kayitHatasi != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                _kayitHatasi!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          FilledButton.icon(
                            onPressed: _kaydediliyor ? null : _kaydet,
                            icon: _kaydediliyor
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              _kaydediliyor ? 'Kaydediliyor...' : 'Kaydet',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
