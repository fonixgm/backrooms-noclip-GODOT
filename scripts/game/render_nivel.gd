## Construye la geometría 3D de un nivel a partir de la rejilla del mapgen:
## suelo/paredes/techo fusionados en ArrayMesh, paneles fluorescentes emisivos,
## salidas como puertas/grietas sobre la cara norte del muro (como componen
## ambos renders del original) y billboards para props/items/entidades.
## Tile (x,y) → mundo (x+0.5, 0, y+0.5). Altura de muro 2.3 (v15).
class_name RenderNivel
extends Node3D

## Altura visual de muros y techo. 3.2 evita el "cielo negro": con 2.3 la
## cámara (2.1) veía por encima de los muros y el techo plano nunca cruzaba
## la línea de visión. La colisión es 2D y no cambia.
const ALTO_MURO := 3.2
const ALTO_OBSTACULO := 1.0

var _map: Dictionary
var _def: Dictionary
var _nodos_salidas: Dictionary = {}   # índice → Node3D
var _nodos_props: Dictionary = {}     # índice → Sprite3D
var _nodos_items: Dictionary = {}     # índice → Sprite3D
var _nodos_ents: Dictionary = {}      # uid → Sprite3D
var _tex_cache: Dictionary = {}

func construir(map: Dictionary, def: Dictionary) -> void:
	_map = map
	_def = def
	for hijo in get_children():
		hijo.queue_free()
	_nodos_salidas = {}
	_nodos_props = {}
	_nodos_items = {}
	_nodos_ents = {}
	_construir_geometria()
	_construir_salidas()
	_construir_props()
	_construir_items()

func _paleta(clave: String, defecto: Color) -> Color:
	var p: Dictionary = _def.get("paleta", {})
	var v: Variant = p.get(clave)
	return Color(str(v)) if v is String else defecto

func _tex(ruta: String) -> Variant:
	if _tex_cache.has(ruta):
		return _tex_cache[ruta]
	var t: Variant = load(ruta) if ResourceLoader.exists(ruta) else null
	if t == null and FileAccess.file_exists(ruta):
		var img := Image.load_from_file(ruta)
		if img != null:
			t = ImageTexture.create_from_image(img)
	_tex_cache[ruta] = t
	return t

