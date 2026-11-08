import 'ortak_ui.dart';
import 'package:flutter/material.dart';
import '../models/odev_kontrol.dart';
import 'modul_ust_bar.dart';

const odevMavi = Color(0xff0066ff);
const odevBaslikMavi = Color(0xff125f9c);
const odevCizgi = Color(0xffe7edf4);

class OdevTema extends StatelessWidget {
  const OdevTema({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => OrtakTema(child: child);
}

class OdevBaslik extends ModulUstBar {
  const OdevBaslik({super.key, super.title, super.actions, super.kompakt});
}

String odevDurumAdi(OdevKontrolDurumu d) => d.baslik;

Color odevDurumRengi(OdevKontrolDurumu d) => switch (d) {
  OdevKontrolDurumu.yapti => const Color(0xff14802a),
  OdevKontrolDurumu.kismen => const Color(0xff886500),
  OdevKontrolDurumu.yapmadi => const Color(0xffe43e52),
  _ => const Color(0xff48515c),
};
Color odevDurumZemini(OdevKontrolDurumu d) => switch (d) {
  OdevKontrolDurumu.yapti => const Color(0xffdef6df),
  OdevKontrolDurumu.kismen => const Color(0xfffff4cf),
  OdevKontrolDurumu.yapmadi => const Color(0xffffe5e8),
  _ => const Color(0xffeceef0),
};

class OdevFormSayfasi extends StatelessWidget {
  const OdevFormSayfasi({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.subtitle,
  });
  final Widget title, content;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: OdevTema(
      child: OrtakSayfa(
        appBar: OdevBaslik(
          title: subtitle == null
              ? title
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    Text(subtitle!, style: const TextStyle(fontSize: 12)),
                  ],
                ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ),
        bottomNavigationBar: actions.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    ),
  );
}
