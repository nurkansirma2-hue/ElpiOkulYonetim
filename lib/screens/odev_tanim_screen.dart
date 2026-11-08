import '../widgets/ortak_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../models/odev_kontrol.dart';
import '../services/bireysel_liste_service.dart';
import '../services/bireysel_odev_kontrol_service.dart';
import 'admin_import_screen.dart';
import 'mesajlasma_screen.dart';
import '../widgets/odev_gorunum.dart';

class OdevTanimScreen extends StatefulWidget {
  const OdevTanimScreen({
    super.key,
    required this.oturum,
    this.gorev,
    this.sinifSubeId,
    this.dersId,
  });
  final BireyselListeOturumu oturum;
  final OdevTanim? gorev;
  final int? sinifSubeId, dersId;

  @override
  State<OdevTanimScreen> createState() => _OdevTanimScreenState();
}

class _OdevTanimScreenState extends State<OdevTanimScreen> {
  final _form = GlobalKey<FormState>();
  final _baslik = TextEditingController(), _aciklama = TextEditingController();
  int? _sinifId, _dersId, _donem;
  OdevGorevTuru _tur = OdevGorevTuru.normalOdev;
  bool _dersUygulamalari = false;
  DateTime _baslangic = DateUtils.dateOnly(DateTime.now());
  DateTime? _teslim;
  List<OdevDersSecenegi> _dersler = [];
  Map<int, String> _ogrenciler = {};
  Set<int> _secilen = {};
  bool _bekle = true,
      _kaydet = false,
      _degisti = false,
      _cikisSoruluyor = false;
  String? _hata;
  PlatformFile? _ek;
  bool _bildir = false;

  @override
  void initState() {
    super.initState();
    final g = widget.gorev;
    if (g != null) {
      _baslik.text = g.baslik;
      _aciklama.text = g.aciklama ?? '';
      _sinifId = g.sinifSubeId;
      _dersId = g.dersId;
      _donem = g.donem;
      _tur = g.gorevTuru;
      _dersUygulamalari = g.dersUygulamalari;
      _baslangic = g.baslangicTarihi;
      _teslim = g.teslimTarihi;
    } else {
      _sinifId =
          widget.sinifSubeId ??
          (widget.oturum.siniflar.isEmpty
              ? null
              : widget.oturum.siniflar.first.sinifSubeId);
      _dersId = widget.dersId;
    }
    _secenekleriYukle();
  }

