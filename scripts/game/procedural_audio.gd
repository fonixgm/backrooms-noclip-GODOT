## ProceduralAudio — todo el audio generado en motor con GDScript.
## Nada de ficheros de audio externos:
##   - Zumbido fluorescente continuo (AudioStreamGenerator, modulado con el
##     parpadeo de las luces; el bucle de relleno vive en level_0.gd).
##   - Pasos con variación húmeda (ruido filtrado + pitch aleatorio).
##   - Susurro de alucinación (ruido suave breve).
class_name ProceduralAudio

## Generador de zumbido fluorescente. Se rellena desde _process() con
## push_frame(); la onda son 60 Hz + armónicos + ruido, con envolvente que
## pulsa con el parpadeo (level_0.gd lo modula con _flicker_actual()).
static func generador_zumbido() -> AudioStreamGenerator:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.6
	return gen

## Paso: ráfaga corta de ruido filtrado. 'humedo' aumenta el low-pass
## (paso sobre moqueta húmeda); cada llamada genera una variante distinta
## de semilla para que los pasos no suenen idénticos.
static func paso(variante: int, humedo: bool) -> AudioStreamWAV:
	var rate := 22050
	var seg := 0.13
	var n := int(rate * seg)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = variante + (9999 if humedo else 0)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var env := exp(-3.2 * t)
		var nz := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, nz, 0.30 if humedo else 0.50)
		lp2 = lerpf(lp2, lp, 0.18 if humedo else 0.40)
		var s := lp2 * 0.55 * env
		var v := int(clampf(s, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

## Susurro breve para alucinaciones auditivas a baja cordura.
static func susurro() -> AudioStreamWAV:
	var rate := 16000
	var seg := 0.7
	var n := int(rate * seg)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var lp := 0.0
	var envolvente := 0.0
	for i in n:
		var t := float(i) / n
		# ataque/decaimiento suave
		envolvente = minf(1.0, envolvente + 0.02) if t < 0.15 else maxf(0.0, envolvente - 0.004)
		var nz := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, nz, 0.12)
		var s := lp * 0.30 * envolvente
		var v := int(clampf(s, -1.0, 1.0) * 30000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
