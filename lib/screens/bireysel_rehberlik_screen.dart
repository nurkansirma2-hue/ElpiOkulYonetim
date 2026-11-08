import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import '../widgets/ana_sayfa_gorunumu.dart';
import '../services/bireysel_rehberlik_service.dart';
import 'bireysel_rehberlik_ogrencileri_screen.dart';
import 'bireysel_rehberlik_dosyasi_screen.dart';

String _iso(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
String _tarihYazi(String t) => t.split('-').reversed.join('.');

class BireyselRehberlikScreen extends StatefulWidget {
  const BireyselRehberlikScreen({super.key, this.service, this.yonetimModu = false});
  final BireyselRehberlikService? service;
  final bool yonetimModu;
  @override
  State<BireyselRehberlikScreen> createState() =>
      _BireyselRehberlikScreenState();
}

class _BireyselRehberlikScreenState extends State<BireyselRehberlikScreen> {
  late final _service = widget.service ?? BireyselRehberlikService.instance;
  BireyselRehberlikBaglami? _baglam;
  List<Map<String, Object?>> _siniflar = [], _atamalar = [];
  bool _yukleniyor = true, _islem = false;
  String? _hata;
  String? _yil;
  List<String> _yillar = [];
  final _gorunum = OrtakGorunumTercihi.instance;

  @override
  void initState() {
    super.initState();
    _gorunum.addListener(_yenileGorunum);
    _gorunum.yukle();
    _yukle();
  }

  void _yenileGorunum() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gorunum.removeListener(_yenileGorunum);
    super.dispose();
  }

  Future<void> _dosyaAc(Map<String, Object?> atama) async {
    if (_baglam == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BireyselRehberlikDosyasiScreen(
          service: _service,
          baglam: _baglam!,
          atama: atama,
          atamaYonetimiAc: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => BireyselRehberlikScreen(
                service: _service,
                yonetimModu: true,
              ),
            ));
          },
        ),
      ),
    );
    if (mounted) await _yukle();
  }

  Future<void> _kurulumBaslat() async {
    if (_islem || _baglam == null) return;
    final devam = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rehberlik dosyam • İlk kurulum'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1/3 • Rehberlik yapacağınız sınıfı ve görev tarihlerini seçin.'),
              SizedBox(height: 12),
              Text('2/3 • Mevcut öğrencileri ve veli bilgilerini dosyanızda kontrol edin. Eksik kayıtları mevcut öğrenci Import ekranından tamamlayabilirsiniz.'),
              SizedBox(height: 12),
              Text('3/3 • Rehberlik Planım bölümünden yıllık planınızı Import ile yükleyebilirsiniz. Belgeler hazır değilse daha sonra tamamlayabilirsiniz.'),
              SizedBox(height: 12),
              Text('Mevcut öğrenciler, belgeler ve geçmiş yıllardaki atamalar silinmez.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sınıfı seç')),
        ],
      ),
    );
    if (devam == true && mounted) await _ekle(ilkKurulum: true);
  }

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final b = await _service.hazirla();
      final siniflar = await _service.siniflariGetir(b);
      final yillar = await _service.atamaYillari(b);
      final yil = yillar.contains(_yil) ? _yil! : b.egitimOgretimYili;
      final atamalar = await _service.atamalariGetir(b, egitimOgretimYili: yil);
      if (!mounted) return;
      setState(() {
        _baglam = b;
        _siniflar = siniflar;
        _atamalar = atamalar;
        _yillar = yillar;
        _yil = yil;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _baglam = null;
          _hata = 'Atamalar okunamadı.\nOrijinal hata: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _mesaj(String mesaj) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mesaj)));
    }
  }

  Future<void> _ekle({bool ilkKurulum = false}) async {
    if (_islem || _baglam == null || _siniflar.isEmpty) return;
    final b = _baglam!;
    setState(() => _islem = true);
    try {
      final secim = await showDialog<_AtamaSecimi>(
        context: context,
        builder: (_) =>
            _AtamaFormu(siniflar: _siniflar, yil: b.egitimOgretimYili),
      );
      if (secim == null || !mounted) return;
      final yeniAtamaId = await _service.atamaKaydet(
        b,
        sinifSubeId: secim.sinifId,
        baslangicTarihi: _iso(secim.baslangic),
        bitisTarihi: secim.bitis == null ? null : _iso(secim.bitis!),
      );
      if (!mounted) return;
      await _yukle();
      _mesaj('Rehberlik ataması kaydedildi.');
      if (ilkKurulum && mounted) {
        final yeni = _atamalar.where((a) => a['RehberlikAtamaId'] == yeniAtamaId);
        if (yeni.isNotEmpty) {
          await _dosyaAc(yeni.first);
        }
      }
    } catch (e) {
      _mesaj('Atama kaydedilemedi.\nOrijinal hata: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _sonlandir(Map<String, Object?> atama) async {
    if (_islem || _baglam == null) return;
    final b = _baglam!;
    setState(() => _islem = true);
    try {
      final baslangic = DateTime.parse(atama['BaslangicTarihi'] as String);
      final simdi = DateUtils.dateOnly(DateTime.now());
      final bitis = await showDatePicker(
        context: context,
        initialDate: simdi.isBefore(baslangic) ? baslangic : simdi,
        firstDate: baslangic,
        lastDate: DateTime(9999, 12, 31),
        helpText: 'Atamanın bitiş tarihini seçin',
        cancelText: 'İptal',
        confirmText: 'Seç',
      );
      if (bitis == null || !mounted) return;
      final onay = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Atamayı sonlandır'),
          content: SingleChildScrollView(
            child: Text(
              '${atama['SinifKodu']} sınıfındaki atamanız ${_tarihYazi(_iso(bitis))} tarihinde sona erecek. Bitiş günü dahildir; kayıt geçmişte korunur.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sonlandır'),
            ),
          ],
        ),
      );
      if (onay != true || !mounted) return;
      await _service.atamayiSonlandir(
        b,
        atamaId: atama['RehberlikAtamaId'] as int,
        bitisTarihi: _iso(bitis),
      );
      if (!mounted) return;
      await _yukle();
      _mesaj('Atamanın bitiş tarihi kaydedildi.');
    } catch (e) {
      _mesaj('Atama sonlandırılamadı.\nOrijinal hata: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.yonetimModu &&
        !_yukleniyor &&
        _hata == null &&
        _baglam != null &&
        _atamalar.length == 1) {
      return BireyselRehberlikDosyasiScreen(
        service: _service,
        baglam: _baglam!,
        atama: _atamalar.single,
        atamaYonetimiAc: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => BireyselRehberlikScreen(
              service: _service,
              yonetimModu: true,
            ),
          ));
          if (mounted) await _yukle();
        },
      );
    }
    return PopScope(
    canPop: !_islem,
    child: OrtakSayfa(
      appBar: ModulUstBar(
        title: Text(widget.yonetimModu ? 'Rehberlik atamalarım' : 'Sınıf Rehberliğim'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _islem || _yukleniyor ? null : _yukle,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _yukleniyor
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_hata != null) ...[
                    Text(_hata!),
                    TextButton(
                      onPressed: _islem ? null : _yukle,
                      child: const Text('Yeniden dene'),
                    ),
                  ] else ...[
                    Text(
                      _baglam!.okulAdi,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${_baglam!.ogretmenAdi} • ${_baglam!.egitimOgretimYili}',
                    ),
                    const SizedBox(height: 12),
                    if (!widget.yonetimModu) AnaMenuYerlesimi(
                      kompakt: _gorunum.kompakt,
                      children: [
                        AnaMenuKart(
                          icon: Icons.folder_open_outlined,
                          baslik: 'Rehberlik Dosyam',
                          onTap: () {
                            if (_islem) return;
                            if (_atamalar.length == 1) {
                              _dosyaAc(_atamalar.first);
                            } else if (_atamalar.isEmpty &&
                                _yil == _baglam!.egitimOgretimYili) {
                              _kurulumBaslat();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Aşağıdaki atamalardan açmak istediğiniz sınıfı seçin.')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    if (!widget.yonetimModu && _atamalar.isEmpty &&
                        _yil == _baglam!.egitimOgretimYili)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_siniflar.isEmpty
                            ? 'İlk kurulum için önce güncel ders programınıza sınıf ekleyin.'
                            : 'Henüz rehberlik atamanız yok. Rehberlik Dosyam kartından ilk kurulumu başlatın.'),
                      ),
                    if (widget.yonetimModu) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_yil),
                      initialValue: _yil,
                      decoration: const InputDecoration(
                        labelText: 'Atama eğitim yılı / geçmiş',
                      ),
                      items: [
                        for (final yil in _yillar)
                          DropdownMenuItem(value: yil, child: Text(yil)),
                      ],
                      onChanged: _islem
                          ? null
                          : (v) {
                              _yil = v;
                              _yukle();
                            },
                    ),
                    const Text(
                      'Rehberlik atamalarım',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_siniflar.isEmpty)
                      const Text(
                        'Yeni atama için güncel ders programınızda bir sınıf bulunmalı. Mevcut atamalarınız aşağıda korunur.',
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed:
                            _islem ||
                                _siniflar.isEmpty ||
                                _yil != _baglam!.egitimOgretimYili
                            ? null
                            : _ekle,
                        icon: const Icon(Icons.add),
                        label: const Text('Yeni atama'),
                      ),
                    ),
                    if (_atamalar.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text(
                          'Bu eğitim yılında rehberlik atamanız bulunmuyor.',
                        ),
                      ),
                    for (final a in _atamalar)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a['SinifKodu'] as String,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'Başlangıç: ${_tarihYazi(a['BaslangicTarihi'] as String)}',
                              ),
                              Text(
                                a['BitisTarihi'] == null
                                    ? 'Bitiş tarihi belirlenmedi'
                                    : 'Bitiş: ${_tarihYazi(a['BitisTarihi'] as String)}',
                              ),
                              FilledButton.icon(
                                onPressed: _islem
                                    ? null
                                    : () => _dosyaAc(a),
                                icon: const Icon(Icons.folder_open),
                                label: const Text('Rehberlik dosyam'),
                              ),
                              TextButton.icon(
                                onPressed: _islem
                                    ? null
                                    : () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                BireyselRehberlikOgrencileriScreen(
                                                  service: _service,
                                                  baglam: _baglam!,
                                                  atamaId:
                                                      a['RehberlikAtamaId']
                                                          as int,
                                                  sinifKodu:
                                                      a['SinifKodu'] as String,
                                                ),
                                          ),
                                        );
                                        if (mounted) await _yukle();
                                      },
                                icon: const Icon(Icons.people_outline),
                                label: const Text('Öğrencilerim'),
                              ),
                              if (a['BitisTarihi'] == null &&
                                  _yil == _baglam!.egitimOgretimYili)
                                TextButton.icon(
                                  onPressed: _islem
                                      ? null
                                      : () => _sonlandir(a),
                                  icon: const Icon(Icons.event_busy),
                                  label: const Text('Atamayı sonlandır'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
      ),
    ),
  );
  }
}

