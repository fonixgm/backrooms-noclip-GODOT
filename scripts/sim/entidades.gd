## IA de entidades del mundo. Port de game/js/sim/entidades.js (v22-v25):
## la taxonomía de comportamientos de las fichas (cazador, errante, imita,
## emboscada, acecho_oscuridad, atraida_luz, estatica_trampa…) en tiempo real,
## persiguiendo al jugador más cercano. El CEREBRO decide waypoints a 260 ms;
## el CUERPO avanza en continuo con Fisica.mover en cada tick de mundo.
class_name Entidades

const PERIODO_CEREBRO := 260 # ms entre decisiones
const TELEGRAPH_MS := 600    # aviso ⚠ antes del golpe
const RASTRO_MS := 4200      # ms sin detectar antes de abandonar la caza
const OLFATO := 1.7          # multiplica el radio de detección (cap 16)
const RADIO_ENT := 0.3       # cuerpo físico de las entidades

## velocidad continua (tiles/s): el jugador va a 4.6
static func vel_de(e: Dictionary) -> float:
	if e.def.get("comportamiento") == "cazador":
		return 5.0 # implacable
	return 4.8 if float(e.def.get("velocidad", 1)) >= 2.0 else 3.4

static func crear(map: Dictionary, defs: Dictionary, rng: Rng) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spawns: Array = map.get("entitySpawns", [])
	for i in spawns.size():
		var s: Dictionary = spawns[i]
		var def: Dictionary = defs[s.id]
		var comp: Variant = def.get("comportamiento")
		out.append({
			"uid": i, "id": s.id, "def": def,
			"x": float(s.x), "y": float(s.y),
			"estado": "latente",
			"revelada": comp != "imita" and comp != "emboscada",
			"dormidaHasta": (22 + rng.entero(0, 8)) * 400 if comp == "cazador" else 0,
			"viva": true,
			"vida": float(def.get("vida", 40)),
			"paralizadaHasta": 0,
			"huyendoHasta": 0,
			"preparando": false, "prepHasta": 0, "prepObjetivo": -1,
			"yaAviso": false,
			"sinVerteDesde": 0,
			"proximoPaso": 0,
			"pasoExtra": 0,
			"wp": null, # tile-waypoint [x, y] hacia el que avanza el cuerpo
		})
	return out

static func _transitable(sala, x: int, y: int) -> bool:
	var g: MapGen.Grid = sala.map.grid
	if x < 0 or y < 0 or x >= g.w or y >= g.h:
		return false
	return MapGen.walkable(g.t[y * g.w + x])

## ¿el TILE destino está reclamado? (waypoint/cuerpo de otra entidad o jugador)
static func _ocupada(sala, x: int, y: int, yo: Dictionary) -> bool:
	for e: Dictionary in sala.entidades:
		if e == yo or not e.viva:
			continue
		if Fisica.tile_de(e.x) == x and Fisica.tile_de(e.y) == y:
			return true
		if e.wp != null and e.wp[0] == x and e.wp[1] == y:
			return true
	for j: Dictionary in sala.jugadores.values():
		if j.escondido == null and Fisica.tile_de(j.x) == x and Fisica.tile_de(j.y) == y:
			return true
	return false

## BFS multi-fuente desde todos los jugadores visibles.
static func _dmap_jugadores(sala) -> PackedInt32Array:
	var g: MapGen.Grid = sala.map.grid
	var d := PackedInt32Array()
	d.resize(g.w * g.h)
	d.fill(-1)
	var cola: Array[int] = []
	for j: Dictionary in sala.jugadores.values():
		if j.escondido != null or j.muerto:
			continue
		var i := Fisica.tile_de(j.y) * g.w + Fisica.tile_de(j.x)
		if i >= 0 and i < d.size() and d[i] != 0:
			d[i] = 0
			cola.append(i)
	var q := 0
	while q < cola.size():
		var i := cola[q]
		q += 1
		var x := i % g.w
		@warning_ignore("integer_division")
		var y := i / g.w
		var v := d[i] + 1
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + dir.x
			var ny := y + dir.y
			if nx < 0 or ny < 0 or nx >= g.w or ny >= g.h:
				continue
			var ni := ny * g.w + nx
			if d[ni] != -1 or not MapGen.walkable(g.t[ni]):
				continue
			d[ni] = v
			cola.append(ni)
	return d

