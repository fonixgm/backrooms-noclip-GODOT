## RNG determinista con semilla (mulberry32) — partidas reproducibles.
## Port bit a bit de game/js/engine/rng.js del repo original:
## toda la aritmética se hace módulo 2^32 con máscaras para replicar
## exactamente Math.imul / >>> / |0 de JavaScript.
## Equivalencias de nombres JS → GDScript:
##   RNG.create → Rng.crear · f → f · int → entero · pick → elegir
##   chance → azar · shuffle → barajar · unit → unidad
## Nota: el hash usa unicode_at(), equivalente a charCodeAt() de JS para
## cadenas BMP (todas las semillas del juego lo son).
class_name Rng
extends RefCounted

const _MASK: int = 0xFFFFFFFF

var _a: int = 0

static func crear(semilla: String) -> Rng:
	var r := Rng.new()
	r._a = hash_cadena(semilla)
	return r

## FNV-1a de 32 bits, idéntico a hashStr() de rng.js.
static func hash_cadena(s: String) -> int:
	var h: int = 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & _MASK
		h = (h * 16777619) & _MASK
	return h

## Math.imul: producto con truncamiento a 32 bits.
static func _imul(a: int, b: int) -> int:
	return (a * b) & _MASK

## Valor determinista [0,1) a partir de una cadena (sin estado), como RNG.unit.
static func unidad(semilla: String) -> float:
	return float(hash_cadena(semilla)) / 4294967296.0

## Siguiente valor [0,1) — núcleo mulberry32.
func f() -> float:
	_a = (_a + 0x6D2B79F5) & _MASK
	var t: int = _a
	t = _imul(t ^ (t >> 15), t | 1)
	t = (((t + _imul(t ^ (t >> 7), t | 61)) & _MASK) ^ t) & _MASK
	return float((t ^ (t >> 14)) & _MASK) / 4294967296.0

## Entero uniforme en [a, b], como rng.int(a, b).
func entero(a: int, b: int) -> int:
	return a + int(floor(f() * float(b - a + 1)))

## Elemento al azar de un array, como rng.pick(arr).
func elegir(arr: Array) -> Variant:
	return arr[int(floor(f() * float(arr.size())))]

## true con probabilidad p, como rng.chance(p).
func azar(p: float) -> bool:
	return f() < p

## Copia barajada (Fisher-Yates), como rng.shuffle(arr).
func barajar(arr: Array) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := int(floor(f() * float(i + 1)))
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a
