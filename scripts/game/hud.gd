## HUD mínimo del port: registro que se desvanece, estado vital, manos,
## oferta de salida, dado, progreso de caminata, tarjeta de nivel, mochila
## textual y pantalla de muerte. Fuente VT323 del original (licencia OFL).
class_name Hud
extends CanvasLayer

var fuente: FontFile
var log_caja: VBoxContainer
var estado_lbl: Label
var manos_lbl: Label
var oferta_panel: PanelContainer
var oferta_lbl: Label
var dado_lbl: Label
var caminata_lbl: Label
var canal_lbl: Label
var tarjeta: ColorRect
var tarjeta_titulo: Label
var tarjeta_clase: Label
var tarjeta_desc: Label
var mochila_panel: PanelContainer
var mochila_lbl: Label
var muerte_panel: ColorRect
var muerte_lbl: Label
var muerte_img: TextureRect

var oferta_activa: Variant = null
var mochila_abierta := false
var tarjeta_visible := false
var _dado_hasta := 0.0
var _tarjeta_hasta := 0.0

func _ready() -> void:
	fuente = load("res://assets/fonts/VT323-Regular.ttf")
	_construir()

func _lbl(tam: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", fuente)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l

func _construir() -> void:
	log_caja = VBoxContainer.new()
	log_caja.position = Vector2(14, 12)
	log_caja.size = Vector2(560, 300)
	add_child(log_caja)

	estado_lbl = _lbl(26)
	estado_lbl.position = Vector2(14, 0)
	estado_lbl.anchor_top = 1.0
	estado_lbl.anchor_bottom = 1.0
	estado_lbl.offset_top = -76
	add_child(estado_lbl)

	manos_lbl = _lbl(24, Color(0.9, 0.88, 0.7))
	manos_lbl.anchor_left = 0.0
	manos_lbl.anchor_right = 1.0
	manos_lbl.anchor_top = 1.0
	manos_lbl.anchor_bottom = 1.0
	manos_lbl.offset_top = -46
	manos_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(manos_lbl)

	caminata_lbl = _lbl(22, Color(0.75, 0.75, 0.75))
	caminata_lbl.anchor_left = 1.0
	caminata_lbl.anchor_right = 1.0
	caminata_lbl.offset_left = -300
	caminata_lbl.offset_top = 12
	# Ocultamos el contador de pasos explícito para no romper la inmersión
	caminata_lbl.visible = false
	add_child(caminata_lbl)

	canal_lbl = _lbl(30, Color(1, 0.8, 0.4))
	canal_lbl.anchor_left = 0.5
	canal_lbl.anchor_top = 0.6
	canal_lbl.offset_left = -120
	add_child(canal_lbl)

	oferta_panel = PanelContainer.new()
	oferta_panel.anchor_left = 0.5
	oferta_panel.anchor_right = 0.5
	oferta_panel.anchor_top = 1.0
	oferta_panel.anchor_bottom = 1.0
	oferta_panel.offset_left = -330
	oferta_panel.offset_right = 330
	oferta_panel.offset_top = -150
	oferta_panel.offset_bottom = -86
	oferta_lbl = _lbl(22, Color(0.95, 0.9, 0.7))
	oferta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	oferta_panel.add_child(oferta_lbl)
	oferta_panel.visible = false
	add_child(oferta_panel)

	dado_lbl = _lbl(84, Color(1, 0.92, 0.6))
	dado_lbl.anchor_left = 0.5
	dado_lbl.anchor_top = 0.35
	dado_lbl.offset_left = -60
	dado_lbl.visible = false
	add_child(dado_lbl)

	mochila_panel = PanelContainer.new()
	mochila_panel.anchor_left = 0.5
	mochila_panel.anchor_right = 0.5
	mochila_panel.anchor_top = 0.5
	mochila_panel.anchor_bottom = 0.5
	mochila_panel.offset_left = -300
	mochila_panel.offset_right = 300
	mochila_panel.offset_top = -220
	mochila_panel.offset_bottom = 220
	mochila_lbl = _lbl(22)
	mochila_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mochila_panel.add_child(mochila_lbl)
	mochila_panel.visible = false
	add_child(mochila_panel)

	# Ranuras de inventario SIEMPRE VISIBLES
	var inv_caja := HBoxContainer.new()
	inv_caja.name = "CajaInventario"
	inv_caja.anchor_left = 0.5
	inv_caja.anchor_top = 1.0
	inv_caja.anchor_right = 0.5
	inv_caja.anchor_bottom = 1.0
	inv_caja.offset_left = -200
	inv_caja.offset_top = -30
	inv_caja.offset_right = 200
	inv_caja.offset_bottom = -6
	inv_caja.alignment = BoxContainer.ALIGNMENT_CENTER
	inv_caja.add_theme_constant_override("separation", 16)
	add_child(inv_caja)
	
	for i in 6:
		var lbl := _lbl(20, Color(0.6, 0.6, 0.6))
		lbl.name = "Slot_%d" % i
		lbl.text = "[%d]-" % (i + 1)
		inv_caja.add_child(lbl)

	tarjeta = ColorRect.new()
	tarjeta.color = Color(0, 0, 0, 1)
	tarjeta.set_anchors_preset(Control.PRESET_FULL_RECT)
	var centro := VBoxContainer.new()
	centro.set_anchors_preset(Control.PRESET_CENTER)
	centro.offset_left = -420
	centro.offset_right = 420
	centro.alignment = BoxContainer.ALIGNMENT_CENTER
	tarjeta_titulo = _lbl(52, Color(1, 0.9, 0.55))
	tarjeta_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tarjeta_clase = _lbl(26, Color(0.7, 0.7, 0.7))
	tarjeta_clase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tarjeta_desc = _lbl(24, Color(0.85, 0.85, 0.8))
	tarjeta_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tarjeta_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centro.add_child(tarjeta_titulo)
	centro.add_child(tarjeta_clase)
	centro.add_child(tarjeta_desc)
	tarjeta.add_child(centro)
	tarjeta.visible = false
	add_child(tarjeta)

	muerte_panel = ColorRect.new()
	muerte_panel.color = Color(0.08, 0, 0, 0.92)
	muerte_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	muerte_img = TextureRect.new()
	muerte_img.set_anchors_preset(Control.PRESET_CENTER)
	muerte_img.offset_left = -96
	muerte_img.offset_right = 96
	muerte_img.offset_top = -230
	muerte_img.offset_bottom = -38
	muerte_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	muerte_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	muerte_img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	muerte_img.visible = false
	muerte_panel.add_child(muerte_img)
	muerte_lbl = _lbl(46, Color(0.95, 0.2, 0.2))
	muerte_lbl.set_anchors_preset(Control.PRESET_CENTER)
	muerte_lbl.offset_left = -400
	muerte_lbl.offset_right = 400
	muerte_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	muerte_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	muerte_panel.add_child(muerte_lbl)
	muerte_panel.visible = false
	add_child(muerte_panel)

func _process(delta: float) -> void:
	# el registro se desvanece a los ~5 s (v16)
	for hijo in log_caja.get_children():
		var l := hijo as Label
		l.set_meta("edad", float(l.get_meta("edad", 0.0)) + delta)
		var edad := float(l.get_meta("edad"))
		if edad > 5.0:
			l.modulate.a = maxf(0.0, 1.0 - (edad - 5.0))
			if l.modulate.a <= 0.0:
				l.queue_free()
	if dado_lbl.visible and Time.get_ticks_msec() / 1000.0 > _dado_hasta:
		dado_lbl.visible = false
	if tarjeta_visible and Time.get_ticks_msec() / 1000.0 > _tarjeta_hasta:
		var t := Time.get_ticks_msec() / 1000.0 - _tarjeta_hasta
		tarjeta.modulate.a = maxf(0.0, 1.0 - t * 1.5)
		if tarjeta.modulate.a <= 0.0:
			tarjeta.visible = false
			tarjeta_visible = false

func log_msg(txt: String, tipo: String = "event") -> void:
	var color := Color(0.9, 0.9, 0.85)
	if tipo == "good":
		color = Color(0.6, 0.95, 0.6)
	elif tipo == "danger":
		color = Color(0.98, 0.5, 0.4)
	var l := _lbl(22, color)
	l.text = txt
	l.set_meta("edad", 0.0)
	log_caja.add_child(l)
	if log_caja.get_child_count() > 8:
		log_caja.get_child(0).queue_free()

func estado(salud: float, sed: float, cordura: float, oxigeno: float, con_oxigeno: bool) -> void:
	var txt := "salud %d   sed %d   cordura %d" % [roundi(salud), roundi(sed), roundi(cordura)]
	if con_oxigeno:
		txt += "   oxígeno %d" % roundi(oxigeno)
	estado_lbl.text = txt
	estado_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.4, 0.35) if salud < 35 else Color.WHITE)

