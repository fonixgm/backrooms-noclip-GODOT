## Escena principal: conecta al mundo local (el patrón de net/local.js),
## integra el movimiento del jugador con Fisica a 60 Hz (_physics_process),
## corre la simulación de salas a 20 Hz como el servidor original, y consume
## los mensajes de la Sala igual que hacía cliente.js. Cámara libre en
## tercera persona (v25): WASD relativo a la cámara, ratón orbita.
class_name Nivel3D
extends Node3D

const TICK_MUNDO := 0.05 # 20 Hz, como sala.js
const ALTURA_CAM := 2.1
const DIST_CAM := 3.4

var nivel_id_catalogo := "level-0"

var sala: Sala
var jug: Dictionary
var render: RenderNivel
var hud: Hud
var camara: Camera3D
var cuerpo: Node3D
var sprite_jugador: Sprite3D
var linterna: SpotLight3D
var luz_cercana: OmniLight3D
var audio_ambiente: AudioStreamPlayer
var audio_sfx: AudioStreamPlayer

var px := 0.0 # posición lógica (esquina de tile, como el original)
var py := 0.0
var rot := PI
var _sec := 0
var _yaw := 0.0
var _tex_jugador: Dictionary = {}   # "down"/"up"/"side" → Texture2D
var _anim_dist := 0.0               # distancia acumulada para animar el paso
var _moviendo := false
var _cola: Array = []
var _acum_tick := 0.0
var _paso_acum := 0.0
var _suelo_t := 0
var _loot_listo := 0
var _bloqueado_muerte := false
var _botin: Dictionary = {} # semilla -> Array de claves resueltas
var _con_oxigeno := false
var _zumbido_player: AudioStreamPlayer
var _zumbido_gen: AudioStreamGenerator
var _zumbido_activo := false
var _hum_t := 0.0
var _flick_acum := 0.0
var _apagon_activo := false            # apagón completo en curso (regla "apagones")
var _apagon_restante := 0.0            # segundos que quedan de apagón
var _apagon_cooldown := 0.0            # hasta el próximo posible apagón
var _reglas_ambiente: Array = []       # caché de reglas activas del nivel actual
var _niebla_color_base := Color.BLACK  # color de niebla sin apagón (para restaurar)

func _ready() -> void:
	_registrar_input()
	_montar_escena()
	_cargar_botin()
	
	if Salas.todas().is_empty():
		randomize()
		Salas.reiniciar()
		Salas.fijar_semilla_base("solo::%08x" % (randi() & 0xFFFFFFFF))
		Salas.activar_remodel(true) # como net/local.js
		
	var args := OS.get_cmdline_user_args()
	var nivel_inicial := nivel_id_catalogo
	# depuración: `--nivel <id>` arranca en otro nivel (el ?nivel= de MMO_DEV)
	var i_nivel := args.find("--nivel")
	if i_nivel >= 0 and i_nivel + 1 < args.size() and Catalogo.niveles.has(args[i_nivel + 1]):
		nivel_inicial = args[i_nivel + 1]
	sala = Salas.asignar(nivel_inicial)
	Salas.preparar_sala(sala)

	if nivel_inicial == "level-188":
		sala.map.spawn = Vector2i(20, 20)
	if nivel_inicial == "the-hub":
		var hub_spawn: Variant = sala.map.grid.meta.get("_spawn_hub")
		if hub_spawn != null:
			sala.map.spawn = Vector2i(int(hub_spawn.x), int(hub_spawn.y))
		# La carretera va de este a oeste: mirar a la derecha (este, rot=0)
		rot = 0.0
		
	# depuración/selftest: `--entidad <id>` materializa una entidad cerca del spawn
	var i_ent := args.find("--entidad")
	if i_ent >= 0 and i_ent + 1 < args.size() and Catalogo.entidades.has(args[i_ent + 1]):
		_inyectar_entidad(args[i_ent + 1])
	jug = sala.entrar(Callable(self, "_al_recibir"), "Errante", _token())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# selftest visual: `--captura [ruta.png]` guarda una captura y sale
	if args.has("--captura"):
		var idx := args.find("--captura")
		var ruta := args[idx + 1] if idx + 1 < args.size() else "user://captura.png"
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			hud.tarjeta_visible = false
			hud.tarjeta.visible = false
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(ruta)
			get_tree().quit())