  @override
  void dispose() {
    _baslik.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  Future<void> _secenekleriYukle() async {
    setState(() {
      _bekle = true;
      _hata = null;
    });
    try {
      if (_sinifId == null) {
        throw StateError('Önce bireysel ders programınızı yükleyin.');
      }
      final dersler = await BireyselOdevKontrolService.dersler(
        widget.oturum,
        _sinifId!,
      );
      final rows = await BireyselOdevKontrolService.ogrenciSecenekleri(
        widget.oturum,
        _sinifId!,
      );
      final adlar = <int, String>{
        for (final r in rows)
          r['OgrenciId'] as int: '${r['OkulNo']} • ${r['Ad']} ${r['Soyad']}',
      };
      var secilen = adlar.keys.toSet();
      if (widget.gorev != null) {
        final gorev = await BireyselOdevKontrolService.gorevGetir(
          widget.oturum,
          widget.gorev!.odevId,
        );
        if (!gorev.aktif) throw StateError('Pasif görev düzenlenemez.');
        final eski = await BireyselOdevKontrolService.katilimcilar(
          widget.oturum,
          gorev.odevId,
        );
        for (final o in eski) {
          adlar[o.ogrenciId] = '${o.okulNo} • ${o.adSoyad}';
        }
        secilen = eski.where((o) => o.aktif).map((o) => o.ogrenciId).toSet();
      }
      if (!mounted) return;
      setState(() {
        _dersler = dersler;
        _ogrenciler = adlar;
        _secilen = secilen;
        if (widget.gorev == null && !dersler.any((d) => d.dersId == _dersId)) {
          _dersId = dersler.isEmpty ? null : dersler.first.dersId;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _hata = 'Görev seçenekleri yüklenemedi.\nOrijinal hata: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _bekle = false);
    }
  }

  Future<void> _tarihSec(bool teslim) async {
    final onceki = teslim ? (_teslim ?? _baslangic) : _baslangic;
    final tarih = await showDatePicker(
      context: context,
      initialDate: onceki,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: teslim ? 'Teslim tarihi' : 'Başlangıç tarihi',
      cancelText: 'İptal',
      confirmText: 'Seç',
    );
    if (!mounted || tarih == null) return;
    setState(() {
      if (teslim) {
        _teslim = tarih;
      } else {
        _baslangic = tarih;
      }
      _degisti = true;
    });
  }

  Future<void> _cik() async {
    if (_kaydet || _cikisSoruluyor) return;
    _cikisSoruluyor = true;
    final cik = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Değişiklikler kaydedilmedi'),
        content: const Text('Kaydetmeden çıkmak istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Düzenlemeye devam et'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaydetmeden çık'),
          ),
        ],
      ),
    );
    _cikisSoruluyor = false;
    if (mounted && cik == true) {
      setState(() => _degisti = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _kaydetGorev() async {
    if (_kaydet || _bekle || !_form.currentState!.validate()) return;
    if (_sinifId == null || _dersId == null || _secilen.isEmpty) {
      setState(() => _hata = 'Sınıf, ders ve en az bir öğrenci seçin.');
      return;
    }
    if (_teslim != null && _teslim!.isBefore(_baslangic)) {
      setState(() => _hata = 'Teslim tarihi başlangıç tarihinden önce olamaz.');
      return;
    }
    setState(() {
      _kaydet = true;
      _hata = null;
    });
    try {
      final int id;
      if (widget.gorev == null) {
        id = await BireyselOdevKontrolService.gorevOlustur(
          widget.oturum,
          sinifSubeId: _sinifId!,
          dersId: _dersId!,
          gorevTuru: _tur,
          dersUygulamalari: _dersUygulamalari,
          baslik: _baslik.text,
          aciklama: _aciklama.text,
          baslangicTarihi: _baslangic,
          teslimTarihi: _teslim,
          donem: _donem,
          ogrenciIdleri: _secilen.toList(),
          kontrolBaslat: true,
          ekAdi: _ek?.name,
          ekVeri: _ek?.bytes == null ? null : Uint8List.fromList(_ek!.bytes!),
        );
      } else {
        id = widget.gorev!.odevId;
        await BireyselOdevKontrolService.gorevGuncelle(
          widget.oturum,
          id,
          gorevTuru: _tur,
          baslik: _baslik.text,
          aciklama: _aciklama.text,
          baslangicTarihi: _baslangic,
          teslimTarihi: _teslim,
          donem: _donem,
          ogrenciIdleri: _secilen.toList(),
        );
      }
      if (mounted) {
        _degisti = false;
        if (_bildir && widget.gorev == null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MesajlasmaScreen(
                kaynakModul: 'OdevBildirim',
                kaynakKayit: '$id',
                ogrenciTelefonu: true,
                baslangicOgrenciIdleri: _secilen,
                izinliOgrenciIdleri: _secilen,
                baslangicMetni:
                    'Sevgili öğrencimiz, ${_baslik.text.trim()} ödevi verilmiştir. ${_aciklama.text.trim()}${_teslim == null ? '' : ' Son teslim: ${odevTarihYaz(_teslim!)}'}',
              ),
            ),
          );
          if (!mounted) return;
        }
        setState(() => _kaydet = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.of(context).pop(id);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Görev kaydedilemedi.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _kaydet = false);
    }
  }

  Widget _alanKarti(IconData ikon, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(OrtakUi.bosluk),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(ikon, color: Theme.of(context).colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: Theme.of(context).inputDecorationTheme
                    .copyWith(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
              ),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _ekSec() async {
    final secim = await FilePicker.platform.pickFiles(withData: true);
    if (secim == null || !mounted) return;
    final f = secim.files.single;
    if (f.size > 10485760 || f.bytes == null) {
      setState(() => _hata = 'Ek dosya okunamadı veya 10 MB sınırını aşıyor.');
      return;
    }
    setState(() {
      _ek = f;
      _degisti = true;
    });
  }

  Widget _dosyaKarti() => _alanKarti(
    Icons.attach_file,
    LayoutBuilder(
      builder: (ctx, constraints) {
        final bilgi = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dosya / Ek', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 4),
            Tooltip(
              message:
                  _ek?.name ??
                  'Ödev dosyası, yönerge veya ek materyal ekleyin.',
              child: Text(
                _ek?.name ?? 'Ödev dosyası, yönerge veya ek materyal ekleyin.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
        final buton = OutlinedButton.icon(
          onPressed: _ekSec,
          icon: const Icon(Icons.upload_outlined),
          label: const Text('Dosya Seç'),
        );
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(ctx).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [bilgi, const SizedBox(height: 8), buton],
          );
        }
        return Row(
          children: [
            Expanded(child: bilgi),
            const SizedBox(width: 12),
            buton,
          ],
        );
      },
    ),
  );

  Widget _digerAyarlar() => Card(
    clipBehavior: Clip.antiAlias,
    child: OrtakGenisleyenBolum(
      key: const ValueKey('odev-diger-ayarlar'),
      initiallyExpanded: true,
      leading: Icon(
        Icons.settings_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('Diğer ayarlar'),
      childrenPadding: const EdgeInsets.all(OrtakUi.bosluk),
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            final donem = DropdownButtonFormField<int>(
              key: const ValueKey('odev-donem'),
              initialValue: _donem ?? 0,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Dönem',
                prefixIcon: Icon(Icons.school_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Belirtilmedi')),
                DropdownMenuItem(value: 1, child: Text('1. dönem')),
                DropdownMenuItem(value: 2, child: Text('2. dönem')),
              ],
              onChanged: (d) => setState(() {
                _donem = d == 0 ? null : d;
                _degisti = true;
              }),
            );
            final baslangic = ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Başlangıç tarihi'),
              subtitle: Text(odevTarihYaz(_baslangic)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () => _tarihSec(false),
            );
            if (constraints.maxWidth < 550 ||
                MediaQuery.textScalerOf(ctx).scale(1) > 1.3) {
              return Column(
                children: [donem, const SizedBox(height: 12), baslangic],
              );
            }
            return Row(
              children: [
                Expanded(child: donem),
                const SizedBox(width: 20),
                Expanded(child: baslangic),
              ],
            );
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => OdevTema(
    child: PopScope<int>(
      canPop: !_kaydet && !_degisti,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _cik();
      },
      child: OrtakSayfa(
        appBar: OdevBaslik(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.gorev == null ? 'Yeni Ödev' : 'Ödevi Düzenle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.gorev == null
                    ? 'Ödev Ekle ve Öğrencilere Paylaş'
                    : 'Ödev bilgilerini güncelle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('odev-kaydet'),
                onPressed:
                    _kaydet || _bekle || _dersId == null || _ogrenciler.isEmpty
                    ? null
                    : _kaydetGorev,
                icon: const Icon(Icons.save_outlined),
                label: Text(_kaydet ? 'Kaydediliyor...' : 'Kaydet'),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: _bekle
              ? const Center(child: CircularProgressIndicator())
              : AbsorbPointer(
                  absorbing: _kaydet,
                  child: Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (_hata != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _hata!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLowest,
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(
                                      OrtakUi.radius,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.assignment_outlined,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                    size: 30,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ödev Bilgileri',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Ödevin temel bilgilerini giriniz.',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _alanKarti(
                          Icons.people_outline,
                          DropdownButtonFormField<int>(
                            key: ValueKey('sinif-$_sinifId'),
                            initialValue: _sinifId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Sınıf / Şube *',
                            ),
                            items: [
                              if (widget.gorev != null && !widget.oturum.siniflar.any((s) => s.sinifSubeId == _sinifId))
                                DropdownMenuItem(value: _sinifId, child: const Text('Ödevin kayıtlı sınıfı')),
                              for (final s in widget.oturum.siniflar)
                                DropdownMenuItem(
                                  value: s.sinifSubeId,
                                  child: Text(
                                    s.sinif,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: widget.gorev != null
                                ? null
                                : (id) {
                                    if (id == null || id == _sinifId) return;
                                    _sinifId = id;
                                    _dersId = null;
                                    _degisti = true;
                                    _secenekleriYukle();
                                  },
                          ),
                        ),
                        _alanKarti(
                          Icons.menu_book_outlined,
                          DropdownButtonFormField<int>(
                            key: ValueKey('ders-$_sinifId-$_dersId'),
                            initialValue: _dersId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Ders *',
                            ),
                            items: [
                              if (widget.gorev != null && !_dersler.any((d) => d.dersId == _dersId))
                                DropdownMenuItem(value: _dersId, child: const Text('Ödevin kayıtlı dersi')),
                              for (final d in _dersler)
                                DropdownMenuItem(
                                  value: d.dersId,
                                  child: Tooltip(
                                    message: d.dersAdi,
                                    child: Text(
                                      d.dersAdi,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: widget.gorev != null
                                ? null
                                : (id) => setState(() {
                                    _dersId = id;
                                    _degisti = true;
                                  }),
                          ),
                        ),
                        _alanKarti(
                          Icons.layers_outlined,
                          DropdownButtonFormField<String>(
                            key: const ValueKey('odev-gorev-turu'),
                            initialValue: _dersUygulamalari
                                ? 'DersUygulamalari'
                                : _tur.kayitDegeri,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Ödev türü *',
                            ),
                            items: [
                              if (widget.gorev == null || _dersUygulamalari)
                                const DropdownMenuItem(
                                  value: 'DersUygulamalari',
                                  child: Text('Ders Uygulamaları'),
                                ),
                              ...OdevGorevTuru.values.map(
                                (t) => DropdownMenuItem(
                                  value: t.kayitDegeri,
                                  child: Text(
                                    t.baslik,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: widget.gorev?.dersUygulamalari == true
                                ? null
                                : (tur) {
                                    if (tur != null) {
                                      setState(() {
                                        _dersUygulamalari =
                                            tur == 'DersUygulamalari';
                                        _tur = _dersUygulamalari
                                            ? OdevGorevTuru.rutinKontrol
                                            : OdevGorevTuru.oku(tur);
                                        _degisti = true;
                                      });
                                    }
                                  },
                          ),
                        ),
                        _alanKarti(
                          Icons.edit_note_outlined,
                          Column(
                            children: [
                              TextFormField(
                                controller: _baslik,
                                decoration: const InputDecoration(
                                  labelText: 'Başlık',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Başlık girin.'
                                    : null,
                                onChanged: (_) =>
                                    setState(() => _degisti = true),
                              ),
                              OrtakGenisleyenBolum(
                                tilePadding: EdgeInsets.zero,
                                title: const Text('Açıklama'),
                                children: [
                                  TextFormField(
                                    controller: _aciklama,
                                    minLines: 2,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                      labelText: 'Açıklama',
                                    ),
                                    onChanged: (_) =>
                                        setState(() => _degisti = true),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _alanKarti(
                          Icons.calendar_month_outlined,
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Teslim Tarihi'),
                            subtitle: Text(
                              _teslim == null
                                  ? 'İsteğe bağlı'
                                  : odevTarihYaz(_teslim!),
                            ),
                            trailing: _teslim == null
                                ? const Icon(Icons.calendar_month)
                                : IconButton(
                                    tooltip: 'Teslim tarihini kaldır',
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => setState(() {
                                      _teslim = null;
                                      _degisti = true;
                                    }),
                                  ),
                            onTap: () => _tarihSec(true),
                          ),
                        ),
                        if (widget.gorev == null) ...[
                          _dosyaKarti(),
                          Card(
                            child: SwitchListTile(
                              secondary: Icon(
                                Icons.notifications_none,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: const Text('Öğrencilere Bildir'),
                              subtitle: const Text(
                                'Kaydettikten sonra mesajı hazırlayıp onaylayın.',
                              ),
                              value: _bildir,
                              onChanged: (v) => setState(() {
                                _bildir = v;
                                _degisti = true;
                              }),
                            ),
                          ),
                        ],
                        Card(
                          child: OrtakGenisleyenBolum(
                            key: const ValueKey('odev-ogrenci-secimi'),
                            maintainState: true,
                            leading: const Icon(Icons.people_outline),
                            title: const Text('Öğrenci listesi'),
                            subtitle: Text(
                              '${_secilen.length}/${_ogrenciler.length} seçili',
                            ),
                            children: [
                              if (_ogrenciler.isEmpty) ...[
                                const Text('Bu sınıfta öğrenci bulunamadı.'),
                                TextButton(
                                  onPressed: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AdminImportScreen(),
                                      ),
                                    );
                                    if (mounted) await _secenekleriYukle();
                                  },
                                  child: const Text('Öğrenci Import'),
                                ),
                              ] else
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Tümünü seç'),
                                  value: _secilen.length == _ogrenciler.length,
                                  onChanged: (v) => setState(() {
                                    _secilen = v == true
                                        ? _ogrenciler.keys.toSet()
                                        : {};
                                    _degisti = true;
                                  }),
                                ),
                              ..._ogrenciler.entries.map(
                                (o) => CheckboxListTile(
                                  key: ValueKey('ogrenci-${o.key}'),
                                  contentPadding: EdgeInsets.zero,
                                  title: OrtakBaslik(o.value, maxLines: 2),
                                  value: _secilen.contains(o.key),
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _secilen.add(o.key);
                                    } else {
                                      _secilen.remove(o.key);
                                    }
                                    _degisti = true;
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _digerAyarlar(),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
}
