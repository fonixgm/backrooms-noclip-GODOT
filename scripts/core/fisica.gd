## Física del movimiento libre. Port de game/js/sim/fisica.js (v22):
## colisión círculo-vs-tile con integración por subpasos y deslizamiento por
## paredes. En Godot corre dentro de _physics_process (60 Hz) para el jugador
## y en el tick de mundo (20 Hz) para las entidades — mismas constantes y
## misma geometría de colisión que el original.
##
## Convención de coordenadas (la histórica del juego): la posición lógica
## `pos` es la ESQUINA del tile — el centro físico/visual está en pos+0.5.
class_name Fisica

const RADIO := 0.35          # radio del cuerpo (en tiles)
const VEL_JUGADOR := 4.6     # tiles/segundo
const GIRO_JUGADOR := 3.1    # rad/s
const SUBPASO := 0.2         # integración por tramos: nada atraviesa esquinas

## Transitable según los valores de tile de MapGen (duplicado a propósito,
## como en el original: esta clase no depende de MapGen).
static func transitable(g: MapGen.Grid, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= g.w or ty >= g.h:
		return false
	var t := g.t[ty * g.w + tx]
	return t == 0 or t == 3 or t == 4 or t == 6 or t == 7

static func factor_terreno(g: MapGen.Grid, cx: float, cy: float) -> float:
	var tx := floori(cx)
	var ty := floori(cy)
	if tx < 0 or ty < 0 or tx >= g.w or ty >= g.h:
		return 1.0
	var tile := g.t[ty * g.w + tx]
	return 0.58 if tile == 6 else (0.82 if tile == 7 else 1.0)

## ¿El círculo con centro (cx,cy) y radio r pisa algún tile NO transitable?
static func choca_centro(g: MapGen.Grid, cx: float, cy: float, r: float) -> bool:
	var x0 := floori(cx - r)
	var x1 := floori(cx + r)
	var y0 := floori(cy - r)
	var y1 := floori(cy + r)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if transitable(g, tx, ty):
				continue
			# punto del tile más cercano al centro del círculo
			var px := maxf(tx, minf(cx, tx + 1))
			var py := maxf(ty, minf(cy, ty + 1))
			if (cx - px) * (cx - px) + (cy - py) * (cy - py) < r * r:
				return true
	return false

## Integra un desplazamiento con colisión y DESLIZAMIENTO por paredes:
## cada subpaso intenta el eje X y el eje Y por separado (si la diagonal
## choca, resbala por el eje libre). Devuelve la nueva `pos` (esquina) como
## Array [x, y] de floats de 64 bits — OJO: Vector2 truncaría a float32 y el
## error se acumularía visiblemente frente al original.
static func mover(g: MapGen.Grid, x: float, y: float, dx: float, dy: float,
		dt: float, vel: float = VEL_JUGADOR, radio: float = RADIO) -> Array:
	var m := sqrt(dx * dx + dy * dy)
	if m == 0.0 or dt == 0.0:
		return [x, y]
	var paso := vel * dt
	var ux := (dx / m) * paso
	var uy := (dy / m) * paso
	var cx := x + 0.5
	var cy := y + 0.5
	var n := maxi(1, ceili(paso / SUBPASO))
	for i in n:
		var factor := factor_terreno(g, cx, cy)
		var sx := (ux / n) * factor
		var sy := (uy / n) * factor
		if not choca_centro(g, cx + sx, cy, radio):
			cx += sx
		if not choca_centro(g, cx, cy + sy, radio):
			cy += sy
	return [cx - 0.5, cy - 0.5]

static func dist(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))

## Tile lógico que pisa una posición continua (el centro manda).
static func tile_de(v: float) -> int:
	return floori(v + 0.5)

## Normaliza un ángulo a (-π, π].
static func norm_ang(a: float) -> float:
	while a > PI:
		a -= PI * 2
	while a <= -PI:
		a += PI * 2
	return a

static func choca(g: MapGen.Grid, x: float, y: float, r: float = RADIO) -> bool:
	return choca_centro(g, x + 0.5, y + 0.5, r)
