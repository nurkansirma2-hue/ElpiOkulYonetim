const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const code = fs.readFileSync(path.join(__dirname, 'Code.gs'), 'utf8');

function setup(ids, fail = false, options = {}) {
  const state = { ids: [...ids], deleted: [], released: 0, opened: [], edits: false };
  const ctx = vm.createContext({
    FormApp: { openById: id => {
      state.opened.push(id);
      if (fail) throw Error('Permission denied');
      return {
        getId: () => options.formId || id,
        getResponses: () => (options.emptyList ? [] : state.ids).map(id => ({ getId: () => id })),
        getResponse: id => state.ids.includes(id) ? {
          getId: () => options.responseId || id,
          getEditResponseUrl: () => `https://docs.google.com/forms/d/e/test/viewform?edit2=${id}`,
        } : null,
        isAcceptingResponses: () => true,
        setAllowResponseEdits: value => state.edits = value,
        deleteResponse: id => {
          state.deleted.push(id);
          if (!options.noDelete) state.ids = state.ids.filter(v => v !== id);
        },
      };
    } },
    LockService: { getUserLock: () => ({
      waitLock: () => {}, releaseLock: () => state.released++,
    }) },
  });
  vm.runInContext(code, ctx);
  return { state, ctx };
}

test('yalnız hedef yanıt silinir; tekrar deneme diğer yanıtı silmez', () => {
  const { state, ctx } = setup(['r1', 'r2']);
  assert.equal(ctx.okulYanitSil('f1', 'r1').absent, true);
  assert.throws(() => ctx.okulYanitSil('f1', 'r1'), /doğrulanamadı/);
  assert.deepEqual(state.ids, ['r2']);
  assert.deepEqual(state.deleted, ['r1']);
  assert.equal(state.released, 2);
});

test('boş yanıt listesi doğrudan bulunan yanıtın silinmesini atlamaz', () => {
  const { state, ctx } = setup(['r1', 'r2'], false, { emptyList: true });
  assert.equal(ctx.okulYanitSil('f1', 'r1').deleted, true);
  assert.deepEqual(state.ids, ['r2']);
});

for (const options of [{ formId: 'f2' }, { responseId: 'r2' }]) {
  test(`kimlik uyuşmazlığında hiçbir yanıt silinmez: ${JSON.stringify(options)}`, () => {
    const { state, ctx } = setup(['r1', 'r2'], false, options);
    assert.throws(() => ctx.okulYanitSil('f1', 'r1'), /eşleşmedi|doğrulanamadı/);
    assert.deepEqual(state.deleted, []);
    assert.deepEqual(state.ids, ['r1', 'r2']);
    assert.equal(state.released, 1);
  });
}

test('silme uygulanmamışsa başarı döndürmez', () => {
  const { state, ctx } = setup(['r1', 'r2'], false, { noDelete: true });
  assert.throws(() => ctx.okulYanitSil('f1', 'r1'), /silindiği doğrulanamadı/);
  assert.deepEqual(state.ids, ['r1', 'r2']);
  assert.equal(state.released, 1);
});

test('başlangıçta bulunamayan kimlik absent başarısı üretmez', () => {
  const { state, ctx } = setup(['r2']);
  assert.throws(() => ctx.okulYanitSil('f1', 'r1'), /doğrulanamadı/);
  assert.deepEqual(state.deleted, []);
  assert.deepEqual(state.ids, ['r2']);
});
test('izin hatası başarı göstermez ve kilit serbest bırakılır', () => {
  const { state, ctx } = setup(['r1'], true);
  assert.throws(() => ctx.okulYanitSil('f1', 'r1'), /Permission denied/);
  assert.deepEqual(state.deleted, []);
  assert.equal(state.released, 1);
});
test('geçersiz kimlikte forma erişilmez', () => {
  const { state, ctx } = setup(['r1']);
  assert.throws(() => ctx.okulYanitSil('f1', '../r1'), /geçersiz/);
  assert.deepEqual(state.opened, []);
});
test('kurulum kontrolü veri değiştirmez', () => {
  const { state, ctx } = setup(['r1']);
  assert.equal(ctx.okulYanitSilKurulumKontrol().ready, true);
  assert.equal(ctx.okulYanitSilKurulumKontrol().implementation, 'exact-response-2026-11-19');
  assert.deepEqual(state.opened, []);
});

test('düzeltme bağlantısı yalnız istenen cevap içindir, cevapları silmez', () => {
  const { state, ctx } = setup(['r1', 'r2']);
  const result = ctx.okulYanitDuzenlemeBaglantisi('f1', 'r2');
  assert.equal(result.responseId, 'r2');
  assert.equal(result.editUrl, 'https://docs.google.com/forms/d/e/test/viewform?edit2=r2');
  assert.equal(state.edits, true);
  assert.deepEqual(state.deleted, []);
});
test('olmayan veya geçersiz cevap için düzenleme açılmaz', () => {
  const { state, ctx } = setup(['r1']);
  assert.throws(() => ctx.okulYanitDuzenlemeBaglantisi('f1', 'r2'), /bulunamadı/);
  assert.throws(() => ctx.okulYanitDuzenlemeBaglantisi('f1', '../r1'), /geçersiz/);
  assert.equal(state.edits, false);
});
