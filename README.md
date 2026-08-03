# BACKROOMS — No-Clip (Godot)

Fork hacia **Godot 4** del proyecto [backrooms-noclip](https://github.com/AgenteMaxo/backrooms-noclip),
un roguelike contextual basado en la [wiki de las Backrooms](https://backrooms.fandom.com),
fiel al lore: niveles, entidades, salidas y mecánicas salen de las páginas reales de la wiki.

Este port reimplementa el juego original (HTML/JS/Canvas) en **Godot 4.7** con render 3D en
tercera persona y física Jolt, manteniendo el mismo núcleo determinista y las mismas fichas
de catálogo en español.

## Cómo jugar

Abre `project.godot` con **Godot 4.7.1** y pulsa **F5** (escena principal: `scenes/menu_principal.tscn`).

- **W / S / A / D**: avanzar, retroceder y girar (relativo a la cámara)
- **Espacio**: interactuar — cruzar salidas, **romper** paredes/suelo agrietados y **registrar muebles** (taquillas, archivadores… con tirada de dado)
- **Q / E**: usar la mano izquierda/derecha · **F**: linterna · **B**: mochila
- **1-6**: usar un objeto de la mochila · **ESC**: ajustes / volver al menú
- Los niveles visitados persisten durante la expedición; las puertas de retorno te llevan de vuelta.
- Escribe una **semilla** en el título para partidas reproducibles (compártela con el chat).
- La **Sala Manila** (Level 0) es un punto de descanso: quedarte el tiempo suficiente te lleva a Level 1 o Level 2.
- El zumbido de los fluorescentes, la moqueta húmeda, los enchufes dispersos y el papel pintado amarillento reproducen fielmente la wiki de Level 0.

Objetivo: encontrar una de las rarísimas rutas de escape de vuelta a la realidad.
La muerte es permanente: despiertas otra vez en Level 0.

## Estructura

```
assets/         Texturas, sprites, sonidos y fuentes (por nivel: level-0, level-1…)
data/           Fichas jugables en español: levels, entities y objects (cargadas tal cual)
levels/         Escenas de los niveles implementados (level_X.gd + level_X.tscn)
scenes/         Escenas generales (menú principal)
scripts/        Motor Godot 4: core/ (determinista), data/, game/ y sim/
tools/          Scripts Node de regresión reproducible (goldens del generador)
```

## Niveles implementados

`levels/` contiene los niveles jugables: **Level 0** (The Lobby, completo y fiel a la wiki),
**Level 1**, **Level 2**, **Level 188** y **The Hub**. El catálogo completo (30+ niveles,
16 entidades y 13 objetos en español) vive en `data/`.

## Comandos del pipeline (Node)

```
node tools/export_golden_mapgen.js    # regenerar el golden del generador de mapas
node tools/export_golden_core.js      # regenerar el golden del núcleo determinista
node tools/export_golden_fisica.js    # regenerar el golden de la física
```

Los goldens se comparan contra la especificación original (port JS) para garantizar que el
port a Godot reproduce el mismo comportamiento bit a bit.

## Escalar más allá de los niveles implementados

El motor carga las fichas de `data/*.es.json` sin tocar código: para añadir un nivel basta
crear su ficha (bioma, paleta, reglas, entidades, salidas) y el generador lo acepta.

## Contribuir

Los Pull Requests son bienvenidos. Solo el autor acepta cambios en este repositorio.

## Licencia

- **Lore y textos derivados de la wiki**: el contenido descriptivo procede de
  [backrooms.fandom.com](https://backrooms.fandom.com) y pertenece a sus autores
  bajo [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/); cada ficha
  del juego conserva la `url` de su página original como atribución.