func _token() -> String:
	var ruta := "user://token.txt"
	if FileAccess.file_exists(ruta):
		return FileAccess.get_file_as_string(ruta).strip_edges()
	var t := "%08x%08x" % [randi(), randi()]
	var f := FileAccess.open(ruta, FileAccess.WRITE)
	f.store_string(t)
	return t

func _registrar_input() -> void:
	var teclas := {
		"mover_adelante": KEY_W, "mover_atras": KEY_S,
		"mover_izq": KEY_A, "mover_der": KEY_D,
		"accion": KEY_SPACE, "usar_izq": KEY_Q, "usar_der": KEY_E,
		"linterna": KEY_F, "mochila": KEY_B,
	}
	for nombre: String in teclas:
		if InputMap.has_action(nombre):
			continue
		InputMap.add_action(nombre)
		var ev := InputEventKey.new()
		ev.physical_keycode = teclas[nombre]
		InputMap.action_add_event(nombre, ev)

var _env: Environment

var _susurro_player: AudioStreamPlayer
var _aluc_timer := 0.0
var _tick_tiempo := 0.0
var _luz_manila: OmniLight3D          # bombilla naranja de Manila Room (flicker)
var _enchufe_tick := 0.0              # acumulador para enchufes quebradizos

func _montar_escena() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.02, 0.015)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.47, 0.35)
	_env.ambient_light_energy = 0.55
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.09, 0.085, 0.05)
	_env.fog_density = 0.045
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	render = RenderNivel.new()
	render.name = "Nivel"
	add_child(render)

	cuerpo = Node3D.new()
	cuerpo.name = "Jugador"
	add_child(cuerpo)
	sprite_jugador = Sprite3D.new()
	# hojas direccionales del jugador (down/up/side, 4 frames cada una)
	for dir_tex in ["down", "up", "side"]:
		var ruta := "res://assets/sprites/player_%s.png" % dir_tex
		if ResourceLoader.exists(ruta):
			_tex_jugador[dir_tex] = load(ruta)
	var tex: Variant = _tex_jugador.get("down")
	if tex != null:
		sprite_jugador.texture = tex
		sprite_jugador.hframes = maxi(1, (tex as Texture2D).get_width() / (tex as Texture2D).get_height())
	sprite_jugador.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite_jugador.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite_jugador.pixel_size = 1.6 / 48.0
	sprite_jugador.position = Vector3(0, 0.85, 0)
	sprite_jugador.shaded = true
	sprite_jugador.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	cuerpo.add_child(sprite_jugador)

	luz_cercana = OmniLight3D.new()
	luz_cercana.omni_range = 7.0
	luz_cercana.light_energy = 0.7
	luz_cercana.light_color = Color(1, 0.94, 0.75)
	luz_cercana.position = Vector3(0, 1.9, 0)
	cuerpo.add_child(luz_cercana)

	linterna = SpotLight3D.new()
	linterna.spot_range = 11.0
	linterna.spot_angle = 24.0
	linterna.light_energy = 3.2
	linterna.light_color = Color(1, 0.97, 0.85)
	linterna.position = Vector3(0, 1.25, 0)
	linterna.visible = false
	cuerpo.add_child(linterna)

	camara = Camera3D.new()
	camara.fov = 70
	add_child(camara)

	audio_ambiente = AudioStreamPlayer.new()
	audio_ambiente.volume_db = -8
	add_child(audio_ambiente)
	audio_sfx = AudioStreamPlayer.new()
	add_child(audio_sfx)
	_susurro_player = AudioStreamPlayer.new()
	add_child(_susurro_player)

	# zumbido fluorescente continuo (regla "zumbido", Level 0): se activa al
	# entrar en un nivel que lo declare y se rellena en _process().
	_zumbido_player = AudioStreamPlayer.new()
	_zumbido_player.name = "Zumbido"
	add_child(_zumbido_player)

	hud = Hud.new()
	add_child(hud)

