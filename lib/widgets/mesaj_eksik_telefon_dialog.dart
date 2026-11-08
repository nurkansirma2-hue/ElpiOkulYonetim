import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mesajlasma.dart';

/// Eksik iletişimi tek tek tamamlar. Yalnız Kaydet kalıcı kayıt yapar.
class MesajEksikTelefonDialog extends StatefulWidget {
  const MesajEksikTelefonDialog({
    super.key,
    required this.kisiler,
    required this.kaydet,
    this.veliBilgileri = const {},
    this.veliTelefonKaydet,
    this.rehberdenSec,
  });
  final List<MesajKisi> kisiler;
  final Future<void> Function(Map<String, String>, List<MesajKisi>) kaydet;
  final Map<String, Map<String, Object?>> veliBilgileri;
  final Future<void> Function(
    MesajKisi,
    String,
    String,
    String,
    Map<String, Object?>,
  )?
  veliTelefonKaydet;
  final Future<String?> Function()? rehberdenSec;
  @override
  State<MesajEksikTelefonDialog> createState() =>
      _MesajEksikTelefonDialogState();
}

class _MesajEksikTelefonDialogState extends State<MesajEksikTelefonDialog> {
  final _telefonlar = <String, TextEditingController>{};
  final _adlar = <String, TextEditingController>{};
  final _veliler = <String, String>{};
  final _atlananlar = <String>{};
  int _sira = 0;
  bool _busy = false, _bitti = false;
  String? _hata, _alanHatasi;
  MesajKisi get _kisi => widget.kisiler[_sira];
  bool get _veli => _kisi.tur == MesajKisiTuru.veli;
  String get _tur => _veliler[_kisi.secimAnahtari] ?? 'Anne';
  String get _turBasligi => _tur == 'Diger' ? 'Diğer veli' : _tur;
  Map<String, Object?> get _bilgiler =>
      widget.veliBilgileri[_kisi.secimAnahtari] ?? const {};
  TextEditingController get _ad => _adlar.putIfAbsent(
    '${_kisi.secimAnahtari}:$_tur',
    () => TextEditingController(
      text: (_bilgiler[_tur == 'Diger' ? 'DigerVeliAdi' : '${_tur}Adi'] ?? '')
          .toString(),
    ),
  );
  TextEditingController get _telefon {
    final key = '${_kisi.secimAnahtari}:${_veli ? _tur : _kisi.tur.kod}';
    return _telefonlar.putIfAbsent(
      key,
      () => TextEditingController(
        text: _veli
            ? (_bilgiler[_tur == 'Diger'
                          ? 'DigerVeliTelefonu'
                          : '${_tur}Telefon'] ??
                      '')
                  .toString()
            : _kisi.telefon,
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [..._telefonlar.values, ..._adlar.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _bitir({bool iptal = false}) {
    if (_bitti) return;
    _bitti = true;
    Navigator.pop(context, iptal ? null : _atlananlar.toSet());
  }

  void _atla() {
    if (_busy || _bitti) return;
    _atlananlar.add(_kisi.secimAnahtari);
    if (_sira + 1 == widget.kisiler.length) {
      _bitir();
    } else {
      setState(() {
        _sira++;
        _hata = null;
        _alanHatasi = null;
      });
    }
  }

  Future<void> _rehberSec() async {
    if (_busy || _bitti) return;
    setState(() {
      _busy = true;
      _hata = null;
    });
    try {
      final tel =
          await (widget.rehberdenSec?.call() ??
              const MethodChannel(
                'elpi_okul_yonetim/mesajlasma',
              ).invokeMethod<String>('rehberTelefonSec'));
      if (!mounted || tel == null) return;
      if (tel.length > 50 || mesajTelefonNormalize(tel) == null) {
        throw const FormatException(
          'Rehberde seçilen telefon numarası geçersiz.',
        );
      }
      setState(() {
        _telefon.text = tel;
        _alanHatasi = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Rehberden numara alınamadı. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _kaydet() async {
    if (_busy || _bitti) return;
    final tel = _telefon.text.trim();
    if (_veli && _ad.text.trim().length > 200) {
      setState(() => _hata = 'Veli adı en fazla 200 karakter olabilir.');
      return;
    }
    if (tel.length > 50 || mesajTelefonNormalize(tel) == null) {
      setState(() => _alanHatasi = 'Geçerli tek telefon numarası girin.');
      return;
    }
    setState(() {
      _busy = true;
      _hata = null;
      _alanHatasi = null;
    });
    try {
      if (_veli) {
        final kaydet = widget.veliTelefonKaydet;
        if (kaydet == null) {
          throw StateError('Veli kaydetme işlemi tanımlı değil.');
        }
        await kaydet(_kisi, _tur, _ad.text.trim(), tel, _bilgiler);
      } else {
        await widget.kaydet({_kisi.secimAnahtari: tel}, [_kisi]);
      }
      if (!mounted) return;
      if (_sira + 1 == widget.kisiler.length) {
        _bitir();
      } else {
        setState(() {
          _sira++;
          _hata = null;
          _alanHatasi = null;
        });
      }
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
      title: Text('${_sira + 1} / ${widget.kisiler.length} kişi'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _veli ? _kisi.aciklama : '${_kisi.tur.baslik} • ${_kisi.ad}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (!_veli) Text(_kisi.aciklama),
            if (_veli)
              DropdownButtonFormField<String>(
                key: ValueKey('eksik-veli-turu-${_kisi.secimAnahtari}'),
                initialValue: _tur,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Veli bilgisi'),
                items: const [
                  DropdownMenuItem(value: 'Anne', child: Text('Anne')),
                  DropdownMenuItem(value: 'Baba', child: Text('Baba')),
                  DropdownMenuItem(value: 'Diger', child: Text('Diğer veli')),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() {
                            _veliler[_kisi.secimAnahtari] = v;
                            _hata = null;
                            _alanHatasi = null;
                          });
                        }
                      },
              ),
            if (_veli)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  key: ValueKey('eksik-veli-adi-${_kisi.secimAnahtari}'),
                  controller: _ad,
                  enabled: !_busy,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Veli adı',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            Text(
              _veli
                  ? 'Ad ve telefon $_turBasligi kaydına yazılacak.'
                  : 'Numara ${_kisi.tur.baslik} kaydına yazılacak.',
            ),
            OutlinedButton.icon(
              key: ValueKey('rehberden-sec-${_kisi.secimAnahtari}'),
              onPressed: _busy ? null : _rehberSec,
              icon: const Icon(Icons.contacts_outlined),
              label: const Text('Rehberden seç'),
            ),
            TextField(
              key: ValueKey('eksik-telefon-${_kisi.secimAnahtari}'),
              controller: _telefon,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              maxLength: 50,
              decoration: InputDecoration(
                labelText: 'Telefon',
                hintText: '05xx…',
                errorText: _alanHatasi,
                border: const OutlineInputBorder(),
              ),
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
        TextButton(onPressed: _busy ? null : _atla, child: const Text('Atla')),
        TextButton(
          onPressed: _busy ? null : () => _bitir(iptal: true),
          child: const Text('İşlemi sonlandır'),
        ),
        FilledButton(
          onPressed: _busy ? null : _kaydet,
          child: const Text('Kaydet ve sonrakine geç'),
        ),
      ],
    ),
  );
}
