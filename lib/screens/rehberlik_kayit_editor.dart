import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/bireysel_rehberlik_service.dart';

class RehberlikKayitEditor extends StatefulWidget {
  const RehberlikKayitEditor({
    super.key,
    required this.service,
    required this.baglam,
    required this.atamaId,
    required this.tur,
    required this.ogrenciler,
    required this.hassasOnay,
    this.kayit,
    this.baslangicIcerik = const {},
    this.baslangicBaslik = '',
    this.baslangicHassas = false,
  });
  final BireyselRehberlikService service;
  final BireyselRehberlikBaglami baglam;
  final int atamaId;
  final String tur, baslangicBaslik;
  final List<Map<String, Object?>> ogrenciler;
  final bool hassasOnay;
  final bool baslangicHassas;
  final Map<String, Object?>? kayit;
  final Map<String, Object?> baslangicIcerik;
  @override
  State<RehberlikKayitEditor> createState() => _EditorState();
}

class _EditorState extends State<RehberlikKayitEditor>
    with WidgetsBindingObserver {
  bool _kilitli = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        state != AppLifecycleState.inactive &&
        _hassas) {
      setState(() => _kilitli = true);
    }
  }

  final _form = GlobalKey<FormState>();
  late final _icerik = widget.kayit == null
      ? widget.baslangicIcerik
      : Map<String, Object?>.from(
          jsonDecode(widget.kayit!['Icerik'] as String) as Map,
        );
  late final _baslik = TextEditingController(
    text: widget.kayit?['Baslik'] as String? ?? widget.baslangicBaslik,
  );
  late final _tarih = TextEditingController(
    text:
        widget.kayit?['Tarih'] as String? ??
        DateTime.now().toIso8601String().substring(0, 10),
  );
  late String _durum = widget.kayit?['Durum'] as String? ?? 'Planlandi';
  late int? _ogrenci = widget.kayit?['OgrenciId'] as int?;
  late bool _hassas =
      widget.baslangicHassas ||
      widget.kayit?['Hassas'] == 1 ||
      widget.tur == 'Gorusme';
  late bool _hassasOnay = widget.hassasOnay;
  late String _toplantiTuru = (_icerik['toplantiTuru'] as String?) ?? 'Veli';
  late final Map<String, TextEditingController> _alanlar = {
    for (final a in _alanAdlari.keys)
      a: TextEditingController(text: (_icerik[a] ?? '').toString()),
  };
  bool _islem = false;
  String? _hata;
  Map<String, String> get _alanAdlari => switch (widget.tur) {
    'Toplanti' => {
      'yer': 'Yer',
      'saat': 'Saat',
      'gundem': 'Gündem (her madde ayrı satır)',
      'davet': 'Davet metni',
      'katilim': 'Katılım (katıldı / katılmadı notları)',
      'tutanak': 'Tutanak',
      'kararlar': 'Kararlar (sorumlu ve süre ile)',
      'takip': 'Karar takip açıklaması',
    },
    'Plan' => {
      'tarih': 'Plandaki tarih / tarih aralığı',
      'hafta': 'Hafta',
      'saat': 'Saat',
      'konu': 'Konu',
      'aciklama': 'Uygulama notu',
    },
    'Gorusme' => {
      'kisi': 'Görüşülen kişi ve yakınlığı',
      'aciklama': 'Görüşme özeti',
      'sonuc': 'Sonuç / yönlendirme',
      'takip': 'Takip açıklaması',
    },
    _ => {
      'aciklama': 'Açıklama',
      'sorumlu': 'Sorumlu',
      'sonuc': 'Sonuç / takip notu',
    },
  };
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _baslik.dispose();
    _tarih.dispose();
    for (final c in _alanlar.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_islem || !_form.currentState!.validate()) return;
    setState(() {
      _islem = true;
      _hata = null;
    });
    try {
      final id = await widget.service.kayitKaydet(
        widget.baglam,
        widget.atamaId,
        id: widget.kayit?['Id'] as int?,
        tur: widget.tur,
        baslik: _baslik.text,
        tarih: _tarih.text,
        durum: _durum,
        ogrenciId: _ogrenci,
        hassas: _hassas,
        hassasOnay: _hassasOnay,
        icerik: {
          ..._icerik,
          ..._alanlar.map((k, v) => MapEntry(k, v.text)),
          if (widget.tur == 'Toplanti') 'toplantiTuru': _toplantiTuru,
        },
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => _hata = 'Kaydedilemedi.\nOrijinal hata: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _hassasDegistir(bool deger) async {
    if (widget.baslangicHassas || _islem) return;
    if (deger && !_hassasOnay) {
      final onay = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Hassas kayıt onayı'),
          content: const Text(
            'Bu kayıt varsayılan olarak gizlenir ve genel belge çıktısına eklenmez. SQLite ve okul yedeği şifreli değildir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Onayla'),
            ),
          ],
        ),
      );
      if (onay != true || !mounted) return;
      await widget.service.kayitlar(widget.baglam, widget.atamaId);
      if (!mounted) return;
      _hassasOnay = true;
    }
    if (mounted) setState(() => _hassas = deger);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_islem,
    child: OrtakSayfa(
      appBar: ModulUstBar(title: Text(rehberlikTurleri[widget.tur] ?? widget.tur)),
      body: _kilitli
          ? Center(
              child: FilledButton(
                onPressed: () async {
                  try {
                    await widget.service.kayitlar(
                      widget.baglam,
                      widget.atamaId,
                    );
                    if (mounted) setState(() => _kilitli = false);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erişim doğrulanamadı: $e')),
                      );
                    }
                  }
                },
                child: const Text('Hassas içeriği yeniden görüntüle'),
              ),
            )
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_hata != null) Text(_hata!),
                  TextFormField(
                    controller: _baslik,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: 'Başlık'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Başlık girin.' : null,
                  ),
                  TextFormField(
                    controller: _tarih,
                    decoration: const InputDecoration(
                      labelText: 'Tarih (YYYY-AA-GG)',
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      final d = DateTime.tryParse(v);
                      return d == null ||
                              d.toIso8601String().substring(0, 10) != v
                          ? 'Geçerli bir tarih girin.'
                          : null;
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _durum,
                    decoration: const InputDecoration(labelText: 'Durum'),
                    items: [
                      for (var i = 0; i < rehberlikDurumlari.length; i++)
                        DropdownMenuItem(
                          value: rehberlikDurumlari[i],
                          child: Text(rehberlikDurumAdlari[i]),
                        ),
                    ],
                    onChanged: _islem
                        ? null
                        : (v) => setState(() => _durum = v!),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _ogrenci,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'İlgili öğrenci (isteğe bağlı)',
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('Sınıf geneli'),
                      ),
                      for (final o in widget.ogrenciler)
                        DropdownMenuItem(
                          value: o['OgrenciId'] as int,
                          child: Text(
                            '${o['OkulNo']} • ${o['Ad']} ${o['Soyad']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _islem
                        ? null
                        : (v) => setState(() => _ogrenci = v),
                  ),
                  if (widget.tur == 'Toplanti')
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _toplantiTuru,
                      decoration: const InputDecoration(
                        labelText: 'Toplantı türü',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Veli',
                          child: Text('Veli toplantısı'),
                        ),
                        DropdownMenuItem(
                          value: 'SOK',
                          child: Text(
                            'Sınıf/Şube Öğretmenler Kurulu',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Ogrenci',
                          child: Text('Öğrenci toplantısı'),
                        ),
                      ],
                      onChanged: _islem
                          ? null
                          : (v) => setState(() => _toplantiTuru = v!),
                    ),
                  for (final a in _alanAdlari.entries)
                    TextFormField(
                      controller: _alanlar[a.key],
                      maxLines: null,
                      minLines: a.key == 'saat' ? 1 : 2,
                      maxLength: 10000,
                      decoration: InputDecoration(labelText: a.value),
                    ),
                  SwitchListTile(
                    title: const Text('Hassas kayıt'),
                    subtitle: Text(
                      widget.baslangicHassas
                          ? 'Hassas kaynak kayıttan devralındı; genel belge çıktısına eklenmez.'
                          : 'Genel belge çıktısına eklenmez.',
                    ),
                    value: _hassas,
                    onChanged: _islem || widget.baslangicHassas
                        ? null
                        : (v) async {
                            try {
                              await _hassasDegistir(v);
                            } catch (e) {
                              if (mounted) {
                                setState(
                                  () => _hata = 'Erişim doğrulanamadı: $e',
                                );
                              }
                            }
                          },
                  ),
                  FilledButton(
                    onPressed: _islem ? null : _kaydet,
                    child: const Text('Kaydet'),
                  ),
                ],
              ),
            ),
    ),
  );
}
