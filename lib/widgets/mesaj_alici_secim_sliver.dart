import 'ortak_genisleyen_bolum.dart';
import 'package:flutter/material.dart';
import '../models/mesajlasma.dart';
import 'mesajlasma_gorunumu.dart';

/// Yalnız seçim arayüzü; veri yetkisi ve gönderim ortak serviste kalır.
class MesajAliciSecimSliver extends StatefulWidget {
  const MesajAliciSecimSliver({
    super.key,
    required this.adaylar,
    required this.siniflar,
    required this.secilenler,
    required this.degistir,
    required this.veliDuzenle,
    required this.ogretmenDuzenle,
    required this.kisiDuzenle,
    this.programdanAktar,
    this.aliciTuruDegisti,
    this.kilitli = false,
    this.ogrenciKapsami = false,
    this.iletisimDuzenleme = true,
    this.sadeceOgretmen = false,
    this.baslangicSinifId,
    this.baslangicAliciTuru,
  });
  final List<MesajKisi> adaylar;
  final Map<int, String> siniflar;
  final Map<String, MesajKisi> secilenler;
  final ValueChanged<List<MesajKisi>> degistir;
  final Future<void> Function(int ogrenciId) veliDuzenle;
  final Future<void> Function(String? kisiId, int? sinifId) ogretmenDuzenle;
  final Future<void> Function(MesajKisi kisi) kisiDuzenle;
  final Future<void> Function(int sinifId)? programdanAktar;
  final bool kilitli;
  final bool ogrenciKapsami;
  final bool iletisimDuzenleme;
  final bool sadeceOgretmen;
  final int? baslangicSinifId;
  final MesajKisiTuru? baslangicAliciTuru;
  final ValueChanged<MesajKisiTuru?>? aliciTuruDegisti;
  @override
  State<MesajAliciSecimSliver> createState() => _MesajAliciSecimState();
}

class _MesajAliciSecimState extends State<MesajAliciSecimSliver> {
  final _arama = TextEditingController();
  int? _sinif;
  bool _ogretmenler = false, _secimAcik = false, _aliciListesiAcik = false;
  int _listeSurumu = 0;
  bool _grupListesiAcik = false;
  bool _hedefSecimiGoster = false, _hedefListesiAcik = true;
  MesajKisiTuru? _ogrenciHedefi;
  @override
  void initState() {
    super.initState();
    if (widget.ogrenciKapsami) _ogrenciHedefi = MesajKisiTuru.ogrenci;
    if (widget.baslangicSinifId != null &&
        widget.siniflar.containsKey(widget.baslangicSinifId)) {
      _sinif = widget.baslangicSinifId;
      _ogrenciHedefi = widget.baslangicAliciTuru;
      _hedefSecimiGoster = widget.baslangicAliciTuru != null;
      _hedefListesiAcik = false;
    }
    if (widget.sadeceOgretmen && widget.siniflar.length == 1) {
      _sinif = widget.siniflar.keys.single;
      _ogretmenler = true;
    }
  }

