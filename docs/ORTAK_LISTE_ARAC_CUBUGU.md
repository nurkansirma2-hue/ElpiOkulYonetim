# Ortak Liste Araç Çubuğu

Kullanıcı isteği: **“Bu ekrana ortak liste kalıbını uygula.”**

Hazır bileşen: `lib/widgets/ortak_liste_arac_cubugu.dart`.
İlk uygulama: Mesajlaşma → Gönderim Geçmişi.

## Davranış

- Alt çubukta **Ara · Filtrele · Sırala** bulunur.
- Ara ve Filtrele ilgili alanları açar/kapatır. Alanı kapatmak seçimi temizlemez.
- Aktif arama veya filtre çubukta vurgulanır; liste üzerinde sonuç sayısı gösterilir.
- Filtre alanları küçük ekranlarda kendi içinde kayar.
- Sıralama seçenekleri ekranın verisine göre belirlenir; seçili seçenek işaretlenir.
- İşlem sürerken çubuk devre dışıdır.
- İsteğe bağlı `ekIslemler` ile ekranın kendi işlem düğmeleri eklenebilir.
- Yeni ekranlara kendiliğinden uygulanmaz. Ekranın veri ve yetki kuralları korunur.

## Kullanım

```dart
OrtakListeAracCubugu<int>(
  etkin: !islemSuruyor,
  aramaAktif: aramaAcik || arama.text.isNotEmpty,
  filtreAktif: filtreAcik || filtreVar,
  ara: () => setState(() => aramaAcik = !aramaAcik),
  filtrele: () => setState(() => filtreAcik = !filtreAcik),
  siralama: siralama,
  siralamaSecenekleri: const {0: 'Yeniden eskiye', 1: 'Ada göre'},
  sirala: (v) => setState(() => siralama = v),
)
```

Çubuk `Scaffold.bottomNavigationBar` veya `OrtakSayfa.bottomNavigationBar`
içinde kullanılır; böylece klavye ve SnackBar ile yerleşimi korunur.
`OrtakSayfa` kullanılırken aynı işlemler `ModulUstBar.actions` içine ayrıca
eklenmez: aksi hâlde ikinci alt çubuk oluşur. Gönderim Geçmişi bu nedenle
**Ara · Filtrele · Sırala · Onayla · Diğer** düzenini tek çubukta kullanır.
Silme, yenileme, hazır mesaj ayarları ve yarım kalan gönderimler “Diğer”dedir.
Filtreler ve kayıtlar tek kaydırma alanındadır; filtreler listeyi sabit bir
bölgenin altına sıkıştırmaz. Dar ekran veya büyük yazıda filtre alanları tek
sütuna geçer. Kartlarda alıcı/konu iki satırla sınırlanır; durum, kanal ve
tarih birbirinden ayrı gösterilir. Uzun alıcı metni tooltip ile okunabilir.

Veri okuma, arama alanı, filtre alanları, sıralama ve temizleme ekranın
sorumluluğundadır. `listeAramaMetni` Türkçe büyük/küçük harfleri ve aksansız
klavyeyi eşleştirir; `listeTurkceKarsilastir` Türkçe alfabetik karşılaştırma yapar.

## Gönderim Geçmişi uygulaması

- Arama: öğrenci/alıcı adı, okul numarası, telefon ve mesaj içeriği.
- Filtre: sınıf, öğrenci, kanal, durum ve dahil edilen başlangıç/bitiş günü.
- Sıralama: yeniden eskiye, eskiden yeniye, öğrenci/alıcı adı A–Z ve Z–A.
- Tekli ve toplu kayıtlar birlikte sıralanır.
- Tümünü seç, onay ve sil işlemleri görünür kayıt kapsamını kullanır.
- Filtre değiştiğinde eski seçim temizlenir. Sıralama değiştiğinde seçim korunur.
- Onay bekliyor ile onaylandı ayrıdır. SMS isteği, teslim edildi anlamına gelmez.

## Uyarlarken doğrula

Arama/filtre birlikte çalışmalı, gizli kayıt toplu işleme alınmamalı,
boş sonuç açıklanmalı, tarihler doğru karşılaştırılmalı ve dar ekran/büyük yazı
kontrol edilmelidir. Referans: `test/mesaj_gecmis_liste_araclari_test.dart`.
