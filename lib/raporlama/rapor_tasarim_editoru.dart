import '../widgets/ortak_genisleyen_bolum.dart';
import 'package:flutter/material.dart';

import 'rapor_modeli.dart';

class RaporTasarimEditoru extends StatelessWidget {
  const RaporTasarimEditoru({
    super.key,
    required this.tanim,
    required this.tasarim,
    required this.veri,
    required this.onDegistir,
    this.onMetinDegisti,
  });

  final RaporTanimi tanim;
  final RaporTasarimi tasarim;
  final RaporVerisi veri;
  final ValueChanged<VoidCallback> onDegistir;
  final VoidCallback? onMetinDegisti;

  String _etiket(List<RaporAlanTanimi> katalog, String id) {
    for (final alan in katalog) {
      if (alan.id == id) return alan.etiket;
    }
    return id;
  }

  bool _serbestMetin(String id) => tanim.bilgiAlanlari.any((alan) =>
      alan.id == id && alan.serbestMetin);

  void _metniDegistir(VoidCallback islem) {
    onDegistir(islem);
    onMetinDegisti?.call();
  }

  void _mesaj(BuildContext context, String metin) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(metin)));
  }

  void _bilgiEkle(BuildContext context, RaporAlanTanimi alan) {
    if (tasarim.bilgiler.length >= 16) {
      _mesaj(context, 'En fazla 16 bilgi alanı eklenebilir.');
      return;
    }
    onDegistir(() => tasarim.bilgiler.add(RaporBilgiAlani(alanId: alan.id,
        sabitMetin: alan.serbestMetin ? 'Yeni başlık' : null)));
  }

  void _sutunEkle(BuildContext context, RaporAlanTanimi alan) {
    if (tasarim.sutunlar.length >= 16) {
      _mesaj(context, 'En fazla 16 sütun eklenebilir.');
      return;
    }
    onDegistir(() => tasarim.sutunlar.add(
        RaporTabloSutunu(alanId: alan.id, baslik: alan.etiket)));
  }

  void _sutunGoster(BuildContext context, RaporTabloSutunu sutun, bool goster) {
    if (!goster && sutun.goster && tasarim.gorunenSutunlar.length <= 1) {
      _mesaj(context, 'En az bir görünür sütun seçin.');
      return;
    }
    onDegistir(() => sutun.goster = goster);
  }

  void _sutunSil(BuildContext context, RaporTabloSutunu sutun) {
    if (sutun.goster && tasarim.gorunenSutunlar.length <= 1) {
      _mesaj(context, 'En az bir görünür sütun seçin.');
      return;
    }
    onDegistir(() => tasarim.sutunlar.remove(sutun));
  }

  Widget _tutamak(String anahtar, int index) => ReorderableDragStartListener(
    key: ValueKey(anahtar),
    index: index,
    child: const Tooltip(
      message: 'Sürükleyerek sırala',
      triggerMode: TooltipTriggerMode.manual,
      child: SizedBox(width: 48, height: 48, child: Icon(Icons.drag_handle)),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OrtakGenisleyenBolum(
        title: const Text('Bilgiler'),
        initiallyExpanded: true,
        children: [
          const Text('Tiklenen bilgiler çıktıda görünür. Yerini seçin veya tutamaktan sıralayın.'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: ReorderableListView.builder(
              key: const ValueKey('ortak-bilgi-sirasi'),
              shrinkWrap: true,
              primary: false,
              physics: const ClampingScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: tasarim.bilgiler.length,
              onReorderItem: (eski, yeni) => onDegistir(() =>
                  tasarim.bilgiler.insert(yeni, tasarim.bilgiler.removeAt(eski))),
              itemBuilder: (context, i) {
                final bilgi = tasarim.bilgiler[i];
                return Padding(
                  key: ObjectKey(bilgi),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        key: ValueKey('ortak-bilgi-goster-$i'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(_etiket(tanim.bilgiAlanlari, bilgi.alanId),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(bilgi.goster ? 'Görünür' : 'Gizli'),
                        value: bilgi.goster,
                        onChanged: (v) => onDegistir(() => bilgi.goster = v!),
                        secondary: _tutamak('ortak-bilgi-sirala-$i', i),
                      ),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Sayfadaki yeri'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: ValueKey('ortak-bilgi-konum-$i'),
                            value: bilgi.konum,
                            isExpanded: true,
                            isDense: true,
                            items: RaporBilgiAlani.konumlar.entries.map((e) =>
                              DropdownMenuItem(value: e.key, child: Text(e.value,
                                  maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                            onChanged: (v) {
                              if (v != null) onDegistir(() => bilgi.konum = v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          for (final alan in tanim.bilgiAlanlari.where((alan) =>
              !tasarim.bilgiler.any((bilgi) => bilgi.alanId == alan.id)))
            CheckboxListTile(
              key: ValueKey('ortak-bilgi-ekle-${alan.id}'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(alan.etiket),
              value: false,
              onChanged: (_) => _bilgiEkle(context, alan),
            ),
          for (final alan in tanim.bilgiAlanlari.where((alan) =>
              alan.serbestMetin && tasarim.bilgiler.any((bilgi) => bilgi.alanId == alan.id)))
            TextButton.icon(
              key: ValueKey('ortak-bilgi-cogalt-${alan.id}'),
              onPressed: () => _bilgiEkle(context, alan),
              icon: const Icon(Icons.add),
              label: Text('${alan.etiket} ekle'),
            ),
          OrtakGenisleyenBolum(
            title: const Text('Bilgi ayrıntıları'),
            children: [
              for (final bilgi in tasarim.bilgiler)
                Padding(
                  key: ObjectKey(bilgi),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Text(_etiket(tanim.bilgiAlanlari, bilgi.alanId))),
                        IconButton(tooltip: 'Bilgi alanını kaldır',
                            onPressed: () => onDegistir(() => tasarim.bilgiler.remove(bilgi)),
                            icon: const Icon(Icons.close)),
                      ]),
                      TextFormField(
                        initialValue: _serbestMetin(bilgi.alanId)
                            ? bilgi.sabitMetin ?? '' : bilgi.onEtiket,
                        maxLength: 160,
                        decoration: InputDecoration(labelText:
                            _serbestMetin(bilgi.alanId) ? 'Metin' : 'Ön etiket'),
                        onChanged: (v) => _metniDegistir(() {
                          if (_serbestMetin(bilgi.alanId)) {
                            bilgi.sabitMetin = v;
                          } else {
                            bilgi.onEtiket = v;
                          }
                        }),
                      ),
                      TextFormField(
                        initialValue: bilgi.altMetin,
                        maxLength: 160,
                        decoration: const InputDecoration(labelText: 'Alt metin'),
                        onChanged: (v) => _metniDegistir(() => bilgi.altMetin = v),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      OrtakGenisleyenBolum(
        key: const ValueKey('ortak-yerlesim-paneli'),
        title: const Text('Sürükle bırak yerleşimi'),
        children: [RaporYerlesimAlani(tanim: tanim, tasarim: tasarim,
            veri: veri, onDegistir: onDegistir)],
      ),
      OrtakGenisleyenBolum(
        title: const Text('Sütunlar'),
        initiallyExpanded: true,
        children: [
          const Text('Tiklenen sütunlar çıktıda görünür. Tutamaktan sürükleyerek sıralayın.'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: ReorderableListView.builder(
              key: const ValueKey('ortak-sutun-sirasi'),
              shrinkWrap: true,
              primary: false,
              physics: const ClampingScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: tasarim.sutunlar.length,
              onReorderItem: (eski, yeni) => onDegistir(() =>
                  tasarim.sutunlar.insert(yeni, tasarim.sutunlar.removeAt(eski))),
              itemBuilder: (context, i) {
                final sutun = tasarim.sutunlar[i];
                return KeyedSubtree(key: ObjectKey(sutun), child: CheckboxListTile(
                  key: ValueKey('ortak-sutun-goster-$i'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(sutun.baslik, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(sutun.goster ? 'Görünür' : 'Gizli'),
                  value: sutun.goster,
                  onChanged: (v) => _sutunGoster(context, sutun, v!),
                  secondary: _tutamak('ortak-sutun-sirala-$i', i),
                ));
              },
            ),
          ),
          for (final alan in tanim.sutunAlanlari.where((alan) =>
              !tasarim.sutunlar.any((sutun) => sutun.alanId == alan.id)))
            CheckboxListTile(
              key: ValueKey('ortak-sutun-ekle-${alan.id}'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(alan.etiket),
              value: false,
              onChanged: (_) => _sutunEkle(context, alan),
            ),
          for (final alan in tanim.sutunAlanlari.where((alan) =>
              alan.tur == RaporHucreTuru.bos &&
              tasarim.sutunlar.any((sutun) => sutun.alanId == alan.id)))
            TextButton.icon(
              key: ValueKey('ortak-sutun-cogalt-${alan.id}'),
              onPressed: () => _sutunEkle(context, alan),
              icon: const Icon(Icons.add),
              label: Text('${alan.etiket} ekle'),
            ),
          OrtakGenisleyenBolum(
            title: const Text('Sütun ayrıntıları'),
            children: [
              for (final sutun in tasarim.sutunlar)
                Padding(
                  key: ObjectKey(sutun),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Text(_etiket(tanim.sutunAlanlari, sutun.alanId))),
                        IconButton(tooltip: 'Sütunu kaldır',
                            onPressed: () => _sutunSil(context, sutun),
                            icon: const Icon(Icons.close)),
                      ]),
                      TextFormField(
                        initialValue: sutun.baslik,
                        maxLength: 50,
                        decoration: const InputDecoration(labelText: 'Sütun başlığı'),
                        onChanged: (v) => _metniDegistir(() => sutun.baslik = v),
                      ),
                      Text('Genişlik: ${sutun.genislik.round()}'),
                      Slider(
                        value: sutun.genislik,
                        min: 1,
                        max: 8,
                        divisions: 7,
                        onChanged: (v) => onDegistir(() => sutun.genislik = v),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      OrtakGenisleyenBolum(
        title: const Text('Sayfa düzeni'),
        children: [
          SwitchListTile(title: const Text('Yatay A4'), value: tasarim.yatay,
              onChanged: (v) => onDegistir(() => tasarim.yatay = v)),
          SwitchListTile(title: const Text('Mümkünse tek sayfaya sığdır'),
              subtitle: const Text('Sığmayan liste sonraki sayfada devam eder.'),
              value: tasarim.tekSayfayaSigdir,
              onChanged: (v) => onDegistir(() => tasarim.tekSayfayaSigdir = v)),
          Text('Yazı boyutu: ${tasarim.yaziBoyutu.round()}'),
          Slider(value: tasarim.yaziBoyutu, min: 6, max: 18, divisions: 12,
              onChanged: (v) => onDegistir(() => tasarim.yaziBoyutu = v)),
          Text('Satır yüksekliği: ${tasarim.satirYuksekligi.round()}'),
          Slider(value: tasarim.satirYuksekligi, min: 16, max: 100, divisions: 42,
              onChanged: (v) => onDegistir(() => tasarim.satirYuksekligi = v)),
        ],
      ),
    ],
  );
}

class RaporYerlesimAlani extends StatelessWidget {
  const RaporYerlesimAlani({super.key, required this.tanim, required this.tasarim,
    required this.veri, required this.onDegistir});

  final RaporTanimi tanim;
  final RaporTasarimi tasarim;
  final RaporVerisi veri;
  final ValueChanged<VoidCallback> onDegistir;

  bool _kabulEdilir(RaporBilgiAlani bilgi) =>
      bilgi.goster && tasarim.bilgiler.contains(bilgi);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Bilgiyi basılı tutup istediğiniz bölgeye sürükleyin.'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          _bolgeSatiri(context, const ['ustSol', 'ustOrta', 'ustSag']),
          Padding(padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(tanim.listeEtiketi, textAlign: TextAlign.center)),
          _bolgeSatiri(context, const ['altSol', 'altOrta', 'altSag']),
        ]),
      ),
    ],
  );

  Widget _bolgeSatiri(BuildContext context, List<String> konumlar) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < konumlar.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(child: _bolge(context, konumlar[i])),
      ],
    ],
  );

  Widget _bolge(BuildContext context, String konum) {
    final renkler = Theme.of(context).colorScheme;
    final bilgiler = <Widget>[];
    for (var i = 0; i < tasarim.bilgiler.length; i++) {
      final bilgi = tasarim.bilgiler[i];
      if (!bilgi.goster || bilgi.konum != konum) continue;
      final alanlar = tanim.bilgiAlanlari.where((alan) => alan.id == bilgi.alanId);
      final etiket = alanlar.isEmpty ? bilgi.alanId : alanlar.first.etiket;
      final yazi = bilgi.yazi(veri.bilgiler);
      bilgiler.add(LongPressDraggable<RaporBilgiAlani>(
        key: ValueKey('ortak-bilgi-surukle-$i'),
        data: bilgi,
        maxSimultaneousDrags: 1,
        feedback: Material(type: MaterialType.transparency,
            child: SizedBox(width: 160, child: _etiket(context, etiket, yazi))),
        childWhenDragging: Opacity(opacity: 0.35, child: _etiket(context, etiket, yazi)),
        child: Tooltip(message: 'Basılı tutup sürükleyin',
            triggerMode: TooltipTriggerMode.manual,
            child: _etiket(context, etiket, yazi)),
      ));
    }
    return DragTarget<RaporBilgiAlani>(
      key: ValueKey('ortak-bolge-$konum'),
      onWillAcceptWithDetails: (details) => _kabulEdilir(details.data),
      onAcceptWithDetails: (details) {
        if (_kabulEdilir(details.data)) onDegistir(() => details.data.konum = konum);
      },
      builder: (context, adaylar, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 200,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: adaylar.isNotEmpty ? renkler.primaryContainer : renkler.surface,
          border: Border.all(color: adaylar.isNotEmpty ? renkler.primary : renkler.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(RaporBilgiAlani.konumlar[konum]!, maxLines: 2,
              overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Expanded(child: bilgiler.isEmpty
              ? Center(child: Text('Buraya bırakın', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: renkler.onSurfaceVariant)))
              : ListView.separated(primary: false, padding: EdgeInsets.zero,
                  itemCount: bilgiler.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 5),
                  itemBuilder: (_, i) => bilgiler[i])),
        ]),
      ),
    );
  }

  Widget _etiket(BuildContext context, String etiket, String yazi) {
    final renkler = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: renkler.secondaryContainer,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: renkler.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(etiket, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                  color: renkler.onSecondaryContainer))),
          Icon(Icons.drag_indicator, size: 12, color: renkler.onSecondaryContainer),
        ]),
        const SizedBox(height: 2),
        Text(yazi.isEmpty ? 'Bilgi girilmedi' : yazi, maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: renkler.onSecondaryContainer)),
      ]),
    );
  }
}