## Atmósfera data-driven desde la ficha del nivel: el ambiente y la niebla
## toman la paleta wiki (fondo/luz). Las reglas se combinan (no son excluyentes):
## "niebla" espesa, "calor" tiñe de rojizo, juntas = garaje brumoso y cálido.
func _ambiente_visual(def: Dictionary) -> void:
	if _env == null:
		return
	var p: Dictionary = def.get("paleta", {})
	var fondo := Color(str(p.get("fondo"))) if p.get("fondo") is String else Color(0.02, 0.02, 0.015)
	var luz := Color(str(p.get("luz"))) if p.get("luz") is String else Color(1, 0.93, 0.7)
	_env.background_color = fondo
	_env.ambient_light_color = luz.lerp(Color(0.5, 0.5, 0.5), 0.35)
	var reglas: Array = def.get("reglas", [])
	
	# niebla: espesa la atmósfera, reduce visibilidad
	if reglas.has("niebla"):
		_env.fog_density = 0.085
		_env.fog_light_color = luz.darkened(0.75)
		_env.ambient_light_energy = 0.42
	# calor: tiñe la niebla de tonos rojizos/cálidos (maquinaria, vapor)
	if reglas.has("calor"):
		_env.fog_light_color = _env.fog_light_color.lerp(Color(0.25, 0.06, 0.03), 0.45)
		_env.ambient_light_color = _env.ambient_light_color.lerp(Color(0.7, 0.3, 0.15), 0.3)
	# sin niebla ni calor: atmósfera por defecto
	if not reglas.has("niebla") and not reglas.has("calor"):
		_env.fog_density = 0.045
		_env.fog_light_color = fondo.lightened(0.06)
		_env.ambient_light_energy = 0.55
	
	# el fondo se funde con la niebla: la distancia se pierde en bruma, nunca
	# en un "cielo" negro recortado sobre los muros
	_env.background_color = _env.fog_light_color
	luz_cercana.light_color = luz
	linterna.light_color = luz.lerp(Color.WHITE, 0.4)

func _sfx(nombre: String) -> void:
	for ext in ["wav", "mp3"]:
		var ruta := "res://assets/sounds/%s.%s" % [nombre, ext]
		if ResourceLoader.exists(ruta):
			audio_sfx.stream = load(ruta)
			audio_sfx.play()
			return

# ---------- zumbido fluorescente (wiki Level 0) ----------

## Activa/desactiva el zumbido según la regla "zumbido" del nivel. El generador
## es un AudioStreamGenerator que se rellena continuamente desde _process().
func _configurar_zumbido(def: Dictionary) -> void:
	var reglas: Array = def.get("reglas", [])
	var debe := reglas.has("zumbido")
	if debe and not _zumbido_activo:
		_zumbido_gen = ProceduralAudio.generador_zumbido()
		_zumbido_player.stream = _zumbido_gen
		# más fuerte que el fluorescente normal del menú: molesto, persistente
		_zumbido_player.volume_db = -9.0
		_zumbido_player.play()
		_zumbido_activo = true
	elif not debe and _zumbido_activo:
		_zumbido_player.stop()
		_zumbido_activo = false
		_zumbido_gen = null

## 60 Hz + armónicos + un poco de ruido de red eléctrica. La amplitud pulsa con
## un parpadeo lento y ocasionalmente cae con un apagón, como el fluorescente.
func _rellenar_zumbido(delta: float) -> void:
	var playback := _zumbido_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null or _zumbido_gen == null:
		return
	_flick_acum += delta
	var flick := 0.92 + 0.08 * sin(_flick_acum * 2.3)
	if fposmod(_flick_acum * 0.22, 1.0) < 0.025:
		flick = 0.5
	var n := int(ceil(delta * _zumbido_gen.mix_rate))
	var t := _hum_t
	var dt := 1.0 / _zumbido_gen.mix_rate
	for i in n:
		var s60 := sin(TAU * 60.0 * t)
		var s120 := sin(TAU * 120.0 * t) * 0.45
		var s240 := sin(TAU * 240.0 * t) * 0.15
		var ruido := (randf() * 2.0 - 1.0) * 0.05
		var muestra := ((s60 + s120 + s240) * 0.35 + ruido) * flick
		playback.push_frame(Vector2(muestra, muestra))
		t += dt
	_hum_t = fposmod(t, 1.0)

# ---------- mensajes de la Sala (el flujo de cliente.js) ----------

func _al_recibir(m: Dictionary) -> void:
	_cola.append(m)

