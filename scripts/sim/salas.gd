## Registro de salas y cruce entre niveles. Port de la parte de módulo de
## game/js/sim/sala.js (window.Salas): asignar/crear salas persistentes por
## semilla, cambiarDeSala con puerta de RETORNO fiel al acceso de entrada, y
## utilidades compartidas (generarMapa sin `prob`, caminoLegal, reloj).
## Estado estático: persiste durante la sesión de juego, igual que el registro
## del original persiste mientras vive la pestaña.
class_name Salas

static var salas: Dictionary = {}          # clave interna -> Sala
static var semilla_base: String = "solo"   # fijar_semilla_base la cambia por run
static var remodel_activo: bool = false
static var _siguiente_id: int = 1
## Reloj inyectable (los tests lo sustituyen, como test-manila.js con Date.now)
static var reloj: Callable = Callable()

static func msec() -> int:
	if reloj.is_valid():
		return reloj.call()
	return Time.get_ticks_msec()

static func siguiente_id() -> int:
	_siguiente_id += 1
	return _siguiente_id - 1

static func fijar_semilla_base(base: String) -> void:
	semilla_base = base

static func activar_remodel(v: bool) -> void:
	remodel_activo = v

## Reinicio completo del registro (nueva run / tests).
static func reiniciar() -> void:
	salas = {}
	_siguiente_id = 1

## En el mundo compartido las salidas aparecen SIEMPRE (se ignora `prob`, que
## era para las ventanas infinitas del modo por turnos legacy).
static func def_para_online(d: Dictionary) -> Dictionary:
	var copia := d.duplicate()
	var salidas := []
	for s: Dictionary in d.get("salidas", []):
		var c := s.duplicate()
		c.erase("prob")
		salidas.append(c)
	copia.salidas = salidas
	return copia

static func generar_mapa(nivel_id: String, semilla: String) -> Dictionary:
	var d: Dictionary = Catalogo.nivel(nivel_id)
	assert(not d.is_empty(), "nivel desconocido: %s" % nivel_id)
	var map := MapGen.generate(def_para_online(d), Rng.crear(semilla))
	return {"def": d, "map": map}

static func es_transitable(map: Dictionary, x: int, y: int) -> bool:
	var g: MapGen.Grid = map.grid
	if x < 0 or y < 0 or x >= g.w or y >= g.h:
		return false
	return MapGen.walkable(MapGen.at(g, x, y))

## ¿Se puede ir de A a B sin cruzar nada sólido? Muestreo cada ~0.2 tiles con
## radio tolerante (0.22 vs 0.35 del cuerpo).
static func camino_legal(g: MapGen.Grid, x0: float, y0: float, x1: float, y1: float) -> bool:
	var d := Fisica.dist(x0, y0, x1, y1)
	var n := maxi(1, ceili(d / 0.2))
	for i in range(1, n + 1):
		var f := float(i) / n
		if Fisica.choca(g, x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, 0.22):
			return false
	return true

static func destino_disponible(d: Variant) -> bool:
	if d == null or not (d is Dictionary):
		return false
	var destino: Variant = (d as Dictionary).get("destino")
	if destino == null:
		return false
	var s := str(destino)
	if s == "*aleatoria" or s == "*visitada":
		return true
	if not s.begins_with("*opciones:"):
		return _nivel_implementado(s)
	for id in s.trim_prefix("*opciones:").split(","):
		if _nivel_implementado(id):
			return true
	return false

static func _nivel_implementado(id_catalogo: String) -> bool:
	if not Catalogo.niveles.has(id_catalogo):
		return false
	var clave := id_catalogo.replace("-", "_")
	if not LevelManager.REGISTRO.has(clave):
		return false
	return LevelManager.REGISTRO[clave].estado != "stub"

static func _clave_interna(nivel_id: String, inst: int) -> String:
	return "local::%s::%d" % [nivel_id, inst]

static func crear_sala(nivel_id: String, inst: int) -> Sala:
	var sala := Sala.new(nivel_id, inst, semilla_base)
	salas[_clave_interna(nivel_id, inst)] = sala
	print("[sala] abierta %s (%d×%d, %d entidades)" % [sala.clave,
		(sala.map.grid as MapGen.Grid).w, (sala.map.grid as MapGen.Grid).h, sala.entidades.size()])
	return sala

static func asignar(nivel_id: String) -> Sala:
	var inst := 1
	while true:
		var clave := _clave_interna(nivel_id, inst)
		var sala: Sala = salas.get(clave)
		if sala == null:
			sala = crear_sala(nivel_id, inst)
		if not sala.llena:
			return sala
		inst += 1
	return null

