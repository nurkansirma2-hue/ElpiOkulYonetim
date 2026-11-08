import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/bireysel_gunluk_plan.dart';
import '../services/belge_disari_aktar_service.dart';
import 'bireysel_dbf_import_screen.dart';
import 'bireysel_yillik_plan_import_screen.dart';
import '../services/bireysel_gunluk_plan_service.dart';
import '../services/bireysel_gunluk_plan_belge_service.dart';

class BireyselGunlukPlanScreen extends StatefulWidget {
  const BireyselGunlukPlanScreen({
    super.key,
    required this.ogretmenProfilId,
    required this.egitimOgretimYili,
    required this.dersId,
    required this.dersAdi,
    required this.sinifSeviyesi,
    required this.tarih,
    this.baslangicSinifKodu = '',
  });

  final int ogretmenProfilId, dersId, sinifSeviyesi;
  final String egitimOgretimYili, dersAdi, baslangicSinifKodu;
  final DateTime tarih;

  @override
  State<BireyselGunlukPlanScreen> createState() =>
      _BireyselGunlukPlanScreenState();
}

class _BireyselGunlukPlanScreenState extends State<BireyselGunlukPlanScreen> {
  static const _alanlar = <String, String>{
    'unite': 'Ünite / tema',
    'konu': 'Konu',
    'kazanimAciklamasi': 'Kazanım açıklaması',
    'aciklamalar': 'Açıklamalar',
    'kazanim': 'Kazanım',
    'ogrenmeCiktisi': 'Öğrenme çıktısı',
    'yontemTeknik': 'Yöntem ve teknik',
    'aracGerec': 'Araç ve gereç',
    'degerlendirme': 'Değerlendirme',
    'dersinIslenisi': 'Dersin işlenişi',
    'etkinlikler': 'Etkinlikler',
  };
  int _istek = 0;
  final _form = GlobalKey<FormState>();
  late final _metinler = {
    for (final alan in _alanlar.keys) alan: TextEditingController(),
  };
  List<GunlukPlanSinifSecenegi> _siniflar = const [];
  BireyselGunlukPlan? _plan;
  int? _seciliSinifId;
  String? _hata;
  bool _yukleniyor = true, _islem = false, _degisti = false;
  bool _metinYukleniyor = false, _cikisaIzin = false, _soruAcik = false;

  @override
  void initState() {
    super.initState();
    for (final controller in _metinler.values) {
      controller.addListener(_metinDegisti);
    }
    _yukle();
  }