func _process(delta: float) -> void:
	while not _cola.is_empty():
		_procesar(_cola.pop_front())
	if _zumbido_activo and _zumbido_gen != null:
		_rellenar_zumbido(delta)
	# Bombilla naranja de Manila Room: parpadea con el mismo flick que los
	# fluorescentes del resto del nivel (wiki: apagones también en Manila).
	if _luz_manila != null:
		var flick := 0.92 + 0.08 * sin(_flick_acum * 2.3)
		if fposmod(_flick_acum * 0.22, 1.0) < 0.025:
			flick = 0.5
		_luz_manila.light_energy = 0.8 * flick
	
	# --- Level 1 wiki: apagones y luces inestables ---
	if _reglas_ambiente.has("apagones") or _reglas_ambiente.has("luces_inestables"):
		var base_energy := 0.42 if _reglas_ambiente.has("niebla") else (0.55 if not _reglas_ambiente.has("calor") else 0.5)
		var flick_extra := 1.0
		
		# luces_inestables: parpadeo más agresivo que el zumbido normal de Level 0
		if _reglas_ambiente.has("luces_inestables"):
			flick_extra = 0.85 + 0.15 * sin(_flick_acum * 5.7)
			if fposmod(_flick_acum * 0.37, 1.0) < 0.04:
				flick_extra = 0.35
		
		# apagones: la wiki dice que duran «minutos, incluso días».
		# En juego: 40-180 segundos cada 90-300 segundos (jugable pero atmosférico).
		if _reglas_ambiente.has("apagones"):
			_apagon_cooldown -= delta
			if _apagon_restante > 0.0:
				_apagon_restante -= delta
				if not _apagon_activo:
					_apagon_activo = true
					_niebla_color_base = _env.fog_light_color if _env != null else Color.BLACK
				flick_extra = 0.04  # casi oscuridad total
			elif _apagon_activo:
				_apagon_activo = false
				if _env != null:
					_env.fog_light_color = _niebla_color_base
			else:
				if _apagon_cooldown <= 0.0:
					_apagon_restante = randf_range(40.0, 180.0)
					_apagon_cooldown = randf_range(90.0, 300.0)
		
		if _env != null:
			_env.ambient_light_energy = base_energy * flick_extra
			# durante el apagón también oscurecemos la niebla
			if _apagon_activo:
				_env.fog_light_color = _niebla_color_base.darkened(0.85)

func _procesar(m: Dictionary) -> void:
	match m.t:
		"bienvenida", "nivel":
			if str(m.nivel) != self.nivel_id_catalogo:
				LevelManager.ir_a_escena_de_nivel(str(m.nivel))
				return
			sala = _sala_de(str(m.nivel))
			_sec = int(m.sec)
			px = float(m.x)
			py = float(m.y)
			rot = float(m.rot)
			if self.nivel_id_catalogo == "the-hub":
				rot = 0.0  # Carretera este-oeste: mirar al este
			_con_oxigeno = (sala.def.get("reglas", []) as Array).has("respiracion_acuatica")
			_aplicar_botin_guardado()
			render.construir(sala.map, sala.def)
			render.poner_entidades(m.get("ents", []))
			_luz_manila = render.find_child("LuzManila", true, false) as OmniLight3D
			if m.get("retorno") != null:
				render.crear_salida_retorno(m.retorno)
			if not m.get("sinTarjeta", false):
				hud.tarjeta_nivel(sala.def)
			if m.get("via") != null:
				hud.log_msg(str(m.via))
			var cam: Variant = m.get("caminata")
			hud.caminata(0 if cam == null else int(cam.pasos), 0 if cam == null else int(cam.objetivo))
			hud.estado(float(m.salud), float(m.sed), float(m.cordura), float(m.oxigeno), _con_oxigeno)
			hud.manos(m.manos)
			hud.actualizar_barra_inv(m.inv)
			hud.oferta(null)
			_bloqueado_muerte = false
			hud.muerte("", false)
			_ambiente_de_nivel(str(m.nivel))
			_ambiente_visual(sala.def)
			_reglas_ambiente = (sala.def.get("reglas", []) as Array)
			_configurar_zumbido(sala.def)
		"aviso", "aviso2":
			hud.log_msg(str(m.txt), "danger" if m.t == "aviso2" else "event")
		"oferta":
			hud.oferta(m)
		"caminata":
			hud.caminata(int(m.pasos), int(m.objetivo))
		"dado":
			hud.dado(int(m.valor), bool(m.exito))
			_sfx("dado")
		"canal":
			hud.canal(true)
		"canalFin":
			hud.canal(false)
		"abierto":
			render.abrir_salida(int(m.i))
			_sfx("golpe")
		"salud":
			jug.salud = float(m.valor)
			hud.estado(jug.salud, float(jug.sed), float(jug.cordura), float(jug.oxigeno), _con_oxigeno)
			if jug.salud < float(jug.get("_saludPrev", 100)):
				_sfx("dano")
			jug["_saludPrev"] = jug.salud
		"estado":
			jug.salud = float(m.salud)
			jug.sed = float(m.sed)
			jug.cordura = float(m.cordura)
			jug.oxigeno = float(m.oxigeno)
			hud.estado(jug.salud, jug.sed, jug.cordura, jug.oxigeno, _con_oxigeno)
		"inv":
			jug.inv = m.inv
			jug.manos = m.manos
			jug.equipo = m.equipo
			hud.manos(m.manos)
			hud.actualizar_barra_inv(m.inv)
			if hud.mochila_abierta:
				hud.mochila(jug, true)
		"mueve":
			if int(m.id) == int(jug.id):
				px = float(m.x)
				py = float(m.y)
				_sec = int(m.sec)
		"esconde":
			if int(m.id) == int(jug.id):
				cuerpo.visible = not bool(m.si)
		"luzDe":
			if int(m.id) == int(jug.id):
				linterna.visible = bool(m.si)
		"muere":
			if int(m.id) == int(jug.id):
				_bloqueado_muerte = true
				hud.muerte(str(m.causa), true)
				_sfx("entidades/smiler" if str(m.causa).contains("Smiler") else "muerte")
		"botinReset":
			_botin.erase(str(m.semilla))
			_guardar_botin()
		"itemSuelto":
			(sala.map.items as Array).append({"x": m.x, "y": m.y, "id": m.id,
				"taken": false, "recien": m.get("recien", false)})
			render.refrescar_items()
		"pos":
			for e: Array in m.get("e", []):
				render.mover_entidad(int(e[0]), float(e[1]), float(e[2]))
		"entPrep":
			render.entidad_evento(int(m.uid), "prep")
		"entFalla":
			render.entidad_evento(int(m.uid), "normal")
		"entHit":
			render.entidad_evento(int(m.uid), "hit")
		"entRevela":
			render.entidad_evento(int(m.uid), "revela")
		"entMuere":
			render.entidad_evento(int(m.uid), "muere")
		"entAtaca":
			render.entidad_evento(int(m.uid), "normal")
			_sfx("golpe")
		"remodel":
			hud.log_msg("Un crujido recorre el nivel. Algo se ha… reorganizado.", "danger")
			render.construir(sala.map, sala.def)
			render.poner_entidades(sala.estado_dinamico().ents)
			_luz_manila = render.find_child("LuzManila", true, false) as OmniLight3D

