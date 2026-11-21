const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

function setup() {
  const state = { rows: [
    { id: 'native-first', at: '2026-11-15T20:38:00Z', value: '9-C • 3004 • Çınar Kızmaz' },
    { id: 'native-last', at: '2026-11-18T10:00:00Z', value: '9-C • 3004 • Çınar Kızmaz' },
    { id: 'native-other', at: '2026-11-18T10:00:00Z', value: '9-C • 4001 • Diğer Öğrenci' },
  ], deleted: [], reads: 0, released: 0, noDelete: false, denied: false, onRead: null };
  const form = {
    getId: () => 'form',
    getResponses: () => {
      state.reads++;
      if (state.onRead) state.onRead(state.reads);
      return state.rows.map(row => ({
        getId: () => row.id,
        getTimestamp: () => new Date(row.at),
        getItemResponses: () => [{
          getItem: () => ({ getId: () => 101, getTitle: () => 'Öğrenciyi seçin' }),
          getResponse: () => row.value,
        }],
      }));
    },
    deleteResponse: id => {
      state.deleted.push(id);
      if (!state.noDelete) state.rows = state.rows.filter(row => row.id !== id);
    },
  };
  const ctx = vm.createContext({
    FormApp: { openById: () => { if (state.denied) throw Error('Permission denied'); return form; } },
    LockService: { getUserLock: () => ({ waitLock: () => {}, releaseLock: () => state.released++ }) },
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'Code.gs'), 'utf8'), ctx);
  return { ctx, state, read: () => ctx.okulYanitlariOku('form') };
}

test('okuma salt okunurdur, silmenin kullanacağı gerçek kimliği ve tam listeyi verir', () => {
  const t = setup();
  const result = t.read();
  assert.equal(result.protocol, 'okul-yanitlar/v2');
  assert.equal(result.complete, true);
  assert.equal(result.count, 3);
  assert.equal(result.responses[0].source, 'apps-script/v2');
  assert.deepEqual(t.state.deleted, []);
});

test('kurulum eski sözleşmeyi korurken doğrudan protokol yeteneğini bildirir', () => {
  const t = setup();
  const result = t.ctx.okulYanitSilKurulumKontrol();
  assert.equal(result.protocol, 'okul-yanit-sil/v1');
  assert.equal(result.implementation, 'exact-response-2026-11-19');
  assert.equal(result.nativeImplementation, 'native-response-2026-11-20');
  assert.equal(result.capabilities.includes('native-response/v2'), true);
  assert.deepEqual(t.state.deleted, []);
});

test('ilk seçilen native yanıt doğrudan silinir; aynı öğrencinin son yanıtı korunur', () => {
  const t = setup();
  const selected = t.read().responses.find(r => r.responseId === 'native-first');
  const result = t.ctx.okulYanitSil('form', selected.responseId, selected);
  assert.equal(result.protocol, 'okul-yanit-sil/v2');
  assert.equal(result.deleted, true);
  assert.equal(result.absent, true);
  assert.deepEqual(t.state.deleted, ['native-first']);
  assert.deepEqual(t.state.rows.map(r => r.id), ['native-last', 'native-other']);
  assert.equal(t.state.released, 1);
});

test('aynı zaman ve aynı cevaplar iki kaydı birleştirmez; yalnız seçilen kimlik silinir', () => {
  const t = setup();
  t.state.rows[1].at = t.state.rows[0].at;
  const selected = t.read().responses.find(r => r.responseId === 'native-first');
  t.ctx.okulYanitSil('form', selected.responseId, selected);
  assert.deepEqual(t.state.deleted, ['native-first']);
  assert.equal(t.state.rows.some(r => r.id === 'native-last'), true);
});

test('eski REST kimliği native kimlikmiş gibi kullanılamaz', () => {
  const t = setup();
  const selected = t.read().responses[0];
  assert.throws(() => t.ctx.okulYanitSil('form', 'rest-first', selected), /geçersiz/);
  assert.deepEqual(t.state.deleted, []);
});

test('yanıt seçildikten sonra içerik değişirse silme yapılmaz', () => {
  const t = setup();
  const selected = t.read().responses.find(r => r.responseId === 'native-first');
  t.state.rows[0].value = 'Yeni cevap';
  assert.throws(() => t.ctx.okulYanitSil('form', selected.responseId, selected), /değişti/);
  assert.deepEqual(t.state.deleted, []);
});

test('son kontrol sırasında değişen kaynak da korunur', () => {
  const t = setup();
  const selected = t.read().responses.find(r => r.responseId === 'native-first');
  t.state.onRead = n => { if (n === 4) t.state.rows[0].value = 'Yeni cevap'; };
  assert.throws(() => t.ctx.okulYanitSil('form', selected.responseId, selected), /değişti/);
  assert.deepEqual(t.state.deleted, []);
});

test('tekrar deneme başka kaydı silmez, önceden yokluk ayrı sonuçtur', () => {
  const t = setup();
  const selected = t.read().responses.find(r => r.responseId === 'native-first');
  t.ctx.okulYanitSil('form', selected.responseId, selected);
  const again = t.ctx.okulYanitSil('form', selected.responseId, selected);
  assert.equal(again.deleted, false);
  assert.equal(again.absent, true);
  assert.deepEqual(t.state.deleted, ['native-first']);
});

test('silme uygulanmazsa başarı dönmez', () => {
  const t = setup();
  const selected = t.read().responses[0];
  t.state.noDelete = true;
  assert.throws(() => t.ctx.okulYanitSil('form', selected.responseId, selected), /doğrulanamadı/);
});

test('okuma sırasında değişen veya tekrarlı liste eksiksiz sayılmaz', () => {
  const t = setup();
  t.state.onRead = n => { if (n === 2) t.state.rows.pop(); };
  assert.throws(t.read, /değişti/);
  const u = setup();
  u.state.rows[1].id = u.state.rows[0].id;
  assert.throws(u.read, /tekrarlı/);
});

test('yanlış form ve izin hatasında hiçbir yanıt silinmez', () => {
  const t = setup();
  const selected = t.read().responses[0];
  assert.throws(() => t.ctx.okulYanitSil('other-form', selected.responseId, selected), /geçersiz/);
  t.state.denied = true;
  assert.throws(t.read, /Permission denied/);
  assert.deepEqual(t.state.deleted, []);
});