  @override
  void didUpdateWidget(covariant BireyselGunlukPlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dersId != widget.dersId ||
        oldWidget.sinifSeviyesi != widget.sinifSeviyesi ||
        oldWidget.baslangicSinifKodu != widget.baslangicSinifKodu ||
        oldWidget.ogretmenProfilId != widget.ogretmenProfilId ||
        oldWidget.egitimOgretimYili != widget.egitimOgretimYili ||
        oldWidget.tarih != widget.tarih) {
      _istek++;
      _plan = null;
      _seciliSinifId = null;
      _degisti = false;
      _yukle();
    }
  }

  @override
  void dispose() {
    for (final controller in _metinler.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _tarihYaz(DateTime tarih) =>
      '${tarih.day.toString().padLeft(2, '0')}.'
      '${tarih.month.toString().padLeft(2, '0')}.${tarih.year}';

  Map<String, String> _planMetinleri(BireyselGunlukPlan plan) => {
    'unite': plan.unite,
    'kazanimAciklamasi': plan.kazanimAciklamasi,
    'aciklamalar': plan.aciklamalar,
    'konu': plan.konu,
    'kazanim': plan.kazanim,
    'ogrenmeCiktisi': plan.ogrenmeCiktisi,
    'yontemTeknik': plan.yontemTeknik,
    'aracGerec': plan.aracGerec,
    'degerlendirme': plan.degerlendirme,
    'dersinIslenisi': plan.dersinIslenisi,
    'etkinlikler': plan.etkinlikler,
  };

  void _metinDegisti() {
    if (_metinYukleniyor || !mounted || _plan == null) return;
    final ilk = _planMetinleri(_plan!);
    final degisti = _metinler.entries.any((e) => e.value.text != ilk[e.key]);
    if (_degisti != degisti) setState(() => _degisti = degisti);
  }

  void _planiGoster(BireyselGunlukPlan plan) {
    _metinYukleniyor = true;
    final metinler = _planMetinleri(plan);
    for (final alan in _metinler.entries) {
      alan.value.text = metinler[alan.key]!;
    }
    _metinYukleniyor = false;
    setState(() {
      _plan = plan;
      _seciliSinifId = plan.sinifSubeId;
      _degisti = false;
      _hata = null;
    });
  }

  Future<void> _yukle() async {
    final istek = ++_istek;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final siniflar = await BireyselGunlukPlanService.siniflariGetir(
        ogretmenProfilId: widget.ogretmenProfilId,
        egitimOgretimYili: widget.egitimOgretimYili,
        dersId: widget.dersId,
        sinifSeviyesi: widget.sinifSeviyesi,
      );
      if (!mounted || istek != _istek) return;
      if (siniflar.isEmpty) {
        throw StateError(
          'Bu ders ve sınıf seviyesi için ders verdiğiniz şube bulunamadı.',
        );
      }
      int? sinifId = _seciliSinifId;
      if (!siniflar.any((sinif) => sinif.sinifSubeId == sinifId)) {
        sinifId = null;
      }
      if (sinifId == null && widget.baslangicSinifKodu.trim().isNotEmpty) {
        final eslesen = siniflar.where(
          (s) => s.sinifKodu == widget.baslangicSinifKodu.trim(),
        );
        if (eslesen.length != 1) {
          throw StateError(
            'Seçilen şube öğretmenin ders kapsamında bulunamadı.',
          );
        }
        sinifId = eslesen.single.sinifSubeId;
      }
      if (sinifId == null && siniflar.length == 1) {
        sinifId = siniflar.single.sinifSubeId;
      }
      setState(() {
        _siniflar = siniflar;
        _seciliSinifId = sinifId;
      });
      if (sinifId != null) await _taslagiGetir(sinifId);
    } catch (e) {
      if (mounted && istek == _istek) {
        setState(() => _hata = 'Günlük plan hazırlanamadı.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted && istek == _istek) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _taslagiGetir(int sinifId) async {
    final istek = _istek;
    final plan = await BireyselGunlukPlanService.hazirla(
      ogretmenProfilId: widget.ogretmenProfilId,
      egitimOgretimYili: widget.egitimOgretimYili,
      dersId: widget.dersId,
      sinifSeviyesi: widget.sinifSeviyesi,
      sinifSubeId: sinifId,
      tarih: widget.tarih,
    );
    if (!mounted || istek != _istek) return;
    if (plan.id == null) {
      final kayit = await BireyselGunlukPlanService.kaydet(plan);
      if (!mounted || istek != _istek) return;
      _planiGoster(kayit);
    } else {
      _planiGoster(plan);
    }
  }

  BireyselGunlukPlan _formdakiPlan() => _plan!.copyWith(
    unite: _metinler['unite']!.text,
    kazanimAciklamasi: _metinler['kazanimAciklamasi']!.text,
    aciklamalar: _metinler['aciklamalar']!.text,
    konu: _metinler['konu']!.text,
    kazanim: _metinler['kazanim']!.text,
    ogrenmeCiktisi: _metinler['ogrenmeCiktisi']!.text,
    yontemTeknik: _metinler['yontemTeknik']!.text,
    aracGerec: _metinler['aracGerec']!.text,
    degerlendirme: _metinler['degerlendirme']!.text,
    dersinIslenisi: _metinler['dersinIslenisi']!.text,
    etkinlikler: _metinler['etkinlikler']!.text,
  );

  Future<BireyselGunlukPlan> _formuKaydet() async {
    if (_plan == null || !(_form.currentState?.validate() ?? false)) {
      throw const FormatException('Plan alanlarını kontrol edin.');
    }
    final istek = _istek;
    final kayit = await BireyselGunlukPlanService.kaydet(_formdakiPlan());
    if (mounted && istek == _istek) _planiGoster(kayit);
    return kayit;
  }

  void _mesaj(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj)));
  }

  Future<bool> _calistir(Future<void> Function() islem) async {
    if (_islem) return false;
    setState(() => _islem = true);
    final istek = _istek;
    try {
      await islem();
      return true;
    } catch (e) {
      if (mounted && istek == _istek) {
        _mesaj('İşlem tamamlanamadı.\nOrijinal hata: $e');
      }
      return false;
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _kaydet() => _calistir(() async {
    await _formuKaydet();
    if (mounted) _mesaj('Günlük plan kaydedildi.');
  });

  Future<void> _pdfOnIzle() => _calistir(() async {
    final istek = _istek;
    if (!(_form.currentState?.validate() ?? false)) return;
    final plan = _formdakiPlan();
    final bytes = await BireyselGunlukPlanBelgeService.pdfOlustur(plan);
    if (!mounted || istek != _istek) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InheritedTheme.captureAll(
          context,
          OrtakSayfa(
            appBar: const ModulUstBar(title: Text('Günlük Plan - PDF')),
            body: PdfPreview(
              build: (_) async => bytes,
              pdfFileName:
                  'Gunluk_Plan_${plan.sinifKodu}_${_tarihYaz(plan.tarih)}.pdf',
              initialPageFormat: PdfPageFormat.a4,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              allowPrinting: true,
              allowSharing: true,
            ),
          ),
        ),
      ),
    );
  });

  Future<void> _belgelereKaydet() => _calistir(() async {
    final istek = _istek;
    final kayit = await _formuKaydet();
    if (!mounted || istek != _istek) return;
    await BireyselGunlukPlanBelgeService.arsiveKaydet(kayit);
    final guncel = await BireyselGunlukPlanService.getir(kayit.id!);
    if (!mounted || istek != _istek) return;
    _planiGoster(guncel);
    _mesaj('Günlük plan PDF’i Belgelerim’e kaydedildi.');
  });

  Future<void> _indir(bool docx) => _calistir(() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final plan = _formdakiPlan();
    final bytes = docx
        ? BireyselGunlukPlanBelgeService.docxOlustur(plan)
        : await BireyselGunlukPlanBelgeService.pdfOlustur(plan);
    await BelgeDisariAktarService.kaydet(
      'Gunluk_Plan_${plan.dersId}_${plan.sinifKodu}_${_tarihYaz(plan.tarih)}_v${plan.surum}.${docx ? 'docx' : 'pdf'}',
      bytes,
    );
  });

  Future<void> _yenidenOlustur() async {
    if (_islem || !await _degisiklikleriEleAl() || !mounted) return;
    await _calistir(() async {
      final istek = _istek;
      final plan = await BireyselGunlukPlanService.hazirla(
        ogretmenProfilId: widget.ogretmenProfilId,
        egitimOgretimYili: widget.egitimOgretimYili,
        dersId: widget.dersId,
        sinifSeviyesi: widget.sinifSeviyesi,
        sinifSubeId: _seciliSinifId!,
        tarih: widget.tarih,
        yenidenOlustur: true,
      );
      if (!mounted || istek != _istek) return;
      final kayit = await BireyselGunlukPlanService.kaydet(plan);
      if (!mounted || istek != _istek) return;
      _planiGoster(kayit);
      _mesaj('Yeni sürüm kaydedildi. Önceki sürüm geçmişte korundu.');
    });
  }

  Future<void> _gecmis() => _calistir(() async {
    final istek = _istek;
    final surumler = await BireyselGunlukPlanService.gecmisiGetir(_plan!.id!);
    if (!mounted || istek != _istek) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Önceki plan sürümleri'),
        content: SizedBox(
          width: 600,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (surumler.isEmpty) const Text('Henüz önceki sürüm yok.'),
              for (final plan in surumler)
                OrtakGenisleyenBolum(
                  title: Text('Sürüm ${plan.surum} • ${plan.haftaTarih}'),
                  children: [
                    SelectableText(
                      BireyselGunlukPlanBelgeService.bolumler(
                        plan,
                      ).entries.map((e) => '${e.key}\n${e.value}').join('\n\n'),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await BelgeDisariAktarService.kaydet(
                            'Gunluk_Plan_${plan.id}_v${plan.surum}.docx',
                            BireyselGunlukPlanBelgeService.docxOlustur(plan),
                          );
                        } catch (e) {
                          if (mounted) _mesaj('Eski sürüm indirilemedi: $e');
                        }
                      },
                      child: const Text('Bu sürümü DOCX indir'),
                    ),
                  ],
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
  });

  Future<void> _kaynakYukle(bool dbf) async {
    if (_islem || !await _degisiklikleriEleAl() || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => dbf
            ? BireyselDbfImportScreen(
                profilId: widget.ogretmenProfilId,
                egitimYili: widget.egitimOgretimYili,
                dersId: widget.dersId,
                dersAdi: widget.dersAdi,
                sinifSeviyesi: widget.sinifSeviyesi,
                kaydedinceDon: true,
              )
            : BireyselYillikPlanImportScreen(
                baslangicDersId: widget.dersId,
                baslangicSinifSeviyesi: widget.sinifSeviyesi,
                kaydedinceDon: true,
              ),
      ),
    );
    if (mounted) await _yukle();
  }

  Future<bool> _degisiklikleriEleAl() async {
    if (!_degisti) return true;
    if (_soruAcik) return false;
    _soruAcik = true;
    try {
      final secim = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kaydedilmemiş değişiklikler'),
          content: const Text('Yazdıklarınızı kaydetmek ister misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ekranda kal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'birak'),
              child: const Text('Kaydetmeden devam et'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'kaydet'),
              child: const Text('Kaydet ve devam et'),
            ),
          ],
        ),
      );
      if (!mounted || secim == null) return false;
      if (secim == 'birak') return true;
      return await _calistir(() async {
        await _formuKaydet();
      });
    } finally {
      _soruAcik = false;
    }
  }

  Future<void> _sinifSec(int? id) async {
    if (id == null || id == _seciliSinifId || _islem) return;
    if (!await _degisiklikleriEleAl() || !mounted) return;
    _istek++;
    setState(() {
      _yukleniyor = true;
      _seciliSinifId = id;
      _plan = null;
      _degisti = false;
    });
    try {
      await _taslagiGetir(id);
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Günlük plan okunamadı.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _geriDon() async {
    if (_islem || !await _degisiklikleriEleAl() || !mounted) return;
    setState(() => _cikisaIzin = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _cikisaIzin || (!_degisti && !_islem),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _geriDon();
    },
    child: OrtakSayfa(
      appBar: const ModulUstBar(title: Text('Günlük Plan Hazırla')),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    widget.dersAdi,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${widget.sinifSeviyesi}. Sınıf • ${widget.egitimOgretimYili}',
                  ),
                  Text('Seçilen tarih: ${_tarihYaz(widget.tarih)}'),
                  if (_plan != null)
                    Text('${_plan!.haftaTarih} • ${_plan!.dersSaati}'),
                  OrtakGenisleyenBolum(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Günlük plan için gerekli kaynaklar'),
                    children: [
                      const Text(
                        'Yalnız seçilen ders, sınıf ve eğitim yılına ait kaynaklar kullanılır. '
                        'Haftanın ders saatleri tek planda ele alınır. Eksik alanlar Açıklamalar bölümünde gösterilir. '
                        'İşleniş, kaynak kazanımlara dayalı düzenlenebilir bir öğretim önerisidir. '
                        'Kayıtlı plan yeni belgelerle kendiliğinden değiştirilmez.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _islem
                                ? null
                                : () => _kaynakYukle(false),
                            child: const Text('Yıllık plan yükle'),
                          ),
                          TextButton(
                            onPressed: _islem ? null : () => _kaynakYukle(true),
                            child: const Text('Ders bilgi formu yükle'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_hata != null) ...[
                    Text(_hata!),
                    TextButton.icon(
                      onPressed: _yukle,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tekrar Dene'),
                    ),
                  ] else ...[
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Sınıf / şube',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          key: const ValueKey('gunluk-plan-sinif'),
                          isExpanded: true,
                          value: _seciliSinifId,
                          hint: const Text('Sınıf/şube seçin'),
                          items: [
                            for (final sinif in _siniflar)
                              DropdownMenuItem(
                                value: sinif.sinifSubeId,
                                child: Text(sinif.sinifKodu),
                              ),
                          ],
                          onChanged: _islem ? null : _sinifSec,
                        ),
                      ),
                    ),
                    if (_plan == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Günlük planı hazırlamak için ders verdiğiniz şubeyi seçin.',
                        ),
                      )
                    else ...[
                      const SizedBox(height: 12),
                      Text('Öğretmen: ${_plan!.ogretmenAdi}'),
                      Text('Okul: ${_plan!.okulAdi}'),
                      const SizedBox(height: 8),
                      Text(
                        _plan!.id == null
                            ? 'Yeni günlük plan. Kaynakta bulunmayan bilgileri ekleyebilirsiniz.'
                            : 'Kayıtlı günlük plan. Düzenlemeleriniz korunuyor.',
                      ),
                      if (_plan!.planBilgisi['kaynaklar']
                          case final Map kaynaklar)
                        Text(
                          'Kaynaklar: Yıllık plan #${kaynaklar['yillikPlanId']} • DBF sürüm ${kaynaklar['dbfSurum']}',
                        ),
                      const SizedBox(height: 16),
                      Form(
                        key: _form,
                        child: Column(
                          children: [
                            for (final alan in _alanlar.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: TextFormField(
                                  key: ValueKey('gunluk-plan-${alan.key}'),
                                  controller: _metinler[alan.key],
                                  readOnly: _islem,
                                  minLines:
                                      alan.key == 'dersinIslenisi' ||
                                          alan.key == 'etkinlikler'
                                      ? 4
                                      : 2,
                                  maxLines: null,
                                  maxLength: 20000,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: InputDecoration(
                                    labelText: alan.value,
                                    alignLabelWithHint: true,
                                    border: const OutlineInputBorder(),
                                    counterText: '',
                                  ),
                                  validator: (text) =>
                                      (text?.length ?? 0) > 20000
                                      ? 'Bu alan en fazla 20.000 karakter olabilir.'
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('gunluk-plan-kaydet'),
                            onPressed: _islem ? null : _kaydet,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Kaydet'),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('gunluk-plan-pdf'),
                            onPressed: _islem ? null : _pdfOnIzle,
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('PDF ön izleme / Yazdır'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _islem ? null : () => _indir(true),
                            icon: const Icon(Icons.description_outlined),
                            label: const Text('DOCX indir'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _islem ? null : () => _indir(false),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('PDF indir'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _islem ? null : _yenidenOlustur,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Yeniden oluştur'),
                          ),
                          if (_plan!.id != null)
                            TextButton(
                              onPressed: _islem ? null : _gecmis,
                              child: const Text('Sürüm geçmişi'),
                            ),
                          OutlinedButton.icon(
                            key: const ValueKey('gunluk-plan-arsiv'),
                            onPressed: _islem ? null : _belgelereKaydet,
                            icon: const Icon(Icons.folder_outlined),
                            label: const Text('Belgelerim’e kaydet'),
                          ),
                        ],
                      ),
                      if (_islem)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: LinearProgressIndicator(),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        _degisti
                            ? 'Kaydedilmemiş değişiklikler var.'
                            : _plan!.id == null
                            ? 'Henüz kaydedilmedi.'
                            : 'Plan kaydedildi.',
                      ),
                    ],
                  ],
                ],
              ),
            ),
    ),
  );
}