func _sala_de(nivel: String) -> Sala:
	for s: Sala in Salas.todas():
		if s.jugadores.has(int(jug.id)) and s.nivelId == nivel:
			return s
	return sala

func _ambiente_de_nivel(nivel: String) -> void:
	audio_ambiente.stop()
	var ruta := "res://assets/sounds/niveles/%s.mp3" % nivel
	if ResourceLoader.exists(ruta):
		var stream: AudioStream = load(ruta)
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		audio_ambiente.stream = stream
		audio_ambiente.play()

# ---------- movimiento + cámara + tick ----------

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= (ev as InputEventMouseMotion).relative.x * 0.004
	elif ev is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(ev: InputEvent) -> void:
	# ESC: cerrar mochila/oferta → liberar ratón → volver al menú.
	# (ui_cancel está vaciado en project.godot; se maneja la tecla directa.)
	if ev is InputEventKey and ev.is_pressed() and not ev.is_echo() \
			and (ev as InputEventKey).physical_keycode == KEY_ESCAPE:
		if _bloqueado_muerte:
			LevelManager.ir_al_menu()
		elif hud.mochila_abierta:
			hud.mochila(jug, false)
		elif hud.oferta_activa != null:
			sala.cruzar(jug, false)
			hud.oferta(null)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			LevelManager.ir_al_menu()
		return
	if _bloqueado_muerte:
		return
	if ev.is_action_pressed("accion"):
		if not _registrar_local():
			sala.accion(jug)
	elif ev.is_action_pressed("usar_izq"):
		if hud.mochila_abierta:
			sala.mochila(jug, {"que": "desequipar", "mano": 0})
			hud.mochila(jug, true)
		else:
			sala.usar(jug, 0)
	elif ev.is_action_pressed("usar_der"):
		if hud.mochila_abierta:
			sala.mochila(jug, {"que": "desequipar", "mano": 1})
			hud.mochila(jug, true)
		else:
			sala.usar(jug, 1)
	elif ev.is_action_pressed("linterna"):
		sala.luz(jug, not jug.luz)
	elif ev.is_action_pressed("mochila"):
		hud.mochila(jug, not hud.mochila_abierta)
	elif ev.is_action_pressed("ui_accept"):
		if hud.oferta_activa != null:
			sala.cruzar(jug, true)
			hud.oferta(null)
	elif ev.is_action_pressed("ui_cancel"):
		if hud.mochila_abierta:
			hud.mochila(jug, false)
		elif hud.oferta_activa != null:
			sala.cruzar(jug, false)
			hud.oferta(null)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif ev is InputEventKey and ev.is_pressed() and not ev.is_echo():
		var k := ev as InputEventKey
		if k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_6:
			var slot := int(k.physical_keycode - KEY_1)
			_accion_mochila(slot, k.shift_pressed)

