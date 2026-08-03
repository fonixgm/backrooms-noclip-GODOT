## Las REGLAS DEL MUNDO. Port de game/js/sim/sala.js (motor dual que usa el
## juego online): una Sala = una instancia viva de un nivel. Entidades
## simuladas, salidas con mecánica (romper con canal + dado), escondites,
## supervivencia, Sala Manila, riesgoVoid, muerte/respawn y cruce con puerta
## de retorno. Se omite la infraestructura MMO (chat, moderación, espectador,
## base de datos): esto es el port single-player.
##
## Mensajería: cada jugador lleva un Callable `ws` que recibe los Dictionary
## que el original mandaba por WebSocket — la capa de juego de Godot los
## consume igual que hacía cliente.js. El reloj lo da Salas.msec() (inyectable
## en tests, como hacía test-manila.js con Date.now).
class_name Sala
extends RefCounted

const CAP_SALA := 60
const PROTECCION_ENTRADA_MS := 3000
const ESCONDITES := ["taquilla", "nevera", "archivador"]

var nivelId: String
var inst: int
var clave: String
var semilla: String
var def: Dictionary
var map: Dictionary
var jugadores: Dictionary = {} # id -> jug (Dictionary)
var rng: Rng                   # dados y azar de la sala
var entidades: Array[Dictionary] = []
var ruido: Variant = null
var alCruzar: Callable = Callable() # lo inyecta el anfitrión (cambio de sala)
var alMorir: Callable = Callable()  # ídem (respawn en Level 0)

var _movidosExtra: Array = []
var _entMovidas: Array = []
var _dmap: PackedInt32Array
var _ultTick: int = 0
var _remodelEn: int = 0

## vector cardinal más cercano a un ángulo θ (0=N, π/2=E, π=S, 3π/2=O)
static func cardinal_de(th: float) -> Vector2i:
	var k := ((roundi(th / (PI / 2.0)) % 4) + 4) % 4
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][k]

static func r2(v: float) -> float:
	return roundf(v * 100.0) / 100.0

func _init(nivel_id: String, instancia: int, semilla_base: String) -> void:
	nivelId = nivel_id
	inst = instancia
	clave = "%s::%d" % [nivel_id, instancia]
	semilla = "%s::%s::%d" % [semilla_base, nivel_id, instancia]
	var gen := Salas.generar_mapa(nivel_id, semilla)
	def = gen.def
	map = gen.map
	rng = Rng.crear(semilla + "::sim")
	entidades = Entidades.crear(map, Catalogo.entidades, Rng.crear(semilla + "::ents"))

var llena: bool:
	get:
		return jugadores.size() >= CAP_SALA

func ocupada(x: int, y: int) -> bool:
	for j: Dictionary in jugadores.values():
		if Fisica.tile_de(j.x) == x and Fisica.tile_de(j.y) == y:
			return true
	return false

## Busca hueco transitable y libre en anillos crecientes.
func buscar_spawn(cx: int = -2147483648, cy: int = 0) -> Vector2i:
	var s: Vector2i = map.spawn if cx == -2147483648 else Vector2i(cx, cy)
	for r in 20:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x := s.x + dx
				var y := s.y + dy
				if Salas.es_transitable(map, x, y) and not ocupada(x, y):
					return Vector2i(x, y)
	return s