func _mat_textura(ruta: String, color_fallback: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var t: Variant = _tex(ruta)
	if t != null:
		m.albedo_texture = t
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		m.albedo_color = color_fallback
	m.roughness = 0.92
	return m

func _construir_geometria() -> void:
	var g: MapGen.Grid = _map.grid
	var nivel_id := str(_def.get("id", ""))
	var es_garaje: bool = str(_def.get("bioma", "")) == "garaje"
	var es_carretera: bool = str(_def.get("bioma", "")) == "carretera"
	var es_hub: bool = nivel_id == "the-hub"
	var alto_pared := ALTO_MURO * (2.2 if es_hub else 1.0)  # túneles altos para The Hub
	# texturas por nivel en res://assets/textures/<id>/{suelo,pared,techo,pilar}.png
	var mat_suelo := _mat_textura("res://assets/textures/%s/suelo.png" % nivel_id,
		_paleta("suelo", Color(0.35, 0.32, 0.2)))
	var mat_pared := _mat_textura("res://assets/textures/%s/pared.png" % nivel_id,
		_paleta("pared", Color(0.55, 0.5, 0.3)))
	var mat_techo := _mat_textura("res://assets/textures/%s/techo.png" % nivel_id,
		_paleta("detalle", Color(0.25, 0.22, 0.14)).darkened(0.2))
	mat_techo.cull_mode = BaseMaterial3D.CULL_DISABLED
	# garaje: los pilares llevan su propia textura (hormigón + franja amarilla)
	var mat_pilar := _mat_textura("res://assets/textures/%s/pilar.png" % nivel_id,
		_paleta("pared", Color(0.6, 0.65, 0.7)).lightened(0.1))
	var mat_linea := StandardMaterial3D.new()
	mat_linea.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_linea.albedo_color = Color(0.85, 0.8, 0.55, 0.55)
	mat_linea.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Línea vial blanca para carretera
	var mat_vial := StandardMaterial3D.new()
	mat_vial.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_vial.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
	mat_vial.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Bordillo de acera
	var mat_bordillo := StandardMaterial3D.new()
	mat_bordillo.albedo_color = Color(0.55, 0.53, 0.50)
	mat_bordillo.roughness = 0.85
	var mat_aceite := StandardMaterial3D.new()
	mat_aceite.albedo_color = Color(0.045, 0.05, 0.06, 0.85)
	mat_aceite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var pilares := _clasificar_pilares(g) if es_garaje else {}
	var mat_panel := StandardMaterial3D.new()
	mat_panel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_panel.albedo_color = _paleta("luz", Color(1, 0.93, 0.7))
	mat_panel.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mat_agua := StandardMaterial3D.new()
	mat_agua.albedo_color = Color(0.15, 0.3, 0.45, 0.8)
	mat_agua.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mat_charco := StandardMaterial3D.new()
	mat_charco.albedo_color = Color(0.2, 0.25, 0.3, 0.85)
	mat_charco.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var r_manila: Rect2i = _map.get("manila", Rect2i(0, 0, 0, 0)) if _map.get("manila") != null else Rect2i(0, 0, 0, 0)
	var hay_manila := r_manila.size.x > 0
	var mat_manila_pared := _mat_textura("res://assets/textures/level-0/manila_pared.png", Color(0.85, 0.8, 0.65))
	var mat_manila_suelo := _mat_textura("res://assets/textures/level-0/manila_suelo.png", Color(0.75, 0.7, 0.55))

	var st_suelo := SurfaceTool.new()
	var st_pared := SurfaceTool.new()
	var st_pilar := SurfaceTool.new()
	var st_techo := SurfaceTool.new()
	var st_panel := SurfaceTool.new()
	var st_agua := SurfaceTool.new()
	var st_charco := SurfaceTool.new()
	var st_linea := SurfaceTool.new()
	var st_aceite := SurfaceTool.new()
	var st_m_pared := SurfaceTool.new()
	var st_m_suelo := SurfaceTool.new()
	var st_vial := SurfaceTool.new()
	var st_bordillo := SurfaceTool.new()
	for st in [st_suelo, st_pared, st_pilar, st_techo, st_panel, st_agua, st_charco, st_linea, st_aceite, st_m_pared, st_m_suelo, st_vial, st_bordillo]:
		(st as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)

	var abierto_al_cielo: bool = _def.get("bioma") == "invernadero"
	var es_hotel: bool = _def.get("bioma") == "hotel"
	for y in g.h:
		for x in g.w:
			var t := int(g.t[y * g.w + x])
			if t == MapGen.VACIO:
				continue
			var en_manila := hay_manila and x >= r_manila.position.x and x < r_manila.end.x and y >= r_manila.position.y and y < r_manila.end.y
			var solido := t == MapGen.PARED or t == MapGen.ESTANTERIA
			var patio_interior := es_hotel and t == MapGen.DECOR
			if solido:
				var pisos := 6 if (abierto_al_cielo or es_hotel) else 1
				var c_pared = st_m_pared if en_manila else (st_pilar if pilares.has(Vector2i(x, y)) else st_pared)
				var h_muro := alto_pared if es_hub else ALTO_MURO
				_muro(c_pared, g, x, y, h_muro, pisos)
				# tapa superior: sella el techo también sobre los muros para
				# que nunca se vea "cielo negro" por encima de un muro lejano
				if es_hub:
					_quad_techo(st_techo, x, y, alto_pared)
				elif not abierto_al_cielo and not es_hotel:
					_quad_techo(st_techo, x, y, ALTO_MURO)
				elif es_hotel:
					_quad_techo(st_techo, x, y, ALTO_MURO * 6.0)
				continue
			# suelo (agua/charco encima como lámina)
			_quad_suelo(st_m_suelo if en_manila else st_suelo, x, y, 0.0)
			if t == MapGen.AGUA:
				_quad_suelo(st_agua, x, y, 0.06)
			elif t == MapGen.CHARCO:
				_quad_suelo(st_charco, x, y, 0.02)
			if t == MapGen.OBSTACULO:
				_caja(st_pared, x, y, ALTO_OBSTACULO)
			if es_garaje:
				# marcas de plaza pintadas: bandas de aparcamiento cada 8 filas,
				# divisores cada 3 columnas (patrón fijo, sin RNG)
				var en_banda := (y % 8) >= 2 and (y % 8) <= 5
				if en_banda and x % 3 == 0:
					_linea_v(st_linea, x, y)
				if x % 3 != 0 and ((y % 8) == 2 or (y % 8) == 5):
					_linea_h(st_linea, x, y, (y % 8) == 2)
				# mancha de aceite en tiles de decorado
				if t == MapGen.DECOR:
					_mancha(st_aceite, x, y)
			if es_hub and t == MapGen.DECOR:
				# Marcas viales blancas sobre el asfalto (centro y separadores de carril)
				_marca_vial(st_vial, x, y)
			
			if es_carretera and not es_hub and t == MapGen.DECOR:
				# Marcas de carril: línea discontinua blanca en el centro de la carretera
				_linea_h(st_linea, x, y, true)
			
			if not abierto_al_cielo and not patio_interior:
				var h_techo := alto_pared if es_hub else ALTO_MURO
				_quad_techo(st_techo, x, y, h_techo)
				if not en_manila and not es_hub and x % 4 == 2 and y % 4 == 2:
					_quad_techo(st_panel, x, y, h_techo - 0.02, 0.3)
				elif en_manila and x == r_manila.position.x + r_manila.size.x / 2 and y == r_manila.position.y + r_manila.size.y / 2:
					# Bombilla naranja solitaria en el centro de Manila.
					# Nombrada para que Nivel3D pueda modular su energía con el
					# parpadeo (flick) de los fluorescentes del resto del nivel.
					var luz := OmniLight3D.new()
					luz.name = "LuzManila"
					luz.light_color = Color(1.0, 0.6, 0.2)
					luz.light_energy = 0.8
					luz.omni_range = 8.0
					luz.position = Vector3(x + 0.5, ALTO_MURO - 0.2, y + 0.5)
					add_child(luz)

	_anadir_mesh(st_suelo, mat_suelo, "Suelo")
	_anadir_mesh(st_pared, mat_pared, "Paredes")
	_anadir_mesh(st_pilar, mat_pilar, "Pilares")
	_anadir_mesh(st_m_suelo, mat_manila_suelo, "ManilaSuelo")
	_anadir_mesh(st_m_pared, mat_manila_pared, "ManilaPared")
	if es_hub:
		_anadir_mesh(st_vial, mat_vial, "MarcasViales")
	if not abierto_al_cielo:
		_anadir_mesh(st_techo, mat_techo, "Techo")
		_anadir_mesh(st_panel, mat_panel, "Paneles")
	
	# --- Level 0: marcas de muebles en la moqueta (wiki: huellas de patas) ---
	var _semilla_l0: int = 0
	if nivel_id == "level-0":
		var st_huella := SurfaceTool.new()
		st_huella.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat_huella := StandardMaterial3D.new()
		mat_huella.albedo_color = Color(0.3, 0.27, 0.15, 0.55)
		mat_huella.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_huella.cull_mode = BaseMaterial3D.CULL_DISABLED
		_semilla_l0 = hash(nivel_id + "muebles")
		for _i in range(35):
			_semilla_l0 = (_semilla_l0 * 1103515245 + 12345) & 0x7FFFFFFF
			var fx := (_semilla_l0 % g.w)
			_semilla_l0 = (_semilla_l0 * 1103515245 + 12345) & 0x7FFFFFFF
			var fy := (_semilla_l0 % g.h)
			var ft := MapGen.at(g, fx, fy)
			if ft == MapGen.VACIO or ft == MapGen.PARED or ft == MapGen.ESTANTERIA:
				continue
			# 4 pequeñas marcas circulares simulando patas de mueble
			for d: Vector2 in [Vector2(0.15, 0.15), Vector2(0.65, 0.15), Vector2(0.15, 0.65), Vector2(0.65, 0.65)]:
				var r := 0.06
				var cx := float(fx) + d.x
				var cy := float(fy) + d.y
				_quad(st_huella,
					Vector3(cx - r, 0.005, cy - r), Vector3(cx + r, 0.005, cy - r),
					Vector3(cx + r, 0.005, cy + r), Vector3(cx - r, 0.005, cy + r),
					Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		_anadir_mesh(st_huella, mat_huella, "HuellasMueble")
	
	# --- Level 0: rejillas de ventilación en el falso techo (wiki) ---
	if nivel_id == "level-0":
		var st_vent := SurfaceTool.new()
		st_vent.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat_vent := _mat_textura("res://assets/generated/ceiling_vent_frame_0.png",
			Color(0.35, 0.33, 0.28))
		mat_vent.cull_mode = BaseMaterial3D.CULL_DISABLED
		_semilla_l0 = hash(nivel_id + "ventilacion")
		for _j in range(25):
			_semilla_l0 = (_semilla_l0 * 1103515245 + 12345) & 0x7FFFFFFF
			var vx := (_semilla_l0 % g.w)
			_semilla_l0 = (_semilla_l0 * 1103515245 + 12345) & 0x7FFFFFFF
			var vy := (_semilla_l0 % g.h)
			var vt := MapGen.at(g, vx, vy)
			if vt == MapGen.VACIO or vt == MapGen.PARED or vt == MapGen.ESTANTERIA:
				continue
			if r_manila.size.x > 0:
				if vx >= r_manila.position.x and vx < r_manila.end.x and vy >= r_manila.position.y and vy < r_manila.end.y:
					continue  # Manila no lleva rejillas
			_quad_techo(st_vent, vx, vy, ALTO_MURO, 0.05)
		_anadir_mesh(st_vent, mat_vent, "RejillasVentilacion")
	_anadir_mesh(st_agua, mat_agua, "Agua")
	_anadir_mesh(st_charco, mat_charco, "Charcos")
	_anadir_mesh(st_linea, mat_linea, "Lineas")
	_anadir_mesh(st_aceite, mat_aceite, "Aceite")

## Componentes sólidos pequeños (≤4 tiles) que no tocan el borde → pilares.
## Solo clasificación visual: la colisión/mapa no cambian (golden tests a salvo).
func _clasificar_pilares(g: MapGen.Grid) -> Dictionary:
	var pilares := {}
	var visto := {}
	for y in g.h:
		for x in g.w:
			var c := Vector2i(x, y)
			if visto.has(c) or MapGen.at(g, x, y) != MapGen.PARED:
				continue
			var comp: Array[Vector2i] = [c]
			var toca_borde := false
			visto[c] = true
			var q := 0
			while q < comp.size() and comp.size() <= 5:
				var p := comp[q]
				q += 1
				if p.x == 0 or p.y == 0 or p.x == g.w - 1 or p.y == g.h - 1:
					toca_borde = true
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n := p + d
					if visto.has(n) or MapGen.at(g, n.x, n.y) != MapGen.PARED:
						continue
					visto[n] = true
					comp.append(n)
			if comp.size() <= 4 and not toca_borde:
				for p in comp:
					pilares[p] = true
	return pilares

## Divisor vertical de plaza (franja fina pintada sobre el suelo).
func _linea_v(st: SurfaceTool, x: int, y: int) -> void:
	var g := 0.05
	_quad(st, Vector3(x - g, 0.012, y), Vector3(x + g, 0.012, y),
		Vector3(x + g, 0.012, y + 1), Vector3(x - g, 0.012, y + 1),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

## Borde horizontal de banda de plazas.
func _linea_h(st: SurfaceTool, x: int, y: int, arriba: bool) -> void:
	var g := 0.05
	var yy := float(y) if arriba else float(y + 1)
	_quad(st, Vector3(x, 0.012, yy - g), Vector3(x + 1, 0.012, yy - g),
		Vector3(x + 1, 0.012, yy + g), Vector3(x, 0.012, yy + g),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

## Mancha de aceite (quad oscuro con margen).
func _mancha(st: SurfaceTool, x: int, y: int) -> void:
	var m := 0.18
	_quad(st, Vector3(x + m, 0.008, y + m), Vector3(x + 1 - m, 0.008, y + m),
		Vector3(x + 1 - m, 0.008, y + 1 - m), Vector3(x + m, 0.008, y + 1 - m),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

## Marca vial blanca discontinua (línea de carril) para The Hub.
func _marca_vial(st: SurfaceTool, x: int, y: int) -> void:
	var g := 0.06  # grosor de la línea
	var largo := 0.5  # mitad del tile = línea discontinua
	var yy := float(y) + 0.25  # centrado en el tile
	_quad(st, Vector3(float(x), 0.015, yy - g), Vector3(float(x) + largo, 0.015, yy - g),
		Vector3(float(x) + largo, 0.015, yy + g), Vector3(float(x), 0.015, yy + g),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

## Bordillo de acera (bloque elevado).
func _bordillo(st: SurfaceTool, x: int, y: int, alto: float) -> void:
	var w := 0.15  # ancho del bordillo
	# Cara superior (horizontal)
	_quad(st, Vector3(x, alto, y), Vector3(x + 1, alto, y),
		Vector3(x + 1, alto, y + w), Vector3(x, alto, y + w),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	# Cara frontal (vertical)
	_quad(st, Vector3(x, 0, y + w), Vector3(x + 1, 0, y + w),
		Vector3(x + 1, alto, y + w), Vector3(x, alto, y + w),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

func _anadir_mesh(st: SurfaceTool, mat: Material, nombre: String) -> void:
	st.generate_normals()
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = nombre
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

func _quad_suelo(st: SurfaceTool, x: int, y: int, alto: float) -> void:
	var a := Vector3(x, alto, y)
	var b := Vector3(x + 1, alto, y)
	var c := Vector3(x + 1, alto, y + 1)
	var d := Vector3(x, alto, y + 1)
	_quad(st, a, b, c, d, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

func _quad_techo(st: SurfaceTool, x: int, y: int, alto: float, margen: float = 0.0) -> void:
	var a := Vector3(x + margen, alto, y + 1 - margen)
	var b := Vector3(x + 1 - margen, alto, y + 1 - margen)
	var c := Vector3(x + 1 - margen, alto, y + margen)
	var d := Vector3(x + margen, alto, y + margen)
	_quad(st, a, b, c, d, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))

## Caras laterales de un muro, solo hacia vecinos no sólidos.
func _muro(st: SurfaceTool, g: MapGen.Grid, x: int, y: int, alto: float, pisos: int = 1) -> void:
	var solido := func(vx: int, vy: int) -> bool:
		var v := MapGen.at(g, vx, vy)
		return v == MapGen.PARED or v == MapGen.ESTANTERIA
	for p in pisos:
		var base_y := p * alto
		if not solido.call(x, y - 1): # cara norte
			_pared_vertical(st, Vector3(x + 1, base_y, y), Vector3(x, base_y, y), alto)
		if not solido.call(x, y + 1): # cara sur
			_pared_vertical(st, Vector3(x, base_y, y + 1), Vector3(x + 1, base_y, y + 1), alto)
		if not solido.call(x - 1, y): # cara oeste
			_pared_vertical(st, Vector3(x, base_y, y), Vector3(x, base_y, y + 1), alto)
		if not solido.call(x + 1, y): # cara este
			_pared_vertical(st, Vector3(x + 1, base_y, y + 1), Vector3(x + 1, base_y, y), alto)

func _caja(st: SurfaceTool, x: int, y: int, alto: float) -> void:
	_pared_vertical(st, Vector3(x + 1, 0, y), Vector3(x, 0, y), alto)
	_pared_vertical(st, Vector3(x, 0, y + 1), Vector3(x + 1, 0, y + 1), alto)
	_pared_vertical(st, Vector3(x, 0, y), Vector3(x, 0, y + 1), alto)
	_pared_vertical(st, Vector3(x + 1, 0, y + 1), Vector3(x + 1, 0, y), alto)
	_quad(st, Vector3(x, alto, y), Vector3(x + 1, alto, y),
		Vector3(x + 1, alto, y + 1), Vector3(x, alto, y + 1),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

func _pared_vertical(st: SurfaceTool, pie_a: Vector3, pie_b: Vector3, alto: float) -> void:
	var u := pie_a.distance_to(pie_b)
	_quad(st, pie_a + Vector3(0, alto, 0), pie_b + Vector3(0, alto, 0), pie_b, pie_a,
		Vector2(0, 0), Vector2(u, 0), Vector2(u, alto / 2.3), Vector2(0, alto / 2.3))

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ud); st.add_vertex(d)

# ---------- salidas ----------

const COLOR_TIPO := {
	"normal": Color(0.85, 0.76, 0.42), "rara": Color(0.4, 0.85, 0.9),
	"arriesgada": Color(0.9, 0.45, 0.3), "llave": Color(0.45, 0.5, 0.55),
	"escape": Color(0.5, 1.0, 0.6), "retorno": Color(0.7, 0.85, 0.7),
}

func _construir_salidas() -> void:
	var exits: Array = _map.exits
	for i in exits.size():
		_nodos_salidas[i] = _crear_salida(exits[i], i)

## También la usa el retorno personal (índice "R").
func crear_salida_retorno(retorno: Dictionary) -> void:
	if _nodos_salidas.has("R"):
		return
	_nodos_salidas["R"] = _crear_salida({"x": retorno.x, "y": retorno.y, "def": retorno}, "R")

func _crear_salida(ex: Dictionary, indice: Variant) -> Node3D:
	var d: Dictionary = ex.def
	var raiz := Node3D.new()
	raiz.name = "Salida_%s" % str(indice)
	raiz.position = Vector3(float(ex.x) + 0.5, 0, float(ex.y) + 0.5)
	add_child(raiz)
	var mec: Variant = d.get("_mec")
	var es_suelo: bool = mec == "romper_suelo"
	var mesh := QuadMesh.new()
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if es_suelo or mec == null and str(d.get("texto", "")).to_lower().contains("trampilla"):
		mesh.size = Vector2(0.9, 0.9)
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.position = Vector3(0, 0.03, 0)
	else:
		mesh.size = Vector2(0.95, 2.0)
		mi.position = Vector3(0, 1.0, -0.47) # sobre la cara norte del muro
	mi.mesh = mesh
	if mec == "romper" or mec == "romper_suelo":
		mat.albedo_color = Color(0.35, 0.33, 0.28) if not d.get("_abierta", false) else Color(0.02, 0.02, 0.02)
	else:
		mat.albedo_color = COLOR_TIPO.get(d.get("tipo", "normal"), Color(0.8, 0.8, 0.8))
	if d.get("ritual") == "emergencia":
		mat.albedo_color = Color(0.9, 0.1, 0.1)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1, 0.15, 0.1)
		luz.omni_range = 4.0
		luz.light_energy = 1.6
		luz.position = Vector3(0, 1.8, 0.3)
		raiz.add_child(luz)
	mi.material_override = mat
	raiz.add_child(mi)
	var etiqueta := Label3D.new()
	etiqueta.text = str(d.get("destino", ""))
	etiqueta.font_size = 36
	etiqueta.pixel_size = 0.004
	etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	etiqueta.modulate = mat.albedo_color.lightened(0.3)
	etiqueta.position = Vector3(0, 2.15, 0)
	raiz.add_child(etiqueta)
	return raiz

func abrir_salida(indice: int) -> void:
	var nodo: Variant = _nodos_salidas.get(indice)
	if nodo == null:
		return
	for hijo in (nodo as Node3D).get_children():
		if hijo is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.02, 0.02, 0.02)
			(hijo as MeshInstance3D).material_override = mat

# ---------- billboards ----------

## Sprites con nombre distinto al id de la ficha (o generados por IA).
const RUTAS_SPRITE := {
	"faceling": "res://assets/sprites/mascara_down.png",
	"hound": "res://assets/sprites/hound.png",
	"clump": "res://assets/sprites/clump.png",
	"deathmoth": "res://assets/sprites/deathmoth.png",
	"skinstealer": "res://assets/sprites/skinstealer.png",
	"window": "res://assets/sprites/window.png",
	"duller": "res://assets/sprites/duller.png",
	"false_puddle": "res://assets/sprites/false_puddle.png",
	"painting": "res://assets/sprites/painting.png",
}

func _sprite(id: String, color_defecto: Color, tam: float) -> Sprite3D:
	var s := Sprite3D.new()
	var ruta: String = RUTAS_SPRITE.get(id, "res://assets/sprites/%s.png" % id)
	var t: Variant = _tex(ruta)
	if t != null:
		s.texture = t
		# hojas horizontales de N frames cuadrados → usa el primer frame
		var tw := (t as Texture2D).get_width()
		var th := (t as Texture2D).get_height()
		if th > 0 and tw > th and tw % th == 0:
			s.hframes = tw / th
			s.frame = 0
	else:
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(color_defecto)
		s.texture = ImageTexture.create_from_image(img)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = tam / 48.0
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	return s

func _color_objeto(id: String) -> Color:
	var d: Dictionary = Catalogo.objetos.get(id, {})
	var c: Variant = d.get("color")
	return Color(str(c)) if c is String else Color(0.6, 0.6, 0.6)

func _construir_props() -> void:
	var props: Array = _map.get("props", [])
	for i in props.size():
		var p: Dictionary = props[i]
		var s := _sprite(str(p.id), _color_objeto(str(p.id)), 1.0)
		s.position = Vector3(float(p.x) + 0.5, 0.5, float(p.y) + 0.5)
		if p.get("registrado", false):
			s.modulate = Color(0.55, 0.55, 0.55)
		add_child(s)
		_nodos_props[i] = s

func marcar_registrado(indice: int) -> void:
	var s: Variant = _nodos_props.get(indice)
	if s != null:
		(s as Sprite3D).modulate = Color(0.55, 0.55, 0.55)

func _construir_items() -> void:
	var items: Array = _map.get("items", [])
	for i in items.size():
		var it: Dictionary = items[i]
		if it.get("taken", false):
			continue
		var s := _sprite(str(it.id), _color_objeto(str(it.id)), 0.6)
		s.position = Vector3(float(it.x) + 0.5, 0.3, float(it.y) + 0.5)
		add_child(s)
		_nodos_items[i] = s

func refrescar_items() -> void:
	var items: Array = _map.get("items", [])
	for i in items.size():
		var it: Dictionary = items[i]
		var nodo: Variant = _nodos_items.get(i)
		if it.get("taken", false) and nodo != null:
			(nodo as Sprite3D).queue_free()
			_nodos_items.erase(i)
		elif not it.get("taken", false) and nodo == null:
			var s := _sprite(str(it.id), _color_objeto(str(it.id)), 0.6)
			s.position = Vector3(float(it.x) + 0.5, 0.3, float(it.y) + 0.5)
			add_child(s)
			_nodos_items[i] = s

func poner_entidades(ents: Array) -> void:
	for uid in _nodos_ents:
		(_nodos_ents[uid] as Sprite3D).queue_free()
	_nodos_ents = {}
	for e: Dictionary in ents:
		if not e.get("viva", true):
			continue
		var s := _sprite(str(e.id), Color(0.9, 0.9, 1.0), 1.4)
		s.position = Vector3(float(e.x) + 0.5, 0.8, float(e.y) + 0.5)
		s.visible = e.get("revelada", true)
		add_child(s)
		_nodos_ents[int(e.uid)] = s

func mover_entidad(uid: int, x: float, y: float) -> void:
	var s: Variant = _nodos_ents.get(uid)
	if s != null:
		(s as Sprite3D).position = Vector3(x + 0.5, 0.8, y + 0.5)

func entidad_evento(uid: int, evento: String) -> void:
	var s: Variant = _nodos_ents.get(uid)
	if s == null:
		return
	var sp := s as Sprite3D
	match evento:
		"muere":
			sp.queue_free()
			_nodos_ents.erase(uid)
		"revela":
			sp.visible = true
		"prep":
			sp.modulate = Color(1.0, 0.75, 0.3)
		"hit":
			sp.modulate = Color(1.0, 0.4, 0.4)
		"normal":
			sp.modulate = Color.WHITE
