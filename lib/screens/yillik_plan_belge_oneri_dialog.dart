import 'package:flutter/material.dart';
import '../services/yillik_plan_belge_oneri_service.dart';

/// -1 manuel seçim; null iptal; diğer değerler aday listesindeki sıradır.
Future<int?> yillikPlanBelgeOnerisiniGoster(
  BuildContext context,
  List<YillikPlanBelgeAdayi> adaylar,
) => showDialog<int>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Drive’da uygun olabilecek planlar'),
    scrollable: true,
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'İzin verdiğiniz dosyalar arasından bulundu. '
            'Kullanmadan önce ön izlemede kontrol edin.',
          ),
          for (var i = 0; i < adaylar.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(adaylar[i].dosya.ad),
                    for (final uyari in adaylar[i].uyarilar) Text(uyari),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, i),
                      child: const Text('Kullan ve ön izle'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('İptal'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(ctx, -1),
        child: const Text('Başka Belge Seç'),
      ),
    ],
  ),
);