func actualizar_barra_inv(inv: Array) -> void:
	var caja := get_node_or_null("CajaInventario")
	if caja == null:
		return
	for i in 6:
		var lbl: Label = caja.get_node("Slot_%d" % i)
		if i < inv.size():
			lbl.text = "[%d] %s" % [(i + 1), _nombre_obj(inv[i])]
			lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		else:
			lbl.text = "[%d] Vacio" % (i + 1)
			lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))

func manos(m: Array) -> void:
	var izq: String = _nombre_obj(m[0])
	var der: String = "»" if m[1] == "=" else _nombre_obj(m[1])
	manos_lbl.text = "[Q] %s   ·   [E] %s" % [izq, der]

func _nombre_obj(id: Variant) -> String:
	if id == null:
		return "—"
	return str(Catalogo.objetos.get(id, {}).get("nombre", id))

func oferta(m: Variant) -> void:
	oferta_activa = m
	if m == null:
		oferta_panel.visible = false
		return
	oferta_lbl.text = "%s\n[ENTER] cruzar   ·   [ESC] ignorar" % str((m as Dictionary).get("texto", ""))
	oferta_panel.visible = true

func dado(valor: int, exito: bool) -> void:
	dado_lbl.text = "🎲 %d" % valor
	dado_lbl.add_theme_color_override("font_color",
		Color(0.6, 0.95, 0.6) if exito else Color(0.95, 0.45, 0.4))
	dado_lbl.visible = true
	_dado_hasta = Time.get_ticks_msec() / 1000.0 + 1.4

