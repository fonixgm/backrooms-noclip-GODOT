## Semilla global diaria. Port de game/js/engine/daily-seed.js.
## El original usa Intl con la zona Europe/Madrid; Godot no tiene base de
## zonas horarias, así que la regla horaria de Madrid se implementa a mano:
## CET (UTC+1) en invierno y CEST (UTC+2) entre el último domingo de marzo
## a la 01:00 UTC y el último domingo de octubre a la 01:00 UTC (regla UE).
class_name DailySeed

const TIME_ZONE := "Europe/Madrid"

## Clave del día ("YYYY-MM-DD") según la fecha civil de Madrid.
## unix_utc < 0 → ahora.
static func clave_dia(unix_utc: int = -1) -> String:
	if unix_utc < 0:
		unix_utc = int(Time.get_unix_time_from_system())
	var desfase: int = 7200 if _es_verano(unix_utc) else 3600
	var d := Time.get_datetime_dict_from_unix_time(unix_utc + desfase)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

## Semilla diaria completa, como DailySeed.seed().
static func semilla(unix_utc: int = -1) -> String:
	return "backrooms-diaria::" + clave_dia(unix_utc)

static func _es_verano(unix_utc: int) -> bool:
	var year: int = Time.get_datetime_dict_from_unix_time(unix_utc).year
	var inicio := _ultimo_domingo_00_utc(year, 3) + 3600
	var fin := _ultimo_domingo_00_utc(year, 10) + 3600
	return unix_utc >= inicio and unix_utc < fin

## Unix de las 00:00 UTC del último domingo del mes (marzo/octubre tienen 31 días).
static func _ultimo_domingo_00_utc(year: int, month: int) -> int:
	var t := Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": 31,
		"hour": 0, "minute": 0, "second": 0,
	})
	var dia_semana: int = Time.get_datetime_dict_from_unix_time(t).weekday
	return int(t) - dia_semana * 86400