class _AtamaSecimi {
  const _AtamaSecimi(this.sinifId, this.baslangic, this.bitis);
  final int sinifId;
  final DateTime baslangic;
  final DateTime? bitis;
}

class _AtamaFormu extends StatefulWidget {
  const _AtamaFormu({required this.siniflar, required this.yil});
  final List<Map<String, Object?>> siniflar;
  final String yil;
  @override
  State<_AtamaFormu> createState() => _AtamaFormuState();
}

class _AtamaFormuState extends State<_AtamaFormu> {
  final _form = GlobalKey<FormState>();
  int? _sinif;
  bool _gonderildi = false;
  DateTime _baslangic = DateUtils.dateOnly(DateTime.now());
  DateTime? _bitis;
  Future<void> _tarihSec(bool baslangic) async {
    final tarih = await showDatePicker(
      context: context,
      initialDate: baslangic ? _baslangic : (_bitis ?? _baslangic),
      firstDate: baslangic ? DateTime(1) : _baslangic,
      lastDate: DateTime(9999, 12, 31),
      helpText: baslangic ? 'Başlangıç tarihini seçin' : 'Bitiş tarihini seçin',
      cancelText: 'İptal',
      confirmText: 'Seç',
    );
    if (tarih == null || !mounted) return;
    setState(() {
      if (baslangic) {
        _baslangic = tarih;
        if (_bitis != null && _bitis!.isBefore(tarih)) _bitis = null;
      } else {
        _bitis = tarih;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Yeni rehberlik ataması'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Eğitim yılı: ${widget.yil}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sınıf'),
              items: widget.siniflar
                  .map(
                    (s) => DropdownMenuItem<int>(
                      value: s['SinifSubeId'] as int,
                      child: Text(
                        s['SinifKodu'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _sinif = v),
              validator: (v) => v == null ? 'Sınıf seçin.' : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _tarihSec(true),
              child: Text('Başlangıç: ${_tarihYazi(_iso(_baslangic))}'),
            ),
            OutlinedButton(
              onPressed: () => _tarihSec(false),
              child: Text(
                _bitis == null
                    ? 'Bitiş tarihi seç (isteğe bağlı)'
                    : 'Bitiş: ${_tarihYazi(_iso(_bitis!))}',
              ),
            ),
            if (_bitis != null)
              TextButton(
                onPressed: () => setState(() => _bitis = null),
                child: const Text('Bitiş tarihini kaldır'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('İptal'),
      ),
      FilledButton(
        onPressed: _gonderildi
            ? null
            : () {
                if (_form.currentState!.validate()) {
                  setState(() => _gonderildi = true);
                  Navigator.pop(
                    context,
                    _AtamaSecimi(_sinif!, _baslangic, _bitis),
                  );
                }
              },
        child: const Text('Kaydet'),
      ),
    ],
  );
}