static func _tile_ent(e: Dictionary) -> Vector2i:
	return Vector2i(Fisica.tile_de(e.x), Fisica.tile_de(e.y))

static func _paso_hacia_jugadores(sala, e: Dictionary) -> bool:
	var g: MapGen.Grid = sala.map.grid
	var dm: PackedInt32Array = sala._dmap
	var t := _tile_ent(e)
	var mejor: Variant = null
	var mejor_v: float = dm[t.y * g.w + t.x]
	if mejor_v < 0:
		mejor_v = INF
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n := t + dir
		if not _transitable(sala, n.x, n.y) or _ocupada(sala, n.x, n.y, e):
			continue
		var v := dm[n.y * g.w + n.x]
		if v >= 0 and v < mejor_v:
			mejor_v = v
			mejor = n
	if mejor != null:
		e.wp = [(mejor as Vector2i).x, (mejor as Vector2i).y]
		return true
	return false

static func _paso_aleatorio(sala, e: Dictionary) -> void:
	var t := _tile_ent(e)
	var dirs: Array = sala.rng.barajar([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
	for dir: Vector2i in dirs:
		var n := t + dir
		if _transitable(sala, n.x, n.y) and not _ocupada(sala, n.x, n.y, e):
			e.wp = [n.x, n.y]
			return

static func _paso_hacia(sala, e: Dictionary, tx: float, ty: float) -> void:
	var t := _tile_ent(e)
	var dx := int(signf(tx - t.x))
	var dy := int(signf(ty - t.y))
	var opciones: Array
	if absf(tx - t.x) > absf(ty - t.y):
		opciones = [Vector2i(dx, 0), Vector2i(0, dy)]
	else:
		opciones = [Vector2i(0, dy), Vector2i(dx, 0)]
	for m: Vector2i in opciones:
		if m.x == 0 and m.y == 0:
			continue
		var n := t + m
		if _transitable(sala, n.x, n.y) and not _ocupada(sala, n.x, n.y, e):
			e.wp = [n.x, n.y]
			return

static func _adyacente(e: Dictionary, j: Dictionary) -> bool:
	return Fisica.dist(e.x, e.y, j.x, j.y) <= 0.95

static func _jugador_adyacente(sala, e: Dictionary) -> Variant:
	for j: Dictionary in sala.jugadores.values():
		if j.escondido == null and not j.muerto and _adyacente(e, j):
			return j
	return null

static func en_penumbra(sala, j: Dictionary) -> bool:
	return float(sala.def.get("oscuridad", 0)) >= 0.5 and not j.luz

## ¿A quién detecta esta entidad? El candidato más cercano que pase el filtro
## de su ficha (vista/oscuridad/luz/adyacente/sigilo/global).
static func detecta(sala, e: Dictionary) -> Variant:
	var d: Dictionary = e.def.get("deteccion", {})
	var objetivo: Variant = null
	var mejor_dist := INF
	for j: Dictionary in sala.jugadores.values():
		if j.escondido != null or j.muerto:
			continue
		var r_mod := -1 if j.equipo.get("pies") == "botas_reforzadas" else 0
		var radio := maxi(1, mini(16, roundi(float(d.get("radio", 6)) * OLFATO)) + r_mod)
		var dd := Fisica.dist(e.x, e.y, j.x, j.y)
		if dd >= mejor_dist:
			continue
		var ve := false
		match d.get("tipo"):
			"vista":
				ve = dd <= radio and _ver(sala, e, j)
			"oscuridad":
				ve = dd <= radio and _ver(sala, e, j) and en_penumbra(sala, j)
			"luz":
				ve = j.luz and dd <= radio
			"adyacente", "contacto":
				ve = dd <= maxf(1, float(d.get("radio", 1)) + r_mod)
			"sigilo":
				ve = dd <= radio and _ver(sala, e, j)
			"global":
				ve = true
			_:
				ve = dd <= maxi(1, 6 + r_mod) and _ver(sala, e, j)
		if ve:
			objetivo = j
			mejor_dist = dd
	return objetivo

## El LOS de Bresenham exige tiles enteros.
static func _ver(sala, e: Dictionary, j: Dictionary) -> bool:
	return Fov.los(sala.map.grid,
		Fisica.tile_de(e.x), Fisica.tile_de(e.y), Fisica.tile_de(j.x), Fisica.tile_de(j.y))

static func _atacar(sala, e: Dictionary, jug: Dictionary, ahora: int) -> void:
	if e.preparando:
		return
	e.preparando = true
	e.yaAviso = true
	e.prepHasta = ahora + TELEGRAPH_MS
	e.prepObjetivo = jug.id
	sala.difundir({"t": "entPrep", "uid": e.uid})

static func _golpe(sala, e: Dictionary, jug: Dictionary, ahora: int) -> void:
	e.preparando = false
	e.prepObjetivo = -1
	if jug.muerto:
		return
	if ahora < int(jug.get("invulnerableHasta", 0)):
		sala.difundir({"t": "entFalla", "uid": e.uid})
		return
	var dano := float(e.def.get("dano", 10))
	jug.salud = maxf(0, jug.salud - dano)
	sala.difundir({"t": "entAtaca", "uid": e.uid, "id": jug.id, "dano": dano})
	sala.enviar(jug.ws, {"t": "salud", "valor": jug.salud})
	if jug.salud <= 0:
		sala.morir(jug, e.def.get("nombre", e.id))

## Pasado el aviso, golpea si sigue teniendo a alguien al lado.
static func _resolver_telegraph(sala, e: Dictionary, ahora: int) -> void:
	if not e.preparando or ahora < int(e.prepHasta):
		return
	var obj: Variant = sala.jugadores.get(e.prepObjetivo)
	if obj != null and (obj as Dictionary).escondido == null and not (obj as Dictionary).muerto \
			and _adyacente(e, obj):
		_golpe(sala, e, obj, ahora)
		return
	var otro: Variant = _jugador_adyacente(sala, e)
	if otro != null:
		_golpe(sala, e, otro, ahora)
		return
	e.preparando = false
	e.prepObjetivo = -1
	sala.difundir({"t": "entFalla", "uid": e.uid})

static func _paso_entidad(sala, e: Dictionary, ahora: int) -> void:
	var comp: Variant = e.def.get("comportamiento")

	if ahora < int(e.paralizadaHasta):
		return

	# huyendo del fuego griego: se aleja de los jugadores (dmap creciente)
	if int(e.huyendoHasta) > 0 and ahora < int(e.huyendoHasta):
		e.preparando = false
		var g: MapGen.Grid = sala.map.grid
		var dm: PackedInt32Array = sala._dmap
		var t := _tile_ent(e)
		var mejor: Variant = null
		var mejor_v := dm[t.y * g.w + t.x]
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := t + dir
			if not _transitable(sala, n.x, n.y) or _ocupada(sala, n.x, n.y, e):
				continue
			var v := dm[n.y * g.w + n.x]
			if v > mejor_v:
				mejor_v = v
				mejor = n
		if mejor != null:
			e.wp = [(mejor as Vector2i).x, (mejor as Vector2i).y]
		return

	if comp == "cazador" and int(e.dormidaHasta) > 0:
		e.dormidaHasta = int(e.dormidaHasta) - PERIODO_CEREBRO
		if int(e.dormidaHasta) <= 0:
			sala.difundir({"t": "aviso2", "txt": "EL CAZADOR HA DESPERTADO."})
		return

	# trampas y emboscadas: inmóviles, golpean a quien se arrima
	if comp == "estatica_trampa" or comp == "emboscada":
		var j: Variant = _jugador_adyacente(sala, e)
		if j != null and detecta(sala, e) != null:
			_atacar(sala, e, j, ahora)
		return

	# imitador: quieto hasta que alguien se acerca; entonces se revela
	if comp == "imita" and not e.revelada:
		if detecta(sala, e) != null:
			e.revelada = true
			e.estado = "caza"
			sala.difundir({"t": "entRevela", "uid": e.uid})
		return

	var objetivo: Variant = detecta(sala, e)
	if objetivo != null:
		e.estado = "caza"
		e.sinVerteDesde = 0
	elif e.estado == "caza":
		if int(e.sinVerteDesde) == 0:
			e.sinVerteDesde = ahora
		elif ahora - int(e.sinVerteDesde) > RASTRO_MS:
			e.estado = "alerta"
			e.sinVerteDesde = 0

	# smilers y acechadores no cazan a quien va con luz en zona iluminada
	if comp == "acecho_oscuridad" and e.estado == "caza" and objetivo != null \
			and not en_penumbra(sala, objetivo):
		e.estado = "alerta"

	# ruido reciente: lo que no caza va a investigar
	var rd: Variant = sala.ruido
	if rd != null and ahora < int((rd as Dictionary).hasta) and e.estado != "caza" \
			and absf(e.x - float((rd as Dictionary).x)) + absf(e.y - float((rd as Dictionary).y)) <= float((rd as Dictionary).radio):
		var jr: Variant = _jugador_adyacente(sala, e)
		if jr != null:
			_atacar(sala, e, jr, ahora)
			return
		e.estado = "alerta"
		_paso_hacia(sala, e, float((rd as Dictionary).x), float((rd as Dictionary).y))
		return

	var ja: Variant = _jugador_adyacente(sala, e)
	if ja != null and (e.estado == "caza" or comp == "cazador"):
		_atacar(sala, e, ja, ahora)
		return

	if e.estado == "caza" or comp == "cazador":
		_paso_hacia_jugadores(sala, e)
		# el cazador mete un paso extra cada 3: es implacable
		e.pasoExtra = int(e.pasoExtra) + 1
		if comp == "cazador" and int(e.pasoExtra) % 3 == 0:
			var j2: Variant = _jugador_adyacente(sala, e)
			if j2 == null:
				_paso_hacia_jugadores(sala, e)
		var j3: Variant = _jugador_adyacente(sala, e)
		if j3 != null:
			_atacar(sala, e, j3, ahora)
	elif comp == "errante" or e.estado == "alerta":
		_paso_aleatorio(sala, e)
		# los errantes hostiles muerden si los rozas mucho rato
		var j4: Variant = _jugador_adyacente(sala, e)
		if comp == "errante" and j4 != null and sala.rng.azar(0.12):
			_atacar(sala, e, j4, ahora)
	elif comp == "atraida_luz":
		if sala.rng.azar(0.5):
			_paso_aleatorio(sala, e)

static func tick(sala, ahora: int, dt: float) -> void:
	if sala.entidades.is_empty() or sala.jugadores.is_empty():
		return
	sala._dmap = _dmap_jugadores(sala)
	for e: Dictionary in sala.entidades:
		if not e.viva:
			continue
		_resolver_telegraph(sala, e, ahora)
		# CEREBRO: decide waypoint/ataque a su cadencia
		if ahora >= int(e.proximoPaso):
			e.proximoPaso = ahora + PERIODO_CEREBRO
			_paso_entidad(sala, e, ahora)
		# CUERPO: avanza en continuo hacia su waypoint en cada tick
		if e.wp != null and not e.preparando and ahora >= int(e.paralizadaHasta):
			var tx := float(e.wp[0])
			var ty := float(e.wp[1])
			var dx: float = tx - e.x
			var dy: float = ty - e.y
			var d := sqrt(dx * dx + dy * dy)
			if d < 0.08:
				e.x = tx
				e.y = ty
				e.wp = null
			else:
				var nueva := Fisica.mover(sala.map.grid, e.x, e.y, dx, dy,
					dt if dt > 0.0 else 0.1, vel_de(e), RADIO_ENT)
				if Fisica.dist(nueva[0], nueva[1], e.x, e.y) < 0.001:
					e.wp = null # atascada: que decida otra cosa
				e.x = nueva[0]
				e.y = nueva[1]
			sala._entMovidas.append(e)
	if sala.ruido != null and ahora > int(sala.ruido.hasta):
		sala.ruido = null
