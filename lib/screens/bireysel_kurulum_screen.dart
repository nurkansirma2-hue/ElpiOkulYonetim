import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';

import '../services/bireysel_profil_service.dart';
import 'bireysel_yedekleme_screen.dart';

class BireyselKurulumScreen extends StatefulWidget {
  const BireyselKurulumScreen({
    super.key,
    required this.onTamamlandi,
    this.duzenleme = false,
  });

  final Future<void> Function() onTamamlandi;
  final bool duzenleme;

  @override
  State<BireyselKurulumScreen> createState() => _BireyselKurulumScreenState();
}

class _BireyselKurulumScreenState extends State<BireyselKurulumScreen> {
  final TextEditingController _adSoyadController = TextEditingController();
  final TextEditingController _bransController = TextEditingController();
  final TextEditingController _okulAdiController = TextEditingController();
  final TextEditingController _okulKisaAdiController = TextEditingController();
  final TextEditingController _egitimOgretimYiliController =
      TextEditingController();

  int? _donem;
  bool? _meslekPaketiAktif;
  bool _profilYuklendi = false;
  bool _yukleniyor = true;
  bool _kaydediliyor = false;

  @override
  void initState() {
    super.initState();
    _profiliYukle();
  }

  @override
  void dispose() {
    _adSoyadController.dispose();
    _bransController.dispose();
    _okulAdiController.dispose();
    _okulKisaAdiController.dispose();
    _egitimOgretimYiliController.dispose();
    super.dispose();
  }

  String _varsayilanEgitimOgretimYili() {
    final simdi = DateTime.now();

    if (simdi.month >= 7) {
      return '${simdi.year}-${simdi.year + 1}';
    }

    return '${simdi.year - 1}-${simdi.year}';
  }