static func todas() -> Array:
	return salas.values()

static func tick_todas(ahora: int) -> void:
	for s: Sala in salas.values():
		if not s.jugadores.is_empty():
			s.tick(ahora)

# ---------- cruce de salas y respawn ----------

static func preparar_sala(sala: Sala) -> void:
	sala.alCruzar = _cambiar_de_sala_cb
	sala.alMorir = _al_morir_cb

static var _cambiar_de_sala_cb := func(jug: Dictionary, sala_vieja: Sala, def_salida: Dictionary, opts: Variant) -> void:
	cambiar_de_sala(jug, sala_vieja, def_salida, opts if opts is Dictionary else {})

static var _al_morir_cb := func(jug: Dictionary, sala_vieja: Sala, causa: String) -> void:
	cambiar_de_sala(jug, sala_vieja, {
		"destino": "level-0",
		"texto": "Moriste (%s). Despiertas otra vez sobre la moqueta húmeda, con las manos vacías." % causa,
	}, {"sinRetorno": true})

static var _re_sin_retorno := _compilar("(?i)agujero|caes |caer |caída|desplom|abismo|pozo|trampilla|no.?clip|desmay|despiert")
static var _re_ventana := _compilar("ventana")
static var _re_puerta := _compilar("puerta|portón|porton|verja|compuerta|salida de emergencia")
static var _re_escalera := _compilar("escalera|ascensor|elevador")

static func _compilar(patron: String) -> RegEx:
	var re := RegEx.new()
	re.compile(patron)
	return re

## salidas de las que físicamente NO se puede volver — la misma regla que el
## original comparte entre online y modo solo.
static func es_sin_retorno(d: Dictionary) -> bool:
	if d.get("_mec") == "noclip":
		return true
	if d.get("sinRetorno", false):
		return true
	if d.get("tipo") == "void":
		return true
	return _re_sin_retorno.search(str(d.get("texto", ""))) != null

## Naturaleza física del camino por el que se entra.
static func estilo_retorno_de(d: Variant) -> Variant:
	if d == null or not (d is Dictionary) or es_sin_retorno(d):
		return null
	var dd: Dictionary = d
	var mec: Variant = dd.get("_mec")
	if mec == null:
		mec = dd.get("mecanica")
	if mec == "noclip" or mec == "romper_suelo" or mec == "manila":
		return null
	if mec == "caminata":
		return "caminata"
	if mec == "romper":
		return "boquete"
	var texto := str(dd.get("texto", "")).to_lower()
	if _re_ventana.search(texto) != null:
		return "ventana"
	if _re_puerta.search(texto) != null:
		return "puerta"
	if _re_escalera.search(texto) != null:
		return "escalera"
	if dd.get("ritual") != null:
		return "ritual"
	return null

static func def_retorno_de(origen: String, def_entrada: Dictionary, opts: Dictionary) -> Variant:
	if opts.get("sinRetorno", false) or origen.is_empty():
		return null
	var estilo: Variant = estilo_retorno_de(def_entrada)
	if estilo == null:
		return null
	var base := {"destino": origen, "tipo": "retorno", "_retornoEstilo": estilo, "_abierta": true}
	match estilo:
		"caminata":
			base.texto = "Desandar el camino recorrido conduce de vuelta."
			base["mecanica"] = "caminata"
			base["_mec"] = "caminata"
		"ventana":
			base.texto = "La ventana por la que llegaste sigue abierta."
			base["_pared"] = true
		"puerta":
			base.texto = "La puerta por la que llegaste sigue abierta."
			if def_entrada.has("ritual"):
				base["ritual"] = def_entrada.ritual
			base["_pared"] = true
		"boquete":
			base.texto = "El boquete por el que llegaste sigue abierto."
			base["mecanica"] = "romper"
			base["_mec"] = "romper"
			base["_pared"] = true
		"escalera":
			base.texto = "La escalera por la que llegaste conduce de vuelta."
		_:
			base.texto = "El mismo acceso por el que llegaste sigue disponible."
			if def_entrada.has("ritual"):
				base["ritual"] = def_entrada.ritual
	return base

static func _mirar_alejandose(jug: Dictionary, puerta_x: float, puerta_y: float) -> void:
	var dx: float = jug.x - puerta_x
	var dy: float = jug.y - puerta_y
	if dx != 0.0 or dy != 0.0:
		jug.rot = atan2(dx, -dy)

