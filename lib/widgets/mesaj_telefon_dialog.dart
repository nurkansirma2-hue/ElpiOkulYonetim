import 'package:flutter/material.dart';
import '../models/mesajlasma.dart';

/// Numara girilmesi isteğe bağlıdır; boş bırakılan alıcı gönderime alınmaz.
class MesajTelefonDialog extends StatefulWidget {
  const MesajTelefonDialog({super.key, required this.bilgiler,
    required this.gecerliAliciVar, this.islemiSonlandir = true});
  final List<Map<String, Object?>> bilgiler;
  final bool gecerliAliciVar, islemiSonlandir;
  @override
  State<MesajTelefonDialog> createState() => _MesajTelefonDialogState();
}

class _MesajTelefonDialogState extends State<MesajTelefonDialog> with WidgetsBindingObserver {
  late final _telefonlar = {for (final r in widget.bilgiler)
    r['id'] as int: TextEditingController(text: r['telefon'] as String)};
  String? _hata;
  bool _gizli = false;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _gizli = state != AppLifecycleState.resumed);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _telefonlar.values) { t.dispose(); }
    super.dispose();
  }
  void _kaydet() {
    final degerler = <int, String>{};
    for (final r in widget.bilgiler) {
      final id = r['id'] as int, tel = _telefonlar[r['id']]!.text.trim();
      if (tel.isEmpty) continue;
      if (tel.length > 50 || mesajTelefonNormalize(tel) == null) {
        setState(() => _hata = '${r['aciklama']}: Geçerli tek telefon numarası girin veya alanı boş bırakın.');
        return;
      }
      degerler[id] = tel;
    }
    if (degerler.isEmpty && !widget.gecerliAliciVar) {
      setState(() => _hata = 'Gönderime devam etmek için en az bir geçerli telefon girin veya işlemi sonlandırın.');
      return;
    }
    Navigator.pop(context, degerler);
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Telefon numaralarını tamamla'),
    content: _gizli ? const Text('Bilgiler gizlendi.') : SizedBox(
      width: 520, height: 340,
      child: ListView.builder(itemCount: widget.bilgiler.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) { return Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Numara girmek isteğe bağlıdır. Boş bırakılanlar gönderime alınmaz. Girilen numaralar ilgili kişinin kaydına yazılır.'),
                if (_hata != null) Text(_hata!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ])); }
            final r = widget.bilgiler[i - 1];
            final tur = r['tur'] == 'Ogrenci' ? 'Öğrenci' : r['tur'] == 'Diger' ? 'Diğer veli' : r['tur'];
            return Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(
              key: ValueKey('mesaj-telefon-${r['id']}'), controller: _telefonlar[r['id']],
              keyboardType: TextInputType.phone, maxLength: 50,
              decoration: InputDecoration(labelText: '$tur telefonu (isteğe bağlı)',
                helperText: r['aciklama'] as String, helperMaxLines: 2,
                hintText: '05xx…', border: const OutlineInputBorder()),
            ));
          }),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: Text(widget.islemiSonlandir ? 'İşlemi sonlandır' : 'Vazgeç')),
      FilledButton(onPressed: _gizli ? null : _kaydet,
        child: const Text('Kaydet ve devam et')),
    ],
  );
}
