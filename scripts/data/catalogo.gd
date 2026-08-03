## Catálogo data-driven del juego: niveles, entidades y objetos.
## Carga TAL CUAL los JSON generados por el pipeline del repo original
## (data/game/*.es.json) — esos ficheros son el contrato y no se transforman.
extends Node

var niveles: Dictionary = {}
var entidades: Dictionary = {}
var objetos: Dictionary = {}

func _ready() -> void:
	cargar()

func cargar() -> void:
	niveles = _leer_json("res://data/levels.es.json")
	entidades = _leer_json("res://data/entities.es.json")
	objetos = _leer_json("res://data/objects.es.json")

## Ficha de un nivel por id (p. ej. "level-0"), o {} si no existe.
func nivel(id: String) -> Dictionary:
	return niveles.get(id, {})

## Ficha de una entidad por id (p. ej. "smiler"), o {} si no existe.
func entidad(id: String) -> Dictionary:
	return entidades.get(id, {})

## Ficha de un objeto por id (p. ej. "linterna"), o {} si no existe.
func objeto(id: String) -> Dictionary:
	return objetos.get(id, {})

static func _leer_json(ruta: String) -> Dictionary:
	var texto := FileAccess.get_file_as_string(ruta)
	if texto.is_empty():
		push_error("Catálogo: no se pudo leer %s" % ruta)
		return {}
	var dato: Variant = JSON.parse_string(texto)
	if not (dato is Dictionary):
		push_error("Catálogo: %s no contiene un objeto JSON" % ruta)
		return {}
	return dato