func _accion_mochila(slot: int, tirar: bool) -> void:
	if slot >= (jug.inv as Array).size():
		return
	if tirar:
		sala.mochila(jug, {"que": "tirar", "slot": slot})
	else:
		var d: Dictionary = Catalogo.objetos.get(jug.inv[slot], {})
		if d.get("equipo") != null:
			sala.mochila(jug, {"que": "ponerEquipo", "slot": slot})
		elif d.get("manos") != null:
			sala.mochila(jug, {"que": "equipar", "slot": slot})
		else:
			sala.mochila(jug, {"que": "usarItem", "slot": slot})
	hud.mochila(jug, true)

func _physics_process(delta: float) -> void:
	# tick de mundo a 20 Hz, como el bucle de net/local.js
	_acum_tick += delta
	while _acum_tick >= TICK_MUNDO:
		_acum_tick -= TICK_MUNDO
		Salas.tick_todas(Salas.msec())

	if hud == null or sala == null or jug.is_empty():
		return

	_tick_tiempo += delta
	var cordura := float(jug.get("cordura", 100.0))
	if cordura < 45.0:
		var intensidad := clampf((45.0 - cordura) / 45.0, 0.0, 1.0)
		camara.h_offset = sin(_tick_tiempo * 12.0) * 0.025 * intensidad
		camara.v_offset = cos(_tick_tiempo * 14.0) * 0.025 * intensidad
		if cordura < 30.0:
			_aluc_timer -= delta
			if _aluc_timer <= 0.0:
				_aluc_timer = randf_range(6.0, 18.0)
				_susurro_player.stream = ProceduralAudio.susurro()
				_susurro_player.volume_db = -12.0 + intensidad * 6.0
				_susurro_player.play()
	else:
		camara.h_offset = 0.0
		camara.v_offset = 0.0

	var bloqueado: bool = _bloqueado_muerte or hud.mochila_abierta or hud.tarjeta_visible \
		or jug.escondido != null
	_moviendo = false
	if not bloqueado:
		var ix := Input.get_action_strength("mover_der") - Input.get_action_strength("mover_izq")
		var iy := Input.get_action_strength("mover_adelante") - Input.get_action_strength("mover_atras")
		if ix != 0.0 or iy != 0.0:
			# WASD relativo a la cámara (v25): adelante = (-sin yaw, -cos yaw)
			var dx := -sin(_yaw) * iy + cos(_yaw) * ix
			var dy := -cos(_yaw) * iy - sin(_yaw) * ix
			var nueva := Fisica.mover(sala.map.grid, px, py, dx, dy, delta)
			var recorrido := Fisica.dist(px, py, nueva[0], nueva[1])
			px = nueva[0]
			py = nueva[1]
			rot = atan2(dx, -dy)
			_moviendo = recorrido > 0.001
			_anim_dist += recorrido
			_paso_acum += recorrido
			if _paso_acum >= 0.75: # paso sonoro (v25)
				_paso_acum = 0.0
				_sfx("paso")
		sala.posicion(jug, {"x": px, "y": py, "rot": rot, "sec": _sec})
		_recoger_suelo()
		
		# Level 0 wiki: enchufes que se desmoronan al contacto (expedition log).
		# Pequeña probabilidad de daño al pasar cerca de un enchufe en la pared.
		if _zumbido_activo:
			_enchufe_tick += delta
			if _enchufe_tick >= 3.0:
				_enchufe_tick = 0.0
				var props: Array = sala.map.get("props", [])
				for p: Dictionary in props:
					if str(p.id) != "enchufe":
						continue
					var dist := Vector2(float(p.x) + 0.5, float(p.y) + 0.5).distance_to(Vector2(px + 0.5, py + 0.5))
					if dist < 1.5 and randf() < 0.12:
						var dano := randi_range(2, 5)
						sala.herir(jug, dano, "enchufe_quebradizo")
						hud.log_msg("El enchufe se desmorona al pasar cerca. Sientes algo caliente bajando por la cara.", "danger")
						_sfx("dano")
						break
		
		# Level 1 wiki: barras de refuerzo (rebar) oxidadas que sobresalen
		# de las paredes. Al rozarlas, causan heridas y posible tétanos.
		if _reglas_ambiente.has("apagones"):
			var tx := floori(px + 0.5)
			var ty := floori(py + 0.5)
			var g: MapGen.Grid = sala.map.grid
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := tx + d.x
				var ny := ty + d.y
				if MapGen.at(g, nx, ny) == MapGen.PARED:
					if randf() < 0.0008:  # ~5% por segundo junto a una pared
						var dano := randi_range(1, 4)
						sala.herir(jug, dano, "barra_oxidada")
						hud.log_msg("Una barra de refuerzo oxidada te rasga al pasar. El tétanos es una preocupación real aquí.", "danger")
						_sfx("dano")
						break

	# nodo visual del jugador y cámara
	cuerpo.position = Vector3(px + 0.5, 0, py + 0.5)
	linterna.rotation.y = -rot
	linterna.rotation.x = -0.08
	var foco := cuerpo.position + Vector3(0, 1.3, 0)
	var deseo := foco + Vector3(sin(_yaw), 0, cos(_yaw)) * DIST_CAM + Vector3(0, ALTURA_CAM - 1.3, 0)
	# la cámara no atraviesa muros: acorta hasta el primer choque
	var dist_libre := DIST_CAM
	var pasos := 8
	for i in range(1, pasos + 1):
		var f := float(i) / pasos
		var p := foco.lerp(deseo, f)
		if Fisica.choca(sala.map.grid, p.x - 0.5, p.z - 0.5, 0.2):
			dist_libre = DIST_CAM * (float(i - 1) / pasos)
			break
	var cam_pos := foco + (deseo - foco).normalized() * maxf(0.6, dist_libre)
	camara.position = cam_pos
	camara.look_at(foco)
	_actualizar_sprite_jugador()