## Casilla libre junto a una puerta, sin colocar al jugador encima.
func buscar_spawn_junto(cx: int, cy: int) -> Vector2i:
	for r in range(1, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x := cx + dx
				var y := cy + dy
				if Salas.es_transitable(map, x, y) and not ocupada(x, y) and not _hay_salida_en(x, y):
					return Vector2i(x, y)
	return buscar_spawn(cx, cy)

func _hay_salida_en(x: int, y: int) -> bool:
	for e: Dictionary in map.exits:
		if int(e.x) == x and int(e.y) == y:
			return true
	return false

## Localiza el acceso personal de vuelta cerca del spawn.
func buscar_lugar_retorno(necesita_pared: bool) -> Variant:
	var s: Vector2i = map.spawn
	var g: MapGen.Grid = map.grid
	var dist := MapGen.bfs_dist(g, s.x, s.y)
	var mejor: Variant = null
	var mejor_d := 2147483647
	for y in range(1, g.h):
		for x in g.w:
			var d := dist[y * g.w + x]
			if d < 0 or d > mejor_d or not Salas.es_transitable(map, x, y) or _casilla_ocupada(x, y):
				continue
			if necesita_pared and MapGen.at(g, x, y - 1) != MapGen.PARED:
				continue
			if d < mejor_d:
				mejor = Vector2i(x, y)
				mejor_d = d
	return mejor

func _casilla_ocupada(x: int, y: int) -> bool:
	if _hay_salida_en(x, y):
		return true
	for p: Dictionary in map.get("props", []):
		if int(p.x) == x and int(p.y) == y:
			return true
	for it: Dictionary in map.get("items", []):
		if not it.get("taken", false) and int(it.x) == x and int(it.y) == y:
			return true
	return ocupada(x, y)

func censo() -> Array:
	var out := []
	for j: Dictionary in jugadores.values():
		out.append({"id": j.id, "nombre": j.nombre, "x": j.x, "y": j.y, "rot": j.rot,
			"escondido": j.escondido != null})
	return out

## Estado que el cliente no puede derivar de la semilla.
func estado_dinamico() -> Dictionary:
	var ents := []
	for e: Dictionary in entidades:
		ents.append({"uid": e.uid, "id": e.id, "x": e.x, "y": e.y,
			"viva": e.viva, "revelada": e.revelada})
	var abiertas := []
	for i in (map.exits as Array).size():
		if (map.exits[i] as Dictionary).def.get("_abierta", false):
			abiertas.append(i)
	return {"ents": ents, "abiertas": abiertas}

func entrar(ws: Callable, nombre: String, token: String) -> Dictionary:
	var id := Salas.siguiente_id()
	var p := buscar_spawn()
	var jug := {
		"id": id, "ws": ws, "nombre": nombre, "token": token,
		"x": float(p.x), "y": float(p.y), "rot": PI, # θ continuo (π = mirando al sur)
		"distSala": 0.0,
		"salud": 100.0, "sed": 100.0, "cordura": 100.0, "oxigeno": 100.0,
		"luz": false, "escondido": null, "muerto": false,
		"inv": [], "manos": [null, null],
		"equipo": {"cara": null, "cuerpo": null, "pies": null},
		"canal": null, "ofertaEn": null, "manila": null, "manilaIntento": 0,
		"retorno": null,
		"visitados": {nivelId: true},
		"nivelesProtegidos": {},
		"invulnerableHasta": 0,
		"sec": 0,
		"_posT": Salas.msec(),
		"_oxigenoEn": Salas.msec() + 1000,
		"_margen": 0.8,
		"pasosSala": 0, "caminataDef": null, "caminataObjetivo": 0,
		"_respawnEn": 0, "_ultLoot": 0, "ultGolpe": 0, "dadosN": 0,
	}
	proteger_primera_visita(jug)
	preparar_caminata(jug)
	var msg := {
		"t": "bienvenida", "id": id, "nivel": nivelId, "inst": inst,
		"semilla": semilla, "x": float(p.x), "y": float(p.y), "rot": jug.rot, "sec": 0,
		"salud": jug.salud, "sed": jug.sed, "cordura": jug.cordura, "oxigeno": jug.oxigeno,
		"inv": jug.inv, "manos": jug.manos, "equipo": jug.equipo,
		"caminata": {"pasos": 0, "objetivo": jug.caminataObjetivo} if jug.caminataObjetivo else null,
		"jugadores": censo(),
	}
	msg.merge(estado_dinamico())
	enviar(ws, msg)
	difundir({"t": "entra", "id": id, "nombre": nombre, "x": jug.x, "y": jug.y, "rot": jug.rot})
	jugadores[id] = jug
	return jug

func proteger_primera_visita(jug: Dictionary, ahora: int = -1) -> bool:
	if ahora < 0:
		ahora = Salas.msec()
	if jug.nivelesProtegidos.has(nivelId):
		return false
	jug.nivelesProtegidos[nivelId] = true
	jug.invulnerableHasta = ahora + PROTECCION_ENTRADA_MS
	return true

## La caminata es PERSONAL: tus pasos reales te van desintonizando hasta que
## haces no-clip al destino. El objetivo sale de tu token.
func preparar_caminata(jug: Dictionary) -> void:
	jug.pasosSala = 0
	jug.distSala = 0.0
	var vuelta: Variant = null
	if jug.retorno != null and (jug.retorno as Dictionary).get("_mec") == "caminata" \
			and Salas.destino_disponible(jug.retorno):
		vuelta = jug.retorno
	var cam: Variant = vuelta
	if cam == null:
		for c: Dictionary in map.get("caminatas", []):
			if Salas.destino_disponible(c):
				cam = c
				break
	jug.caminataDef = cam
	jug.caminataObjetivo = MapGen.walking_goal(def, "%s::%s" % [jug.token, clave], 1, 0) \
		if cam != null else 0

func resolver_destino(jug: Dictionary, d: Variant) -> Variant:
	if d == null or not (d as Dictionary).has("destino"):
		return null
	var dd: Dictionary = d
	var destino_raw := str(dd.destino)
	if Catalogo.niveles.has(destino_raw):
		return dd
	var candidatos: Array = []
	if destino_raw == "*visitada":
		for id: String in jug.visitados:
			if Catalogo.niveles.has(id) and id != nivelId:
				candidatos.append(id)
		candidatos.sort()
	elif destino_raw == "*aleatoria":
		for id: String in Catalogo.niveles:
			if id != nivelId:
				candidatos.append(id)
		candidatos.sort()
	elif destino_raw.begins_with("*opciones:"):
		for id in destino_raw.trim_prefix("*opciones:").split(","):
			if Catalogo.niveles.has(id):
				candidatos.append(id)
	if candidatos.is_empty():
		return null
	var destino: Variant = RouteSeed.elegir(DailySeed.semilla(), nivelId, dd, candidatos)
	var copia := dd.duplicate()
	copia.destino = destino
	copia["_destinoResuelto"] = destino
	return copia

func enviar_inv(jug: Dictionary) -> void:
	enviar(jug.ws, {"t": "inv", "inv": jug.inv, "manos": jug.manos, "equipo": jug.equipo})

func enviar_estado(jug: Dictionary) -> void:
	enviar(jug.ws, {"t": "estado", "salud": jug.salud, "sed": jug.sed,
		"cordura": jug.cordura, "oxigeno": jug.oxigeno})

func herir(jug: Dictionary, cantidad: float, causa: String) -> void:
	jug.salud = maxf(0, jug.salud - cantidad)
	enviar_estado(jug)
	if jug.salud <= 0:
		morir(jug, causa)

func supervivencia(jug: Dictionary, distancia: float) -> void:
	if distancia <= 0 or jug.muerto:
		return
	jug["_supervivencia"] = float(jug.get("_supervivencia", 0)) + distancia
	var pasos := floori(float(jug["_supervivencia"]) / 4.0)
	if pasos == 0:
		return
	jug["_supervivencia"] = float(jug["_supervivencia"]) - pasos * 4
	var reglas: Array = def.get("reglas", [])
	var posesion := {}
	for oid in jug.inv + jug.manos + (jug.equipo as Dictionary).values():
		if oid != null:
			posesion[oid] = true
	var traje_hostil: bool = posesion.has("avmh")
	var proteccion_quimica: bool = traje_hostil or posesion.has("repelente_corrosion")
	var mascara: bool = jug.equipo.get("cara") == "mascara_gas" or traje_hostil or proteccion_quimica
	var chaqueta: bool = jug.equipo.get("cuerpo") == "chaqueta" or traje_hostil
	var botas: bool = jug.equipo.get("pies") == "botas_reforzadas"
	# sed y cordura drenan por TILES reales con la cadencia del modo original
	var tiles := pasos * 4
	jug["_sedAcum"] = float(jug.get("_sedAcum", 0)) + tiles
	var cad_sed := 4 if reglas.has("calor") else 9
	if float(jug["_sedAcum"]) >= cad_sed:
		var n := floori(float(jug["_sedAcum"]) / cad_sed)
		jug["_sedAcum"] = float(jug["_sedAcum"]) - n * cad_sed
		jug.sed = maxf(0, jug.sed - n)
	var drena_cordura := false
	for r in ["zumbido", "alucinaciones", "aislamiento", "vigilado"]:
		if reglas.has(r):
			drena_cordura = true
			break
	if drena_cordura:
		jug["_corduraAcum"] = float(jug.get("_corduraAcum", 0)) + tiles
		var cad_cordura := (20 if reglas.has("zumbido") else 25) * (2 if mascara else 1)
		if float(jug["_corduraAcum"]) >= cad_cordura:
			var n := floori(float(jug["_corduraAcum"]) / cad_cordura)
			jug["_corduraAcum"] = float(jug["_corduraAcum"]) - n * cad_cordura
			jug.cordura = maxf(0, jug.cordura - n)
	if reglas.has("frio") and not chaqueta:
		herir(jug, pasos, "el frío")
	# charcos sirena: las botas anulan el arrastre sobre agua
	var tx := Fisica.tile_de(jug.x)
	var ty := Fisica.tile_de(jug.y)
	var g: MapGen.Grid = map.grid
	if not jug.muerto and reglas.has("agua_traicionera") and not botas \
			and g.t[ty * g.w + tx] == 3 and rng.azar(0.12):
		herir(jug, 3, "una corriente anómala")
	if not jug.muerto and jug.sed == 0:
		herir(jug, pasos, "la deshidratación")
	if not jug.muerto and jug.cordura == 0:
		morir(jug, "perdiste la cordura")
	if not jug.muerto:
		enviar_estado(jug)

func salir(jug: Dictionary) -> void:
	if not jugadores.erase(jug.id):
		return
	difundir({"t": "sale", "id": jug.id})

## v24: el MOVIMIENTO es del cliente; aquí se VALIDA (velocidad + paredes).
func posicion(jug: Dictionary, m: Dictionary) -> void:
	if jug.muerto or jug.escondido != null:
		return
	if int(m.get("sec", 0)) < int(jug.sec):
		return # anterior a un teleport: obsoleto
	var ahora := Salas.msec()
	var dt := minf(1.5, (ahora - int(jug["_posT"])) / 1000.0)
	jug["_posT"] = ahora
	jug["_margen"] = minf(3.2, float(jug["_margen"]) + dt * Fisica.VEL_JUGADOR * 1.12)
	var d := Fisica.dist(jug.x, jug.y, float(m.x), float(m.y))
	var exceso_vel: bool = d > 1.3 or d > float(jug["_margen"])
	if exceso_vel or not Salas.camino_legal(map.grid, jug.x, jug.y, float(m.x), float(m.y)):
		jug.sec = int(jug.sec) + 1
		enviar(jug.ws, {"t": "mueve", "id": jug.id, "x": r2(jug.x), "y": r2(jug.y), "sec": jug.sec})
		return
	jug["_margen"] = float(jug["_margen"]) - d
	jug.x = float(m.x)
	jug.y = float(m.y)
	if m.has("rot"):
		jug.rot = float(m.rot)
	_movidosExtra.append(jug)
	# canal de romper: alejarse del punto de inicio lo interrumpe
	if jug.canal != null and Fisica.dist(float(m.x), float(m.y),
			float(jug.canal.origen[0]), float(jug.canal.origen[1])) > 0.3:
		cancelar_canal(jug, "Te apartas: dejas lo que estabas haciendo.")
	# un no-clip puede cambiar de sala inmediatamente
	if proximidad(jug):
		return
	supervivencia(jug, d)
	caminata_avanza(jug, d)
	manila_avanza(jug)

## Sala Manila: permanencia REAL (minutos de reloj), ambiental.
func manila_avanza(jug: Dictionary) -> void:
	var rect: Variant = map.get("manila")
	if rect == null or jug.muerto:
		jug.manila = null
		return
	var r: Rect2i = rect
	var dentro: bool = jug.x >= r.position.x and jug.x < r.position.x + r.size.x \
		and jug.y >= r.position.y and jug.y < r.position.y + r.size.y
	if not dentro:
		jug.manila = null
		return
	if jug.manila == null:
		jug.manilaIntento = int(jug.manilaIntento) + 1
		var seg := MapGen.manila_goal(map.manilaSalida, "%s::%s" % [jug.token, clave], jug.manilaIntento)
		jug.manila = {"desde": Salas.msec(), "objetivoMs": seg * 1000, "aviso": 0}
		return
	var frac := float(Salas.msec() - int(jug.manila.desde)) / float(jug.manila.objetivoMs)
	if frac >= 1:
		jug.manila = null
		var original: Variant = map.get("manilaSalida")
		if original == null or not alCruzar.is_valid():
			return
		var destino := str((original as Dictionary).destino)
		if destino.begins_with("*opciones:"):
			destino = rng.elegir(Array(destino.trim_prefix("*opciones:").split(",")))
		var d: Dictionary = (original as Dictionary).duplicate()
		d.destino = destino
		d["_destinoResuelto"] = destino
		enviar(jug.ws, {"t": "aviso", "txt": "El tiempo se te ha escapado de las manos. Ya no sabes cuánto llevas aquí."})
		alCruzar.call(jug, self, d, {"sinTarjeta": true})
	elif frac >= 0.8 and int(jug.manila.aviso) < 2:
		jug.manila.aviso = 2
		enviar(jug.ws, {"t": "aviso", "txt": "Cuesta recordar por qué entraste aquí…"})
	elif frac >= 0.5 and int(jug.manila.aviso) < 1:
		jug.manila.aviso = 1
		enviar(jug.ws, {"t": "aviso", "txt": "Este sitio empieza a difuminarte los sentidos…"})

## caminata personal por DISTANCIA recorrida (1 «paso» ≈ 1 tile)
func caminata_avanza(jug: Dictionary, d: float) -> void:
	if int(jug.caminataObjetivo) == 0 or jug.muerto:
		return
	jug.distSala = float(jug.distSala) + d
	var pasos := floori(float(jug.distSala))
	if pasos > int(jug.pasosSala):
		jug.pasosSala = pasos
		if pasos % 20 == 0 or pasos >= int(jug.caminataObjetivo):
			enviar(jug.ws, {"t": "caminata", "pasos": pasos, "objetivo": jug.caminataObjetivo})
		if pasos >= int(jug.caminataObjetivo):
			var def_c: Variant = resolver_destino(jug, jug.caminataDef)
			if def_c == null:
				jug.caminataObjetivo = 0
				enviar(jug.ws, {"t": "aviso", "txt": "La ruta se desvanece: el nivel destino está en desarrollo."})
				return
			if alCruzar.is_valid():
				# Cruce silencioso: no anuncia "Has encontrado la salida"
				alCruzar.call(jug, self, def_c, {"sinTarjeta": true, "silencioso": true})

## consecuencias de la posición (por PROXIMIDAD): ofertar salida a <0.6
## (histéresis: se rearma al alejarse >1.0)
func proximidad(jug: Dictionary) -> bool:
	var s: Variant = salida_cerca(jug, 0.6)
	if s != null and (s as Dictionary).ex.def.get("_mec") == "noclip":
		jug.ofertaEn = (s as Dictionary).i
		# El no-clip es un error en la realidad: ocurre al instante y sin avisar
		alCruzar.call(jug, self, (s as Dictionary).ex.def, {"sinTarjeta": true, "silencioso": true})
		return true
	if s != null and not _misma_oferta(jug, s):
		ofrecer(jug, s)
	elif s == null and jug.ofertaEn != null and salida_cerca(jug, 1.0) == null:
		jug.ofertaEn = null
	return false

func _misma_oferta(jug: Dictionary, s: Dictionary) -> bool:
	return typeof(jug.ofertaEn) == typeof(s.i) and jug.ofertaEn == s.i

func salida_cerca(jug: Dictionary, radio: float) -> Variant:
	var mejor: Variant = null
	var mejor_d := radio
	var exits: Array = map.exits
	for i in exits.size():
		var e: Dictionary = exits[i]
		var d := Fisica.dist(float(e.x), float(e.y), jug.x, jug.y)
		if d <= mejor_d:
			mejor_d = d
			mejor = {"i": i, "ex": e}
	# tu retorno físico personal compite como una salida más (nunca la caminata)
	if jug.retorno != null:
		var r: Dictionary = jug.retorno
		if r.get("_mec") != "caminata" and r.has("x") and r.has("y"):
			var d := Fisica.dist(float(r.x), float(r.y), jug.x, jug.y)
			if d <= mejor_d:
				mejor = {"i": "R", "ex": {"x": r.x, "y": r.y, "def": r}}
	return mejor

func ofrecer(jug: Dictionary, s: Dictionary) -> void:
	jug.ofertaEn = s.i
	var d: Dictionary = s.ex.def
	var mec: Variant = d.get("_mec")
	if (mec == "romper" or mec == "romper_suelo") and not d.get("_abierta", false):
		enviar(jug.ws, {"t": "aviso", "txt":
			"El suelo CRUJE bajo la moqueta. Pulsa ESPACIO para intentar romperlo."
			if mec == "romper_suelo" else
			"Esta pared está AGRIETADA: suena hueca. Pulsa ESPACIO para intentar abrirla."})
		return
	enviar(jug.ws, {"t": "oferta", "i": s.i, "texto": d.get("texto", ""),
		"destino": d.get("destino"), "tipo": d.get("tipo")})

## ESPACIO contextual. Los contenedores NO pasan por aquí (v25): registrar,
## dado y botín son del cliente.
func accion(jug: Dictionary) -> void:
	if jug.muerto or jug.canal != null:
		return
	if jug.escondido != null:
		esconder(jug, false, {})
		return
	var prop_escondite: Variant = null
	for p: Dictionary in map.get("props", []):
		if ESCONDITES.has(p.get("id")) and Fisica.dist(float(p.x), float(p.y), jug.x, jug.y) <= 1.2:
			prop_escondite = p
			break
	var s: Variant = salida_cerca(jug, 1.0)
	if s != null:
		var d: Dictionary = (s as Dictionary).ex.def
		var mec: Variant = d.get("_mec")
		if (mec == "romper" or mec == "romper_suelo") and not d.get("_abierta", false):
			iniciar_romper(jug, s)
			return
		if mec == "noclip":
			cruzar(jug, true)
			return
		ofrecer(jug, s)
		return
	if prop_escondite != null:
		esconder(jug, true, prop_escondite)
		return
	enviar(jug.ws, {"t": "aviso", "txt": "No hay nada con lo que interactuar aquí."})

## alta de botín (v25): el cliente resolvió su dado individual.
func loot(jug: Dictionary, id: String) -> void:
	if jug.muerto:
		return
	var d: Variant = Catalogo.objetos.get(id)
	if d == null:
		return
	var ahora := Salas.msec()
	if ahora - int(jug["_ultLoot"]) < 1200:
		return # cadencia máxima de botín
	if (jug.inv as Array).size() >= 6:
		enviar(jug.ws, {"t": "aviso", "txt": "No te cabe nada más en la mochila."})
		return
	jug["_ultLoot"] = ahora
	(jug.inv as Array).append(id)
	# tubería o linterna a una mano libre: lista para usar
	var m := (jug.manos as Array).find(null)
	if m >= 0 and (d.get("manos") != null or (d.get("efecto", {}) as Dictionary).get("toggle") == "luz"):
		jug.manos[m] = id
		(jug.inv as Array).pop_back()
	enviar_inv(jug)

func esconder(jug: Dictionary, si: bool, prop: Dictionary) -> void:
	if si:
		jug.escondido = {"x": prop.x, "y": prop.y}
		jug.x = float(prop.x)
		jug.y = float(prop.y)
		jug.sec = int(jug.sec) + 1
		difundir({"t": "mueve", "id": jug.id, "x": r2(jug.x), "y": r2(jug.y), "sec": jug.sec})
		enviar(jug.ws, {"t": "aviso", "txt": "Te metes dentro. Nada debería verte… si nadie te vio entrar."})
	else:
		jug.escondido = null
	difundir({"t": "esconde", "id": jug.id, "si": si})

## romper pared/suelo: canal de 1 s + dado
func iniciar_romper(jug: Dictionary, s: Dictionary) -> void:
	var herramienta := (jug.manos as Array).has("tuberia")
	jug.canal = {"tipo": "romper", "i": s.i, "hasta": Salas.msec() + 1000,
		"herramienta": herramienta, "origen": [jug.x, jug.y]}
	hacer_ruido(jug.x, jug.y, 10)
	difundir({"t": "canal", "id": jug.id, "ms": 1000})

func cancelar_canal(jug: Dictionary, motivo: String) -> void:
	jug.canal = null
	enviar(jug.ws, {"t": "canalFin", "ok": false})
	if not motivo.is_empty():
		enviar(jug.ws, {"t": "aviso", "txt": motivo})

func _tiene_trebol(jug: Dictionary) -> bool:
	return (jug.inv as Array).has("trebol") or (jug.manos as Array).has("trebol") \
		or (jug.equipo as Dictionary).values().has("trebol")

func resolver_canal(jug: Dictionary) -> void:
	var c: Dictionary = jug.canal
	jug.canal = null
	if not (c.i is int):
		return
	var ex: Dictionary = map.exits[c.i]
	if ex.def.get("_abierta", false):
		return
	var d := rng.entero(1, 20)
	if _tiene_trebol(jug):
		d = mini(20, d + 2)
	var es_suelo: bool = ex.def.get("_mec") == "romper_suelo"
	var umbral: int = 7 if c.herramienta else (11 if es_suelo else 12)
	var exito := d >= umbral
	enviar(jug.ws, {"t": "dado", "id": jug.id, "valor": d, "exito": exito})
	enviar(jug.ws, {"t": "canalFin", "ok": true})
	if exito:
		ex.def["_abierta"] = true
		difundir({"t": "abierto", "i": c.i})
		hacer_ruido(float(ex.x), float(ex.y), 12)
	elif not c.herramienta:
		# romper a puñetazos/pisotones duele
		jug.salud = maxf(0, jug.salud - 2)
		enviar(jug.ws, {"t": "salud", "valor": jug.salud})
		if jug.salud <= 0:
			morir(jug, "tus propios golpes")

## cruzar salidas
func cruzar(jug: Dictionary, si: bool) -> void:
	if not si:
		jug.ofertaEn = null
		return
	var s: Variant = salida_cerca(jug, 1.0)
	if s == null or jug.muerto:
		return
	var d: Variant = resolver_destino(jug, (s as Dictionary).ex.def)
	if d == null:
		enviar(jug.ws, {"t": "aviso", "txt": "La ruta está bloqueada: ese nivel aún está en desarrollo."})
		return
	var dd: Dictionary = d
	# Puerta con llave (The Hub): necesita llave_nivel en el inventario
	if dd.get("tipo") == "llave":
		var inv: Array = jug.inv as Array
		var idx := inv.find("llave_nivel")
		if idx < 0:
			enviar(jug.ws, {"t": "aviso", "txt": "La puerta no tiene pomo. Necesitas una Llave de Nivel para abrirla."})
			return
		inv.remove_at(idx)
		enviar_inv(jug)
		enviar(jug.ws, {"t": "aviso", "txt": "Introduces la Llave de Nivel. La cerradura cede con un clic seco."})
	var mec: Variant = dd.get("_mec")
	if (mec == "romper" or mec == "romper_suelo") and not dd.get("_abierta", false):
		return
	if not Catalogo.niveles.has(str(dd.destino)):
		enviar(jug.ws, {"t": "aviso", "txt": "La ruta está bloqueada: ese nivel aún está en desarrollo."})
		return
	# riesgoVoid: el mismo d20 determinista de la sala
	if dd.get("tipo") == "arriesgada" and float(dd.get("riesgoVoid", 0)) > 0:
		var dado := rng.entero(1, 20)
		if _tiene_trebol(jug):
			dado = mini(20, dado + 2)
		var umbral := roundi(float(dd.riesgoVoid) * 20)
		var exito := dado > umbral
		if mec != "noclip":
			enviar(jug.ws, {"t": "dado", "id": jug.id, "valor": dado, "exito": exito})
		if not exito:
			morir(jug, "el Vacío")
			return
	if alCruzar.is_valid():
		var opts: Variant = {"sinTarjeta": true, "sinRetorno": true, "silencioso": true} \
			if mec == "noclip" else null
		alCruzar.call(jug, self, dd, opts)

func aplicar_numericos(jug: Dictionary, d: Dictionary) -> void:
	var ef: Dictionary = d.get("efecto", {})
	if ef.has("salud"):
		if float(ef.salud) < 0:
			herir(jug, absf(float(ef.salud)), d.get("nombre", ""))
		else:
			jug.salud = minf(100, jug.salud + float(ef.salud))
	if ef.has("sed"):
		jug.sed = maxf(0, minf(100, jug.sed + float(ef.sed)))
	if ef.has("cordura"):
		jug.cordura = maxf(0, minf(100, jug.cordura + float(ef.cordura)))
	if ef.has("ruido"):
		hacer_ruido(jug.x, jug.y, float(ef.ruido))
	enviar_estado(jug)
	if not jug.muerto and (jug.salud <= 0 or jug.sed <= 0 or jug.cordura <= 0):
		morir(jug, d.get("nombre", ""))

func entidades_en_radio(jug: Dictionary, radio: float) -> Array:
	var out := []
	for e: Dictionary in entidades:
		if e.viva and Fisica.dist(e.x, e.y, jug.x, jug.y) <= radio:
			out.append(e)
	return out

func entidad_frontal(jug: Dictionary, rango: int) -> Variant:
	var f := cardinal_de(float(jug.get("rot", PI)))
	var mejor: Variant = null
	var mejor_d := 2147483647
	for e: Dictionary in entidades:
		if not e.viva:
			continue
		var dx := roundi(e.x - jug.x)
		var dy := roundi(e.y - jug.y)
		var delante: bool = (absi(dy) <= 1 and signi(dx) == f.x) if f.x != 0 \
			else (absi(dx) <= 1 and signi(dy) == f.y)
		var d := absi(dx) + absi(dy)
		if delante and d <= rango and d < mejor_d:
			mejor = e
			mejor_d = d
	return mejor

func danar_entidad(e: Dictionary, dano: float) -> void:
	e.vida = float(e.vida) - dano
	e.revelada = true
	if float(e.vida) <= 0:
		e.viva = false
		difundir({"t": "entMuere", "uid": e.uid})
	else:
		difundir({"t": "entHit", "uid": e.uid})

func usar_activo_catalogo(jug: Dictionary, d: Dictionary) -> bool:
	var ef: Dictionary = d.get("efecto", {})
	var radio := float(ef.get("radio", 3))
	aplicar_numericos(jug, d)
	if jug.muerto:
		return true
	match ef.get("activo"):
		"fuego", "fuego_menor", "toxina", "gas":
			for e: Dictionary in entidades_en_radio(jug, radio):
				danar_entidad(e, float(ef.get("dano", 30 if ef.activo == "fuego" else 20)))
				if ef.activo != "fuego_menor":
					e.huyendoHasta = Salas.msec() + 4000
			hacer_ruido(jug.x, jug.y, 12 if ef.activo == "fuego" else 8)
			difundir({"t": "golpe", "id": jug.id, "x": jug.x, "y": jug.y})
			return true
		"paralisis":
			for e: Dictionary in entidades_en_radio(jug, radio if radio > 0 else 1):
				e.paralizadaHasta = Salas.msec() + 90000
				difundir({"t": "entHit", "uid": e.uid})
			return true
		"disparo":
			var e: Variant = entidad_frontal(jug, 7)
			hacer_ruido(jug.x, jug.y, float(ef.get("radio", 10)))
			var f := cardinal_de(float(jug.get("rot", PI)))
			difundir({"t": "golpe", "id": jug.id, "x": jug.x + f.x, "y": jug.y + f.y})
			if e != null:
				danar_entidad(e, float(ef.get("dano", 34)))
			return true
		"flash":
			for e: Dictionary in entidades_en_radio(jug, radio):
				e.revelada = true
				e.paralizadaHasta = Salas.msec() + 1800
				difundir({"t": "entHit", "uid": e.uid})
			return true
		"ruido":
			hacer_ruido(jug.x, jug.y, radio)
			return true
		"repeler", "sellar":
			for e: Dictionary in entidades_en_radio(jug, radio):
				e.huyendoHasta = Salas.msec() + 5000
			return true
		"salida":
			var salidas := []
			for s: Dictionary in def.get("salidas", []):
				if s.has("destino") and Catalogo.niveles.has(str(s.destino)) and s.get("tipo") != "sellada":
					salidas.append(s)
			var salida: Variant = rng.elegir(salidas) if not salidas.is_empty() else null
			if salida == null or not alCruzar.is_valid():
				enviar(jug.ws, {"t": "aviso", "txt": "%s vibra, pero no encuentra ruta estable." % d.get("nombre", "")})
				return true
			alCruzar.call(jug, self, salida, null)
			return true
		"blink":
			var f := cardinal_de(float(jug.get("rot", PI)))
			for dist_blink in range(5, 1, -1):
				var tx := roundi(jug.x) + f.x * dist_blink
				var ty := roundi(jug.y) + f.y * dist_blink
				if not Salas.es_transitable(map, tx, ty):
					continue
				jug.x = float(tx)
				jug.y = float(ty)
				jug.sec = int(jug.sec) + 1
				difundir({"t": "mueve", "id": jug.id, "x": r2(jug.x), "y": r2(jug.y), "sec": jug.sec})
				return true
			enviar(jug.ws, {"t": "aviso", "txt": "%s no encuentra hueco." % d.get("nombre", "")})
			return true
		"claridad":
			enviar(jug.ws, {"t": "aviso", "txt": "%s: entiendes un poco mejor este sitio." % d.get("nombre", "")})
			return true
		"glitch":
			for e: Dictionary in entidades_en_radio(jug, radio):
				e.revelada = true
				difundir({"t": "entHit", "uid": e.uid})
			return true
		"celeridad", "ocultar", "refugio":
			jug.escondido = {"temporal": true}
			difundir({"t": "esconde", "id": jug.id, "si": true})
			return true
		"riesgo":
			enviar(jug.ws, {"t": "aviso", "txt": "%s reacciona de forma peligrosa." % d.get("nombre", "")})
			return true
	return false

func usar(jug: Dictionary, mano: int) -> void:
	if jug.muerto or jug.escondido != null:
		return
	var id: Variant = jug.manos[mano]
	var d: Variant = Catalogo.objetos.get(id) if id is String else null
	if d != null and (d.get("efecto", {}) as Dictionary).get("toggle") == "luz":
		luz(jug, not jug.luz)
		return
	if d != null and (d.get("efecto", {}) as Dictionary).has("activo") and usar_activo_catalogo(jug, d):
		if (d.get("efecto", {}) as Dictionary).get("activo") != "paralisis":
			if int(d.get("manos", 0)) == 2 or jug.manos[1] == "=":
				jug.manos = [null, null]
			else:
				jug.manos[mano] = null
			enviar_inv(jug)
		return
	if d == null and id == "linterna":
		luz(jug, not jug.luz)
		return
	if id != "tuberia":
		return
	var ahora := Salas.msec()
	if ahora - int(jug.ultGolpe) < 400:
		return
	jug.ultGolpe = ahora
	var f := cardinal_de(float(jug.get("rot", PI)))
	var tx: float = jug.x + f.x
	var ty: float = jug.y + f.y
	difundir({"t": "golpe", "id": jug.id, "x": tx, "y": ty})
	hacer_ruido(jug.x, jug.y, 8)
	# el barrido alcanza a la entidad viva más cercana al punto de impacto
	var e: Variant = null
	var mejor := 0.9
	for e2: Dictionary in entidades:
		if not e2.viva:
			continue
		var dd := Fisica.dist(e2.x, e2.y, tx, ty)
		if dd <= mejor:
			mejor = dd
			e = e2
	if e == null:
		return
	var fuerte := false
	for oid in (jug.inv as Array) + (jug.manos as Array):
		if oid is String and (Catalogo.objetos.get(oid, {}).get("efecto", {}) as Dictionary).get("pasivo") == "fuerza":
			fuerte = true
			break
	(e as Dictionary).vida = float((e as Dictionary).vida) - (20 if fuerte else 12)
	(e as Dictionary).revelada = true
	if float((e as Dictionary).vida) <= 0:
		(e as Dictionary).viva = false
		difundir({"t": "entMuere", "uid": (e as Dictionary).uid})
	else:
		difundir({"t": "entHit", "uid": (e as Dictionary).uid})

## la linterna solo alumbra EN LA MANO
func luz(jug: Dictionary, si: bool) -> void:
	var tiene_luz := false
	for id in jug.manos:
		if id is String and (Catalogo.objetos.get(id, {}).get("efecto", {}) as Dictionary).get("toggle") == "luz":
			tiene_luz = true
			break
	if si and not tiene_luz:
		enviar(jug.ws, {"t": "aviso", "txt": "Necesitas una fuente de luz en la mano (B: mochila)."})
		si = false
	if jug.luz == si:
		return
	jug.luz = si
	difundir({"t": "luzDe", "id": jug.id, "si": jug.luz})

## mochila autoritativa
func mochila(jug: Dictionary, m: Dictionary) -> void:
	if jug.muerto:
		return
	match m.get("que"):
		"equipar":
			var id: Variant = (jug.inv as Array)[m.slot] if int(m.slot) < (jug.inv as Array).size() else null
			var d: Variant = Catalogo.objetos.get(id) if id is String else null
			if d == null or d.get("manos") == null:
				enviar(jug.ws, {"t": "aviso", "txt": "Eso no se empuña."})
				return
			if int(d.manos) == 2:
				if jug.manos[0] != null or jug.manos[1] != null:
					enviar(jug.ws, {"t": "aviso", "txt": "Necesitas las DOS manos libres."})
					return
				jug.manos = [id, "="]
			else:
				var libre := (jug.manos as Array).find(null)
				if libre < 0:
					enviar(jug.ws, {"t": "aviso", "txt": "Tienes las manos ocupadas."})
					return
				jug.manos[libre] = id
			(jug.inv as Array).remove_at(m.slot)
		"desequipar":
			var mano := int(m.mano)
			if jug.manos[mano] == "=":
				mano = 0
			var id: Variant = jug.manos[mano]
			if id == null:
				return
			if (jug.inv as Array).size() >= 6:
				enviar(jug.ws, {"t": "aviso", "txt": "La mochila está llena."})
				return
			var d: Variant = Catalogo.objetos.get(id)
			if d != null and int(d.get("manos", 0)) == 2:
				jug.manos = [null, null]
			else:
				jug.manos[mano] = null
			(jug.inv as Array).append(id)
		"usarItem":
			var id: Variant = (jug.inv as Array)[m.slot] if int(m.slot) < (jug.inv as Array).size() else null
			var d: Variant = Catalogo.objetos.get(id) if id is String else null
			if d == null:
				return
			var ef: Dictionary = d.get("efecto", {})
			if ef.has("activo") and usar_activo_catalogo(jug, d):
				if ef.get("activo") != "paralisis":
					(jug.inv as Array).remove_at(m.slot)
				enviar(jug.ws, {"t": "aviso", "txt": "Usas %s." % d.get("nombre", "")})
			elif ef.has("salud") or ef.has("sed") or ef.has("cordura") or ef.has("ruido"):
				aplicar_numericos(jug, d)
				(jug.inv as Array).remove_at(m.slot)
				enviar(jug.ws, {"t": "aviso", "txt": "Usas %s." % d.get("nombre", "")})
			elif ef.get("toggle") == "luz":
				luz(jug, not jug.luz)
			else:
				enviar(jug.ws, {"t": "aviso", "txt": "Aquí dentro, eso todavía no surte efecto."})
				return
		"tirar", "arrojar":
			var id: Variant = (jug.inv as Array)[m.slot] if int(m.slot) < (jug.inv as Array).size() else null
			if id == null:
				return
			(jug.inv as Array).remove_at(m.slot)
			var tx: float = jug.x
			var ty: float = jug.y
			if m.que == "arrojar":
				# vuela hasta 4 casillas hacia donde miras: distracción sonora
				var f := cardinal_de(float(jug.get("rot", PI)))
				var jx := Fisica.tile_de(jug.x)
				var jy := Fisica.tile_de(jug.y)
				for dist_a in range(4, 0, -1):
					if Salas.es_transitable(map, jx + f.x * dist_a, jy + f.y * dist_a):
						tx = jx + f.x * dist_a
						ty = jy + f.y * dist_a
						break
				hacer_ruido(tx, ty, 12)
			enviar(jug.ws, {"t": "itemSuelto", "x": tx, "y": ty, "id": id, "recien": m.que == "tirar"})
		"ponerEquipo":
			var id: Variant = (jug.inv as Array)[m.slot] if int(m.slot) < (jug.inv as Array).size() else null
			var d: Variant = Catalogo.objetos.get(id) if id is String else null
			if d == null or d.get("equipo") == null:
				enviar(jug.ws, {"t": "aviso", "txt": "Eso no se viste."})
				return
			var anterior: Variant = jug.equipo[d.equipo]
			jug.equipo[d.equipo] = id
			(jug.inv as Array).remove_at(m.slot)
			if anterior != null:
				(jug.inv as Array).append(anterior)
		"quitarEquipo":
			var id: Variant = jug.equipo.get(m.tipo)
			if id == null:
				return
			if (jug.inv as Array).size() >= 6:
				enviar(jug.ws, {"t": "aviso", "txt": "La mochila está llena."})
				return
			jug.equipo[m.tipo] = null
			(jug.inv as Array).append(id)
	enviar_inv(jug)
	# si la linterna salió de las manos con la luz encendida, se apaga sola
	var tiene_luz := false
	for id in jug.manos:
		if id is String and (Catalogo.objetos.get(id, {}).get("efecto", {}) as Dictionary).get("toggle") == "luz":
			tiene_luz = true
			break
	if jug.luz and not tiene_luz:
		luz(jug, false)

func hacer_ruido(x: float, y: float, radio: float) -> void:
	ruido = {"x": x, "y": y, "radio": radio, "hasta": Salas.msec() + 3200}

## muerte: como el roguelike, despiertas otra vez en Level 0.
## (El setTimeout de 2.5 s del original se procesa en tick() vía _respawnEn.)
func morir(jug: Dictionary, causa: String) -> void:
	jug.muerto = true
	jug.escondido = null
	jug.canal = null
	jug.manila = null
	if jug.luz:
		luz(jug, false) # la linterna se pierde con el resto
	enviar(jug.ws, {"t": "botinReset", "semilla": semilla})
	difundir({"t": "muere", "id": jug.id, "causa": causa})
	jug["_causaMuerte"] = causa
	jug["_respawnEn"] = Salas.msec() + 2500

func _procesar_respawn(jug: Dictionary) -> void:
	jug["_respawnEn"] = 0
	if not jugadores.has(jug.id):
		return
	jug.salud = 100.0
	jug.sed = 100.0
	jug.cordura = 100.0
	jug.oxigeno = 100.0
	jug.muerto = false
	jug.inv = []
	jug.manos = [null, null]
	# lo VESTIDO también se queda atrás
	jug.equipo = {"cara": null, "cuerpo": null, "pies": null}
	enviar_inv(jug)
	if alMorir.is_valid():
		alMorir.call(jug, self, str(jug.get("_causaMuerte", "")))

## remodelación no euclidiana: EVENTO de sala (v21) — activa en modo local
func remodelar() -> bool:
	var g: MapGen.Grid = map.grid
	const CH := 14
	if g.w < CH + 6 or g.h < CH + 6:
		return false
	for intento in 12:
		var cx := rng.entero(2, g.w - CH - 3)
		var cy := rng.entero(2, g.h - CH - 3)
		# fuera de la vista de TODOS los jugadores de la sala
		var vista := false
		for j: Dictionary in jugadores.values():
			var ncx := maxf(cx, minf(j.x, cx + CH - 1))
			var ncy := maxf(cy, minf(j.y, cy + CH - 1))
			if maxf(absf(j.x - ncx), absf(j.y - ncy)) < 20:
				vista = true
				break
		if vista:
			continue
		var toca_salida := false
		for e: Dictionary in map.exits:
			if int(e.x) >= cx and int(e.x) < cx + CH and int(e.y) >= cy and int(e.y) < cy + CH:
				toca_salida = true
				break
		if toca_salida:
			continue
		var backup := PackedByteArray()
		backup.resize(CH * CH)
		for y in CH:
			for x in CH:
				backup[y * CH + x] = g.t[(cy + y) * g.w + (cx + x)]
		for y in range(1, CH - 1):
			for x in range(1, CH - 1):
				var gx := cx + x
				var gy := cy + y
				var viejo := g.t[gy * g.w + gx]
				if viejo == MapGen.VACIO or viejo == MapGen.AGUA:
					continue
				var pilar := (gx % 2 == 0 and gy % 2 == 0) or rng.azar(0.22)
				g.t[gy * g.w + gx] = MapGen.PARED if pilar else MapGen.SUELO
		for it: Dictionary in map.items:
			if not it.get("taken", false) and _dentro_chunk(it, cx, cy, CH):
				g.t[int(it.y) * g.w + int(it.x)] = MapGen.SUELO
		for pr: Dictionary in map.get("props", []):
			if _dentro_chunk(pr, cx, cy, CH):
				g.t[int(pr.y) * g.w + int(pr.x)] = MapGen.SUELO
		for e: Dictionary in entidades:
			if e.viva and e.x >= cx and e.x < cx + CH and e.y >= cy and e.y < cy + CH:
				g.t[Fisica.tile_de(e.y) * g.w + Fisica.tile_de(e.x)] = MapGen.SUELO
		# validar: salidas Y jugadores siguen conectados (BFS del spawn)
		var s: Vector2i = map.spawn
		var dist := MapGen.bfs_dist(g, s.x, s.y)
		var ok := true
		for e: Dictionary in map.exits:
			if dist[int(e.y) * g.w + int(e.x)] < 0:
				ok = false
				break
		if ok:
			for j: Dictionary in jugadores.values():
				if dist[Fisica.tile_de(j.y) * g.w + Fisica.tile_de(j.x)] < 0:
					ok = false
					break
		if not ok:
			for y in CH:
				for x in CH:
					g.t[(cy + y) * g.w + (cx + x)] = backup[y * CH + x]
			continue
		var tiles := []
		for y in CH:
			for x in CH:
				tiles.append(g.t[(cy + y) * g.w + (cx + x)])
		difundir({"t": "remodel", "x": cx, "y": cy, "ch": CH, "tiles": tiles})
		return true
	return false

static func _dentro_chunk(p: Dictionary, cx: int, cy: int, ch: int) -> bool:
	return int(p.x) >= cx and int(p.x) < cx + ch and int(p.y) >= cy and int(p.y) < cy + ch

## tick de simulación (lo llama el anfitrión a 20 Hz)
func tick(ahora: int) -> void:
	if jugadores.is_empty():
		return
	var dt := minf(0.25, (ahora - (_ultTick if _ultTick != 0 else ahora)) / 1000.0)
	_ultTick = ahora
	var movidos := _movidosExtra
	_movidosExtra = []
	for jug: Dictionary in jugadores.values():
		if jug.canal != null and ahora >= int(jug.canal.hasta):
			resolver_canal(jug)
		if jug.muerto and int(jug.get("_respawnEn", 0)) > 0 and ahora >= int(jug["_respawnEn"]):
			_procesar_respawn(jug)
	if (def.get("reglas", []) as Array).has("respiracion_acuatica"):
		for jug: Dictionary in jugadores.values():
			if jug.muerto or ahora < int(jug.get("_oxigenoEn", 0)):
				continue
			jug["_oxigenoEn"] = ahora + 1000
			var tx := Fisica.tile_de(jug.x)
			var ty := Fisica.tile_de(jug.y)
			var g: MapGen.Grid = map.grid
			var en_agua := g.t[ty * g.w + tx] == 3
			var respiradero := false
			for air: Dictionary in map.get("airPockets", []):
				if Fisica.dist(float(air.x), float(air.y), jug.x, jug.y) <= 1.25:
					respiradero = true
					break
			var antes := float(jug.get("oxigeno", 100))
			jug.oxigeno = minf(100, antes + (28 if respiradero else 18)) \
				if (not en_agua or respiradero) else maxf(0, antes - 4)
			if jug.oxigeno == 20 and antes > 20:
				enviar(jug.ws, {"t": "aviso", "txt": "Te queda muy poco oxígeno."})
			if jug.oxigeno == 0:
				herir(jug, 8, "el ahogamiento")
			if not jug.muerto:
				enviar_estado(jug)
	Entidades.tick(self, ahora, dt)
	# difusión BATCHED de posiciones
	if not movidos.is_empty() or not _entMovidas.is_empty():
		var jlist := []
		var vistos := {}
		for j: Dictionary in movidos:
			if vistos.has(j.id):
				continue
			vistos[j.id] = true
			jlist.append([j.id, r2(j.x), r2(j.y), r2(float(j.get("rot", 0)))])
		var elist := []
		for e: Dictionary in _entMovidas:
			elist.append([e.uid, r2(e.x), r2(e.y)])
		difundir({"t": "pos", "j": jlist, "e": elist})
		_entMovidas = []
	# regla no_euclidiana: cada 45-90 s el nivel se reorganiza (modo local)
	if Salas.remodel_activo and (def.get("reglas", []) as Array).has("no_euclidiano"):
		if _remodelEn == 0:
			_remodelEn = ahora + 45000 + rng.entero(0, 45000)
		if ahora >= _remodelEn:
			_remodelEn = ahora + 45000 + rng.entero(0, 45000)
			remodelar()

func enviar(ws: Callable, msg: Dictionary) -> void:
	if ws.is_valid():
		ws.call(msg)

func difundir(msg: Dictionary, excepto_id: int = -1) -> void:
	for j: Dictionary in jugadores.values():
		if j.id != excepto_id and (j.ws as Callable).is_valid():
			(j.ws as Callable).call(msg)
