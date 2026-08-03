## LevelManager — framework de niveles + semilla.
##
## Registro de niveles intercambiables: para añadir un nivel nuevo (p. ej.
## Level 2/3) basta con registrar su ficha (registrar_nivel() o añadirla a
## REGISTRO) con su id, nombre y escena; el resto del juego no cambia.
##
## Semilla: fija por defecto (20260802) para partidas reproducibles.
## API preparada para la seed diaria del servidor:
##   - inyectar_seed_diaria("...")  -> punto único donde el servidor inyecta
##                                     la semilla del día (HTTP futuro).
##   - semilla_diaria_servidor()    -> semilla diaria local (DailySeed) para
##                                     cuando aún no hay servidor.
## Llamar a set_seed() antes de entrar a un nivel para regenerarlo.
extends Node

const SEED_FIJA := "20260802"

const ESCENA_MENU := "res://scenes/menu_principal.tscn"
# Las escenas de juego se resuelven vía REGISTRO (nivel_3d_inicial para la inicial)

## Nivel del catálogo (id JSON, p. ej. "level-0") con el que arranca el modo
## 3D principal. El menú lo fija antes de cambiar a la escena del juego.
var nivel_3d_inicial := "level-0"

## Registro de niveles. nivel_actual_id cambia con cargar_nivel().
var REGISTRO: Dictionary = {
	"level_0": {
		"id": "level_0",
		"nombre": "Level 0: «The Lobby»",
		"escena": "res://levels/level_0/level_0.tscn",
		"estado": "jugable",
	},
	"level_1": {
		"id": "level_1",
		"nombre": "Level 1: «Parking Zone»",
		"escena": "res://levels/level_1/level_1.tscn",
		"estado": "jugable",
	},
	"level_2": {
		"id": "level_2",
		"nombre": "Level 2: «Pipe Dreams»",
		"escena": "res://levels/level_2/level_2.tscn",
		"estado": "jugable",
	},
	"the_hub": {
		"id": "the_hub",
		"nombre": "The Hub",
		"escena": "res://levels/the_hub/the_hub.tscn",
		"estado": "jugable",
	},
	"level_188": {
		"id": "level_188",
		"nombre": "Level 188: «The Windows»",
		"escena": "res://levels/level_188/level_188.tscn",
		"estado": "jugable",
	},
}

signal nivel_cambiado(id_nuevo: String)

var nivel_actual_id := "level_0"
var _seed_activa := SEED_FIJA

func obtener_seed() -> String:
	return _seed_activa

func set_seed(seed_value: String) -> void:
	_seed_activa = seed_value

## API de inyección de seed diaria (preparada para el servidor).
## Si llega vacía o no disponible, usa la semilla diaria local.
func inyectar_seed_diaria(seed_servidor: String) -> void:
	_seed_activa = seed_servidor if seed_servidor != "" else DailySeed.semilla()

## Semilla diaria local calculada por DailySeed (port de daily-seed.js).
func semilla_diaria_servidor() -> String:
	return DailySeed.semilla()

func nivel_info(id: String) -> Dictionary:
	return REGISTRO.get(id, {})

## Registrar un nivel nuevo es tan simple como llamar a esto:
##   LevelManager.registrar_nivel({"id": "level_2", "nombre": "...",
##       "escena": "res://scenes/level_2.tscn", "estado": "jugable"})
func registrar_nivel(def_nivel: Dictionary) -> bool:
	var id: String = def_nivel.get("id", "")
	if id == "" or REGISTRO.has(id):
		return false
	REGISTRO[id] = def_nivel
	return true

## Transición de nivel. Cambia nivel_actual_id y carga la escena registrada.
func cargar_nivel(id: String) -> bool:
	if not REGISTRO.has(id):
		push_warning("LevelManager: nivel desconocido '%s'" % id)
		return false
	nivel_actual_id = id
	emit_signal("nivel_cambiado", id)
	return get_tree().change_scene_to_file(REGISTRO[id].escena) == OK

## Vuelve a la pantalla de título.
func ir_al_menu() -> bool:
	return get_tree().change_scene_to_file(ESCENA_MENU) == OK

## Lanza el juego 3D principal (juego.tscn) empezando en un nivel del
## catálogo JSON (id tipo "level-0"). Es el modo fiel al juego web.
func jugar_3d(id_catalogo: String = "level-0") -> bool:
	nivel_3d_inicial = id_catalogo
	var clave := id_catalogo.replace("-", "_")
	if REGISTRO.has(clave) and REGISTRO[clave].estado != "stub":
		return get_tree().change_scene_to_file(REGISTRO[clave].escena) == OK
	return false

## Llama al cambio de escena durante el juego. Devuelve false si no existe.
func ir_a_escena_de_nivel(id_catalogo: String) -> bool:
	var clave := id_catalogo.replace("-", "_")
	if REGISTRO.has(clave) and REGISTRO[clave].estado != "stub":
		get_tree().change_scene_to_file.call_deferred(REGISTRO[clave].escena)
		return true
	return false
