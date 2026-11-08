import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';

import '../models/dbf_belgesi.dart';
import '../models/ortak_import.dart';
import '../services/bireysel_dbf_service.dart';
import '../services/dbf_dosya_service.dart';
import '../services/dbf_kaynak_service.dart';
import 'bireysel_belgelerim_screen.dart';

class BireyselDbfImportScreen extends StatefulWidget {
  const BireyselDbfImportScreen({
    super.key,
    required this.profilId,
    required this.egitimYili,
    required this.dersId,
    required this.dersAdi,
    required this.sinifSeviyesi,
    this.dosyaSec,
    this.kaynakAc,
    this.kaydedinceDon = false,
  });
  final int profilId, dersId, sinifSeviyesi;
  final String egitimYili, dersAdi;
  final Future<DbfBelgesi?> Function(BuildContext)? dosyaSec;
  final Future<void> Function(String)? kaynakAc;
  final bool kaydedinceDon;

  @override
  State<BireyselDbfImportScreen> createState() =>
      _BireyselDbfImportScreenState();
}

class _BireyselDbfImportScreenState extends State<BireyselDbfImportScreen> {
  final _surum = TextEditingController();
  DbfBelgesi? _kayit, _onIzleme;
  String _adres = DbfKaynakService.varsayilanAdres;
  String? _hata;
  bool _islem = true, _onay = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _surum.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    await _calistir(() async {
      final adres = await DbfKaynakService.getir();
      final kayit = await BireyselDbfService.instance.getir(
        profilId: widget.profilId,
        egitimYili: widget.egitimYili,
        dersId: widget.dersId,
        sinifSeviyesi: widget.sinifSeviyesi,
      );
      if (!mounted) return;
      setState(() {
        _adres = adres;
        _kayit = kayit;
        _surum.text = kayit?.programSurumu ?? '';
      });
    });
  }

  Future<void> _calistir(Future<void> Function() f) async {
    setState(() {
      _islem = true;
      _hata = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'İşlem tamamlanamadı.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _adresDegistir() async {
    final controller = TextEditingController(text: _adres);
    final sonuc = await showDialog<String>(
      context: context,
      builder: (context) {
        String? hata;
        return StatefulBuilder(
          builder: (context, yenile) => AlertDialog(
            title: const Text('DBF Kaynak Sayfası'),
            content: TextField(
              controller: controller,
              maxLength: 2048,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'HTTPS adresi',
                errorText: hata,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    controller.text = DbfKaynakService.varsayilanAdres,
                child: const Text('MEB adresini kullan'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    Navigator.pop(
                      context,
                      DbfKaynakService.dogrula(
                        controller.text.trim(),
                      ).toString(),
                    );
                  } catch (e) {
                    yenile(() => hata = e.toString());
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
        );
      },
    );
    // Diyaloğun kapanış animasyonu TextField'i kullanmaya devam edebilir.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (!mounted || sonuc == null) return;
    await _calistir(() async {
      await DbfKaynakService.kaydet(sonuc);
      if (mounted) {
        setState(() {
          _adres = sonuc;
          _onay = false;
        });
      }
    });
  }

  Future<void> _dosyaSec({bool arsivden = false}) => _calistir(() async {
    DbfBelgesi? belge;
    if (arsivden) {
      final dosya = await Navigator.of(context).push<ImportDosya>(
        MaterialPageRoute(
          builder: (_) =>
              const BireyselBelgelerimScreen(secimUzantilari: {'pdf'}),
        ),
      );
      if (dosya != null) {
        belge = await DbfDosyaService.pdfOku(dosya.ad, dosya.bytes);
      }
    } else {
      belge = await (widget.dosyaSec ?? DbfDosyaService.sec)(context);
    }
    if (!mounted || belge == null) return;
    if (belge.sinifSeviyesi != widget.sinifSeviyesi ||
        importNormalize(belge.dersAdi) != importNormalize(widget.dersAdi)) {
      throw StateError(
        'Seçilen DBF: ${belge.dersAdi}, ${belge.sinifSeviyesi}. sınıf. '
        'Bu dosya seçili ders ve sınıfla uyuşmuyor.',
      );
    }
    setState(() {
      _onIzleme = belge;
      _onay = false;
    });
  });

  Future<void> _kaydet() => _calistir(() async {
    if (!_onay || _onIzleme == null) return;
    final kayit = await BireyselDbfService.instance.kaydet(
      profilId: widget.profilId,
      egitimYili: widget.egitimYili,
      dersId: widget.dersId,
      sinifSeviyesi: widget.sinifSeviyesi,
      belge: _onIzleme!,
      beklenenSurum: _kayit?.surum ?? 0,
      kaynakAdresi: _adres,
      programSurumu: _surum.text,
    );
    if (!mounted) return;
    setState(() {
      _kayit = kayit;
      _onIzleme = null;
      _onay = false;
      _islem = false;
    });
    if (widget.kaydedinceDon) {
      // PopScope yeni canPop değerini bir sonraki karede alır.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ders bilgi formu kaydedildi.')),
    );
  });

  @override
  Widget build(BuildContext context) {
    final belge = _onIzleme ?? _kayit;
    return PopScope(
      canPop: !_islem,
      child: OrtakSayfa(
        appBar: const ModulUstBar(title: Text('Ders Bilgi Formu')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.dersAdi,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('${widget.sinifSeviyesi}. Sınıf • ${widget.egitimYili}'),
              if (widget.kaydedinceDon)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Günlük plan için bu dersin Ders Bilgi Formu eksik. '
                    'Dosyayı yükleyip onaylayın; kayıt sonrası günlük plana devam edilecek.'),
                ),
              const SizedBox(height: 16),
              const Text('DBF Kaynak Sayfası'),
              SelectableText(_adres),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _islem
                        ? null
                        : () => _calistir(
                            () => (widget.kaynakAc ?? DbfKaynakService.ac)(
                              _adres,
                            ),
                          ),
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('MEB’den Dosya Bul'),
                  ),
                  TextButton(
                    onPressed: _islem ? null : _adresDegistir,
                    child: const Text('Kaynak Adresini Değiştir'),
                  ),
                ],
              ),
              const Text(
                'Sayfadan dosyayı indirin, ardından bu ekrana dönüp seçin. '
                'Kaynak adresi sonradan değiştirilebilir. Dosya içeriği başka bir sunucuya gönderilmez.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _islem ? null : () => _dosyaSec(),
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Google Drive’dan DBF Seç'),
              ),
              const Text(
                'Açılan dosya seçicide Google Drive konumunu seçin. '
                'Drive hesabınız cihazda kullanılabilir olmalıdır. '
                'Seçilen PDF veya RAR mevcut doğrulama ve ön izleme '
                'adımlarından geçer; onaylamadan kaydedilmez.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _islem ? null : () => _dosyaSec(),
                icon: const Icon(Icons.upload_file),
                label: Text(
                  _kayit == null
                      ? 'İndirilen Dosyayı Yükle'
                      : 'DBF’yi Değiştir',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _islem ? null : () => _dosyaSec(arsivden: true),
                icon: const Icon(Icons.folder_open),
                label: const Text('Belgelerimden PDF Seç'),
              ),
              const Text(
                'Desteklenen: metin içeren MEB DBF PDF’si veya DBF dosyalarının bulunduğu RAR. '
                'Taranmış/görsel PDF’lerde OCR uygulanmaz.',
              ),
              if (_islem)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
              if (_hata != null) ...[
                SelectableText(
                  _hata!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _islem ? null : _yukle,
                  child: const Text('Kaydı yeniden oku'),
                ),
              ],
              if (_kayit != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Kayıtlı DBF: ${_kayit!.dosyaAdi}\n'
                    'Program: ${_kayit!.programSurumu} • Kayıt sürümü: ${_kayit!.surum}\n'
                    'Bu ders ve eğitim yılı için yeniden yüklemeniz gerekmez.',
                  ),
                ),
              if (belge != null) ...[
                Text(
                  _onIzleme == null
                      ? 'Kayıtlı kaynak metni'
                      : 'Ön izleme — henüz kaydedilmedi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${belge.dersAdi} • ${belge.sinifSeviyesi}. sınıf • ${belge.sayfalar.length} sayfa',
                ),
                const Text(
                  'Sayfa metinlerini kontrol edin. Tablo sütunları metin çıkarımında ardışık görünebilir. '
                  'Bu adım DBF kaynağını kaydeder; günlük planlarınızı değiştirmez.',
                ),
                for (var i = 0; i < belge.sayfalar.length; i++)
                  OrtakGenisleyenBolum(
                    key: ValueKey('${belge.icerikOzeti}-$i'),
                    title: Text('Sayfa ${i + 1}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(belge.sayfalar[i]),
                      ),
                    ],
                  ),
              ],
              if (_onIzleme != null) ...[
                TextField(
                  controller: _surum,
                  enabled: !_islem,
                  maxLength: 100,
                  onChanged: (_) => setState(() => _onay = false),
                  decoration: const InputDecoration(
                    labelText: 'Program sürümü / yılı',
                    hintText: 'Belgeden doğruladığınız sürümü yazın (ör. 2026)',
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _onay,
                  onChanged: _islem
                      ? null
                      : (v) => setState(() => _onay = v ?? false),
                  title: Text(
                    _kayit == null
                        ? 'Ders, sınıf, program sürümü ve kaynak metnini kontrol ettim.'
                        : 'Kontrol ettim; bu dersin kayıtlı DBF kaynağının yenisiyle değiştirilmesini onaylıyorum.',
                  ),
                ),
                FilledButton(
                  onPressed: _islem || !_onay || _surum.text.trim().isEmpty
                      ? null
                      : _kaydet,
                  child: const Text('Onayla ve Kaydet'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