## cruce de salas: sacar de la vieja, meter en la del destino y mandar el
## estado nuevo. RETORNO FIEL AL ACCESO DE ENTRADA (puerta→puerta,
## caminata→caminata; caídas/no-clip/muerte no dejan acceso inventado).
static func cambiar_de_sala(jug: Dictionary, sala_vieja: Sala, def_salida: Dictionary, opts: Dictionary = {}) -> void:
	sala_vieja.salir(jug)
	var nueva := asignar(str(def_salida.destino))
	preparar_sala(nueva)
	var origen := sala_vieja.nivelId
	jug.visitados[nueva.nivelId] = true
	var def_retorno: Variant = def_retorno_de(origen, def_salida, opts) \
		if origen != nueva.nivelId else null
	jug.retorno = null
	var p: Vector2i
	# Reutiliza una salida natural solo si tiene la MISMA naturaleza que el
	# acceso de entrada.
	var i_vuelta := -1
	if def_retorno != null and (def_retorno as Dictionary).get("_mec") != "caminata":
		var exits: Array = nueva.map.exits
		for i in exits.size():
			var e: Dictionary = exits[i]
			if str(e.def.get("destino")) != origen:
				continue
			if estilo_retorno_de(e.def) != (def_retorno as Dictionary)["_retornoEstilo"]:
				continue
			if (def_retorno as Dictionary).get("_pared", false) \
					and MapGen.at(nueva.map.grid, int(e.x), int(e.y) - 1) != MapGen.PARED:
				continue
			i_vuelta = i
			break
	if i_vuelta >= 0:
		# el nivel ya tiene la puerta que conecta de vuelta: apareces a su lado
		var ex: Dictionary = nueva.map.exits[i_vuelta]
		p = nueva.buscar_spawn_junto(int(ex.x), int(ex.y))
		jug.ofertaEn = null
		jug.x = float(p.x)
		jug.y = float(p.y)
		_mirar_alejandose(jug, float(ex.x), float(ex.y))
	elif def_retorno != null and (def_retorno as Dictionary).get("_mec") == "caminata":
		# el camino de vuelta se activa recorriendo distancia real
		jug.retorno = def_retorno
		p = nueva.buscar_spawn()
		jug.ofertaEn = null
	elif def_retorno != null:
		# acceso físico personal: solo si existe una ubicación válida
		var lugar: Variant = nueva.buscar_lugar_retorno((def_retorno as Dictionary).get("_pared", false))
		if lugar != null:
			var r: Vector2i = lugar
			p = nueva.buscar_spawn_junto(r.x, r.y)
			var ret: Dictionary = (def_retorno as Dictionary).duplicate()
			ret["x"] = r.x
			ret["y"] = r.y
			jug.retorno = ret
			jug.ofertaEn = null
			jug.x = float(p.x)
			jug.y = float(p.y)
			_mirar_alejandose(jug, float(r.x), float(r.y))
		else:
			p = nueva.buscar_spawn()
			jug.ofertaEn = null
	else:
		p = nueva.buscar_spawn()
		jug.ofertaEn = null
	jug.x = float(p.x)
	jug.y = float(p.y)
	jug.oxigeno = 100.0
	jug["_oxigenoEn"] = msec() + 1000
	jug.canal = null
	jug.escondido = null
	jug.manila = null
	jug.sec = int(jug.sec) + 1
	jug["_posT"] = msec()
	jug["_margen"] = 0.8
	nueva.proteger_primera_visita(jug)
	nueva.preparar_caminata(jug)
	var id: int = jug.id
	nueva.jugadores[id] = jug
	var msg := {
		"t": "nivel", "nivel": nueva.nivelId, "inst": nueva.inst, "semilla": nueva.semilla,
		"x": jug.x, "y": jug.y, "rot": jug.rot, "sec": jug.sec,
		"via": null if opts.get("silencioso", false) else def_salida.get("texto"),
		"sinTarjeta": opts.get("sinTarjeta", false),
		"salud": jug.salud, "sed": jug.sed, "cordura": jug.cordura, "oxigeno": jug.oxigeno,
		"inv": jug.inv, "manos": jug.manos, "equipo": jug.equipo,
		"retorno": jug.retorno,
		"caminata": {"pasos": 0, "objetivo": jug.caminataObjetivo} if jug.caminataObjetivo else null,
		"jugadores": nueva.censo(),
	}
	msg.merge(nueva.estado_dinamico())
	nueva.enviar(jug.ws, msg)
	nueva.difundir({"t": "entra", "id": id, "nombre": jug.nombre,
		"x": jug.x, "y": jug.y, "rot": jug.rot}, id)
	if jug.luz:
		nueva.difundir({"t": "luzDe", "id": id, "si": true})
	print("[→] %s#%d cruza a %s" % [jug.nombre, id, nueva.clave])
