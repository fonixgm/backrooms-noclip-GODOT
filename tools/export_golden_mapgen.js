// Genera los goldens del mapgen ejecutando el MapGen.generate ORIGINAL (JS)
// sobre las fichas reales de levels.es.json. La salida es la especificación
// que el port GDScript debe reproducir exactamente (geometría bit a bit).
// Uso: node tools/export_golden_mapgen.js [rutaRepoOriginal]
'use strict';

const path = require('path');
const fs = require('fs');

const REPO = process.argv[2] || 'C:/Users/fonix/Documents/GitHub/backrooms-noclip';
global.window = global;
require(path.join(REPO, 'game/js/engine/rng.js'));
require(path.join(REPO, 'game/js/mapgen/mapgen.js'));
const LEVELS = require(path.join(REPO, 'data/game/levels.es.json'));
const { RNG, MapGen } = global;

const SEMILLAS = [
  'golden-1', 'golden-2', 'golden-3', 'golden-4', 'golden-5',
  'backrooms-diaria::2026-07-19', 'moqueta-1234', 'pre-fix-4',
  'mmo::2026-07-19::level-0::1', 'ñandú-42',
];
const NIVELES = ['level-0', 'level-1'];

// JSON.parse(JSON.stringify(x)) elimina las claves undefined (p. ej. el
// campo `registrado: undefined` de los props decorativos no-contenedor),
// igual que hará el comparador GDScript.
const limpiar = (x) => (x === null || x === undefined ? null : JSON.parse(JSON.stringify(x)));

const casos = [];
for (const nivelId of NIVELES) {
  const def = LEVELS[nivelId];
  if (!def) throw new Error(`No existe ${nivelId} en levels.es.json`);
  for (const semilla of SEMILLAS) {
    const res = MapGen.generate(def, RNG.create(semilla));
    casos.push({
      nivel: nivelId,
      semilla,
      w: res.w,
      h: res.h,
      grid: Array.from(res.grid.t).map((v) => v.toString(16)).join(''),
      spawn: res.spawn,
      exits: res.exits.map((e) => ({ x: e.x, y: e.y, def: limpiar(e.def) })),
      items: res.items,
      entitySpawns: res.entitySpawns,
      props: res.props.map(limpiar),
      airPockets: res.airPockets,
      caminatas: res.caminatas.map(limpiar),
      manila: limpiar(res.manila),
      manilaSalida: limpiar(res.manilaSalida),
    });
  }
}

const destino = path.join(__dirname, '..', 'tests', 'golden', 'mapgen.json');
fs.mkdirSync(path.dirname(destino), { recursive: true });
fs.writeFileSync(destino, JSON.stringify(casos, null, 0));
console.log(`Golden escrito: ${casos.length} casos en ${destino}`);