## Sprite direccional del jugador respecto a la cámara: de espaldas (up),
## de frente (down) o de perfil (side, volteado según el lado), con la
## animación de 4 frames avanzando por distancia recorrida.
func _actualizar_sprite_jugador() -> void:
	if _tex_jugador.is_empty():
		return
	# Quieto: conserva la última orientación (orbitar la cámara alrededor del
	# personaje parado NO debe hacerle "andar hacia atrás" ni cambiar de cara).
	if not _moviendo:
		sprite_jugador.frame = 0
		return
	var rel := wrapf(rot - _yaw, -PI, PI)
	var clave := "side"
	var flip := rel < 0.0
	if absf(rel) < PI * 0.3:
		clave = "up"      # se aleja de la cámara: de espaldas
		flip = false
	elif absf(rel) > PI * 0.7:
		clave = "down"    # camina hacia la cámara: de frente
		flip = false
	var tex: Texture2D = _tex_jugador.get(clave, _tex_jugador.get("down"))
	if tex != null and sprite_jugador.texture != tex:
		sprite_jugador.texture = tex
		sprite_jugador.hframes = maxi(1, tex.get_width() / tex.get_height())
	sprite_jugador.flip_h = flip
	sprite_jugador.frame = int(_anim_dist * 2.2) % maxi(1, sprite_jugador.hframes)

## Materializa una entidad del catálogo a 4-8 tiles del spawn (selftest).
func _inyectar_entidad(id: String) -> void:
	var s: Vector2i = sala.map.spawn
	for r in range(4, 9):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if not Salas.es_transitable(sala.map, s.x + dx, s.y + dy):
					continue
				var nuevas: Array[Dictionary] = Entidades.crear(
					{"entitySpawns": [{"x": s.x + dx, "y": s.y + dy, "id": id}]},
					Catalogo.entidades, Rng.crear("debug::" + id))
				nuevas[0].uid = 9000 + sala.entidades.size()
				sala.entidades.append(nuevas[0])
				return

# ---------- botín individual (v25, port de cliente.js) ----------

