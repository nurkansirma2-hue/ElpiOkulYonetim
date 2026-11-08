import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class OgrenciFotoWidget extends StatelessWidget {
  final String? fotoYolu;
  final Uint8List? fotoVerisi;
  final bool yerel;
  final double? width;
  final double? height;
  final double radius;
  final bool daire;
  final IconData bosIcon;
  final BoxFit fit;

  const OgrenciFotoWidget({
    super.key,
    required this.fotoYolu,
    this.fotoVerisi,
    this.yerel = false,
    this.width,
    this.height,
    this.radius = 12,
    this.daire = true,
    this.bosIcon = Icons.person,
    this.fit = BoxFit.cover,
  });

  String get _temizYol => (fotoYolu ?? '').trim();

  bool get _fotoVar => _temizYol.isNotEmpty;

  bool get _isFullNetworkImage {
    return _temizYol.startsWith('http://') || _temizYol.startsWith('https://');
  }

  bool get _isRelativeApiImage {
    return _temizYol.startsWith('/resimler/');
  }

  Widget _bosGorsel() {
    if (daire) {
      return CircleAvatar(
        radius: (width ?? 60) / 2,
        backgroundColor: Colors.blue.shade100,
        child: Icon(bosIcon, color: Colors.blue),
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(bosIcon, size: 50, color: Colors.grey),
    );
  }

  Widget _fileGorsel(String yol) {
    final file = File(yol);

    if (!file.existsSync()) {
      return _bosGorsel();
    }

    if (daire) {
      return CircleAvatar(
        radius: (width ?? 60) / 2,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: FileImage(file),
        onBackgroundImageError: (_, __) {},
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return _bosGorsel();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final veri = fotoVerisi;
    if (veri != null && veri.isNotEmpty) {
      final gorsel = Image.memory(
        veri,
        width: width ?? 60,
        height: height ?? width ?? 60,
        fit: fit,
        cacheWidth: ((width ?? 60) * MediaQuery.devicePixelRatioOf(context))
            .round(),
        errorBuilder: (_, __, ___) => _bosGorsel(),
      );
      return daire
          ? ClipOval(child: gorsel)
          : ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: gorsel,
            );
    }
    if (_isFullNetworkImage || _isRelativeApiImage) return _bosGorsel();
    if (!_fotoVar) {
      return _bosGorsel();
    }

    return _fileGorsel(_temizYol);
  }
}
