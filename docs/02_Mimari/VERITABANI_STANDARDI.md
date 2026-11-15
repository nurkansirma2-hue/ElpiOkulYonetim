# Veritabanı standardı

Bireysel mod SQLite, kurumsal mod SQL Server kullanır. USE/GO yalnız SQL Server betikleri içindir. Mod verileri karıştırılmaz; mod değişimi veri silmez. Şema veya veri değişikliğinde mevcut kayıtlar ve yedek uyumu doğrulanır.

## 25. SQL STANDARDI

SQL Server 2025 ve SSMS 2022 uyumluluğu korunur.

Hazırlanan SQL betikleri şu satırlarla başlar:

```sql
USE [OkulYonetimMini]
GO
```

SQL hazırlamak ile veritabanında çalıştırmak ayrı işlemlerdir.

Açık onay olmadan DROP, TRUNCATE, toplu DELETE, veri kaybı doğuran migration veya geri dönüşü zor şema değişikliği çalıştırılmaz.
