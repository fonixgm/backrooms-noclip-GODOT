## Campo de visión estilo Darkwood. Port de game/js/engine/fov.js:
## raycasting por tiles con línea de Bresenham. En el port 3D la luz real la
## dan las lámparas, pero el LOS sigue siendo la base de la detección de las
## entidades (sim/entidades) y del minimapa.
class_name Fov

static func blocks(g: MapGen.Grid, x: int, y: int) -> bool:
	var v := MapGen.PARED if (x < 0 or y < 0 or x >= g.w or y >= g.h) else int(g.t[y * g.w + x])
	return v == MapGen.PARED or v == MapGen.ESTANTERIA or v == MapGen.OBSTACULO

## Línea de Bresenham: ¿hay visión directa de (x0,y0) a (x1,y1)?
static func los(g: MapGen.Grid, x0: int, y0: int, x1: int, y1: int) -> bool:
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	var x := x0
	var y := y0
	while not (x == x1 and y == y1):
		if not (x == x0 and y == y0) and blocks(g, x, y):
			return false
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return true

## Visibilidad: intensidad de luz 0..1 por tile.
static func compute(g: MapGen.Grid, px: int, py: int, radius: int) -> PackedFloat32Array:
	var light := PackedFloat32Array()
	light.resize(g.w * g.h)
	var r2 := radius * radius
	var x0 := maxi(0, px - radius - 1)
	var x1 := mini(g.w - 1, px + radius + 1)
	var y0 := maxi(0, py - radius - 1)
	var y1 := mini(g.h - 1, py + radius + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d2 := (x - px) * (x - px) + (y - py) * (y - py)
			if d2 > r2 * 1.4:
				continue
			if not los(g, px, py, x, y):
				continue
			var d := sqrt(float(d2))
			light[y * g.w + x] = maxf(0.0, minf(1.0, 1.15 - (d / radius) * 0.95))
	light[py * g.w + px] = 1.0
	return light
