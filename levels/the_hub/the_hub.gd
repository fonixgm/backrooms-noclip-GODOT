extends Nivel3D

## The Hub — Nivel anómalo / Nexo de túneles
## Carretera de asfalto, luces que viran al rojo, puertas con llave.

func _init() -> void:
	nivel_id_catalogo = "the-hub"

var _luz_roja_activa := false
var _luz_roja_timer := 0.0
var _luz_roja_duracion := 0.0
var _luz_cooldown := 0.0
var _luz_naranja := Color("#ffb050")
var _luz_roja := Color("#cc2020")
var _color_actual := Color.WHITE
var _vapor_timer := 0.0   # aliento visible (bajo cero)

func _ready() -> void:
	super._ready()
	_luz_roja_timer = randf_range(90.0, 180.0)
	_luz_cooldown = 0.0
	_color_actual = _luz_naranja

func _process(delta: float) -> void:
	super._process(delta)
	_procesar_luces_rojas(delta)
	_procesar_vapor(delta)

## Ciclo de luces rojas: las lámparas naranjas viran al rojo 30-90s
func _procesar_luces_rojas(delta: float) -> void:
	if not _reglas_ambiente.has("luces_rojas"):
		return
	_luz_roja_timer -= delta
	if _luz_roja_activa:
		_luz_roja_duracion -= delta
		if _luz_roja_duracion <= 0.0:
			_luz_roja_activa = false
			_luz_cooldown = randf_range(60.0, 120.0)
			_color_actual = _luz_naranja
			_aplicar_luz()
	else:
		if _luz_cooldown > 0.0:
			_luz_cooldown -= delta
		elif _luz_roja_timer <= 0.0:
			_luz_roja_activa = true
			_luz_roja_duracion = randf_range(30.0, 90.0)
			_color_actual = _luz_roja
			_aplicar_luz()
			_luz_roja_timer = randf_range(90.0, 180.0)
	
	# Transición gradual del color
	var target: Color = _luz_roja if _luz_roja_activa else _luz_naranja
	if abs(_color_actual.r - target.r) > 0.01:
		_color_actual = _color_actual.lerp(target, delta * 2.5)
		_aplicar_luz()

func _aplicar_luz() -> void:
	if not is_instance_valid(render):
		return
	var w: WorldEnvironment = render.get_node_or_null("WorldEnvironment") if render else null
	if w and w.environment:
		w.environment.ambient_light_color = _color_actual
		if _luz_roja_activa:
			w.environment.volumetric_fog_albedo = _color_actual.darkened(0.4)

## Aliento visible por temperatura bajo cero (~cada 3s)
func _procesar_vapor(delta: float) -> void:
	if not _reglas_ambiente.has("bajo_cero"):
		return
	_vapor_timer += delta
	if _vapor_timer >= 3.0:
		_vapor_timer = 0.0
		_emitir_vapor()

func _emitir_vapor() -> void:
	if not is_instance_valid(cuerpo):
		return
	var p: GPUParticles3D = GPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.lifetime = 1.5
	p.amount = 6
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.spread = 25.0
	mat.gravity = Vector3(0, 0.25, 0)
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.6
	mat.scale_min = 0.06
	mat.scale_max = 0.18
	mat.color = Color(1.0, 1.0, 1.0, 0.3)
	p.process_material = mat
	p.position = cuerpo.position + Vector3(0, 0.7, 0)
	add_child(p)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
