// Genera los goldens de referencia (rng, semilla diaria, route-seed) ejecutando
// el código JS ORIGINAL del repo fuente. La salida (tests/golden/core.json) es
// la especificación que los ports GDScript deben reproducir bit a bit.
// Uso: node tools/export_golden_core.js [rutaRepoOriginal]
'use strict';

const path = require('path');
const fs = require('fs');

const REPO = process.argv[2] || 'C:/Users/fonix/Documents/GitHub/backrooms-noclip';
global.window = global;
require(path.join(REPO, 'game/js/engine/rng.js'));
const DailySeed = require(path.join(REPO, 'game/js/engine/daily-seed.js'));
const RouteSeed = require(path.join(REPO, 'game/js/engine/route-seed.js'));
const RNG = global.RNG;

const SEMILLAS = [
  'backrooms-diaria::2026-07-19',
  'moqueta-1234',
  'level-0',
  'semilla con ñ y acentós',
  'mmo::2026-07-19::level-0::1',
];

const rng = {};
for (const s of SEMILLAS) {
  const caso = {};
  let r = RNG.create(s);
  caso.f = Array.from({ length: 12 }, () => r.f());
  // f()*2^32 es entero exacto: permite comparar bit a bit sin depender de
  // la precisión del parser de floats JSON de Godot.
  caso.f_u32 = caso.f.map((v) => v * 4294967296);
  r = RNG.create(s);
  caso.int_1_100 = Array.from({ length: 8 }, () => r.int(1, 100));
  r = RNG.create(s);
  caso.pick_abcde = Array.from({ length: 5 }, () => r.pick(['a', 'b', 'c', 'd', 'e']));
  r = RNG.create(s);
  caso.shuffle_0_9 = r.shuffle([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  r = RNG.create(s);
  caso.chance_05 = Array.from({ length: 8 }, () => r.chance(0.5));
  caso.hash = (function () { // hash de la semilla en sí
    let h = 2166136261 >>> 0;
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
    return h >>> 0;
  })();
  rng[s] = caso;
}

const unit = {};
for (const clave of ['runSeed:var:3:7', 'tilesHD::papel_rayas', 'a', '', 'ñu::ñu']) {
  unit[clave] = RNG.unit(clave) * 4294967296; // entero exacto (== hash)
}

// Instantes críticos: cambios CET↔CEST de 2025-2027 y medianoches de Madrid.
const instantesISO = [
  '2026-07-19T12:00:00Z',
  '2026-07-18T21:59:59Z', '2026-07-18T22:00:00Z', // medianoche Madrid (verano)
  '2026-01-15T22:59:59Z', '2026-01-15T23:00:00Z', // medianoche Madrid (invierno)
  '2026-03-29T00:59:59Z', '2026-03-29T01:00:00Z', // entrada en CEST 2026
  '2026-10-25T00:59:59Z', '2026-10-25T01:00:00Z', // salida de CEST 2026
  '2025-03-30T00:59:59Z', '2025-03-30T01:00:00Z',
  '2025-10-26T00:59:59Z', '2025-10-26T01:00:00Z',
  '2027-03-28T00:59:59Z', '2027-03-28T01:00:00Z',
  '2027-10-31T00:59:59Z', '2027-10-31T01:00:00Z',
  '2026-12-31T23:30:00Z', // cambio de año
];
const daily = instantesISO.map((iso) => {
  const fecha = new Date(iso);
  return { unix: Math.floor(fecha.getTime() / 1000), clave: DailySeed.dayKey(fecha), semilla: DailySeed.seed(fecha) };
});

const route = [
  { seed: 'backrooms-diaria::2026-07-19', origen: 'level-0', ruta: { texto: 'Una sala tranquila y aislada', destino: '*opciones:level-1,level-2' }, candidatos: ['level-1', 'level-2'] },
  { seed: 'moqueta-1234', origen: 'level-0', ruta: { destino: '*opciones:level-1,level-2' }, candidatos: ['level-1', 'level-2'] },
  { seed: 'moqueta-1234', origen: 'level-1', ruta: { id: 'r1' }, candidatos: ['a', 'b', 'c'] },
  { seed: 'x', origen: 'y', ruta: {}, candidatos: ['unico'] },
].map((c) => ({ ...c, resultado: RouteSeed.pick(c.seed, c.origen, c.ruta, c.candidatos) }));

const salida = { rng, unit, daily, route };
const destino = path.join(__dirname, '..', 'tests', 'golden', 'core.json');
fs.mkdirSync(path.dirname(destino), { recursive: true });
fs.writeFileSync(destino, JSON.stringify(salida, null, 1));
console.log('Golden escrito en', destino);