  Future<void> _profiliYukle() async {
    try {
      final profil = await BireyselProfilService.getir();
      final okul = await BireyselProfilService.okulProfiliniGetir();
      final meslekPaketiAktif =
          await BireyselProfilService.meslekPaketiTercihiniGetir();

      if (!mounted) {
        return;
      }

      if (profil != null) {
        _adSoyadController.text = (profil['AdSoyad'] ?? '').toString();
        _bransController.text = (profil['Brans'] ?? '').toString();
        _okulAdiController.text = (profil['OkulAdi'] ?? '').toString();
        _egitimOgretimYiliController.text = (profil['EgitimOgretimYili'] ?? '')
            .toString();
      } else {
        _adSoyadController.clear();
        _bransController.clear();
        _okulAdiController.clear();
        _egitimOgretimYiliController.text = _varsayilanEgitimOgretimYili();
      }

      if (okul != null) {
        _okulAdiController.text = (okul['OkulAdi'] ?? '').toString();
        _okulKisaAdiController.text = (okul['OkulKisaAdi'] ?? '').toString();
        _egitimOgretimYiliController.text = (okul['EgitimYili'] ?? '')
            .toString();
        final donem = okul['Donem'];
        _donem = donem == 1 || donem == 2 ? donem as int : null;
      }
      if (okul == null) {
        _okulKisaAdiController.clear();
        _donem = null;
      }
      _meslekPaketiAktif = meslekPaketiAktif;
      _profilYuklendi = true;
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bireysel öğretmen profili yüklenirken hata oluştu.\n'
            'Orijinal hata: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _yukleniyor = false;
        });
      }
    }
  }

  Future<void> _kaydet() async {
    if (_yukleniyor || !_profilYuklendi || _kaydediliyor) {
      return;
    }

    final adSoyad = _adSoyadController.text.trim();
    final brans = _bransController.text.trim();
    final okulAdi = _okulAdiController.text.trim();
    final okulKisaAdi = _okulKisaAdiController.text.trim();
    final donem = _donem;
    final meslekPaketiAktif = _meslekPaketiAktif;
    final egitimOgretimYili = _egitimOgretimYiliController.text.trim();

    if (adSoyad.isEmpty) {
      _mesajGoster('Ad Soyad boş bırakılamaz.');
      return;
    }

    if (brans.isEmpty) {
      _mesajGoster('Branş boş bırakılamaz.');
      return;
    }

    if (okulAdi.isEmpty) {
      _mesajGoster('Okul Adı boş bırakılamaz.');
      return;
    }

    if (okulKisaAdi.isEmpty) {
      _mesajGoster('Okul Kısa Adı boş bırakılamaz.');
      return;
    }

    if (donem == null || (donem != 1 && donem != 2)) {
      _mesajGoster('Lütfen 1. veya 2. dönemi seçin.');
      return;
    }

    if (egitimOgretimYili.isEmpty) {
      _mesajGoster('Eğitim Öğretim Yılı boş bırakılamaz.');
      return;
    }

    if (meslekPaketiAktif == null) {
      _mesajGoster('Lütfen meslek paketi için Evet veya Hayır seçin.');
      return;
    }

    setState(() {
      _kaydediliyor = true;
    });

    try {
      await BireyselProfilService.kaydet(
        adSoyad: adSoyad,
        brans: brans,
        okulAdi: okulAdi,
        okulKisaAdi: okulKisaAdi,
        egitimOgretimYili: egitimOgretimYili,
        donem: donem,
        meslekPaketiAktif: meslekPaketiAktif,
      );

      if (!mounted) {
        return;
      }

      await widget.onTamamlandi();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _mesajGoster(
        'Bireysel öğretmen profili kaydedilirken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _kaydediliyor = false;
        });
      }
    }
  }

  void _mesajGoster(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj)));
  }

  @override
  Widget build(BuildContext context) {
    return OrtakSayfa(
      appBar: ModulUstBar(
        title: Text(
          widget.duzenleme ? 'Profilim' : 'Bireysel Öğretmen Kurulumu',
        ),
        centerTitle: true,
        automaticallyImplyLeading: widget.duzenleme,
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 72,
                        color: Colors.indigo,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Öğretmen Bilgileri',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bu bilgiler yalnızca bireysel öğretmen modunda '
                        'kullanılacaktır.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _yukleniyor || _kaydediliyor
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BireyselYedeklemeScreen(
                                    onGeriYuklendi: () async {
                                      if (await BireyselProfilService.profilBilgileriTamMi()) {
                                        await widget.onTamamlandi();
                                      } else {
                                        await _profiliYukle();
                                      }
                                    },
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.restore),
                        label: const Text('Mevcut Yedeğimi Geri Yükle'),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _adSoyadController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Ad Soyad *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _bransController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Branş *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.menu_book_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _okulAdiController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Okul Adı *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _okulKisaAdiController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Okul Kısa Adı *',
                          hintText: 'DTMTAL',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.short_text),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _egitimOgretimYiliController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_kaydediliyor) {
                            _kaydet();
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Eğitim Öğretim Yılı *',
                          hintText: '2026-2027',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        initialValue: _donem,
                        decoration: const InputDecoration(
                          labelText: 'Dönem *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.date_range_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1. Dönem')),
                          DropdownMenuItem(value: 2, child: Text('2. Dönem')),
                        ],
                        onChanged: _kaydediliyor
                            ? null
                            : (deger) => setState(() => _donem = deger),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<bool>(
                        initialValue: _meslekPaketiAktif,
                        decoration: const InputDecoration(
                          labelText: 'Meslek paketi yüklensin mi? *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.work_outline),
                        ),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('Evet')),
                          DropdownMenuItem(value: false, child: Text('Hayır')),
                        ],
                        onChanged: _kaydediliyor
                            ? null
                            : (deger) =>
                                  setState(() => _meslekPaketiAktif = deger),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _kaydediliyor || !_profilYuklendi
                              ? null
                              : _kaydet,
                          icon: _kaydediliyor
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward),
                          label: Text(
                            _kaydediliyor
                                ? 'Kaydediliyor...'
                                : widget.duzenleme
                                ? 'Kaydet'
                                : 'Devam Et',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
