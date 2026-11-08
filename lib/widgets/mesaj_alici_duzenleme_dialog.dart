import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import '../models/mesajlasma.dart';

class MesajOgretmenDialog extends StatefulWidget {
  const MesajOgretmenDialog({
    super.key,
    required this.siniflar,
    required this.seciliSiniflar,
    required this.kaydet,
    this.ad = '',
    this.telefon = '',
    this.sinifIliskileriKayitli = false,
  });
  final Map<int, String> siniflar;
  final Set<int> seciliSiniflar;
  final String ad, telefon;
  final bool sinifIliskileriKayitli;
  final Future<void> Function(String ad, String telefon, Set<int> siniflar)
  kaydet;
  @override
  State<MesajOgretmenDialog> createState() => _MesajOgretmenDialogState();
}

class _MesajOgretmenDialogState extends State<MesajOgretmenDialog> {
  late final _ad = TextEditingController(text: widget.ad);
  late final _telefon = TextEditingController(text: widget.telefon);
  late final _siniflar = Set<int>.of(widget.seciliSiniflar);
  bool _dogrulandi = false, _busy = false;
  bool get _dogrulamaGerekli =>
      !widget.sinifIliskileriKayitli ||
      !setEquals(_siniflar, widget.seciliSiniflar);
  String? _hata;
  @override
  void dispose() {
    _ad.dispose();
    _telefon.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_busy) return;
    if (_ad.text.trim().isEmpty ||
        _ad.text.trim().length > 200 ||
        (_telefon.text.trim().isNotEmpty &&
            mesajTelefonNormalize(_telefon.text) == null) ||
        _siniflar.isEmpty ||
        (_dogrulamaGerekli && !_dogrulandi)) {
      setState(
        () => _hata =
            'Öğretmen adını, telefonunu ve en az bir sınıfı kontrol edip ders ilişkisini doğrulayın.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      await widget.kaydet(
        _ad.text.trim(),
        _telefon.text.trim(),
        Set<int>.of(_siniflar),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _hata =
              'Kaydedilemedi. Girişleriniz korunuyor. Orijinal hata: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Öğretmen ve ders sınıfları'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Bu kişi uygulamanın öğretmen profili değildir. Yalnız ders verdiğiniz sınıflarla ilişkili iletişim kaydıdır.',
            ),
            TextField(
              key: const ValueKey('mesaj-ogretmen-ad'),
              controller: _ad,
              enabled: !_busy,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Öğretmen adı soyadı',
              ),
            ),
            TextField(
              key: const ValueKey('mesaj-ogretmen-telefon'),
              controller: _telefon,
              enabled: !_busy,
              maxLength: 50,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Öğretmen telefonu (isteğe bağlı)',
              ),
            ),
            const Text('Bu öğretmenin derse girdiği sınıflar'),
            for (final e in widget.siniflar.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.value),
                value: _siniflar.contains(e.key),
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        if (v == true) {
                          _siniflar.add(e.key);
                        } else {
                          _siniflar.remove(e.key);
                        }
                        _dogrulandi = false;
                      }),
              ),
            if (_dogrulamaGerekli)
              CheckboxListTile(
                key: const ValueKey('mesaj-ogretmen-dogrula'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Bu öğretmenin seçilen sınıflarda derse girdiğini doğruladım.',
                ),
                value: _dogrulandi,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _dogrulandi = v == true),
              ),
            if (_hata != null)
              Text(
                _hata!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _busy ? null : _kaydet,
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
}

/// Kaydetme hatasında dialog kapanmaz; girilen isim ve telefon korunur.
class MesajKisiTelefonDialog extends StatefulWidget {
  const MesajKisiTelefonDialog({
    super.key,
    required this.kisi,
    required this.kaydet,
    this.veliAdi,
    this.veliKaydet,
  });
  final MesajKisi kisi;
  final Future<void> Function(String telefon) kaydet;
  final String? veliAdi;
  final Future<void> Function(String ad, String telefon)? veliKaydet;
  @override
  State<MesajKisiTelefonDialog> createState() => _MesajKisiTelefonDialogState();
}

class _MesajKisiTelefonDialogState extends State<MesajKisiTelefonDialog> {
  late final _telefon = TextEditingController(text: widget.kisi.telefon);
  late final _ad = TextEditingController(text: widget.veliAdi ?? '');
  String? _hata;
  bool _busy = false;
  @override
  void dispose() {
    _telefon.dispose();
    _ad.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_busy) return;
    if (_telefon.text.trim().length > 50 ||
        mesajTelefonNormalize(_telefon.text) == null) {
      setState(() => _hata = 'Geçerli tek telefon numarası girin.');
      return;
    }
    if (widget.veliKaydet != null &&
        (_ad.text.trim().isEmpty || _ad.text.trim().length > 200)) {
      setState(() => _hata = 'Veli adını girin (en fazla 200 karakter).');
      return;
    }
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      if (widget.veliKaydet != null) {
        await widget.veliKaydet!(_ad.text.trim(), _telefon.text.trim());
      } else {
        await widget.kaydet(_telefon.text.trim());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _hata = 'Kaydedilemedi. Girişiniz korunuyor. Orijinal hata: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kisi;
    final tur = k.tur == MesajKisiTuru.veli
        ? (k.veliTuru == 'Diger' ? 'Diğer veli' : k.veliTuru)
        : k.tur.baslik;
    final gorunenAd =
        widget.veliKaydet != null && (widget.veliAdi ?? '').trim().isEmpty
        ? 'Adı kaydedilmemiş'
        : widget.veliAdi ?? k.ad;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          widget.veliKaydet == null
              ? 'Telefonu düzenle'
              : 'Veli bilgilerini düzenle',
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${k.tur.baslik} • $gorunenAd'),
              Text(k.aciklama),
              Text('Numara $tur kaydına yazılacak.'),
              if (widget.veliKaydet != null)
                TextField(
                  key: const ValueKey('mesaj-kisi-ad'),
                  controller: _ad,
                  enabled: !_busy,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: '$tur adı'),
                ),
              TextField(
                key: const ValueKey('mesaj-kisi-telefon'),
                controller: _telefon,
                enabled: !_busy,
                maxLength: 50,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: '$tur telefonu'),
              ),
              if (_hata != null)
                Text(
                  _hata!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: _busy ? null : _kaydet,
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
