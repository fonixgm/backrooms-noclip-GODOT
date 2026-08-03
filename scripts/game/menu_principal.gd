## MenuPrincipal — pantalla de título del juego (port de la portada web).
## Fondo panorámico del Level 0 con paneo lento + viñeta, título con parpadeo
## fluorescente, cita de la wiki y botones: Hacer no-clip (jugar), Niveles
## (selector desde el registro del LevelManager) y Salir.
## Zumbido fluorescente procedural de fondo (ProceduralAudio).
extends Control

const CITAS: Array[String] = [
	"«Si no tienes cuidado y haces no-clip fuera de la realidad, acabarás aquí.»",
	"«Solo pasillos que no llevan a ninguna parte, y el zumbido.»",
	"«La niebla nunca se disipa del todo. Y a veces la niebla te mira.»",
]

var _fondo: TextureRect
var _titulo: Label
var _cita: Label
var _panel_niveles: PanelContainer
var _hum_player: AudioStreamPlayer
var _hum_gen: AudioStreamGenerator
var _hum_t := 0.0
var _t := 0.0

func _ready() -> void:
	_montar_fondo()
	_montar_ui()
	_montar_audio()

func _fuente(tam: int, etiqueta: Label) -> void:
	var f: Font = load("res://assets/fonts/PressStart2P-Regular.ttf") if ResourceLoader.exists("res://assets/fonts/PressStart2P-Regular.ttf") else null
	if f != null:
		etiqueta.add_theme_font_override("font", f)
	etiqueta.add_theme_font_size_override("font_size", tam)

func _montar_fondo() -> void:
	var negro := ColorRect.new()
	negro.name = "FondoNegro"
	negro.color = Color(0.02, 0.018, 0.008)
	negro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(negro)
	_fondo = TextureRect.new()
	_fondo.name = "Panorama"
	if ResourceLoader.exists("res://assets/generated/menu_fondo_backrooms_frame_0.png"):
		_fondo.texture = load("res://assets/generated/menu_fondo_backrooms_frame_0.png")
	_fondo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	# margen extra para el paneo lento
	_fondo.offset_left = -40
	_fondo.offset_right = 40
	_fondo.offset_top = -24
	_fondo.offset_bottom = 24
	_fondo.modulate = Color(0.72, 0.68, 0.55)
	add_child(_fondo)
	var vineta := TextureRect.new()
	vineta.name = "Vineta"
	
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var c := Vector2(127.5, 127.5)
	for y in 256:
		for x in 256:
			var d := Vector2(x, y).distance_to(c) / 128.0
			var v := clampf(d - 0.45, 0.0, 1.0)
			v = pow(v, 1.6)
			img.set_pixel(x, y, Color(0, 0, 0, v))
	
	vineta.texture = ImageTexture.create_from_image(img)
	vineta.stretch_mode = TextureRect.STRETCH_SCALE
	vineta.set_anchors_preset(Control.PRESET_FULL_RECT)
	vineta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vineta.modulate = Color(1, 1, 1, 0.75)
	add_child(vineta)

func _montar_ui() -> void:
	var centro := VBoxContainer.new()
	centro.name = "Centro"
	centro.set_anchors_preset(Control.PRESET_CENTER)
	centro.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centro.grow_vertical = Control.GROW_DIRECTION_BOTH
	centro.alignment = BoxContainer.ALIGNMENT_CENTER
	centro.add_theme_constant_override("separation", 14)
	add_child(centro)

	var sobre := Label.new()
	sobre.text = "B A C K R O O M S"
	sobre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sobre.modulate = Color(0.92, 0.85, 0.55, 0.9)
	_fuente(26, sobre)
	centro.add_child(sobre)
	_titulo = sobre

	var sub := Label.new()
	sub.text = "N O C L I P"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.75, 0.68, 0.42, 0.8)
	_fuente(12, sub)
	centro.add_child(sub)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 18)
	centro.add_child(sep)

	centro.add_child(_boton("HACER NO-CLIP", Callable(self, "_on_jugar")))
	centro.add_child(_boton("NIVELES", Callable(self, "_on_niveles")))
	centro.add_child(_boton("SALIR", Callable(self, "_on_salir")))

	_cita = Label.new()
	_cita.name = "Cita"
	_cita.text = CITAS[randi() % CITAS.size()]
	_cita.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cita.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cita.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cita.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cita.offset_top = -64
	_cita.offset_left = -320
	_cita.offset_right = 320
	_cita.modulate = Color(0.85, 0.78, 0.55, 0.55)
	_fuente(8, _cita)
	add_child(_cita)

	var semilla := Label.new()
	semilla.name = "Semilla"
	semilla.text = "Semilla %s" % LevelManager.obtener_seed()
	semilla.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	semilla.offset_top = -28
	semilla.offset_left = 12
	semilla.modulate = Color(1, 1, 1, 0.3)
	_fuente(8, semilla)
	add_child(semilla)

	_montar_panel_niveles()

