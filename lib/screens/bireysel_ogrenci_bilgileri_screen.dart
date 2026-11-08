import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import '../services/bireysel_liste_service.dart';
import '../widgets/veli_secim_dialog.dart';
import '../models/mesajlasma.dart';

class BireyselOgrenciBilgileriScreen extends StatefulWidget {
  const BireyselOgrenciBilgileriScreen({
    super.key,
    required this.oturum,
    required this.ogrenciId,
  });
  final BireyselListeOturumu oturum;
  final int ogrenciId;
  @override
  State<BireyselOgrenciBilgileriScreen> createState() => _BilgilerState();
}

class _BilgilerState extends State<BireyselOgrenciBilgileriScreen>
    with WidgetsBindingObserver {
  Future<Map<String, Object?>>? _bilgiler;
  bool _gizli = false;
  bool _kaydediliyor = false;
  Future<void> _duzenle(Map<String, Object?> o, String kisi) async {
    if (_kaydediliyor) return;
    setState(() => _kaydediliyor = true);
    try {
      final kayit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _IletisimDuzenleDialog(
          kisi: kisi,
          ogrenci: o,
          kaydet: (degerler) => BireyselListeService.iletisimKaydet(
            widget.oturum,
            widget.ogrenciId,
            kisi,
            degerler,
            onceki: o,
          ),
        ),
      );
      if (kayit == true && mounted) {
        setState(_yukle);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bilgiler kaydedildi.')));
      }
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  Future<void> _veli(Map<String, Object?> o) async {
    final secim = await showDialog<VeliSecimi>(
      context: context,
      builder: (_) => VeliSecimDialog(ogrenci: o),
    );
    if (secim == null || !mounted || _gizli) return;
    setState(() => _kaydediliyor = true);
    try {
      await BireyselListeService.veliKaydet(
        widget.oturum,
        widget.ogrenciId,
        secim.tur,
        ad: secim.ad,
        telefon: secim.telefon,
        onceki: secim.onceki,
      );
      if (mounted) setState(_yukle);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veli kaydedilemedi. Orijinal hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _yukle();
  }

  void _yukle() {
    _bilgiler = BireyselListeService.ogrenciBilgileri(
      widget.oturum,
      widget.ogrenciId,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _gizli = state != AppLifecycleState.resumed;
      if (!_gizli) _yukle();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _alan(String baslik, Object? deger) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(baslik),
    subtitle: SelectableText(
      (deger ?? '').toString().trim().isEmpty
          ? 'Kaydedilmemiş'
          : deger.toString(),
    ),
  );
  Widget _kisiKart(Map<String, Object?> o, String kisi) {
    final ogrenci = kisi == 'Ogrenci';
    final ad = ogrenci ? 'Öğrenci' : (o['${kisi}Adi'] ?? '').toString().trim();
    final telefon = (o[ogrenci ? 'Telefon' : '${kisi}Telefon'] ?? '')
        .toString()
        .trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: ValueKey('kisi-$kisi'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: _kaydediliyor ? null : () => _duzenle(o, kisi),
        leading: CircleAvatar(
          child: Icon(ogrenci ? Icons.school_outlined : Icons.person_outline),
        ),
        title: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              ogrenci ? 'Öğrenci iletişimi' : kisi,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (o['VeliTuru'] == kisi)
              const Chip(
                label: Text('Veli'),
                avatar: Icon(Icons.verified_user_outlined, size: 16),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!ogrenci) Text(ad.isEmpty ? 'Ad kaydedilmemiş' : ad),
              const SizedBox(height: 4),
              Text(telefon.isEmpty ? 'Telefon kaydedilmemiş' : telefon),
            ],
          ),
        ),
        trailing: const Icon(Icons.edit_outlined, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: const ModulUstBar(title: Text('Öğrenci bilgileri')),
    body: _gizli
        ? const Center(child: Text('Bilgiler gizlendi.'))
        : FutureBuilder<Map<String, Object?>>(
            future: _bilgiler,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Bilgiler okunamadı. Orijinal hata: ${snapshot.error}',
                        ),
                        TextButton(
                          onPressed: () => setState(_yukle),
                          child: const Text('Yeniden dene'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (snapshot.connectionState != ConnectionState.done ||
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final o = snapshot.data!;
              final ekler = o['EkBilgiler'] as List<Map<String, Object?>>;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '${o['Ad']} ${o['Soyad']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${o['SinifKodu']} • No: ${o['OkulNo']} • ${widget.oturum.yil}',
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Düzenlemek için ilgili karta dokunun.'),
                  ),
                  _kisiKart(o, 'Ogrenci'),
                  _kisiKart(o, 'Anne'),
                  _kisiKart(o, 'Baba'),
                  if (o['VeliTuru'] == 'Diger')
                    Card(
                      child: ListTile(
                        title: Text(
                          (o['VeliAdi'] ?? '').toString().trim().isEmpty
                              ? 'Diğer veli'
                              : o['VeliAdi'].toString(),
                        ),
                        subtitle: Text(
                          (o['VeliTelefonu'] ?? '').toString().trim().isEmpty
                              ? 'Telefon kaydedilmemiş'
                              : o['VeliTelefonu'].toString(),
                        ),
                        leading: const Icon(Icons.verified_user_outlined),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: _kaydediliyor ? null : () => _veli(o),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: _kaydediliyor ? null : () => _veli(o),
                    child: const Text('Veli ilişkisini değiştir'),
                  ),
                  const Divider(),
                  const Text(
                    'Formlardan kaydedilen ek bilgiler',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Yalnız onaylanıp öğrenciye kaydedilen bilgiler gösterilir.',
                  ),
                  if (ekler.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Kaydedilmiş ek form bilgisi yok.'),
                    ),
                  for (final e in ekler) ...[
                    _alan(e['Baslik'].toString(), e['Deger']),
                    Text('Form: ${e['FormBaslik']}'),
                    const Divider(),
                  ],
                ],
              );
            },
          ),
  );
}

class _IletisimDuzenleDialog extends StatefulWidget {
  const _IletisimDuzenleDialog({
    required this.kisi,
    required this.ogrenci,
    required this.kaydet,
  });
  final String kisi;
  final Map<String, Object?> ogrenci;
  final Future<void> Function(Map<String, String>) kaydet;
  @override
  State<_IletisimDuzenleDialog> createState() => _IletisimDuzenleState();
}

class _IletisimDuzenleState extends State<_IletisimDuzenleDialog>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  late final _alanlar = widget.kisi == 'Ogrenci'
      ? {'Telefon': 'Telefon'}
      : {'${widget.kisi}Adi': 'Ad soyad', '${widget.kisi}Telefon': 'Telefon'};
  late final _controllers = {
    for (final key in _alanlar.keys)
      key: TextEditingController(text: widget.ogrenci[key]?.toString()),
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
    if (_busy || _gizli || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      await widget.kaydet({
        for (final e in _controllers.entries) e.key: e.value.text,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = 'Kaydedilemedi. Orijinal hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        '${widget.kisi == 'Ogrenci' ? 'Öğrenci' : widget.kisi} bilgilerini düzenle',
      ),
      content: _gizli
          ? const Text('Bilgiler gizlendi.')
          : SingleChildScrollView(
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in _alanlar.entries)
                      TextFormField(
                        key: ValueKey('iletisim-${e.key}'),
                        controller: _controllers[e.key],
                        enabled: !_busy,
                        maxLength: e.key.contains('Telefon') ? 50 : 200,
                        keyboardType: e.key.contains('Telefon')
                            ? TextInputType.phone
                            : TextInputType.name,
                        decoration: InputDecoration(labelText: e.value),
                        validator: (v) =>
                            e.key.contains('Telefon') &&
                                (v ?? '').trim().isNotEmpty &&
                                mesajTelefonNormalize(v!) == null
                            ? 'Geçerli tek telefon numarası girin.'
                            : null,
                      ),
                    if (_hata != null)
                      Text(
                        _hata!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _busy || _gizli ? null : _kaydet,
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
}
