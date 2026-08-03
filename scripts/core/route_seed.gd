## Resuelve destinos variables sin consumir el RNG mutable de la partida.
## Port de game/js/engine/route-seed.js (mismo hash FNV-1a que Rng).
class_name RouteSeed

## Hash FNV-1a de 32 bits de cualquier valor convertido a cadena.
static func hash_ruta(valor: Variant) -> int:
	return Rng.hash_cadena(str(valor))

## Elige un candidato de forma estable para (semilla, nivel origen, ruta).
## route: la definición de la salida (usa id/texto/text/destino como identidad,
## con la misma semántica de "primer valor no vacío" que el || de JS).
static func elegir(semilla: String, origen_id: String, ruta: Dictionary, candidatos: Array) -> Variant:
	if candidatos.is_empty():
		return null
	var identidad := "ruta"
	for campo in ["id", "texto", "text", "destino"]:
		var v: Variant = ruta.get(campo)
		if v is String and not (v as String).is_empty():
			identidad = v
			break
	var clave := "%s::%s::%s" % [semilla, origen_id, identidad]
	return candidatos[Rng.hash_cadena(clave) % candidatos.size()]
