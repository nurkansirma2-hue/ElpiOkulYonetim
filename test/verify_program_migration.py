import re, sqlite3
from pathlib import Path
source = Path('elpi_okul_yonetim/lib/database/ders_programi_surumu.dart').read_text(encoding='utf-8')
source = source.split('static Future<DateTime>')[0]
sqls = re.findall(r"await db.execute\('''(.*?)'''\);|await db.execute\('([^'\n]*)'\);", source, re.S)
db = sqlite3.connect(':memory:')
db.executescript('''PRAGMA foreign_keys=ON;
CREATE TABLE OgretmenProfil(OgretmenProfilId INTEGER PRIMARY KEY);
INSERT INTO OgretmenProfil VALUES(1);
CREATE TABLE DersProgrami(DersProgramiId INTEGER PRIMARY KEY,OgretmenProfilId INTEGER,EgitimOgretimYili TEXT,Aktif INTEGER,OlusturmaTarihi TEXT);
INSERT INTO DersProgrami VALUES(1,1,'2026/2027',1,'2026-09-14');
INSERT INTO DersProgrami VALUES(2,1,'2026/2027',0,'2026-09-01');''')
for multi,single in sqls: db.execute(multi or single)
assert len(sqls)==7, len(sqls)
assert db.execute('SELECT ProgramSurumId FROM DersProgrami WHERE DersProgramiId=1').fetchone()[0]==1
assert db.execute('SELECT ProgramSurumId FROM DersProgrami WHERE DersProgramiId=2').fetchone()[0] is None
assert db.execute('SELECT BaslangicTarihi FROM DersProgramiSurum').fetchone()[0] is None
assert db.execute('SELECT count(*) FROM GecerliDersProgrami').fetchone()[0]==1
db.execute("UPDATE DersProgramiSurum SET BitisTarihi='2020-01-01'")
assert db.execute('SELECT count(*) FROM GecerliDersProgrami').fetchone()[0]==0
db.execute("INSERT INTO DersProgramiSurum VALUES(2,1,'2026/2027','2099-01-01',NULL,1,'now')")
db.execute("INSERT INTO DersProgrami VALUES(3,1,'2026/2027',1,'now',2)")
assert db.execute('SELECT count(*) FROM GecerliDersProgrami').fetchone()[0]==0
db.execute("INSERT INTO DersProgramiGorev VALUES(1,2,'Çarşamba',1,'08:00','08:40','Koordinatörlük')")
assert not db.execute('PRAGMA foreign_key_check').fetchall()
print('SQLite migration, legacy preservation, current-view date filters and coordination foreign keys: passed')