func _boton(texto: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(280, 40)
	b.focus_mode = Control.FOCUS_ALL
	var f: Font = load("res://assets/fonts/PressStart2P-Regular.ttf") if ResourceLoader.exists("res://assets/fonts/PressStart2P-Regular.ttf") else null
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.03, 0.85)
	sb.border_color = Color(0.62, 0.55, 0.32, 0.7)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	var sb_hover: StyleBoxFlat = sb.duplicate()
	sb_hover.bg_color = Color(0.14, 0.12, 0.05, 0.9)
	sb_hover.border_color = Color(0.95, 0.87, 0.55, 0.9)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("focus", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	b.add_theme_color_override("font_color", Color(0.92, 0.85, 0.55))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.7))
	b.pressed.connect(cb)
	return b

## Selector de niveles: se alimenta del REGISTRO del LevelManager.
func _montar_panel_niveles() -> void:
	_panel_niveles = PanelContainer.new()
	_panel_niveles.name = "PanelNiveles"
	_panel_niveles.visible = false
	_panel_niveles.set_anchors_preset(Control.PRESET_CENTER)
	_panel_niveles.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel_niveles.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.028, 0.015, 0.96)
	sb.border_color = Color(0.62, 0.55, 0.32, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(18)
	_panel_niveles.add_theme_stylebox_override("panel", sb)
	add_child(_panel_niveles)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	_panel_niveles.add_child(caja)
	var t := Label.new()
	t.text = "NIVELES"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.modulate = Color(0.92, 0.85, 0.55)
	_fuente(12, t)
	caja.add_child(t)
	# Niveles del juego 3D (los del catálogo JSON del piloto)
	for id: String in ["level-0", "level-1", "level-2", "the-hub", "level-188"]:
		var ficha: Dictionary = Catalogo.nivel(id)
		var nombre: String = str(ficha.get("nombre", id))
		caja.add_child(_boton(nombre, Callable(self, "_on_jugar_3d").bind(id)))
	caja.add_child(_boton("VOLVER", Callable(self, "_on_cerrar_niveles")))

func _montar_audio() -> void:
	_hum_player = AudioStreamPlayer.new()
	_hum_player.name = "Hum"
	_hum_player.volume_db = -14.0
	_hum_gen = ProceduralAudio.generador_zumbido()
	_hum_player.stream = _hum_gen
	add_child(_hum_player)
	_hum_player.play()

func _process(delta: float) -> void:
	_t += delta
	_rellenar_zumbido(delta)
	# paneo lento del panorama
	if _fondo != null:
		_fondo.position.x = sin(_t * 0.08) * 30.0
		_fondo.position.y = cos(_t * 0.06) * 14.0
	# parpadeo fluorescente del título
	if _titulo != null:
		var flick := 0.78 + 0.22 * sin(_t * 11.0)
		if fposmod(_t * 0.5, 1.0) < 0.05:
			flick = 0.35
		_titulo.modulate.a = clampf(0.55 + 0.45 * flick, 0.0, 1.0)

func _rellenar_zumbido(delta: float) -> void:
	var playback := _hum_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var n := int(ceil(delta * _hum_gen.mix_rate))
	var t := _hum_t
	for i in n:
		var s60 := sin(TAU * 60.0 * t)
		var s120 := sin(TAU * 120.0 * t) * 0.45
		var muestra := (s60 + s120) * 0.35
		playback.push_frame(Vector2(muestra, muestra))
		t += 1.0 / _hum_gen.mix_rate
	_hum_t = fposmod(t, 1.0)

func _on_jugar() -> void:
	LevelManager.jugar_3d("level-0")

func _on_jugar_3d(id: String) -> void:
	LevelManager.jugar_3d(id)

func _on_niveles() -> void:
	_panel_niveles.visible = true

func _on_cerrar_niveles() -> void:
	_panel_niveles.visible = false

func _on_cargar_nivel(id: String) -> void:
	LevelManager.cargar_nivel(id)

func _on_salir() -> void:
	get_tree().quit()
