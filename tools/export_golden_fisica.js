// Goldens de física y FOV: trayectorias de Fisica.mover y casos de FOV.los /
// FOV.compute ejecutados con el JS original sobre un mapa real por semilla.
// Uso: node tools/export_golden_fisica.js [rutaRepoOriginal]
'use strict';

const path = require('path');
const fs = require('fs');

const REPO = process.argv[2] || 'C:/Users/fonix/Documents/GitHub/backrooms-noclip';
global.window = global;
require(path.join(REPO, 'game/js/engine/rng.js'));
require(path.join(REPO, 'game/js/mapgen/mapgen.js'));
require(path.join(REPO, 'game/js/engine/fov.js'));
const Fisica = require(path.join(REPO, 'game/js/sim/fisica.js'));
const LEVELS = require(path.join(REPO, 'data/game/levels.es.json'));
const { RNG, MapGen, FOV } = global;

// mapa real de Level 1 (56×56, con charcos/obstáculos que ejercitan factorTerreno)
const res = MapGen.generate(LEVELS['level-1'], RNG.create('fisica-golden'));
const g = res.grid;
const [sx, sy] = res.spawn;

// trayectorias: desde el spawn, secuencias de (dx,dy,dt) — incluye diagonales
// contra paredes (deslizamiento), dt grandes (varios subpasos) y terrenos lentos
const secuencias = [
  { nombre: 'recta', pasos: Array.from({ length: 40 }, () => [1, 0, 1 / 60]) },
  { nombre: 'diagonal', pasos: Array.from({ length: 60 }, () => [0.7071, 0.7071, 1 / 60]) },
  { nombre: 'zigzag', pasos: Array.from({ length: 50 }, (_, i) => [Math.sin(i * 0.3), Math.cos(i * 0.2), 1 / 60]) },
  { nombre: 'dt-grande', pasos: Array.from({ length: 10 }, () => [-1, 0.4, 0.25]) },
  { nombre: 'lenta-ent', pasos: Array.from({ length: 30 }, (_, i) => [Math.cos(i * 0.5), Math.sin(i * 0.5), 0.05]), vel: 3.4, radio: 0.3 },
];
const trayectorias = secuencias.map((s) => {
  let x = sx, y = sy;
  const puntos = [];
  for (const [dx, dy, dt] of s.pasos) {
    [x, y] = Fisica.mover(g, x, y, dx, dy, dt, s.vel, s.radio);
    puntos.push([x, y]);
  }
  return { nombre: s.nombre, desde: [sx, sy], pasos: s.pasos, vel: s.vel ?? null, radio: s.radio ?? null, puntos };
});

// LOS entre pares de puntos del mapa (mezcla de visibles y bloqueados)
const rngLos = RNG.create('fisica-golden::los');
const losCases = [];
for (let i = 0; i < 60; i++) {
  const x0 = rngLos.int(1, g.w - 2), y0 = rngLos.int(1, g.h - 2);
  const x1 = rngLos.int(1, g.w - 2), y1 = rngLos.int(1, g.h - 2);
  losCases.push({ x0, y0, x1, y1, ve: FOV.los(g, x0, y0, x1, y1) });
}

// compute alrededor del spawn (radio 8): solo celdas con luz > 0
const luz = FOV.compute(g, sx, sy, 8);
const compute = [];
for (let i = 0; i < luz.length; i++)
  if (luz[i] > 0) compute.push([i, Math.round(luz[i] * 1e6) / 1e6]);

const salida = {
  semilla: 'fisica-golden', nivel: 'level-1', spawn: [sx, sy],
  choca: [ // casos puntuales de chocaCentro
    ...Array.from({ length: 40 }, (_, i) => {
      const r = RNG.create('fisica-golden::choca::' + i);
      const cx = r.f() * g.w, cy = r.f() * g.h, rad = 0.2 + r.f() * 0.3;
      return { cx, cy, rad, choca: Fisica.choca(g, cx - 0.5, cy - 0.5, rad) };
    }),
  ],
  trayectorias, losCases, compute,
};

const destino = path.join(__dirname, '..', 'tests', 'golden', 'fisica.json');
fs.writeFileSync(destino, JSON.stringify(salida, null, 0));
console.log('Golden física/FOV escrito en', destino);