func caminata(pasos: int, objetivo: int) -> void:
	caminata_lbl.text = "" if objetivo == 0 else "caminata: %d / %d pasos" % [pasos, objetivo]

func canal(activo: bool) -> void:
	canal_lbl.text = "⚒ rompiendo…" if activo else ""

func tarjeta_nivel(d: Dictionary) -> void:
	tarjeta_titulo.text = str(d.get("nombre", d.get("id", "")))
	tarjeta_clase.text = str(d.get("clase", ""))
	tarjeta_desc.text = str(d.get("descripcion", ""))
	tarjeta.modulate.a = 1.0
	tarjeta.visible = true
	tarjeta_visible = true
	_tarjeta_hasta = Time.get_ticks_msec() / 1000.0 + 2.6

func mochila(jug: Dictionary, abierta: bool) -> void:
	mochila_abierta = abierta
	mochila_panel.visible = abierta
	if not abierta:
		return
	var lineas := ["MOCHILA  (B para cerrar)", ""]
	var inv: Array = jug.inv
	for i in 6:
		var id: Variant = inv[i] if i < inv.size() else null
		lineas.append("  [%d] %s" % [i + 1, _nombre_obj(id)])
	lineas.append("")
	lineas.append("Manos: %s / %s   ([Q]/[E] fuera de la mochila para usar)" %
		[_nombre_obj(jug.manos[0]), "»" if jug.manos[1] == "=" else _nombre_obj(jug.manos[1])])
	var eq: Dictionary = jug.equipo
	lineas.append("Vistiendo: cara %s · cuerpo %s · pies %s" %
		[_nombre_obj(eq.get("cara")), _nombre_obj(eq.get("cuerpo")), _nombre_obj(eq.get("pies"))])
	lineas.append("")
	lineas.append("1-6 empuñar/usar/vestir · MAYÚS+1-6 tirar al suelo")
	mochila_lbl.text = "\n".join(lineas)

func muerte(causa: String, visible_p: bool) -> void:
	muerte_panel.visible = visible_p
	if not visible_p:
		return
	# muerte especial por Smiler: oscuridad total y su sonrisa (mensaje del
	# original, pantalla `smiler-death`)
	if causa.contains("Smiler") and ResourceLoader.exists("res://assets/sprites/smiler.png"):
		muerte_panel.color = Color(0, 0, 0, 1)
		muerte_img.texture = load("res://assets/sprites/smiler.png")
		muerte_img.visible = true
		muerte_lbl.text = "Tocaste la sonrisa.\nEl Smiler te arrastró a la oscuridad."
		muerte_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	else:
		muerte_panel.color = Color(0.08, 0, 0, 0.92)
		muerte_img.visible = false
		muerte_lbl.add_theme_color_override("font_color", Color(0.95, 0.2, 0.2))
		muerte_lbl.text = "HAS MUERTO\n%s\n\nLas Backrooms no te dejan ir…" % causa
