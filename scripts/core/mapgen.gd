## Generación procedural de mapas por arquetipo de bioma.
## Port FIEL de game/js/mapgen/mapgen.js (repo original): mismo orden de
## consumo del RNG, mismos bucles (incluidos los que evalúan rng en la
## condición) y mismos cortocircuitos, para que la geometría sea idéntica
## bit a bit a la del JS con la misma semilla (ver tests/golden/).
## Tiles: 0 suelo · 1 pared · 2 vacío · 3 agua · 4 decorado · 5 estantería
##        · 6 libros · 7 charco · 8 obstáculo
class_name MapGen

const SUELO := 0
const PARED := 1
const VACIO := 2
const AGUA := 3
const DECOR := 4
const ESTANTERIA := 5
const LIBROS := 6
const CHARCO := 7
const OBSTACULO := 8

## Cuadrícula: w, h, tiles en PackedByteArray y metadatos por arquetipo
## (equivalente a las propiedades g._* que el JS cuelga del grid).
class Grid:
	var w: int
	var h: int
	var t: PackedByteArray
	var meta: Dictionary = {}

	func _init(ancho: int, alto: int, relleno: int) -> void:
		w = ancho
		h = alto
		t = PackedByteArray()
		t.resize(w * h)
		t.fill(relleno)

