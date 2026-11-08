import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UygulamaEkleTanitim extends StatefulWidget {
  const UygulamaEkleTanitim({
    super.key,
    required this.child,
    this.enabled = true,
  });
  static const tercihAnahtari = 'ders_uygulama_ekle_tanitim_gizle_v1';
  final Widget child;
  final bool enabled;
  @override
  State<UygulamaEkleTanitim> createState() => _UygulamaEkleTanitimState();
}

class _UygulamaEkleTanitimState extends State<UygulamaEkleTanitim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animasyon = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  Timer? _sure;
  bool _goster = false, _bitti = false;
  @override
  void initState() {
    super.initState();
    _baslat();
  }

  Future<void> _baslat() async {
    late SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (!mounted ||
        !widget.enabled ||
        prefs.getBool(UygulamaEkleTanitim.tercihAnahtari) == true) {
      return;
    }
    setState(() => _goster = true);
    if (!MediaQuery.disableAnimationsOf(context)) {
      _animasyon.repeat(reverse: true);
    }
    _sure = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _animasyon.stop();
      setState(() => _bitti = true);
    });
  }

  Future<void> _gizle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kayit = await prefs.setBool(
        UygulamaEkleTanitim.tercihAnahtari,
        true,
      );
      if (mounted && kayit) setState(() => _goster = false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Tercih kaydedilemedi. Yeniden deneyin.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _sure?.cancel();
    _animasyon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AnimatedBuilder(
        animation: _animasyon,
        builder: (ctx, child) => DecoratedBox(
          key: ValueKey(
            _goster && !_bitti ? 'uygulama-ekle-vurgu' : 'uygulama-ekle-normal',
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              if (_goster && !_bitti)
                BoxShadow(
                  color: Theme.of(ctx).colorScheme.primary.withValues(
                    alpha: .15 + _animasyon.value * .35,
                  ),
                  blurRadius: 4 + _animasyon.value * 12,
                  spreadRadius: _animasyon.value * 3,
                ),
            ],
          ),
          child: child,
        ),
        child: widget.child,
      ),
      if (_goster && _bitti)
        Row(
          children: [
            Checkbox(
              key: const ValueKey('uygulama-ekle-bir-daha-gosterme'),
              value: false,
              onChanged: (v) {
                if (v == true) _gizle();
              },
            ),
            Expanded(
              child: GestureDetector(
                onTap: _gizle,
                child: const Text(
                  'Bir daha gösterme',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ),
    ],
  );
}