func _roll_dice() -> int:
	var d := Rng.crear("%s::dado::%d" % [sala.semilla, int(jug.dadosN)]).entero(1, 20)
	jug.dadosN = int(jug.dadosN) + 1
	if (jug.inv as Array).has("trebol") or (jug.manos as Array).has("trebol"):
		d = mini(20, d + 2)
	return d

func _pool_cajas() -> Array:
	var basicos := ["agua_almendras", "agua_almendras", "botiquin", "linterna", "tuberia", "trebol"]
	var pool := basicos.duplicate()
	for id: String in Catalogo.objetos:
		if not basicos.has(id):
			pool.append(id)
	return pool

func _registrar_local() -> bool:
	if jug.escondido != null:
		return false
	var props: Array = sala.map.get("props", [])
	for i in props.size():
		var p: Dictionary = props[i]
		if not p.get("contenedor", false) or p.get("registrado", false):
			continue
		if Fisica.dist(float(p.x), float(p.y), px, py) > 1.2:
			continue
		p.registrado = true
		_apuntar_botin("%d,%d" % [int(p.x), int(p.y)])
		render.marcar_registrado(i)
		_sfx("registrar")
		var d := _roll_dice()
		hud.dado(d, d >= 14)
		if d >= 14:
			var pool := _pool_cajas()
			var idx := mini(pool.size() - 1,
				floori(float(d - 14) / 7.0 * pool.size() + (randi() % 3)))
			var id: String = pool[idx]
			if (jug.inv as Array).size() >= 6:
				hud.log_msg("Dado: %d. Hay algo útil… pero no te cabe nada más." % d)
			else:
				hud.log_msg("Dado: %d. Encuentras: %s." % [d,
					Catalogo.objetos.get(id, {}).get("nombre", id)], "good")
				_encolar_loot(id)
		elif d >= 7:
			hud.log_msg("Dado: %d. Vacío. Solo polvo y papel amarillento." % d)
		else:
			hud.log_msg("Dado: %d. Algo se escurre entre tus dedos. Retrocedes de golpe." % d, "danger")
		return true
	return false

## la Sala impone cadencia de 1.2 s por alta de botín: se espacian los envíos
func _encolar_loot(id: String) -> void:
	var ahora := Time.get_ticks_msec()
	var cuando := maxi(ahora, _loot_listo + 1300)
	_loot_listo = cuando
	if cuando <= ahora:
		sala.loot(jug, id)
	else:
		get_tree().create_timer((cuando - ahora) / 1000.0).timeout.connect(
			func() -> void: sala.loot(jug, id))

func _recoger_suelo() -> void:
	var ahora := Time.get_ticks_msec()
	if ahora - _suelo_t < 150:
		return
	_suelo_t = ahora
	var items: Array = sala.map.get("items", [])
	for it: Dictionary in items:
		if it.get("taken", false):
			continue
		var d := Fisica.dist(float(it.x), float(it.y), px, py)
		if it.get("recien", false):
			if d > 0.8:
				it.recien = false
			continue
		if d >= 0.5:
			continue
		if (jug.inv as Array).size() >= 6:
			continue
		it.taken = true
		_apuntar_botin("suelo:%d,%d" % [int(it.x), int(it.y)])
		render.refrescar_items()
		hud.log_msg("Recoges: %s." % Catalogo.objetos.get(it.id, {}).get("nombre", it.id), "good")
		_encolar_loot(str(it.id))
		break # uno por escaneo

# ---------- persistencia del botín por semilla (el localStorage del original) ----------

func _cargar_botin() -> void:
	var ruta := "user://botin.json"
	if FileAccess.file_exists(ruta):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ruta))
		if d is Dictionary:
			_botin = d

func _guardar_botin() -> void:
	var f := FileAccess.open("user://botin.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_botin))

func _apuntar_botin(clave: String) -> void:
	var lista: Array = _botin.get(sala.semilla, [])
	lista.append(clave)
	_botin[sala.semilla] = lista.slice(maxi(0, lista.size() - 400))
	_guardar_botin()

func _aplicar_botin_guardado() -> void:
	var lista: Array = _botin.get(sala.semilla, [])
	if lista.is_empty():
		return
	for p: Dictionary in sala.map.get("props", []):
		if p.get("contenedor", false) and lista.has("%d,%d" % [int(p.x), int(p.y)]):
			p.registrado = true
	for it: Dictionary in sala.map.get("items", []):
		if lista.has("suelo:%d,%d" % [int(it.x), int(it.y)]):
			it.taken = true
