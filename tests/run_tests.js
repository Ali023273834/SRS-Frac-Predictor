// Regression test: the prediction engine inside index.html must reproduce the locked MATLAB model v3 (test_vectors.json):
// Gaussian-process brain dose and plan quality, OAR random forest, decision rule, and the 27 validation plans.
// Run from the repository root:  node tests/run_tests.js
const fs = require('fs'), path = require('path'), vm = require('vm');
const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const engine = html.split('// ENGINE-START')[1].split('// ENGINE-END')[0];
const M = JSON.parse(html.split('<script type="application/json" id="model">')[1].split('</script>')[0]);
const sb = { module: { exports: {} }, Math, console, isNaN, isFinite, Number, String };
vm.createContext(sb); vm.runInContext(engine + '\nmodule.exports = ENGINE;', sb);
const E = sb.module.exports;
const T = JSON.parse(fs.readFileSync(path.join(__dirname, 'test_vectors.json'), 'utf8'));
let n = 0, fail = 0;
const bad = m => { fail++; if (fail <= 15) console.log('FAIL', m); };
const close = (a, b) => Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(b));
const dec = key => ({ loc: key[1] === '1' ? 'central' : 'peripheral', shape: key[3] === '1' ? 'irregular' : 'regular' });
for (const c of T.cases) {                                   // MATLAB GPR predictions
  for (const s of M.schemes) { n++; if (!close(E.brain(M, s, c.v, c.combo), c.brain[s])) bad(`brain ${s} v=${c.v} ${c.combo}`); }
  for (const [kk, val] of Object.entries(c.quality)) { const [s, k] = kk.split('|'); n++; if (!close(E.quality(M, s, k, c.v, c.combo), val)) bad(`quality ${kk} v=${c.v}`); }
  const R = E.predict(M, { v: c.v, ...dec(c.combo), oar: 'none', d: null, contact: null });
  n++; if (R.rec !== c.rec) bad(`decision v=${c.v} ${c.combo}: app ${R.rec}, expected ${c.rec}`);
}
for (const o of T.oar_cases) {                               // MATLAB OAR forest
  n++; if (!close(E.oarPct(M, o.d, o.v, o.chiasm, o.contact_code, o.regimen), o.oar_pct)) bad(`OAR % d=${o.d} v=${o.v} ${o.regimen}`);
}
for (const o of T.combined) {                                // brain + OAR rule
  const R = E.predict(M, { v: o.v, ...dec(o.combo), oar: o.oar, d: o.oar === 'none' ? null : o.d, contact: o.contact });
  n++; if (R.error || R.rec !== o.recommended) bad(`combined v=${o.v} ${o.oar} d=${o.d} ${o.contact}: app ${R.rec} ${R.error || ''}, expected ${o.recommended}`);
}
for (const c of T.validation) {                              // the 27 validation plans: same brain dose and scheme as MATLAB
  const R = E.predict(M, { v: c.v, ...dec(c.combo), oar: 'none', d: null, contact: null });
  n++; if (R.rec !== c.rec) bad(`validation ${c.case_id}: app ${R.rec}, MATLAB ${c.rec}`);
}
{                                                            // re-irradiation: strong warning, recommendation unchanged (reference only)
  const base = { v: 8, loc: 'central', shape: 'irregular', oar: 'none', d: null, contact: null };
  const a = E.predict(M, base), b = E.predict(M, { ...base, reirr: true });
  n++; if (!(b.rec === a.rec && b.warnings.length === a.warnings.length + 1 && b.warnings[0][0] === 'e' && /Re-irradiation/.test(b.warnings[0][1]))) bad('re-irradiation warning');
}
console.log(`${n - fail}/${n} checks passed`);
process.exit(fail ? 1 : 0);
