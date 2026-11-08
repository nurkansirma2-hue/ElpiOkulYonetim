import 'package:flutter/material.dart';
import '../database/veli_iliskisi.dart';
import '../models/mesajlasma.dart';

class VeliSecimi {
  const VeliSecimi(this.tur, this.ad, this.telefon, {this.onceki});
  final String tur, ad, telefon;
  final Map<String, Object?>? onceki;
}

class VeliSecimDialog extends StatefulWidget {
  const VeliSecimDialog({super.key, required this.ogrenci});

  /// VeliIliskisi.gorunum tarafından hazırlanır; diğer veli ayrı korunur.
  final Map<String, Object?> ogrenci;
  @override
  State<VeliSecimDialog> createState() => _VeliSecimState();
}

class _VeliSecimState extends State<VeliSecimDialog>
    with WidgetsBindingObserver {
  bool _gizli = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _gizli = state != AppLifecycleState.resumed);
  }

  late String _tur = widget.ogrenci['VeliTuru'] as String;
  late final _adlar = {
    for (final t in VeliIliskisi.turler.keys)
      t: TextEditingController(
        text: widget.ogrenci[t == 'Diger' ? 'DigerVeliAdi' : '${t}Adi']
            ?.toString(),
      ),
  };
  late final _telefonlar = {
    for (final t in VeliIliskisi.turler.keys)
      t: TextEditingController(
        text: widget.ogrenci[t == 'Diger' ? 'DigerVeliTelefonu' : '${t}Telefon']
            ?.toString(),
      ),
  };
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [..._adlar.values, ..._telefonlar.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Veli ilişkisi'),
    content: _gizli
        ? const Text('Bilgiler gizlendi.')
        : SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _tur,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Öğrencinin velisi',
                    ),
                    items: [
                      for (final e in VeliIliskisi.turler.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _tur = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey('veli-adi-$_tur'),
                    controller: _adlar[_tur],
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: '${VeliIliskisi.turler[_tur]} adı',
                    ),
                  ),
                  TextFormField(
                    key: ValueKey('veli-telefon-$_tur'),
                    controller: _telefonlar[_tur],
                    maxLength: 50,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: '${VeliIliskisi.turler[_tur]} telefonu',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ||
                            mesajTelefonNormalize(v!) != null
                        ? null
                        : 'Geçerli tek telefon numarası girin.',
                  ),
                  Text(
                    'Bilgiler ${VeliIliskisi.turler[_tur]} kaydına yazılacak.',
                  ),
                ],
              ),
            ),
          ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: _gizli
            ? null
            : () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(
                    context,
                    VeliSecimi(
                      _tur,
                      _adlar[_tur]!.text.trim(),
                      _telefonlar[_tur]!.text.trim(),
                      onceki: Map.unmodifiable(widget.ogrenci),
                    ),
                  );
                }
              },
        child: const Text('Kaydet'),
      ),
    ],
  );
}
