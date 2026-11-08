import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';

class TestModuluScreen extends StatelessWidget {
  const TestModuluScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OrtakSayfa(
      appBar: const ModulUstBar(title: Text('Test Modülü')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Test Modülü açıldı',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Bu ekran, yeni modülün uygulamaya eklendiğini kontrol etmek içindir. '
                  'Okul ve öğrenci verilerinde değişiklik yapmaz.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Ana sayfaya dön'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