  @override
  void dispose() {
    _arama.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MesajAliciSecimSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sinif != 0 && !widget.siniflar.containsKey(_sinif)) {
      _sinif = null;
      _ogretmenler = false;
    }
  }

  Future<void> _ogrenciSec(List<MesajKisi> ogrenciler) async {
    if (widget.kilitli || _secimAcik || ogrenciler.isEmpty) return;
    if (_hedefSecimiGoster && _ogrenciHedefi == null) {
      setState(() {
        _hedefListesiAcik = true;
        _listeSurumu++;
      });
      return;
    }
    setState(() => _secimAcik = true);
    try {
      final tur =
          _ogrenciHedefi ??
          await showDialog<MesajKisiTuru>(
            context: context,
            builder: (c) => SimpleDialog(
              title: Text(
                ogrenciler.length == 1
                    ? 'Mesaj kime gönderilsin?'
                    : '${ogrenciler.length} öğrenci için alıcı seçin',
              ),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, MesajKisiTuru.ogrenci),
                  child: Text(
                    ogrenciler.length == 1
                        ? 'Öğrencinin kendisine'
                        : 'Öğrencilerin kendilerine',
                  ),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, MesajKisiTuru.veli),
                  child: Text(
                    ogrenciler.length == 1 ? 'Velisine' : 'Velilerine',
                  ),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('İptal'),
                ),
              ],
            ),
          );
      if (tur == null || !mounted || widget.kilitli) return;
      widget.aliciTuruDegisti?.call(tur);
      final yeni = Map<String, MesajKisi>.of(widget.secilenler);
      for (final o in ogrenciler) {
        final uygun = widget.adaylar.where(
          (k) => k.tur == tur && k.kisiId == o.kisiId && k.sinifId == o.sinifId,
        );
        if (uygun.isNotEmpty) {
          yeni.putIfAbsent(uygun.first.secimAnahtari, () => uygun.first);
        }
      }
      widget.degistir(yeni.values.toList());
      setState(() {
        _aliciListesiAcik = false;
        _listeSurumu++;
      });
    } finally {
      if (mounted) setState(() => _secimAcik = false);
    }
  }

  void _ogretmenSec(List<MesajKisi> kisiler, {bool cikar = false}) {
    final yeni = Map<String, MesajKisi>.of(widget.secilenler);
    for (final k in kisiler) {
      if (cikar) {
        yeni.remove(k.secimAnahtari);
      } else {
        yeni.putIfAbsent(k.secimAnahtari, () => k);
      }
    }
    widget.degistir(yeni.values.toList());
    setState(() {
      _aliciListesiAcik = false;
      _listeSurumu++;
    });
  }

  Future<void> _ogretmenleriGoster() async {
    if (widget.kilitli || _secimAcik || _sinif == null) return;
    widget.aliciTuruDegisti?.call(MesajKisiTuru.ogretmen);
    setState(() {
      _ogretmenler = true;
      _aliciListesiAcik = false;
      _grupListesiAcik = false;
      _listeSurumu++;
    });
    if (widget.adaylar.any(
      (k) =>
          k.tur == MesajKisiTuru.ogretmen &&
          (_sinif == 0 || k.sinifId == _sinif),
    )) {
      return;
    }
    final aktar = widget.programdanAktar;
    if (aktar == null || _sinif == 0) return;
    setState(() => _secimAcik = true);
    try {
      await aktar(_sinif!);
    } finally {
      if (mounted) setState(() => _secimAcik = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final arama = _arama.text.trim().toLowerCase();
    final ogretmen = widget.sadeceOgretmen || (_ogretmenler && arama.isEmpty);
    final listeGoster =
        (_sinif != null || arama.isNotEmpty) &&
        (ogretmen ||
            _ogrenciHedefi != null ||
            (arama.isNotEmpty && !_hedefSecimiGoster));
    final bulunan = <String, MesajKisi>{};
    for (final k in widget.adaylar) {
      if (k.tur !=
          (ogretmen ? MesajKisiTuru.ogretmen : MesajKisiTuru.ogrenci)) {
        continue;
      }
      if (arama.isEmpty
          ? (_sinif == null || (_sinif != 0 && k.sinifId != _sinif))
          : !'${k.ad} ${k.aciklama}'.toLowerCase().contains(arama)) {
        continue;
      }
      bulunan.putIfAbsent(k.secimAnahtari, () => k);
    }
    final rows = bulunan.values.toList();
    bool secili(MesajKisi k) => ogretmen
        ? widget.secilenler.containsKey(k.secimAnahtari)
        : _ogrenciHedefi != null
        ? widget.secilenler.containsKey(
            '${_ogrenciHedefi == MesajKisiTuru.ogrenci ? 'Ogrenci' : 'Veli'}:${k.kisiId}',
          )
        : widget.secilenler.containsKey('Ogrenci:${k.kisiId}') ||
              widget.secilenler.containsKey('Veli:${k.kisiId}');
    final seciliSayisi = rows.where(secili).length;
    final kilitli = widget.kilitli || _secimAcik;
    final siniflar = widget.siniflar.entries.toList()
      ..sort((a, b) {
        final seviye = RegExp(r'^\s*(\d+)');
        final aSeviye =
            int.tryParse(seviye.firstMatch(a.value)?.group(1) ?? '') ?? 0;
        final bSeviye =
            int.tryParse(seviye.firstMatch(b.value)?.group(1) ?? '') ?? 0;
        final sonuc = aSeviye.compareTo(bSeviye);
        return sonuc == 0 ? a.value.compareTo(b.value) : sonuc;
      });
    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MesajAdimBasligi(
                adim: 1,
                baslik: widget.sadeceOgretmen
                    ? 'Ders öğretmenlerini seç'
                    : widget.ogrenciKapsami
                    ? 'Formun öğrencilerini seç'
                    : 'Alıcıları seç',
                aciklama: widget.sadeceOgretmen
                    ? 'Form bağlantısının gönderileceği öğretmenler.'
                    : widget.ogrenciKapsami
                    ? 'Formun hangi öğrenciler hakkında olduğunu belirleyin.'
                    : 'Mesaj göndermek istediğiniz öğrencileri belirleyin.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('mesaj-ogrenci-arama'),
                controller: _arama,
                enabled: !kilitli,
                onChanged: (_) => setState(() {
                  widget.aliciTuruDegisti?.call(_ogrenciHedefi);
                  _sinif = widget.sadeceOgretmen && widget.siniflar.length == 1
                      ? widget.siniflar.keys.single
                      : null;
                  _ogretmenler = widget.sadeceOgretmen;
                  _aliciListesiAcik = true;
                }),
                decoration: InputDecoration(
                  labelText: widget.sadeceOgretmen
                      ? 'Öğretmen ara'
                      : 'Öğrenci ara',
                  hintText: 'Ad, soyad, sınıf veya numara',
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              MesajSecimYuzeyi(
                icon: Icons.badge_outlined,
                renk: mesajSinifRengi,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('mesaj-sinif-$_sinif'),
                  initialValue: _sinif,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sınıf',
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Sınıf seçin'),
                    ),
                    const DropdownMenuItem<int>(
                      value: 0,
                      child: Text('Tüm sınıflar'),
                    ),
                    for (final e in siniflar)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: kilitli || widget.siniflar.isEmpty
                      ? null
                      : (v) => setState(() {
                          widget.aliciTuruDegisti?.call(_ogrenciHedefi);
                          _sinif = v;
                          _ogretmenler = widget.sadeceOgretmen;
                          _aliciListesiAcik = false;
                          _grupListesiAcik = false;
                          _listeSurumu++;
                          _arama.clear();
                        }),
                ),
              ),
              if (_sinif != null &&
                  !widget.ogrenciKapsami &&
                  !widget.sadeceOgretmen)
                MesajAciliKarti(
                  renk: mesajGrupRengi,
                  margin: const EdgeInsets.only(top: 8),
                  clipBehavior: Clip.antiAlias,
                  child: OrtakGenisleyenBolum(
                    dense: true,
                    minTileHeight: 48,
                    key: ValueKey('mesaj-alici-grubu-$_sinif-$_listeSurumu'),
                    initiallyExpanded: _grupListesiAcik,
                    onExpansionChanged: (v) =>
                        setState(() => _grupListesiAcik = v),
                    title: const Text('Alıcı grubu'),
                    leading: const MesajRenkliSimge(
                      icon: Icons.groups_outlined,
                      renk: mesajGrupRengi,
                    ),
                    subtitle: Text(
                      _ogretmenler ? 'Ders öğretmenleri' : 'Öğrenciler',
                    ),
                    children: [
                      ListTile(
                        title: const Text('Sınıf öğrencileri'),
                        leading: const Icon(Icons.groups_outlined),
                        selected: !_ogretmenler,
                        trailing: !_ogretmenler
                            ? const Icon(Icons.check)
                            : null,
                        enabled: !kilitli,
                        onTap: kilitli
                            ? null
                            : () => setState(() {
                                widget.aliciTuruDegisti?.call(_ogrenciHedefi);
                                _ogretmenler = false;
                                _aliciListesiAcik = false;
                                _grupListesiAcik = false;
                                _hedefSecimiGoster = true;
                                _hedefListesiAcik = true;
                                _listeSurumu++;
                              }),
                      ),
                      ListTile(
                        title: const Text('Sınıfta derse giren öğretmenler'),
                        leading: const Icon(Icons.school_outlined),
                        selected: _ogretmenler,
                        trailing: _ogretmenler ? const Icon(Icons.check) : null,
                        enabled: !kilitli,
                        onTap: kilitli ? null : _ogretmenleriGoster,
                      ),
                    ],
                  ),
                ),
              if (!ogretmen &&
                  _hedefSecimiGoster &&
                  (_sinif != null || arama.isNotEmpty))
                MesajAciliKarti(
                  renk: mesajVeliRengi,
                  margin: const EdgeInsets.only(top: 8),
                  clipBehavior: Clip.antiAlias,
                  child: OrtakGenisleyenBolum(
                    dense: true,
                    minTileHeight: 48,
                    key: ValueKey('mesaj-ogrenci-hedefi-$_listeSurumu'),
                    initiallyExpanded: _hedefListesiAcik,
                    onExpansionChanged: (v) =>
                        setState(() => _hedefListesiAcik = v),
                    leading: const MesajRenkliSimge(
                      icon: Icons.person_outline,
                      renk: mesajVeliRengi,
                    ),
                    title: Text(
                      _ogrenciHedefi == null
                          ? 'Mesaj kime gönderilsin?'
                          : 'Mesaj alıcısı: ${_ogrenciHedefi == MesajKisiTuru.ogrenci ? 'Kendisi' : 'Velisi'}',
                      key: const ValueKey('mesaj-ogrenci-hedef-basligi'),
                    ),
                    children: [
                      for (final hedef in [
                        MesajKisiTuru.ogrenci,
                        MesajKisiTuru.veli,
                      ])
                        ListTile(
                          key: ValueKey('mesaj-ogrenci-hedef-${hedef.name}'),
                          title: Text(
                            hedef == MesajKisiTuru.ogrenci
                                ? 'Kendisi'
                                : 'Velisi',
                          ),
                          leading: Icon(
                            hedef == MesajKisiTuru.ogrenci
                                ? Icons.person_outline
                                : Icons.family_restroom,
                          ),
                          selected: _ogrenciHedefi == hedef,
                          trailing: _ogrenciHedefi == hedef
                              ? const Icon(Icons.check)
                              : null,
                          enabled: !kilitli,
                          onTap: kilitli
                              ? null
                              : () => setState(() {
                                  widget.aliciTuruDegisti?.call(hedef);
                                  _ogrenciHedefi = hedef;
                                  _hedefListesiAcik = false;
                                  _aliciListesiAcik = false;
                                  _listeSurumu++;
                                }),
                        ),
                    ],
                  ),
                ),
              if (_sinif == null && arama.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Öğrenci arayın veya sınıf seçin.'),
                ),
              if (widget.siniflar.isEmpty)
                const Text(
                  'Ders sınıfı bulunamadı. Önce ders programınızı yükleyin.',
                ),
            ],
          ),
        ),
        if (listeGoster)
          MesajAciliKarti(
            renk: mesajListeRengi,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            clipBehavior: Clip.antiAlias,
            child: OrtakGenisleyenBolum(
              dense: true,
              minTileHeight: 48,
              key: ValueKey(
                'mesaj-alici-listesi-$_sinif-$ogretmen-$arama-$_listeSurumu',
              ),
              initiallyExpanded: _aliciListesiAcik,
              onExpansionChanged: (v) => setState(() => _aliciListesiAcik = v),
              leading: const MesajRenkliSimge(
                icon: Icons.format_list_bulleted,
                renk: mesajListeRengi,
              ),
              title: Text(
                '${ogretmen ? 'Öğretmen listesi' : 'Öğrenci listesi'} ($seciliSayisi/${rows.length} seçili)',
                key: const ValueKey('mesaj-alici-liste-basligi'),
              ),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: kilitli || rows.isEmpty
                          ? null
                          : () {
                              if (ogretmen) {
                                _ogretmenSec(rows);
                              } else {
                                _ogrenciSec(rows);
                              }
                            },
                      child: const Text('Görünenleri seç'),
                    ),
                    TextButton(
                      onPressed: kilitli || seciliSayisi == 0
                          ? null
                          : () {
                              final anahtarlar = <String>{
                                for (final k in rows)
                                  if (ogretmen)
                                    k.secimAnahtari
                                  else ...[
                                    if (_ogrenciHedefi != MesajKisiTuru.veli)
                                      'Ogrenci:${k.kisiId}',
                                    if (_ogrenciHedefi != MesajKisiTuru.ogrenci)
                                      'Veli:${k.kisiId}',
                                  ],
                              };
                              widget.degistir(
                                widget.secilenler.values
                                    .where(
                                      (k) =>
                                          !anahtarlar.contains(k.secimAnahtari),
                                    )
                                    .toList(),
                              );
                            },
                      child: const Text('Seçimi kaldır'),
                    ),
                  ],
                ),
                if (rows.isEmpty)
                  Text(
                    ogretmen
                        ? 'Bu sınıfta kayıtlı ders öğretmeni yok. Aktarım için Import Merkezi’ni kullanın.'
                        : 'Eşleşen öğrenci bulunamadı.',
                  ),
              ],
            ),
          ),
        if (listeGoster && _aliciListesiAcik)
          for (final k in rows)
            ListTile(
              key: ValueKey('mesaj-aday-${k.secimAnahtari}'),
              leading: Checkbox(
                value: secili(k),
                onChanged: kilitli
                    ? null
                    : (v) {
                        if (ogretmen) {
                          _ogretmenSec([k], cikar: v != true);
                        } else if (v == true) {
                          _ogrenciSec([k]);
                        } else {
                          widget.degistir(
                            widget.secilenler.values
                                .where(
                                  (s) =>
                                      s.tur == MesajKisiTuru.ogretmen ||
                                      s.kisiId != k.kisiId ||
                                      (_ogrenciHedefi != null &&
                                          s.tur != _ogrenciHedefi),
                                )
                                .toList(),
                          );
                          setState(() {
                            _aliciListesiAcik = false;
                            _listeSurumu++;
                          });
                        }
                      },
              ),
              title: Text(k.ad),
              subtitle: Text(
                ogretmen && k.aciklama.contains(' • ')
                    ? k.aciklama.substring(k.aciklama.indexOf(' • ') + 3)
                    : k.aciklama,
              ),
              onTap: kilitli
                  ? null
                  : () {
                      if (ogretmen) {
                        _ogretmenSec(
                          [k],
                          cikar: widget.secilenler.containsKey(k.secimAnahtari),
                        );
                      } else {
                        _ogrenciSec([k]);
                      }
                    },
              trailing: widget.ogrenciKapsami || !widget.iletisimDuzenleme
                  ? null
                  : IconButton(
                      key: ValueKey(
                        ogretmen
                            ? 'ogretmen-duzenle-${k.kisiId}'
                            : 'veli-duzenle-${k.kisiId}',
                      ),
                      tooltip: ogretmen
                          ? 'Öğretmeni düzenle'
                          : _ogrenciHedefi == MesajKisiTuru.ogrenci
                          ? 'Öğrenci telefonunu düzenle'
                          : 'Veli bilgilerini düzenle',
                      onPressed: kilitli
                          ? null
                          : () => ogretmen
                                ? widget.ogretmenDuzenle(k.kisiId, _sinif)
                                : _ogrenciHedefi == MesajKisiTuru.ogrenci
                                ? widget.kisiDuzenle(k)
                                : widget.veliDuzenle(int.parse(k.kisiId)),
                      icon: const Icon(Icons.edit_outlined),
                    ),
            ),
      ]),
    );
  }
}