static func at(g: Grid, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= g.w or y >= g.h:
		return PARED
	return g.t[y * g.w + x]

static func set_tile(g: Grid, x: int, y: int, v: int) -> void:
	if x >= 0 and y >= 0 and x < g.w and y < g.h:
		g.t[y * g.w + x] = v

static func walkable(v: int) -> bool:
	return v == SUELO or v == AGUA or v == DECOR or v == LIBROS or v == CHARCO

# ---------- arquetipos ----------

## Laberinto denso con salas abiertas (Level 0, 27, 130, 483...)
## Se genera a 1/3 de resolución y se escala ×3 → pasillos de 3 huecos.
@warning_ignore("integer_division")
static func gen_pasillos(w: int, h: int, rng: Rng, opts: Dictionary = {}) -> Grid:
	var hw := ceili(w / 3.0)
	var hh := ceili(h / 3.0)
	var small := Grid.new(hw, hh, PARED)
	var cw := (hw - 1) / 2
	var ch := (hh - 1) / 2
	var seen := {}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	seen[Vector2i(0, 0)] = true
	set_tile(small, 1, 1, SUELO)
	while not stack.is_empty():
		var c: Vector2i = stack[stack.size() - 1]
		var dirs := rng.barajar([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
		var moved := false
		for d: Vector2i in dirs:
			var n := c + d
			if n.x < 0 or n.y < 0 or n.x >= cw or n.y >= ch or seen.has(n):
				continue
			seen[n] = true
			set_tile(small, c.x * 2 + 1 + d.x, c.y * 2 + 1 + d.y, SUELO)
			set_tile(small, n.x * 2 + 1, n.y * 2 + 1, SUELO)
			stack.append(n)
			moved = true
			break
		if not moved:
			stack.pop_back()
	# escala ×3 al tamaño real, con borde exterior de pared
	var g := Grid.new(w, h, PARED)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			g.t[y * w + x] = small.t[(y / 3) * hw + (x / 3)]
	# abre salas y atajos para que respire
	var salas: int = opts.get("salas", 8)
	var min_w: int = opts.get("salaMinW", 3)
	var max_w: int = opts.get("salaMaxW", 6)
	var min_h: int = opts.get("salaMinH", 3)
	var max_h: int = opts.get("salaMaxH", 5)
	var separacion: int = opts.get("separacionSalas", 0)
	var irregulares: bool = opts.get("irregulares", false)
	var rects: Array[Rect2i] = []
	var creadas := 0
	var intentos := 0
	while creadas < salas and intentos < salas * 16:
		intentos += 1
		var rw := rng.entero(min_w, max_w)
		var rh := rng.entero(min_h, max_h)
		var rx := rng.entero(1, w - rw - 2)
		var ry := rng.entero(1, h - rh - 2)
		var piezas: Array[Rect2i] = [Rect2i(rx, ry, rw, rh)]
		# Level 0: algunas salas reciben un anexo desplazado. Solo se ABRE
		# suelo, nunca se cierran corredores existentes.
		if irregulares and rng.azar(0.55):
			var aw := rng.entero(2, maxi(2, floori(rw * 0.7)))
			var ah := rng.entero(2, maxi(2, floori(rh * 0.7)))
			var desplaza: int = rng.elegir([-floori(aw * 0.6), rw - floori(aw * 0.4)])
			var ax := maxi(1, mini(w - aw - 2, rx + desplaza))
			var ay := maxi(1, mini(h - ah - 2, ry + rng.entero(0, maxi(0, rh - ah))))
			piezas.append(Rect2i(ax, ay, aw, ah))
		var x0 := piezas[0].position.x
		var y0 := piezas[0].position.y
		var x1 := piezas[0].end.x
		var y1 := piezas[0].end.y
		for p in piezas:
			x0 = mini(x0, p.position.x)
			y0 = mini(y0, p.position.y)
			x1 = maxi(x1, p.end.x)
			y1 = maxi(y1, p.end.y)
		var union := Rect2i(x0, y0, x1 - x0, y1 - y0)
		var solapa := false
		for r in rects:
			if union.position.x < r.end.x + separacion and union.end.x + separacion > r.position.x \
					and union.position.y < r.end.y + separacion and union.end.y + separacion > r.position.y:
				solapa = true
				break
		if solapa:
			continue
		for p in piezas:
			for y in range(p.position.y, p.end.y):
				for x in range(p.position.x, p.end.x):
					set_tile(g, x, y, SUELO)
		rects.append(union)
		creadas += 1
	var atajos: int = opts.get("atajos", w)
	for i in atajos:
		var x := rng.entero(2, w - 3)
		var y := rng.entero(2, h - 3)
		if at(g, x, y) == PARED and \
				((walkable(at(g, x - 1, y)) and walkable(at(g, x + 1, y))) or \
				(walkable(at(g, x, y - 1)) and walkable(at(g, x, y + 1)))):
			if rng.azar(0.4):
				set_tile(g, x, y, SUELO)
	g.meta["_rects"] = rects
	return g

## Level 0.01: corredores muy largos y paralelos.
static func gen_laberinto_longitudinal(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, PARED)
	var bandas: Array[int] = []
	var y := 5
	while y < h - 4:
		bandas.append(y)
		for x in range(1, w - 1):
			for dy in range(-1, 2):
				set_tile(g, x, y + dy, SUELO)
		# Ensanchamientos escasos. OJO fidelidad: el JS evalúa rng.int(6,11)
		# EN LA CONDICIÓN del bucle interior (una tirada por comprobación).
		var x := rng.entero(12, 20)
		while x < w - 12:
			var arriba := rng.azar(0.5)
			var y0 := y - 5 if arriba else y + 2
			var yy := y0
			while yy < y0 + 4:
				var xx := x
				while xx < x + rng.entero(6, 11):
					set_tile(g, xx, yy, SUELO)
					xx += 1
				yy += 1
			x += rng.entero(20, 34)
		y += 10
	# Conectores alternos garantizan un único componente.
	for i in range(bandas.size() - 1):
		var x := 10 + ((i * 23 + rng.entero(0, 12)) % maxi(14, w - 24))
		for yy in range(bandas[i], bandas[i + 1] + 1):
			for dx in range(-1, 2):
				set_tile(g, x + dx, yy, SUELO)
		if rng.azar(0.65):
			var x2 := mini(w - 8, x + rng.entero(18, 36))
			for yy in range(bandas[i], bandas[i + 1] + 1):
				set_tile(g, x2, yy, SUELO)
	# El extremo oriental ya muestra daños.
	var deterioradas := 0
	for yy in range(2, h - 2):
		var x := floori(w * 0.62)
		while x < w - 2:
			if at(g, x, yy) == SUELO and rng.azar(((float(x) / w) - 0.55) * 0.12):
				set_tile(g, x, yy, DECOR)
				deterioradas += 1
			x += 1
	g.meta["_longitudinal"] = {"bandas": bandas.size(), "eje": "x", "deterioradas": deterioradas}
	return g

## Espacio abierto con pilares (Level 1)
@warning_ignore("integer_division")
static func gen_garaje(w: int, h: int, rng: Rng, opts: Dictionary = {}) -> Grid:
	var g := Grid.new(w, h, SUELO)
	for x in w:
		set_tile(g, x, 0, PARED)
		set_tile(g, x, h - 1, PARED)
	for y in h:
		set_tile(g, 0, y, PARED)
		set_tile(g, w - 1, y, PARED)
	var y := 4
	while y < h - 4:
		var x := 4
		while x < w - 4:
			set_tile(g, x, y, PARED)
			set_tile(g, x + 1, y, PARED)
			set_tile(g, x, y + 1, PARED)
			set_tile(g, x + 1, y + 1, PARED)
			x += rng.entero(5, 7)
		y += rng.entero(5, 7)
	# muros parciales y coches (decoración sólida)
	for i in 10:
		var x := rng.entero(4, w - 8)
		var yy := rng.entero(4, h - 5)
		var largo := rng.entero(3, 7)
		if rng.azar(0.5):
			for j in largo:
				set_tile(g, x + j, yy, PARED)
		else:
			for j in largo:
				set_tile(g, x, yy + j, PARED)
	for i in 26:
		var dx := rng.entero(2, w - 3)
		var dy := rng.entero(2, h - 3)
		set_tile(g, dx, dy, DECOR)
	if opts.get("level1", false):
		var props: Array[Dictionary] = []
		# Charcos persistentes de agua de almendras.
		for i in maxi(5, (w * h) / 900):
			var cx := rng.entero(4, w - 5)
			var cy := rng.entero(4, h - 5)
			for dy in range(-1, 2):
				for dx in range(-2, 3):
					if float(dx * dx) / 4.0 + dy * dy > 1.4 or not walkable(at(g, cx + dx, cy + dy)):
						continue
					set_tile(g, cx + dx, cy + dy, CHARCO)
		# Coches rarísimos: dos tiles sólidos cada uno.
		var cars := maxi(1, mini(3, (w * h) / 3200 + 1))
		for i in cars:
			for intento in 80:
				var x := rng.entero(4, w - 6)
				var yy := rng.entero(4, h - 5)
				if not walkable(at(g, x, yy)) or not walkable(at(g, x + 1, yy)):
					continue
				set_tile(g, x, yy, OBSTACULO)
				set_tile(g, x + 1, yy, OBSTACULO)
				props.append({"x": x, "y": yy, "id": "coche", "ancho": 2,
					"color": rng.elegir(["rojo", "azul", "blanco", "negro"])})
				break
		g.meta["_propsEstructurales"] = props
		var charcos := 0
		for v in g.t:
			if v == CHARCO:
				charcos += 1
		g.meta["_garaje"] = {"charcos": charcos, "coches": props.size()}
	return g

## Túneles serpenteantes (Level 2, 268, The Hub, L13)
@warning_ignore("integer_division")
static func gen_tuneles(w: int, h: int, rng: Rng, opts: Dictionary = {}) -> Grid:
	var hw := ceili(w / 3.0)
	var hh := ceili(h / 3.0)
	var small := Grid.new(hw, hh, PARED)
	var x := rng.entero(2, hw - 3)
	var y := rng.entero(2, hh - 3)
	var walkers: int = opts.get("walkers", 5)
	for k in walkers:
		var wx := x
		var wy := y
		var dir: Vector2i = rng.elegir([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
		for i in hw * 4:
			set_tile(small, wx, wy, SUELO)
			if rng.azar(0.22):
				dir = rng.elegir([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
			wx = maxi(1, mini(hw - 2, wx + dir.x))
			wy = maxi(1, mini(hh - 2, wy + dir.y))
		var floors := collect_floors(small)
		var p: Vector2i = rng.elegir(floors)
		x = p.x
		y = p.y
	var g := Grid.new(w, h, PARED)
	for yy in range(1, h - 1):
		for xx in range(1, w - 1):
			g.t[yy * w + xx] = small.t[(yy / 3) * hw + (xx / 3)]
	return g

## Ala de hospital (Level 14, 16, 188): alas horizontales apiladas + pasillo
## vertical, con habitaciones en "peine".
@warning_ignore("integer_division")
static func gen_hospital(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, PARED)
	var room := func(x: int, y: int, rw: int, rh: int) -> void:
		for yy in range(maxi(1, y), mini(h - 1, y + rh)):
			for xx in range(maxi(1, x), mini(w - 1, x + rw)):
				set_tile(g, xx, yy, SUELO)
	var room_w := 5
	var room_h := 5
	var paso := room_w + 2
	var y_min := room_h + 3
	var y_max := h - room_h - 4
	var n_bandas := maxi(2, mini(4, (y_max - y_min) / (room_h * 2 + 5) + 1))
	var bandas: Array[int] = []
	for i in n_bandas:
		bandas.append(roundi(y_min + (0.0 if n_bandas == 1 else float(i * (y_max - y_min)) / (n_bandas - 1))))
	var mid_x := w / 2
	room.call(mid_x - 1, 2, 2, h - 4) # pasillo vertical, de punta a punta
	for y in bandas:
		room.call(2, y - 1, w - 4, 2) # cada ala horizontal
	var hub_banda: int = bandas[bandas.size() / 2]
	var hub_w := mini(w - 10, rng.entero(8, 11))
	var hub_h := mini(room_h * 2 + 1, rng.entero(7, 9))
	var hub_x := mid_x - hub_w / 2
	var hub_y := hub_banda - hub_h / 2
	room.call(hub_x, hub_y, hub_w, hub_h) # puesto de enfermería
	var peine_h := func(y: int, x0: int, x1: int) -> void:
		var x := x0
		while x + room_w <= x1:
			var rw := room_w + 3 if rng.azar(0.2) else room_w # quirófano ocasional
			var puerta := x + rw / 2
			if y - 3 - room_h > 1:
				room.call(x, y - 3 - room_h, rw, room_h)
				set_tile(g, puerta, y - 2, SUELO)
			if y + 2 + room_h < h - 1:
				room.call(x, y + 2, rw, room_h)
				set_tile(g, puerta, y + 1, SUELO)
			x += paso
	for y in bandas:
		if y == hub_banda:
			peine_h.call(y, 4, hub_x - 2)
			peine_h.call(y, hub_x + hub_w + 2, w - room_w - 2)
		else:
			peine_h.call(y, 4, mid_x - 3)
			peine_h.call(y, mid_x + 3, w - room_w - 2)
	return g

## Habitaciones BSP + corredores (oficinas, hoteles)
@warning_ignore("integer_division")
static func gen_oficinas(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, PARED)
	var rooms: Array[Rect2i] = []
	_oficinas_split(g, rng, rooms, 1, 1, w - 2, h - 2, 4)
	# conecta habitaciones consecutivas con pasillos en L de 2 de ancho
	for i in range(1, rooms.size()):
		var a := rooms[i - 1]
		var b := rooms[i]
		var x1 := a.position.x + a.size.x / 2
		var y1 := a.position.y + a.size.y / 2
		var x2 := b.position.x + b.size.x / 2
		var y2 := b.position.y + b.size.y / 2
		while x1 != x2:
			set_tile(g, x1, y1, SUELO)
			set_tile(g, x1, y1 + 1, SUELO)
			x1 += signi(x2 - x1)
		while y1 != y2:
			set_tile(g, x1, y1, SUELO)
			set_tile(g, x1 + 1, y1, SUELO)
			y1 += signi(y2 - y1)
	return g

## Partición BSP recursiva de gen_oficinas (función aparte porque las lambdas
## de GDScript capturan por valor y no pueden recursar sobre sí mismas).
static func _oficinas_split(g: Grid, rng: Rng, rooms: Array[Rect2i],
		x: int, y: int, rw: int, rh: int, depth: int) -> void:
	if depth <= 0 or (rw < 12 and rh < 12):
		var pw := rng.entero(maxi(4, rw - 6), rw - 2)
		var ph := rng.entero(maxi(3, rh - 6), rh - 2)
		var px := x + rng.entero(1, maxi(1, rw - pw - 1))
		var py := y + rng.entero(1, maxi(1, rh - ph - 1))
		rooms.append(Rect2i(px, py, pw, ph))
		for yy in range(py, py + ph):
			for xx in range(px, px + pw):
				set_tile(g, xx, yy, SUELO)
		return
	if rw > rh:
		var cut := rng.entero(floori(rw * 0.35), floori(rw * 0.65))
		_oficinas_split(g, rng, rooms, x, y, cut, rh, depth - 1)
		_oficinas_split(g, rng, rooms, x + cut, y, rw - cut, rh, depth - 1)
	else:
		var cut := rng.entero(floori(rh * 0.35), floori(rh * 0.65))
		_oficinas_split(g, rng, rooms, x, y, rw, cut, depth - 1)
		_oficinas_split(g, rng, rooms, x, y + cut, rw, rh - cut, depth - 1)

## The End: librería comercial abandonada (mitad delantera abierta, fondo con
## hileras bajas de estanterías).
@warning_ignore("integer_division")
static func gen_biblioteca(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, SUELO)
	for x in w:
		set_tile(g, x, 0, PARED)
		set_tile(g, x, h - 1, PARED)
	for y in h:
		set_tile(g, 0, y, PARED)
		set_tile(g, w - 1, y, PARED)
	var mid_x := w / 2
	var pasillo := maxi(7, mini(11, (w / 11) | 1))
	var fondo_hasta := h - 27
	var props: Array[Dictionary] = []
	# Filas con corte irregular. OJO fidelidad: rng.int(0,1) se evalúa en la
	# CONDICIÓN del bucle (una tirada por comprobación), como en el JS.
	var fila := func(x0: int, x1: int, y: int) -> void:
		var hueco := rng.entero(x0 + 5, x1 - 5)
		var x := x0 + rng.entero(0, 1)
		while x <= x1 - rng.entero(0, 1):
			if absi(x - hueco) > 1:
				set_tile(g, x, y, ESTANTERIA)
			x += 1
	var y := 6
	while y <= fondo_hasta:
		fila.call(5, mid_x - ceili(pasillo / 2.0) - 1, y)
		fila.call(mid_x + ceili(pasillo / 2.0) + 1, w - 6, y)
		y += 5
	# Zonas de lectura sin anaqueles.
	var reading_halls := [
		{"x": 8, "y": 13, "w": 13, "h": 10},
		{"x": w - 23, "y": maxi(9, fondo_hasta - 12), "w": 14, "h": 10},
	]
	for hall: Dictionary in reading_halls:
		for hy in range(hall.y, hall.y + hall.h):
			for hx in range(hall.x, hall.x + hall.w):
				set_tile(g, hx, hy, SUELO)
	# Pilares en los pasillos entre filas.
	y = 8
	while y < h - 20:
		var x := 12
		while x < w - 10:
			if absi(x - mid_x) >= pasillo / 2.0 + 1 and at(g, x, y) == SUELO:
				set_tile(g, x, y, OBSTACULO)
				props.append({"x": x, "y": y, "id": "pilar_biblioteca"})
			x += 16
		y += 15
	# Mostrador de caja en U frente al punto de aparición.
	var caja_y := h - 15
	var caja_x0 := mid_x - 10
	var caja_x1 := mid_x + 10
	for x in range(caja_x0, caja_x1 + 1):
		if absi(x - mid_x) <= 1:
			continue
		set_tile(g, x, caja_y, OBSTACULO)
		props.append({"x": x, "y": caja_y, "id": "mostrador"})
	for x in [caja_x0, caja_x1]:
		for cy in range(caja_y - 3, caja_y):
			set_tile(g, x, cy, OBSTACULO)
			props.append({"x": x, "y": cy, "id": "mostrador", "orientacion": "vertical"})
	for x in [caja_x0 + 4, caja_x1 - 4]:
		props.append({"x": x, "y": caja_y, "id": "terminal_biblioteca"})
	# Mesas bajas de novedades, con colisión.
	for e: Array in [[mid_x - 20, h - 24], [mid_x + 18, h - 24], [mid_x - 29, h - 12], [mid_x + 27, h - 11]]:
		set_tile(g, e[0], e[1], OBSTACULO)
		props.append({"x": e[0], "y": e[1], "id": "mesa_expositora"})
	# Carteles suspendidos: no bloquean el suelo.
	props.append({"x": mid_x, "y": caja_y, "id": "cartel_the_end"})
	props.append({"x": mid_x, "y": 5, "id": "cartel_the_end_near"})
	var shelf_tiles := 0
	for yy in range(1, h - 1):
		for xx in range(1, w - 1):
			if at(g, xx, yy) == ESTANTERIA:
				shelf_tiles += 1
	var columns := 0
	for p in props:
		if p.id == "pilar_biblioteca":
			columns += 1
	g.meta["_biblioteca"] = {
		"shelfTiles": shelf_tiles, "corridorWidth": pasillo, "readingHalls": reading_halls,
		"checkout": {"x": caja_x0, "y": caja_y, "w": caja_x1 - caja_x0 + 1},
		"columns": columns, "signs": 2,
	}
	g.meta["_propsEstructurales"] = props
	var spawn_pool: Array[Vector2i] = []
	for sy in range(h - 9, h - 5):
		for sx in range(mid_x - 4, mid_x + 5):
			if at(g, sx, sy) == SUELO:
				spawn_pool.append(Vector2i(sx, sy))
	g.meta["_spawnPool"] = spawn_pool
	return g

## Autómata celular: cuevas / exteriores (Level 6, 144, 909, 996)
static func gen_exterior(w: int, h: int, rng: Rng, opts: Dictionary = {}) -> Grid:
	var g := Grid.new(w, h, PARED)
	var density: float = opts.get("density", 0.44)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if not rng.azar(density):
				set_tile(g, x, y, SUELO)
	for it in 4:
		var nt := g.t.duplicate()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var walls := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if at(g, x + dx, y + dy) == PARED:
							walls += 1
				nt[y * g.w + x] = PARED if walls >= 5 else SUELO
		g.t = nt
	return g

## Bosque: claros + arboledas + lagos (Level 45, 186, 626)
static func gen_bosque(w: int, h: int, rng: Rng, opts: Dictionary = {}) -> Grid:
	var g := gen_exterior(w, h, rng, {"density": 0.36})
	var lagos: int = opts.get("lagos", 0)
	if lagos:
		for i in lagos:
			var cx := rng.entero(6, w - 7)
			var cy := rng.entero(6, h - 7)
			var r := rng.entero(2, 4)
			for y in range(cy - r, cy + r + 1):
				for x in range(cx - r, cx + r + 1):
					if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r and at(g, x, y) == SUELO:
						set_tile(g, x, y, AGUA)
	for i in 30:
		var dx := rng.entero(2, w - 3)
		var dy := rng.entero(2, h - 3)
		set_tile(g, dx, dy, DECOR)
	return g

## Invernadero flotante (Level 13): corredores de cristal sobre el vacío.
@warning_ignore("integer_division")
static func gen_invernadero(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, VACIO)
	var carve := func(x: int, y: int, ancho: int) -> void:
		for dy in ancho:
			for dx in ancho:
				set_tile(g, x + dx, y + dy, SUELO)
	# corredor principal serpenteante
	var x := 4
	var y := rng.entero(h / 3, (h * 2) / 3)
	var dir_y := 0
	var hitos: Array[Vector2i] = [Vector2i(x, y)]
	while x < w - 8:
		var largo := rng.entero(8, 16)
		var i := 0
		while i < largo and x < w - 5:
			carve.call(x, y, 3)
			x += 1
			i += 1
		hitos.append(Vector2i(x, y))
		# quiebro vertical
		dir_y = rng.elegir([-1, 1])
		var salto := rng.entero(4, 9)
		for j in salto:
			var ny := y + dir_y
			if ny < 3 or ny > h - 7:
				break
			y = ny
			carve.call(x, y, 3)
		hitos.append(Vector2i(x, y))
	# pasarelas laterales cortas con mirador
	var barajados := rng.barajar(hitos)
	for k in mini(4, barajados.size()):
		var hito: Vector2i = barajados[k]
		var dir: int = rng.elegir([-1, 1])
		var largo := rng.entero(4, 7)
		for i in range(1, largo + 1):
			var ny := hito.y + dir * i
			if ny < 3 or ny > h - 6:
				break
			carve.call(hito.x, ny, 2)
	# salas-jardín con vegetación
	for i in 3:
		var hito: Vector2i = rng.elegir(hitos)
		var rw := rng.entero(6, 9)
		var rh := rng.entero(5, 8)
		var rx := maxi(2, mini(w - rw - 2, hito.x - 2))
		var ry := maxi(2, mini(h - rh - 2, hito.y - 2))
		for yy in range(ry, ry + rh):
			for xx in range(rx, rx + rw):
				set_tile(g, xx, yy, DECOR if rng.azar(0.18) else SUELO)
	# paredes de cristal: todo borde del suelo que da al vacío
	for yy in h:
		for xx in w:
			if at(g, xx, yy) != VACIO:
				continue
			var vecino_suelo := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if walkable(at(g, xx + d.x, yy + d.y)):
					vecino_suelo = true
					break
			if vecino_suelo:
				set_tile(g, xx, yy, PARED)
	return g

## Ciudad y barrios: edificios transitables con fachada, puerta e interior.
static func gen_ciudad(w: int, h: int, rng: Rng, opts: Dictionary = {}) -> Grid:
	var g := Grid.new(w, h, SUELO)
	var residencial: bool = opts.get("residencial", false)
	for x in w:
		set_tile(g, x, 0, PARED)
		set_tile(g, x, h - 1, PARED)
	for y in h:
		set_tile(g, 0, y, PARED)
		set_tile(g, w - 1, y, PARED)
	var y := 3
	while y < h - 6:
		var x := 3
		var bh := rng.entero(7 if residencial else 8, 11 if residencial else 14)
		while x < w - 6:
			var bw := rng.entero(8 if residencial else 9, 13 if residencial else 16)
			var x2 := mini(x + bw, w - 3)
			var y2 := mini(y + bh, h - 3)
			if x2 - x >= 6 and y2 - y >= 6 and rng.azar(0.9):
				for xx in range(x, x2 + 1):
					set_tile(g, xx, y, PARED)
					set_tile(g, xx, y2, PARED)
				for yy in range(y, y2 + 1):
					set_tile(g, x, yy, PARED)
					set_tile(g, x2, yy, PARED)
				var puerta := rng.entero(x + 2, x2 - 2)
				set_tile(g, puerta, y2, SUELO)
				if x2 - x >= 10:
					var tabique := rng.entero(x + 4, x2 - 4)
					for yy in range(y + 1, y2):
						set_tile(g, tabique, yy, PARED)
					set_tile(g, tabique, rng.entero(y + 2, y2 - 2), SUELO)
				if not residencial and y2 - y >= 10:
					var tabique := rng.entero(y + 4, y2 - 4)
					for xx in range(x + 1, x2):
						if at(g, xx, tabique) != PARED:
							set_tile(g, xx, tabique, PARED)
					set_tile(g, rng.entero(x + 2, x2 - 2), tabique, SUELO)
			x += bw + rng.entero(3, 5)
		y += bh + rng.entero(4, 6)
	for i in 32:
		var dx := rng.entero(2, w - 3)
		var dy := rng.entero(2, h - 3)
		if at(g, dx, dy) == SUELO:
			set_tile(g, dx, dy, DECOR)
	return g

## Torres: plataformas sobre el vacío unidas por vigas (Level 385)
@warning_ignore("integer_division")
static func gen_torres(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, VACIO)
	var plats: Array[Rect2i] = []
	var n := rng.entero(9, 12)
	for i in n:
		var pw := rng.entero(5, 9)
		var ph := rng.entero(4, 7)
		var px := rng.entero(2, w - pw - 3)
		var py := rng.entero(2, h - ph - 3)
		plats.append(Rect2i(px, py, pw, ph))
		for y in range(py, py + ph):
			for x in range(px, px + pw):
				set_tile(g, x, y, SUELO)
	for i in range(1, plats.size()):
		var a := plats[i - 1]
		var b := plats[i]
		var x1 := a.position.x + a.size.x / 2
		var y1 := a.position.y + a.size.y / 2
		var x2 := b.position.x + b.size.x / 2
		var y2 := b.position.y + b.size.y / 2
		while x1 != x2:
			if at(g, x1, y1) == VACIO:
				set_tile(g, x1, y1, DECOR)
			x1 += signi(x2 - x1)
		while y1 != y2:
			if at(g, x1, y1) == VACIO:
				set_tile(g, x1, y1, DECOR)
			y1 += signi(y2 - y1)
	return g

## Redes de pasarelas: nodos habitables conectados por puentes anchos.
@warning_ignore("integer_division")
static func gen_pasarelas(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, VACIO)
	var nodos: Array[Dictionary] = []
	var carve := func(x: int, y: int, rw: int, rh: int, tile: int = SUELO) -> void:
		for yy in range(maxi(1, y), mini(h - 1, y + rh)):
			for xx in range(maxi(1, x), mini(w - 1, x + rw)):
				set_tile(g, xx, yy, tile)
	var total := maxi(6, w / 17)
	for i in total:
		var rw := rng.entero(8, 13)
		var rh := rng.entero(6, 10)
		var x := mini(w - rw - 2, 3 + (i * (w - 18)) / maxi(1, total - 1))
		var banda := i % 3
		var y_centro := floori(h * 0.28) if banda == 0 else (floori(h * 0.7) if banda == 1 else floori(h * 0.5))
		var y := maxi(2, mini(h - rh - 2, y_centro - rh / 2 + rng.entero(-3, 3)))
		carve.call(x, y, rw, rh)
		nodos.append({"x": x, "y": y, "w": rw, "h": rh, "cx": x + rw / 2, "cy": y + rh / 2})
	var bridge := func(a: Dictionary, b: Dictionary) -> void:
		var x: int = a.cx
		var y: int = a.cy
		while x != b.cx:
			for d in range(-1, 2):
				if at(g, x, y + d) == VACIO:
					set_tile(g, x, y + d, DECOR)
			x += signi(b.cx - x)
		while y != b.cy:
			for d in range(-1, 2):
				if at(g, x + d, y) == VACIO:
					set_tile(g, x + d, y, DECOR)
			y += signi(b.cy - y)
	for i in range(1, nodos.size()):
		bridge.call(nodos[i - 1], nodos[i])
	if nodos.size() > 4:
		bridge.call(nodos[0], nodos[3])
		bridge.call(nodos[2], nodos[nodos.size() - 1])
	# Algunas plataformas alojan cabinas con una puerta real.
	for i in nodos.size():
		var nodo := nodos[i]
		if i % 2 == 0 and nodo.w >= 9 and nodo.h >= 7:
			var x0: int = nodo.x + 2
			var y0: int = nodo.y + 2
			var x1: int = nodo.x + nodo.w - 3
			var y1: int = nodo.y + nodo.h - 3
			for x in range(x0, x1 + 1):
				set_tile(g, x, y0, PARED)
				set_tile(g, x, y1, PARED)
			for y in range(y0, y1 + 1):
				set_tile(g, x0, y, PARED)
				set_tile(g, x1, y, PARED)
			set_tile(g, (x0 + x1) / 2, y1, SUELO)
	g.meta["_pasarelas"] = {"nodos": nodos.size(),
		"puentes": nodos.size() + (1 if nodos.size() > 4 else -1)}
	return g

## Complejo inundado: islas de suelo entre grandes bolsas de agua.
static func gen_acuatico(w: int, h: int, rng: Rng, opts: Dictionary = {}) -> Grid:
	var g := gen_exterior(w, h, rng, {"density": opts.get("density", 0.32)})
	var lagos: int = opts.get("lagos", 12)
	for i in lagos:
		var cx := rng.entero(5, w - 6)
		var cy := rng.entero(5, h - 6)
		var rx := rng.entero(2, 6)
		var ry := rng.entero(2, 5)
		for y in range(cy - ry, cy + ry + 1):
			for x in range(cx - rx, cx + rx + 1):
				var fx := float(x - cx) / rx
				var fy := float(y - cy) / ry
				if fx * fx + fy * fy <= 1.0 and at(g, x, y) == SUELO:
					set_tile(g, x, y, AGUA)
	return g

## Level 37.2: salas blancas anchas cubiertas por agua somera.
static func gen_piscinas(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, AGUA)
	for x in w:
		set_tile(g, x, 0, PARED)
		set_tile(g, x, h - 1, PARED)
	for y in h:
		set_tile(g, 0, y, PARED)
		set_tile(g, w - 1, y, PARED)
	var camaras := 1
	var x := 17
	while x < w - 8:
		for y in range(1, h - 1):
			set_tile(g, x, y, PARED)
		var y := 7
		while y < h - 5:
			for dx in range(-1, 3):
				set_tile(g, x + dx, y, AGUA)
			y += 15
		camaras += 1
		x += rng.entero(15, 20)
	var wy := 15
	while wy < h - 8:
		for xx in range(1, w - 1):
			set_tile(g, xx, wy, PARED)
		var xx := 9
		while xx < w - 6:
			for dy in range(-1, 3):
				set_tile(g, xx, wy + dy, AGUA)
			xx += 19
		camaras += 1
		wy += rng.entero(13, 18)
	var plataformas := 0
	for i in 9:
		var x0 := rng.entero(3, w - 10)
		var y0 := rng.entero(3, h - 8)
		var rw := rng.entero(3, 7)
		var rh := rng.entero(2, 5)
		for y in range(y0, y0 + rh):
			for px in range(x0, x0 + rw):
				if at(g, px, y) == AGUA:
					set_tile(g, px, y, DECOR)
		plataformas += 1
	g.meta["_piscinas"] = {"camaras": camaras, "plataformas": plataformas}
	return g

## Océano real: el agua domina; las zonas secas son búnkeres o plataformas.
@warning_ignore("integer_division")
static func gen_oceano(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, AGUA)
	for x in w:
		set_tile(g, x, 0, PARED)
		set_tile(g, x, h - 1, PARED)
	for y in h:
		set_tile(g, 0, y, PARED)
		set_tile(g, w - 1, y, PARED)
	var estructuras: Array[Rect2i] = [Rect2i(w / 2 - 7, h / 2 - 5, 14, 10)]
	for i in 7:
		estructuras.append(Rect2i(rng.entero(3, w - 11), rng.entero(3, h - 9),
			rng.entero(5, 9), rng.entero(4, 7)))
	for i in estructuras.size():
		var r := estructuras[i]
		var x2 := mini(w - 2, r.position.x + r.size.x)
		var y2 := mini(h - 2, r.position.y + r.size.y)
		for yy in range(r.position.y, y2 + 1):
			for xx in range(r.position.x, x2 + 1):
				set_tile(g, xx, yy, SUELO)
		if i == 0:
			for xx in range(r.position.x, x2 + 1):
				set_tile(g, xx, r.position.y, PARED)
				set_tile(g, xx, y2, PARED)
			for yy in range(r.position.y, y2 + 1):
				set_tile(g, r.position.x, yy, PARED)
				set_tile(g, x2, yy, PARED)
			set_tile(g, (r.position.x + x2) / 2, y2, SUELO)
	for i in floori(w * h * 0.012):
		var x := rng.entero(2, w - 3)
		var y := rng.entero(2, h - 3)
		if at(g, x, y) == AGUA and rng.azar(0.35):
			set_tile(g, x, y, PARED)
	return g

## Túnel de carretera para The Hub: calzada de múltiples carriles, arcenes,
## marcas viales blancas y ramales de salida laterales.
@warning_ignore("integer_division")
static func gen_hub_tunel(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, PARED)
	var mid_y := h / 2
	# Calzada principal: ocupa casi todo el alto del mapa
	var road_half := h / 2 - 3  # deja solo 3 filas de pared a cada lado
	road_half = mini(road_half, 20)  # máximo 41 tiles de ancho (20*2+1)
	# Marcas viales
	var carril := 7
	for y in range(mid_y - road_half, mid_y + road_half + 1):
		for x in range(1, w - 1):
			var tile: int = SUELO
			if y == mid_y:
				tile = DECOR  # línea central
			elif (y - mid_y) % carril == 0:
				tile = DECOR  # separador de carril
			set_tile(g, x, y, tile)
	
	# Ramales: túneles que salen de la carretera principal
	for branch in 3:
		var bx := rng.entero(10, w - 11)
		var up := rng.azar(0.5)
		var end := rng.entero(2, mid_y - road_half - 3) if up else rng.entero(mid_y + road_half + 3, h - 3)
		# Conectar desde la carretera hasta el final del ramal
		var y0 := mini(mid_y, end)
		var y1 := maxi(mid_y, end)
		for y in range(y0, y1 + 1):
			for dx in range(-2, 3):
				set_tile(g, bx + dx, y, SUELO)
		# Zona de ensanche al final
		var sy := end - 2 if up else end
		for y in range(sy, sy + 5):
			for x in range(bx - 6, bx + 7):
				set_tile(g, x, y, SUELO)
	
	g.meta["_spawn_hub"] = {"x": w / 2, "y": mid_y}
	g.meta["_spawnPool"] = [Vector2i(w / 2, mid_y)] as Array[Vector2i]
	return g

## Carretera anómala con arcenes, cruces y áreas de servicio.
@warning_ignore("integer_division")
static func gen_carretera(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, PARED)
	var mid_y := h / 2
	for y in range(mid_y - 3, mid_y + 4):
		for x in range(1, w - 1):
			set_tile(g, x, y, DECOR if y == mid_y else SUELO)
	for branch in 5:
		var bx := rng.entero(8, w - 9)
		var up := rng.azar(0.5)
		var end := rng.entero(3, mid_y - 7) if up else rng.entero(mid_y + 7, h - 4)
		var y0 := mini(mid_y, end)
		var y1 := maxi(mid_y, end)
		for y in range(y0, y1 + 1):
			for dx in range(-1, 2):
				set_tile(g, bx + dx, y, SUELO)
		var sy := end - 2 if up else end
		for y in range(sy, sy + 5):
			for x in range(bx - 5, bx + 6):
				set_tile(g, x, y, SUELO)
	return g

## Vagones encadenados por un corredor ferroviario estrecho.
@warning_ignore("integer_division")
static func gen_tren(w: int, h: int, rng: Rng) -> Grid:
	var g := Grid.new(w, h, PARED)
	var cy := h / 2
	for x in range(1, w - 1):
		for y in range(cy - 2, cy + 3):
			set_tile(g, x, y, SUELO)
	var x := 4
	while x < w - 10:
		var arriba := rng.azar(0.5)
		var y0 := cy - 8 if arriba else cy + 3
		for y in range(y0, y0 + 6):
			for xx in range(x, mini(w - 2, x + 8)):
				set_tile(g, xx, y, SUELO)
		var puerta_y := cy - 3 if arriba else cy + 3
		set_tile(g, x + 4, puerta_y, SUELO)
		x += rng.entero(10, 15)
	return g

## Arquitecturas semánticas detectadas en la wiki.
@warning_ignore("integer_division")
static func gen_arquitectura(w: int, h: int, rng: Rng, tipo: String) -> Grid:
	var g := Grid.new(w, h, PARED)
	var props: Array[Dictionary] = []
	var carve := func(x: int, y: int, rw: int, rh: int, tile: int = SUELO) -> void:
		for yy in range(maxi(1, y), mini(h - 1, y + rh)):
			for xx in range(maxi(1, x), mini(w - 1, x + rw)):
				set_tile(g, xx, yy, tile)
	var prop := func(x: int, y: int, id: String, extra: Dictionary = {}) -> void:
		if not walkable(at(g, x, y)):
			return
		set_tile(g, x, y, OBSTACULO)
		var p := {"x": x, "y": y, "id": id, "contenedor": false}
		p.merge(extra, true)
		props.append(p)

	if tipo == "sala_unica":
		carve.call(2, 2, w - 4, h - 4)
		var y := 8
		while y < h - 7:
			var x := 9
			while x < w - 8:
				if rng.azar(0.55):
					prop.call(x, y, "mesa")
				x += 16
			y += 12
		g.meta["_salaUnica"] = {"area": (w - 4) * (h - 4)}
	elif tipo == "hotel_atrio":
		carve.call(2, 2, w - 4, h - 4)
		var ax := floori(w * 0.27)
		var ay := floori(h * 0.25)
		var aw := maxi(12, floori(w * 0.46))
		var ah := maxi(10, floori(h * 0.5))
		for x in range(ax, ax + aw):
			set_tile(g, x, ay, PARED)
			set_tile(g, x, ay + ah - 1, PARED)
		for y in range(ay, ay + ah):
			set_tile(g, ax, y, PARED)
			set_tile(g, ax + aw - 1, y, PARED)
		carve.call(ax + 1, ay + 1, aw - 2, ah - 2, DECOR)
		carve.call(ax + aw / 2 - 1, ay - 1, 3, 3)
		carve.call(ax + aw / 2 - 1, ay + ah - 2, 3, 3)
		carve.call(ax - 1, ay + ah / 2 - 1, 3, 3)
		carve.call(ax + aw - 2, ay + ah / 2 - 1, 3, 3)
		var x := 8
		while x < w - 7:
			for y in range(3, ay - 2):
				set_tile(g, x, y, PARED)
			for y in range(ay + ah + 2, h - 3):
				set_tile(g, x, y, PARED)
			prop.call(x - 3, 5, "cama")
			prop.call(x - 3, h - 6, "cama")
			x += 9
		g.meta["_atrio"] = {"x": ax, "y": ay, "w": aw, "h": ah}
	elif tipo == "viviendas_conectadas":
		carve.call(2, 2, w - 4, h - 4)
		var cx := w / 2
		for x in range(2, w - 2):
			if absi(x - cx) > 1:
				var y := 11
				while y < h - 3:
					set_tile(g, x, y, PARED)
					y += 11
		var vx := 10
		while vx < w - 3:
			for y in range(2, h - 2):
				if y % 11 > 2:
					set_tile(g, vx, y, PARED)
			vx += 10
		carve.call(cx - 1, 2, 3, h - 4)
		var wy := 11
		while wy < h - 3:
			var wx := 5
			while wx < w - 4:
				carve.call(wx, wy - 1, 2, 3)
				wx += 10
			wy += 11
		var py := 6
		while py < h - 4:
			var px := 6
			while px < w - 5:
				prop.call(px, py, "cama")
				px += 10
			py += 11
	elif tipo == "sotanos_conectados":
		carve.call(2, 2, w - 4, h - 4)
		var cy := h / 2
		carve.call(2, cy - 2, w - 4, 5)
		var x := 11
		while x < w - 7:
			for y in range(3, h - 3):
				if absi(y - cy) > 2:
					set_tile(g, x, y, PARED)
			carve.call(x - 1, cy - 3, 3, 7)
			x += 12
		var filtraciones := 0
		var fy := 6
		while fy < h - 5:
			var fx := 6
			while fx < w - 5:
				if at(g, fx, fy) == SUELO and rng.azar(0.45):
					set_tile(g, fx, fy, CHARCO)
					filtraciones += 1
				fx += 11
			fy += 9
		g.meta["_sotanos"] = {"filtraciones": filtraciones}
	elif tipo == "recinto_deportivo":
		carve.call(2, 2, w - 4, h - 4)
		var banda := maxi(10, (w - 8) / 3)
		for k in 3:
			var x0 := 4 + k * banda
			for y in range(6, h - 8):
				set_tile(g, x0, y, DECOR)
				set_tile(g, mini(w - 4, x0 + banda - 2), y, DECOR)
			var my := 8
			while my < h - 9:
				prop.call(mini(w - 5, x0 + banda - 4), my, "marcador")
				my += 8
		var bx := 5
		while bx < w - 5:
			prop.call(bx, h - 5, "banco")
			bx += 5
		g.meta["_pistas"] = 3
	elif tipo == "galerias_comerciales":
		carve.call(2, 2, w - 4, h - 4)
		var cx := w / 2
		var cy := h / 2
		var gx := 3
		while gx < w - 3:
			for y in range(3, h - 3):
				if absi(y - cy) > 2 and y % 12 > 2:
					set_tile(g, gx, y, PARED)
			gx += 10
		var gy := 9
		while gy < h - 4:
			for x in range(3, w - 3):
				if absi(x - cx) > 2 and x % 10 > 2:
					set_tile(g, x, gy, PARED)
			gy += 12
		carve.call(cx - 2, 2, 5, h - 4)
		carve.call(2, cy - 2, w - 4, 5)
		var py := 6
		while py < h - 5:
			var px := 6
			while px < w - 5:
				if absi(px - cx) > 3 and absi(py - cy) > 3:
					prop.call(px, py, "mostrador")
				px += 10
			py += 8
	elif tipo == "planta_estudio":
		carve.call(2, 2, w - 4, h - 4)
		var cy := h / 2
		carve.call(2, cy - 2, w - 4, 5)
		var x := 12
		while x < w - 8:
			for y in range(3, h - 3):
				if absi(y - cy) > 2:
					set_tile(g, x, y, PARED)
			carve.call(x - 1, cy - 3, 3, 7)
			prop.call(x - 5, maxi(5, cy - 8), "camara_estudio")
			prop.call(x + 5, mini(h - 6, cy + 8), "foco_estudio")
			x += 16
		g.meta["_platos"] = maxi(2, w / 16)
	elif tipo == "banos_publicos":
		carve.call(2, 2, w - 4, h - 4)
		var cy := h / 2
		var x := 5
		while x < w - 4:
			for y in range(3, cy - 2):
				set_tile(g, x, y, PARED)
			for y in range(cy + 2, h - 3):
				set_tile(g, x, y, PARED)
			carve.call(x - 1, cy - 3, 2, 3)
			carve.call(x - 1, cy + 1, 2, 3)
			prop.call(x - 2, 4, "lavabo")
			prop.call(x - 2, h - 5, "lavabo")
			x += 5
		carve.call(2, cy - 2, w - 4, 5)
	elif tipo == "castillo":
		carve.call(2, 2, w - 4, h - 4)
		var mx := maxi(8, floori(w * 0.22))
		var my := maxi(7, floori(h * 0.2))
		for x in range(mx, w - mx):
			set_tile(g, x, my, PARED)
			set_tile(g, x, h - my - 1, PARED)
		for y in range(my, h - my):
			set_tile(g, mx, y, PARED)
			set_tile(g, w - mx - 1, y, PARED)
		carve.call(w / 2 - 2, my - 1, 5, 3)
		carve.call(w / 2 - 2, h - my - 1, 5, 3)
		carve.call(mx - 1, h / 2 - 2, 3, 5)
		carve.call(w - mx - 1, h / 2 - 2, 3, 5)
		for t: Array in [[4, 4], [w - 10, 4], [4, h - 10], [w - 10, h - 10]]:
			var tx: int = t[0]
			var ty: int = t[1]
			for yy in range(ty, ty + 6):
				for xx in range(tx, tx + 6):
					if xx == tx or yy == ty or xx == tx + 5 or yy == ty + 5:
						set_tile(g, xx, yy, PARED)
			carve.call(tx + 2, ty + 2, 2, 2)
		prop.call(w / 2, h / 2, "altar")
	elif tipo == "sala_columnada":
		carve.call(1, 1, w - 2, h - 2)
		var pilares := 0
		var y := 6
		while y < h - 5:
			var x := 6
			while x < w - 5:
				set_tile(g, x, y, PARED)
				set_tile(g, x + 1, y, PARED)
				set_tile(g, x, y + 1, PARED)
				set_tile(g, x + 1, y + 1, PARED)
				pilares += 1
				x += 7
			y += 7
		g.meta["_columnas"] = pilares
	elif tipo == "zoologico":
		carve.call(2, 2, w - 4, h - 4, DECOR)
		var cx := w / 2
		var cy := h / 2
		for y in range(3, h - 3):
			for x in range(3, w - 3):
				if absi(x - cx) > 2 and absi(y - cy) > 2:
					set_tile(g, x, y, PARED)
		carve.call(cx - 2, 2, 5, h - 4, DECOR)
		carve.call(2, cy - 2, w - 4, 5, DECOR)
		var recintos := 0
		var ry := 5
		while ry < h - 12:
			var rx := 5
			while rx < w - 15:
				var rw := mini(12, w - rx - 3)
				var rh := mini(10, h - ry - 3)
				carve.call(rx + 1, ry + 1, rw - 2, rh - 2, AGUA if rng.azar(0.3) else DECOR)
				for xx in range(rx, rx + rw):
					set_tile(g, xx, ry, PARED)
					set_tile(g, xx, ry + rh - 1, PARED)
				for yy in range(ry, ry + rh):
					set_tile(g, rx, yy, PARED)
					set_tile(g, rx + rw - 1, yy, PARED)
				var puerta_x := rx + rw / 2
				var puerta_y := ry + rh - 1 if ry < cy else ry
				set_tile(g, puerta_x, puerta_y, SUELO)
				# Une cada recinto al eje más cercano para garantizar acceso.
				for yy in range(mini(puerta_y, cy), maxi(puerta_y, cy) + 1):
					set_tile(g, puerta_x, yy, DECOR)
				prop.call(rx + 2, ry + 2, "tanque_acuatico" if rng.azar(0.3) else "cartel_zoo")
				recintos += 1
				rx += 18
			ry += 15
		var zx := 9
		while zx < w - 8:
			if at(g, zx, cy) == DECOR:
				prop.call(zx, cy, "carrito_zoo")
			zx += 22
		g.meta["_zoologico"] = {"recintos": recintos, "senderos": 2, "cx": cx, "cy": cy}
	elif tipo == "parque_recreativo":
		carve.call(2, 2, w - 4, h - 4)
		var y := 7
		while y < h - 6:
			var x := 7
			while x < w - 6:
				prop.call(x, y, "maquina_arcade")
				if rng.azar(0.45):
					prop.call(x + 2, y, "maquina_arcade")
				x += 10
			y += 9
		var cy := 12
		while cy < h - 7:
			carve.call(3, cy, w - 6, 3, DECOR)
			cy += 18
	elif tipo == "cementerio":
		carve.call(1, 1, w - 2, h - 2, DECOR)
		var y := 6
		while y < h - 5:
			var x := 5
			while x < w - 4:
				if x % 16 > 3 and y % 20 > 3:
					prop.call(x, y, "lapida")
				x += 4
			y += 5
		for x in range(3, w - 3):
			set_tile(g, x, h / 2, SUELO)
		for cy in range(3, h - 3):
			set_tile(g, w / 2, cy, SUELO)
		for t: Array in [[5, 5], [w - 12, 5], [5, h - 11], [w - 12, h - 11]]:
			var tx: int = t[0]
			var ty: int = t[1]
			for yy in range(ty, ty + 6):
				for xx in range(tx, tx + 7):
					if xx == tx or yy == ty or xx == tx + 6 or yy == ty + 5:
						set_tile(g, xx, yy, PARED)
			carve.call(tx + 3, ty + 5, 1, 2)
	elif tipo == "prision":
		var cx := w / 2
		carve.call(cx - 2, 1, 5, h - 2)
		var y := 3
		while y < h - 6:
			for side in [-1, 1]:
				var x := 2 if side < 0 else cx + 4
				var rw := cx - 5 if side < 0 else w - cx - 6
				carve.call(x, y, rw, 5)
				carve.call(cx - 3 if side < 0 else cx + 3, y + 2, 2, 1)
				var xx := x + 3
				while xx < x + rw - 1:
					set_tile(g, xx, y + 4, PARED)
					xx += 5
			y += 7
	elif tipo == "aeropuerto":
		var cy := h / 2
		carve.call(1, cy - 4, w - 2, 9) # terminal longitudinal
		var x := 4
		while x < w - 9:
			carve.call(x, 3, 8, cy - 7)
			carve.call(x, cy + 5, 8, h - cy - 8)
			carve.call(x + 3, cy - 5, 2, 11) # puertas de embarque
			var yy := 7
			while yy < cy - 5:
				prop.call(x + 2, yy, "asiento_terminal")
				yy += 3
			yy = cy + 7
			while yy < h - 5:
				prop.call(x + 5, yy, "asiento_terminal")
				yy += 3
			x += 11
	elif tipo == "estadio":
		carve.call(1, 1, w - 2, h - 2)
		var margen_x := maxi(8, floori(w * 0.18))
		var margen_y := maxi(7, floori(h * 0.2))
		var y := 3
		while y < h - 3:
			var x := 3
			while x < w - 3:
				var campo := x >= margen_x and x < w - margen_x and y >= margen_y and y < h - margen_y
				var pasillo := x == margen_x - 2 or x == w - margen_x + 1 \
					or y == margen_y - 2 or y == h - margen_y + 1
				if not campo and not pasillo:
					prop.call(x, y, "grada")
				x += 3
			y += 3
		g.meta["_campo"] = {"x": margen_x, "y": margen_y, "w": w - margen_x * 2, "h": h - margen_y * 2}
	elif tipo == "teatro":
		carve.call(2, 2, w - 4, h - 4)
		var escenario_y := maxi(5, floori(h * 0.22))
		var y := escenario_y + 5
		while y < h - 4:
			var x := 4
			while x < w - 4:
				if absf(x - w / 2.0) > 2:
					prop.call(x, y, "butaca")
				x += 3
			y += 3
		for x in range(4, w - 4):
			set_tile(g, x, escenario_y, DECOR)
		g.meta["_escenario"] = {"x": 4, "y": escenario_y - 4, "w": w - 8, "h": 5}
	elif tipo == "templo":
		var nave_x := maxi(4, floori(w * 0.18))
		carve.call(nave_x, 2, w - nave_x * 2, h - 4)
		carve.call(2, floori(h * 0.42), w - 4, maxi(7, floori(h * 0.16))) # crucero
		var y := 8
		while y < h - 9:
			for x in [nave_x + 3, w - nave_x - 4]:
				prop.call(x, y, "banco")
			y += 5
		prop.call(w / 2, 5, "altar")
	elif tipo == "museo":
		carve.call(2, 2, w - 4, h - 4)
		var x := 10
		while x < w - 8:
			for y in range(3, h - 3):
				if y % 14 > 3:
					set_tile(g, x, y, PARED)
			x += 12
		var wy := 10
		while wy < h - 8:
			for wx in range(3, w - 3):
				if wx % 12 > 3:
					set_tile(g, wx, wy, PARED)
			wy += 14
		var py := 6
		while py < h - 5:
			var px := 6
			while px < w - 5:
				prop.call(px, py, "vitrina")
				px += 8
			py += 8
	elif tipo == "almacen":
		carve.call(1, 1, w - 2, h - 2)
		var x := 5
		while x < w - 5:
			for y in range(4, h - 4):
				if y % 13 > 2:
					set_tile(g, x, y, ESTANTERIA)
					set_tile(g, x + 1, y, ESTANTERIA)
			x += 6
		var px := 3
		while px < w - 3:
			prop.call(px, h - 4, "palet")
			px += 14
	elif tipo == "restaurante":
		carve.call(2, 2, w - 4, h - 4)
		var cocina_x := floori(w * 0.7)
		for y in range(3, h - 3):
			if y % 9 > 2:
				set_tile(g, cocina_x, y, PARED)
		var my := 6
		while my < h - 5:
			var mx := 6
			while mx < cocina_x - 3:
				prop.call(mx, my, "mesa")
				mx += 6
			my += 5
		var ey := 5
		while ey < h - 5:
			prop.call(w - 6, ey, "encimera")
			ey += 6
	else: # bunker
		carve.call(2, 2, w - 4, h - 4)
		var x := 10
		while x < w - 7:
			for y in range(3, h - 3):
				if y % 12 > 2:
					set_tile(g, x, y, PARED)
			carve.call(x - 1, h / 2 - 1, 3, 3)
			x += 11
		var by := 10
		while by < h - 7:
			for bx in range(3, w - 3):
				if bx % 11 > 2:
					set_tile(g, bx, by, PARED)
			by += 12
	g.meta["_propsEstructurales"] = props
	g.meta["_arquitectura"] = {"tipo": tipo, "props": props.size()}
	return g

# ---------- utilidades comunes ----------

static func collect_floors(g: Grid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in g.h:
		for x in g.w:
			if walkable(at(g, x, y)):
				out.append(Vector2i(x, y))
	return out

## Conserva solo el mayor componente conexo de suelo.
static func keep_largest(g: Grid) -> Grid:
	var comp_of := PackedInt32Array()
	comp_of.resize(g.w * g.h)
	comp_of.fill(-1)
	var best := -1
	var best_size := 0
	var comp := 0
	for y in g.h:
		for x in g.w:
			if not walkable(at(g, x, y)) or comp_of[y * g.w + x] != -1:
				continue
			var size := 0
			var q: Array[Vector2i] = [Vector2i(x, y)]
			comp_of[y * g.w + x] = comp
			while not q.is_empty():
				var c: Vector2i = q.pop_back()
				size += 1
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n := c + d
					if n.x < 0 or n.y < 0 or n.x >= g.w or n.y >= g.h:
						continue
					if walkable(at(g, n.x, n.y)) and comp_of[n.y * g.w + n.x] == -1:
						comp_of[n.y * g.w + n.x] = comp
						q.append(n)
			if size > best_size:
				best_size = size
				best = comp
			comp += 1
	for i in g.t.size():
		if walkable(g.t[i]) and comp_of[i] != best:
			g.t[i] = PARED
	return g

## Distancias BFS desde un punto (para colocar salidas lejos del spawn).
static func bfs_dist(g: Grid, sx: int, sy: int) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(g.w * g.h)
	d.fill(-1)
	d[sy * g.w + sx] = 0
	var q: Array[Vector2i] = [Vector2i(sx, sy)]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + dir
			if n.x < 0 or n.y < 0 or n.x >= g.w or n.y >= g.h:
				continue
			if walkable(at(g, n.x, n.y)) and d[n.y * g.w + n.x] == -1:
				d[n.y * g.w + n.x] = d[c.y * g.w + c.x] + 1
				q.append(n)
	return d

# ---------- despacho de generadores (GENS del JS) ----------

## Ejecuta el generador de un arquetipo. Las claves replican el objeto GENS
## del JS, incluidos los alias de topología semántica y los casos especiales
## por id de nivel (level-0, level-1, level-37-2).
static func _gen(clave: String, w: int, h: int, rng: Rng, lv: Dictionary) -> Grid:
	match clave:
		"pasillos", "laberinto_salas", "laberinto_no_euclidiano":
			if lv.get("id") == "level-0":
				return gen_pasillos(w, h, rng, {"salas": 16, "salaMinW": 4, "salaMaxW": 14,
					"salaMinH": 3, "salaMaxH": 10, "irregulares": true,
					"separacionSalas": 3, "atajos": floori(w * 1.35)})
			return gen_pasillos(w, h, rng)
		"garaje", "garaje_abierto", "garaje_infinito":
			return gen_garaje(w, h, rng, {"level1": lv.get("id") == "level-1"})
		"tuneles", "tuneles_anchos":
			return gen_tuneles(w, h, rng, {"ancho": true})
		"hospital", "alas_hospitalarias", "escuela", "alas_escolares", \
		"laboratorio", "alas_laboratorio":
			return gen_hospital(w, h, rng)
		"oficinas", "planta_oficinas", "hotel", "planta_hotel":
			return gen_oficinas(w, h, rng)
		"biblioteca", "biblioteca_abierta":
			return gen_biblioteca(w, h, rng)
		"exterior", "terreno_abierto":
			return gen_exterior(w, h, rng)
		"bosque", "bosque_claros":
			var lagos := 5 if (lv.get("reglas", []) as Array).has("agua_traicionera") else 2
			return gen_bosque(w, h, rng, {"lagos": lagos})
		"ciudad", "ciudad_transitable", "ruinas":
			return gen_ciudad(w, h, rng)
		"torres", "vertical", "espacial", "cielo":
			return gen_torres(w, h, rng)
		"invernadero":
			return gen_invernadero(w, h, rng)
		"acuatico":
			return gen_acuatico(w, h, rng, {"lagos": 10})
		"instalacion_inundada":
			if lv.get("id") == "level-37-2":
				return gen_piscinas(w, h, rng)
			return gen_acuatico(w, h, rng, {"lagos": 10})
		"oceano", "oceano_abierto":
			return gen_oceano(w, h, rng)
		"aguas_someras":
			var g := gen_oceano(w, h, rng)
			g.meta["_arquitectura"] = {"tipo": "aguas_someras", "props": 0}
			return g
		"desierto":
			return gen_exterior(w, h, rng, {"density": 0.25})
		"nevado":
			return gen_exterior(w, h, rng, {"density": 0.3})
		"centro_comercial", "industrial", "nave_industrial", "fabrica", \
		"estacion", "andenes":
			return gen_garaje(w, h, rng)
		"residencial", "barrio_transitable":
			return gen_ciudad(w, h, rng, {"residencial": true})
		"alcantarillas":
			return gen_tuneles(w, h, rng, {"walkers": 7})
		"cuevas":
			var g := gen_tuneles(w, h, rng, {"walkers": 7})
			g.meta["_arquitectura"] = {"tipo": "cuevas", "props": 0}
			return g
		"tren", "vagones":
			return gen_tren(w, h, rng)
		"carretera":
			if lv.get("id") == "the-hub":
				return gen_hub_tunel(w, h, rng)
			return gen_carretera(w, h, rng)
		"parque":
			return gen_bosque(w, h, rng, {"lagos": 1})
		"granja":
			return gen_exterior(w, h, rng, {"density": 0.28})
		"pantano":
			return gen_bosque(w, h, rng, {"lagos": 7})
		"surreal", "geometria_surreal":
			return gen_pasillos(w, h, rng, {"salas": 14, "irregulares": true, "atajos": floori(w * 1.5)})
		"laberinto_longitudinal":
			return gen_laberinto_longitudinal(w, h, rng)
		"corredor_longitudinal":
			var g := gen_laberinto_longitudinal(w, h, rng)
			g.meta["_arquitectura"] = {"tipo": "corredor_longitudinal", "props": 0}
			return g
		"plataformas", "vacio_cosmico":
			return gen_pasarelas(w, h, rng)
		"recreativo", "parque_recreativo":
			return gen_arquitectura(w, h, rng, "parque_recreativo")
		"cementerio":
			return gen_arquitectura(w, h, rng, "cementerio")
		"hotel_atrio", "viviendas_conectadas", "sotanos_conectados", \
		"recinto_deportivo", "galerias_comerciales", "castillo", "sala_columnada", \
		"zoologico", "planta_estudio", "banos_publicos", "sala_unica", "prision", \
		"templo", "aeropuerto", "estadio", "teatro", "museo", "bunker", "almacen", \
		"restaurante":
			return gen_arquitectura(w, h, rng, clave)
		"estacion_espacial":
			return gen_arquitectura(w, h, rng, "bunker")
		"aeronave":
			var g := gen_tren(w, h, rng)
			g.meta["_arquitectura"] = {"tipo": "aeronave", "props": 0}
			return g
	# clave desconocida: el llamante decide el fallback
	return null

static func _tiene_gen(clave: Variant) -> bool:
	if not (clave is String):
		return false
	const CLAVES := ["pasillos", "garaje", "tuneles", "hospital", "oficinas", "biblioteca",
		"recreativo", "cementerio", "exterior", "bosque", "ciudad", "torres", "invernadero",
		"acuatico", "oceano", "desierto", "nevado", "espacial", "cielo", "hotel",
		"centro_comercial", "residencial", "escuela", "industrial", "fabrica", "laboratorio",
		"alcantarillas", "estacion", "tren", "carretera", "parque", "granja", "pantano",
		"ruinas", "surreal", "laberinto_salas", "garaje_abierto", "tuneles_anchos",
		"alas_hospitalarias", "planta_oficinas", "terreno_abierto", "bosque_claros",
		"ciudad_transitable", "vertical", "instalacion_inundada", "oceano_abierto",
		"plataformas", "planta_hotel", "galerias_comerciales", "barrio_transitable",
		"alas_escolares", "nave_industrial", "alas_laboratorio", "andenes", "vagones",
		"geometria_surreal", "laberinto_no_euclidiano", "laberinto_longitudinal",
		"garaje_infinito", "biblioteca_abierta", "hotel_atrio", "aguas_someras",
		"viviendas_conectadas", "sotanos_conectados", "recinto_deportivo", "castillo",
		"cuevas", "sala_columnada", "parque_recreativo", "zoologico", "planta_estudio",
		"banos_publicos", "aeronave", "estacion_espacial", "vacio_cosmico", "sala_unica",
		"corredor_longitudinal", "prision", "templo", "aeropuerto", "estadio", "teatro",
		"museo", "bunker", "almacen", "restaurante"]
	return CLAVES.has(clave)

# ---------- mecánicas de salida ----------

static var _re_noclip := _compilar("no.?clip")
static var _re_romper_suelo := _compilar("(romp|quebr|abre)[^.]*(suelo|piso)|suelo (falso|débil|agrietado)")
static var _re_romper := _compilar("(romp|derrib|golpea|atraviesa|agriet)[^.]*(pared|muro)|pared (falsa|débil|agrietada)")
static var _re_caminata := _compilar("caminar sin rumbo|camina[r]? (durante|hasta|lejos)|andar (durante|hasta|sin)|deambul|vagar? (por|durante|hasta)|durante horas|durante días|kilómetros")
static var _re_suelo := _compilar("(?i)suelo|caer|agujero|fosa|hoyo|trampilla|pozo|precipicio|fall|escalera|ascensor|elevador")

static func _compilar(patron: String) -> RegEx:
	var re := RegEx.new()
	re.compile(patron)
	return re

## Mecánica derivada del texto de la wiki (v20), como mecanicaDe(s) del JS.
## Devuelve "" cuando el JS devolvería null.
static func mecanica_de(s: Dictionary) -> String:
	var mec: Variant = s.get("mecanica")
	if mec is String and not (mec as String).is_empty():
		return mec
	var t := str(s.get("texto", "")).to_lower()
	if _re_noclip.search(t):
		return "noclip"
	if _re_romper_suelo.search(t):
		return "romper_suelo"
	if _re_romper.search(t):
		return "romper"
	if _re_caminata.search(t):
		return "caminata"
	return ""

## Objetivo de pasos de una salida por caminata (reproducible por semilla).
static func walking_goal(level_def: Dictionary, run_seed: String, entry: int = 1, attempt: int = 0) -> int:
	var range_: Array = level_def.get("pasosCaminata", [800, 1200])
	var a := maxi(1, floori(float(range_[0])))
	var b := maxi(a, floori(float(range_[1])))
	return Rng.crear("%s::%s::caminata::%d::%d" % [run_seed, level_def.get("id"), entry, attempt]).entero(a, b)

## Permanencia en la Sala Manila (segundos reales).
static func manila_goal(salida_def: Dictionary, seed_key: String, attempt: int = 0) -> int:
	var range_: Array = salida_def.get("permanenciaS", [180, 300])
	var a := maxi(1, floori(float(range_[0])))
	var b := maxi(a, floori(float(range_[1])))
	return Rng.crear("%s::manila::%d" % [seed_key, attempt]).entero(a, b)

# ---------- generación completa de un nivel ----------

const PROPS_BIOMA := {
	"pasillos": ["cable", "enchufe"], "garaje": ["cono", "bidon"], "tuneles": ["bidon", "cable"],
	"hospital": ["camilla", "silla"], "oficinas": ["silla", "caja"], "biblioteca": [],
	"recreativo": ["silla"], "cementerio": ["roca_p"],
	"bosque": ["seta", "roca_p"], "exterior": ["roca_p"], "ciudad": ["farola"], "torres": ["caja"],
	"invernadero": ["silla", "caja"],
	"acuatico": ["roca_p", "bidon"], "oceano": ["roca_p", "caja"],
	"desierto": ["roca_p", "bidon"], "nevado": ["roca_p", "caja"],
	"espacial": ["cable", "caja"], "cielo": ["roca_p", "caja"],
	"hotel": ["silla", "caja"], "centro_comercial": ["silla", "caja"],
	"residencial": ["silla", "caja"], "escuela": ["silla", "caja"],
	"industrial": ["bidon", "cable"], "fabrica": ["bidon", "cable"], "laboratorio": ["camilla", "cable"],
	"alcantarillas": ["bidon", "cable"], "estacion": ["silla", "caja"], "tren": ["silla", "caja"],
	"carretera": ["cono", "bidon"], "parque": ["seta", "roca_p"], "granja": ["caja", "roca_p"],
	"pantano": ["seta", "roca_p"], "ruinas": ["roca_p", "cable"], "surreal": ["silla", "cable"],
}

const CONT_BIOMA := {
	"pasillos": "taquilla", "garaje": "taquilla", "tuneles": "cofre", "hospital": "nevera",
	"oficinas": "archivador", "biblioteca": "archivador", "recreativo": "archivador",
	"cementerio": "cofre", "bosque": "cofre", "exterior": "cofre", "ciudad": "cofre",
	"torres": "cofre", "invernadero": "cofre",
	"acuatico": "cofre", "oceano": "cofre", "desierto": "cofre", "nevado": "cofre",
	"espacial": "cofre", "cielo": "cofre", "hotel": "nevera", "centro_comercial": "archivador",
	"residencial": "nevera", "escuela": "archivador", "industrial": "taquilla",
	"fabrica": "taquilla", "laboratorio": "nevera", "alcantarillas": "cofre",
	"estacion": "taquilla", "tren": "taquilla",
	"carretera": "cofre", "parque": "cofre", "granja": "cofre", "pantano": "cofre",
	"ruinas": "cofre", "surreal": "cofre",
}

## Los muebles "de pared" van físicamente pegados a un muro (pared al norte).
const PROPS_PARED := ["taquilla", "archivador", "nevera", "reloj", "camilla",
	"farola", "estanteria", "ordenador", "salida_falsa"]

## Decorativos que cuelgan del muro: se colocan en una celda con pared al norte
## y se marcan con "pared": true para que el renderer los dibuje en la pared.
const DECORATIVOS_PARED := ["enchufe"]

static func generate(level_def: Dictionary, rng: Rng) -> Dictionary:
	var tam: Array = level_def.get("tam", [48, 48])
	var w := int(tam[0])
	var h := int(tam[1])
	# v20: los niveles con varias salidas CRECEN. Un nivel infinito conserva
	# su tamaño declarado: es una VENTANA móvil (Level 0 queda en 150×150).
	var n_sal := (level_def.get("salidas", []) as Array).size()
	var infinito: bool = bool(level_def.get("infinito", false))
	var esc := 1.0 if infinito else (1.45 if n_sal >= 5 else (1.25 if n_sal >= 3 else 1.0))
	if esc > 1.0:
		w = mini(190, roundi(w * esc))
		h = mini(190, roundi(h * esc))
	var topologia: Variant = (level_def.get("mapa", {}) as Dictionary).get("topologia")
	var clave: String = ""
	if _tiene_gen(topologia):
		clave = topologia
	elif _tiene_gen(level_def.get("bioma")):
		clave = level_def.get("bioma")
	else:
		clave = "pasillos"
	var g := _gen(clave, w, h, rng, level_def)
	keep_largest(g)
	var floors := collect_floors(g)
	if floors.size() < 60: # mapa degenerado: reintenta con variante
		g = gen_pasillos(w, h, rng, {"salas": 10})
		keep_largest(g)
		floors = collect_floors(g)

	var reglas: Array = level_def.get("reglas", [])
	var requiere_aire := reglas.has("respiracion_acuatica")
	var suelo_seco: Array[Vector2i] = []
	for p in floors:
		if at(g, p.x, p.y) != AGUA:
			suelo_seco.append(p)
	var acceso_tematico: Array[Vector2i] = []
	if g.meta.has("_zoologico"):
		var zoo: Dictionary = g.meta["_zoologico"]
		for p in floors:
			if absi(p.x - zoo.cx) <= 2 or absi(p.y - zoo.cy) <= 2:
				acceso_tematico.append(p)
	var bioma := str(level_def.get("bioma", ""))
	var urbano := bioma == "ciudad" or bioma == "residencial"
	var accesos_urbanos: Array[Vector2i] = []
	if urbano:
		for p in floors:
			if (at(g, p.x - 1, p.y) == PARED and at(g, p.x + 1, p.y) == PARED) \
					or (at(g, p.x, p.y - 1) == PARED and at(g, p.x, p.y + 1) == PARED):
				accesos_urbanos.append(p)
	var junto_acceso: Array[Vector2i] = []
	if urbano:
		for p in floors:
			for a in accesos_urbanos:
				if absi(a.x - p.x) + absi(a.y - p.y) == 1:
					junto_acceso.append(p)
					break
	var spawn_tematico: Array[Vector2i] = []
	for p: Vector2i in g.meta.get("_spawnPool", [] as Array[Vector2i]):
		if walkable(at(g, p.x, p.y)):
			spawn_tematico.append(p)
	var spawn_pool: Array[Vector2i]
	if not spawn_tematico.is_empty():
		spawn_pool = spawn_tematico
	elif requiere_aire and not suelo_seco.is_empty():
		spawn_pool = suelo_seco
	elif not acceso_tematico.is_empty():
		spawn_pool = acceso_tematico
	elif not junto_acceso.is_empty():
		spawn_pool = junto_acceso
	else:
		spawn_pool = floors
	var spawn: Vector2i = rng.elegir(spawn_pool)
	var dist := bfs_dist(g, spawn.x, spawn.y)
	var reach: Array[Vector2i] = []
	for p in floors:
		if dist[p.y * g.w + p.x] > 0:
			reach.append(p)
	# far solo se usa para conocer la distancia máxima (far[0] del JS).
	var max_dist := 0
	for p in reach:
		max_dist = maxi(max_dist, dist[p.y * g.w + p.x])

	# salidas (v20): REPARTIDAS por el nivel.
	var exits: Array[Dictionary] = []
	var caminatas: Array[Dictionary] = [] # salidas SIN casilla
	var usable: Array[Dictionary] = []
	var manila_salida: Variant = null # salida SIN casilla (permanencia en map.manila)
	for source: Dictionary in level_def.get("salidas", []):
		if source.get("tipo") == "void":
			continue
		# Cada aparición tiene estado propio.
		var s: Dictionary = source.duplicate()
		var mec := mecanica_de(source)
		s["_mec"] = mec if not mec.is_empty() else null
		s["_abierta"] = false
		if source.has("prob") and not rng.azar(float(source["prob"])):
			continue
		if mec == "caminata":
			caminatas.append(s)
			continue
		if mec == "manila":
			manila_salida = s
			continue
		usable.append(s)

	# Sala Manila (Level 0): aparece con probabilidad baja y lejos del spawn.
	var manila: Variant = null
	var rects: Array[Rect2i] = g.meta.get("_rects", [] as Array[Rect2i])
	if manila_salida != null and not rects.is_empty() and rng.azar(0.2):
		var candidatas: Array[Rect2i] = []
		for r in rects:
			var dx := (r.position.x + r.size.x / 2.0) - spawn.x
			var dy := (r.position.y + r.size.y / 2.0) - spawn.y
			if sqrt(dx * dx + dy * dy) > 12.0:
				candidatas.append(r)
		if not candidatas.is_empty():
			manila = rng.elegir(candidatas)
	# pool ANCHO: toda casilla a más del 45% de la distancia máxima al spawn
	var far_pool: Array[Vector2i] = []
	var umbral := maxf(12.0, max_dist * 0.45)
	for p in reach:
		if dist[p.y * g.w + p.x] >= umbral:
			far_pool.append(p)
	var con_pared: Array[Vector2i] = []
	var sin_pared: Array[Vector2i] = []
	for p in far_pool:
		if at(g, p.x, p.y - 1) == PARED:
			con_pared.append(p)
		else:
			sin_pared.append(p)
	var puestas: Array[Vector2i] = []
	var elegir_lejana := func(pool: Array[Vector2i]) -> Variant:
		var best: Variant = null
		var best_score := -1
		for p in pool:
			var pegada := false
			for q in puestas:
				if absi(q.x - p.x) + absi(q.y - p.y) < 3:
					pegada = true
					break
			if pegada:
				continue
			var score := dist[p.y * g.w + p.x] # lejos del spawn…
			for q in puestas: # …y lejos de las otras salidas
				score = mini(score, absi(p.x - q.x) + absi(p.y - q.y))
			if score > best_score:
				best_score = score
				best = p
		return best
	for s in usable:
		# puertas/grietas EXIGEN pared al norte; trampillas/escaleras van libres
		var de_suelo: bool = s.get("_mec") != "romper" and _re_suelo.search(str(s.get("texto", ""))) != null
		var pool: Array[Vector2i]
		if de_suelo:
			pool = sin_pared if not sin_pared.is_empty() else con_pared
		else:
			pool = con_pared if not con_pared.is_empty() else sin_pared
		var p: Variant = elegir_lejana.call(pool)
		if p != null:
			puestas.append(p)
			exits.append({"x": (p as Vector2i).x, "y": (p as Vector2i).y, "def": s})
	var ocupadas := {}
	for e in exits:
		ocupadas[int(e.y) * g.w + int(e.x)] = true
	var libre := func(p: Vector2i) -> bool:
		return not ocupadas.has(p.y * g.w + p.x)
	var reservar := func(p: Vector2i) -> Vector2i:
		ocupadas[p.y * g.w + p.x] = true
		return p
	var elegir_libre := func(pool: Array[Vector2i]) -> Variant:
		var libres: Array[Vector2i] = []
		for p in pool:
			if libre.call(p):
				libres.append(p)
		return rng.elegir(libres) if not libres.is_empty() else null

	# Los muebles estructurales ya forman parte de la planta: reserva sus celdas.
	var props_estructurales: Array = g.meta.get("_propsEstructurales", [])
	for p: Dictionary in props_estructurales:
		reservar.call(Vector2i(int(p.x), int(p.y)))

	# objetos
	var items: Array[Dictionary] = []
	for o: Dictionary in level_def.get("objetos", []):
		var rango: Array = o.get("n")
		var n := rng.entero(int(rango[0]), int(rango[1]))
		for i in n:
			var p: Variant = elegir_libre.call(reach)
			if p == null:
				continue
			reservar.call(p)
			items.append({"x": (p as Vector2i).x, "y": (p as Vector2i).y, "id": o.get("id")})

	# props decorativos y contenedores registrables por bioma
	var props: Array[Dictionary] = []
	for structural: Dictionary in props_estructurales:
		var copia := structural.duplicate()
		copia["contenedor"] = false
		props.append(copia)
	var con_pared_norte: Array[Vector2i] = []
	for p in reach:
		if at(g, p.x, p.y - 1) == PARED:
			con_pared_norte.append(p)
	var sitio_para := func(id: String) -> Variant:
		var pool: Array[Vector2i] = con_pared_norte \
			if PROPS_PARED.has(id) and not con_pared_norte.is_empty() else reach
		return elegir_libre.call(pool)
	var decorativos: Array = PROPS_BIOMA.get(bioma, [])
	if bioma == "biblioteca":
		var n_libros := rng.entero(18, 30)
		for i in n_libros:
			var p: Variant = elegir_libre.call(reach)
			if p == null:
				continue
			reservar.call(p)
			set_tile(g, (p as Vector2i).x, (p as Vector2i).y, LIBROS)
			props.append({"x": (p as Vector2i).x, "y": (p as Vector2i).y,
				"id": "libros_caidos", "contenedor": false})
		var muebles: Array[String] = []
		for i in rng.entero(2, 4):
			muebles.append("ordenador")
		for i in rng.entero(6, 10):
			muebles.append("silla")
		for id in muebles:
			var p: Variant = sitio_para.call(id)
			if p == null:
				continue
			reservar.call(p)
			props.append({"x": (p as Vector2i).x, "y": (p as Vector2i).y,
				"id": id, "contenedor": false})
	if level_def.get("id") == "level-0-01":
		for i in rng.entero(7, 12):
			var p: Variant = sitio_para.call("salida_falsa")
			if p == null:
				continue
			reservar.call(p)
			props.append({"x": (p as Vector2i).x, "y": (p as Vector2i).y,
				"id": "salida_falsa", "contenedor": false})
		for i in rng.entero(10, 18):
			var p: Variant = elegir_libre.call(reach)
			if p == null:
				continue
			reservar.call(p)
			props.append({"x": (p as Vector2i).x, "y": (p as Vector2i).y,
				"id": "botella_vacia" if rng.azar(0.5) else "zapato_roto", "contenedor": false})
	if urbano:
		var elegidos := rng.barajar(accesos_urbanos).slice(0, 18)
		for p: Vector2i in elegidos:
			if not libre.call(p):
				continue
			reservar.call(p)
			props.append({"x": p.x, "y": p.y, "id": "portico", "contenedor": false})
	if not decorativos.is_empty():
		var n := rng.entero(7, 13)
		for i in n:
			var id: String = rng.elegir(decorativos)
			# los decorativos de pared exigen un muro al norte
			var pool: Variant = con_pared_norte \
				if DECORATIVOS_PARED.has(id) and not con_pared_norte.is_empty() else null
			var p: Variant = elegir_libre.call(pool) if pool != null else sitio_para.call(id)
			if p == null:
				continue
			reservar.call(p)
			# las cajas de madera SIEMPRE se pueden registrar (v17)
			var es_cont := id == "caja"
			var entrada := {"x": (p as Vector2i).x, "y": (p as Vector2i).y,
				"id": id, "contenedor": es_cont}
			if DECORATIVOS_PARED.has(id):
				entrada["pared"] = true
			if es_cont:
				entrada["registrado"] = false
			props.append(entrada)
	var n_cont := rng.entero(0, 1) if bioma == "biblioteca" else rng.entero(3, 5)
	for i in n_cont:
		var id: String = CONT_BIOMA.get(bioma, "cofre")
		var p: Variant = sitio_para.call(id)
		if p == null:
			continue
		reservar.call(p)
		props.append({"x": (p as Vector2i).x, "y": (p as Vector2i).y,
			"id": id, "contenedor": true, "registrado": false})
	# el reloj es exclusivo de Level 80 — SIEMPRE colgado de una pared
	if level_def.get("id") == "level-80":
		for i in 6:
			var p: Variant = sitio_para.call("reloj")
			if p == null:
				continue
			reservar.call(p)
			props.append({"x": (p as Vector2i).x, "y": (p as Vector2i).y,
				"id": "reloj", "contenedor": false})

	# Respiraderos visibles dentro del agua.
	var air_pockets: Array[Dictionary] = []
	if requiere_aire:
		var agua_alcanzable: Array[Vector2i] = []
		for p in reach:
			if at(g, p.x, p.y) == AGUA and libre.call(p):
				agua_alcanzable.append(p)
		var candidatos := rng.barajar(agua_alcanzable)
		@warning_ignore("integer_division")
		var cantidad := maxi(6, mini(24, agua_alcanzable.size() / 350))
		for p: Vector2i in candidatos:
			if air_pockets.size() >= cantidad:
				break
			var cerca := false
			for q in air_pockets:
				if absi(int(q.x) - p.x) + absi(int(q.y) - p.y) < 10:
					cerca = true
					break
			if cerca:
				continue
			reservar.call(p)
			air_pockets.append({"x": p.x, "y": p.y})
			props.append({"x": p.x, "y": p.y, "id": "burbuja_aire", "contenedor": false})

	# spawns de entidades (fieles a la ficha del nivel), lejos del jugador
	var entity_spawns: Array[Dictionary] = []
	var mid_pool: Array[Vector2i] = []
	for p in reach:
		if dist[p.y * g.w + p.x] >= 8:
			mid_pool.append(p)
	for e: Dictionary in level_def.get("entidades", []):
		if not rng.azar(float(e.get("prob", 1))):
			continue
		var rango: Array = e.get("n")
		var n := rng.entero(int(rango[0]), int(rango[1]))
		for i in n:
			var p: Vector2i = rng.elegir(mid_pool if not mid_pool.is_empty() else reach)
			entity_spawns.append({"x": p.x, "y": p.y, "id": e.get("id")})

	return {
		"w": w, "h": h, "grid": g, "spawn": spawn, "exits": exits, "items": items,
		"entitySpawns": entity_spawns, "props": props, "airPockets": air_pockets,
		"dist": dist, "caminatas": caminatas, "manila": manila, "manilaSalida": manila_salida,
	}
