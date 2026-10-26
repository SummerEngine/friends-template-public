extends SceneTree
## Cast prep: the cast's logo-like pictures get their plain background keyed out (a flood fill of the edge colour with a soft edge) and
## are written as transparent PNGs, the originals untouched. Run it through tools/cast_prep.py (which also checks the output):
##
##   "$SUMMER" --headless --audio-driver Dummy --path demo -s "$PWD/tools/cast_prep.gd" -- --cast=/abs/dir [--also=a.png,b.jpg]
##
## Sources: cast.json brand.logo and balloon.picture, a goal_sign.png|.jpg|.jpeg|.webp in the cast dir, plus --also (file names in the cast dir).
## Output: <cast dir>/prepared/<source stem>.png and <cast dir>/prepared/manifest.json
##   {"format": "cast-prep-v1", "files": {"<source name>": {"sha256", "result", "background" (keyed), "size" [w, h] (keyed)}}}
## result: "keyed" (a prepared PNG exists), "transparent" (the border is already transparent), "busy" (the border is not one flat
## colour: a photo or scene, left alone), "empty" (keying would leave under 2% opaque pixels). A prepared file whose source is gone or
## no longer keyed is deleted, an empty prepared/ folder is removed. Same input bytes give the same output bytes.
## The last line is `CAST_PREP ok=true keyed=<n> skipped=<n>` or `CAST_PREP ok=false <reason>`; the exit code is 0 only for ok=true.
## Plain Image code: it needs nothing of the project it runs in and decodes png, jpg and webp.
##
## Algorithm (RGBA8, all distances are the largest per-channel difference, 0..255; ring = the 1 px border of the picture):
##  1. Ring pixels with alpha < 128 are transparent. At least 80% of the ring transparent -> "transparent".
##  2. The background colour bgc is the per-channel median (upper median) of the ring's opaque pixels. spread_p75 is the 75th percentile
##     (sorted distances, index floor(0.75 * (n - 1))) of the ring pixels' distances to bgc; transparent ring pixels count as distance 0.
##     tol = clamp(2.5 * spread_p75, 14, 36). The ring is near-uniform when at least 90% of its pixels are within tol of bgc
##     (that is the same as the 90th-percentile spread being <= tol); otherwise -> "busy".
##  3. Flood fill (4-connected) from every ring pixel that is transparent or within tol of bgc; a pixel joins when it is transparent or
##     within tol of bgc. The filled pixels are the background. Background-coloured regions the fill cannot reach stay opaque on purpose.
##  4. Soft edge: every other pixel within 4 px (Chebyshev) of a background pixel is in the band
##     (a soft, upscaled edge is several pixels wide; 2 px left a light fringe on a real logo). Its foreground colour fg is the mean colour
##     of the pixels in its 11x11 neighbourhood that are neither band nor background (none there: the 19x19 neighbourhood; none either: it stays
##     opaque and unchanged). When fg is within tol of bgc nothing can tell them apart and the pixel stays opaque. Else alpha = clamp(dot(p - bgc, fg - bgc) / |fg - bgc|^2, 0, 1),
##     colour = clamp((p - bgc * (1 - alpha)) / alpha), then alpha goes through a smoothstep from 0.15..0.85 to 0..1. Background pixels
##     get alpha 0, interior pixels are not touched.
##  5. Colour bleed: transparent pixels within 4 steps (4-connected, raster order) of a pixel with alpha > 0 take the colour of the pixel
##     they were reached from, so bilinear sampling shows no light halo. Other transparent pixels get bgc.
##  6. Trim: the box of pixels with alpha > 8 plus 4% of the longer side on each side (kept inside the picture); used when it cuts more
##     than 3% of the area, else the full canvas stays. Under 2% opaque pixels -> "empty". No scaling.
const FORMAT := "cast-prep-v1"
const PICTURE_SUFFIXES := ["png", "jpg", "jpeg", "webp"]
const PREPARED := "prepared"
const MANIFEST := "manifest.json"
const GOAL_SIGN := "goal_sign"
const BORDER_TRANSPARENT := 0.8
const BORDER_UNIFORM := 0.9
const TOL_FACTOR := 2.5
const TOL_MIN := 14.0
const TOL_MAX := 36.0
const BAND := 4
const FG_RADIUS := 5
const FG_RADIUS_WIDE := 9
const SMOOTH_LO := 0.15
const SMOOTH_HI := 0.85
const BLEED := 4
const SOLID := 8
const MIN_OPAQUE := 0.02
const TRIM_MARGIN := 0.04
const TRIM_GAIN := 0.03


func _init() -> void:
	var options := _options()
	var cast_dir: String = options.get("cast", "")
	if cast_dir == "" or not DirAccess.dir_exists_absolute(cast_dir):
		_finish(false, "--cast=<absolute dir> must name an existing folder")
		return
	cast_dir = cast_dir.simplify_path()
	var also: Array = []
	for name in String(options.get("also", "")).split(",", false):
		also.append(name.strip_edges())
	var sources := _sources(cast_dir, also)
	var prepared_dir := cast_dir.path_join(PREPARED)
	var files := {}
	var kept := {}  # file names that stay in prepared/
	var keyed := 0
	for name in sources:
		var stem: String = name.get_basename()
		var target: String = stem + ".png"
		var path: String = cast_dir.path_join(name)
		var outcome: Dictionary = _prep(path)
		if outcome.has("error"):
			_finish(false, "%s: %s" % [name, outcome["error"]])
			return
		var entry := {"sha256": FileAccess.get_sha256(path), "result": outcome["result"]}
		if outcome["result"] == "keyed":
			if kept.has(target):
				_finish(false, "%s and another picture would both become prepared/%s; rename one" % [name, target])
				return
			DirAccess.make_dir_recursive_absolute(prepared_dir)
			var image: Image = outcome["image"]
			if image.save_png(prepared_dir.path_join(target)) != OK:
				_finish(false, "cannot write prepared/%s" % target)
				return
			kept[target] = true
			entry["background"] = outcome["background"]
			entry["size"] = [image.get_width(), image.get_height()]
			keyed += 1
		files[name] = entry
		print("CAST_PREP file=%s result=%s%s" % [name, entry["result"], (" background=%s size=%dx%d" % [entry["background"], entry["size"][0], entry["size"][1]]) if entry["result"] == "keyed" else ""])
	var manifest_path := prepared_dir.path_join(MANIFEST)
	if files.is_empty():
		_clean(prepared_dir, {})
	else:
		DirAccess.make_dir_recursive_absolute(prepared_dir)
		kept[MANIFEST] = true
		var manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
		if manifest == null:
			_finish(false, "cannot write prepared/%s" % MANIFEST)
			return
		manifest.store_string(JSON.stringify({"format": FORMAT, "files": files}, "  ", true) + "\n")
		manifest.close()
		_clean(prepared_dir, kept)
	_finish(true, "keyed=%d skipped=%d" % [keyed, files.size() - keyed])


func _finish(ok: bool, text: String) -> void:
	print("CAST_PREP ok=%s %s" % ["true" if ok else "false", text])
	quit(0 if ok else 1)


func _options() -> Dictionary:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			options[argument.get_slice("=", 0).substr(2)] = argument.substr(argument.find("=") + 1)
	return options


func _is_picture_name(name: String) -> bool:
	return name != "" and name == name.get_file() and not name.begins_with(".") and not name.contains("\\") \
		and PICTURE_SUFFIXES.has(name.get_extension().to_lower())


## The cast's source pictures that exist, sorted by file name.
func _sources(cast_dir: String, also: Array) -> Array:
	var names := {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(cast_dir.path_join("cast.json")))
	if parsed is Dictionary:
		for place in [["brand", "logo"], ["balloon", "picture"]]:
			var section = parsed.get(place[0], {})
			if section is Dictionary and section.get(place[1], "") is String:
				names[section.get(place[1], "")] = true
	for file in DirAccess.get_files_at(cast_dir):
		if file.get_basename() == GOAL_SIGN:
			names[file] = true
	for name in also:
		names[name] = true
	var found := []
	for name in names:
		if _is_picture_name(name) and FileAccess.file_exists(cast_dir.path_join(name)):
			found.append(name)
	found.sort()
	return found


## Deletes everything in prepared/ that is not in `kept` (and its import sidecars); removes the folder when nothing is left.
func _clean(prepared_dir: String, kept: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(prepared_dir):
		return
	for file in DirAccess.get_files_at(prepared_dir):
		var base := file
		for sidecar in [".import", ".uid"]:
			if base.ends_with(sidecar):
				base = base.trim_suffix(sidecar)
		if not kept.has(base):
			DirAccess.remove_absolute(prepared_dir.path_join(file))
	if DirAccess.get_files_at(prepared_dir).is_empty() and DirAccess.get_directories_at(prepared_dir).is_empty():
		DirAccess.remove_absolute(prepared_dir)


## {"result": "transparent"|"busy"|"empty"} or {"result": "keyed", "image": Image, "background": "#rrggbb"} or {"error": text}.
func _prep(path: String) -> Dictionary:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return {"error": "cannot be read as a picture (png, jpg or webp)"}
	image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()
	var count := w * h
	var d: PackedByteArray = image.get_data()

	# 1. The ring.
	var ring := PackedInt32Array()
	for x in range(w):
		ring.append(x)
		if h > 1:
			ring.append((h - 1) * w + x)
	for y in range(1, h - 1):
		ring.append(y * w)
		if w > 1:
			ring.append(y * w + w - 1)
	var clear := 0
	var reds := PackedInt32Array()
	var greens := PackedInt32Array()
	var blues := PackedInt32Array()
	for i in ring:
		var o := i * 4
		if d[o + 3] < 128:
			clear += 1
		else:
			reds.append(d[o])
			greens.append(d[o + 1])
			blues.append(d[o + 2])
	if clear >= BORDER_TRANSPARENT * ring.size():
		return {"result": "transparent"}

	# 2. Background colour and tolerance.
	reds.sort()
	greens.sort()
	blues.sort()
	var middle := reds.size() / 2
	var br := reds[middle]
	var bg_green := greens[middle]
	var bb := blues[middle]
	var distances := PackedInt32Array()
	for i in ring:
		var o := i * 4
		if d[o + 3] < 128:
			distances.append(0)
		else:
			distances.append(maxi(maxi(absi(d[o] - br), absi(d[o + 1] - bg_green)), absi(d[o + 2] - bb)))
	var sorted := distances.duplicate()
	sorted.sort()
	var spread := sorted[int(floor(0.75 * (sorted.size() - 1)))]
	var tol := clampf(TOL_FACTOR * spread, TOL_MIN, TOL_MAX)
	var within := 0
	for value in distances:
		if value <= tol:
			within += 1
	if within < BORDER_UNIFORM * distances.size():
		return {"result": "busy"}

	# 3. Flood fill from the ring.
	var near := PackedByteArray()
	near.resize(count)
	for i in range(count):
		var o := i * 4
		if d[o + 3] < 128 or (absi(d[o] - br) <= tol and absi(d[o + 1] - bg_green) <= tol and absi(d[o + 2] - bb) <= tol):
			near[i] = 1
	var bg := PackedByteArray()
	bg.resize(count)
	var stack := PackedInt32Array()
	stack.resize(count)
	var top := 0
	for i in ring:
		if near[i] == 1 and bg[i] == 0:
			bg[i] = 1
			stack[top] = i
			top += 1
	while top > 0:
		top -= 1
		var i := stack[top]
		var x := i % w
		var y := i / w
		if x > 0 and near[i - 1] == 1 and bg[i - 1] == 0:
			bg[i - 1] = 1
			stack[top] = i - 1
			top += 1
		if x < w - 1 and near[i + 1] == 1 and bg[i + 1] == 0:
			bg[i + 1] = 1
			stack[top] = i + 1
			top += 1
		if y > 0 and near[i - w] == 1 and bg[i - w] == 0:
			bg[i - w] = 1
			stack[top] = i - w
			top += 1
		if y < h - 1 and near[i + w] == 1 and bg[i + w] == 0:
			bg[i + w] = 1
			stack[top] = i + w
			top += 1

	# 4. The band: pixels within BAND px of a background pixel. A background pixel with a non-background 4-neighbour is enough to find them all.
	var band := PackedByteArray()
	band.resize(count)
	var touch := PackedByteArray()  # background and band pixels that can border the picture: bleed candidates
	touch.resize(count)
	for i in range(count):
		if bg[i] == 0:
			continue
		var x := i % w
		var y := i / w
		var edge := (x > 0 and bg[i - 1] == 0) or (x < w - 1 and bg[i + 1] == 0) or (y > 0 and bg[i - w] == 0) or (y < h - 1 and bg[i + w] == 0)
		if not edge:
			continue
		touch[i] = 1
		for dy in range(-BAND, BAND + 1):
			var yy := y + dy
			if yy < 0 or yy >= h:
				continue
			for dx in range(-BAND, BAND + 1):
				var xx := x + dx
				if xx >= 0 and xx < w and bg[yy * w + xx] == 0:
					band[yy * w + xx] = 1
	var out := d.duplicate()
	for i in range(count):
		if bg[i] == 1:
			out[i * 4 + 3] = 0
	for i in range(count):
		if band[i] == 0:
			continue
		var x := i % w
		var y := i / w
		var sum_r := 0
		var sum_g := 0
		var sum_b := 0
		var n := 0
		for radius in [FG_RADIUS, FG_RADIUS_WIDE]:  # a thin speck has no interior pixel close by: look wider before giving up
			for yy in range(maxi(y - radius, 0), mini(y + radius, h - 1) + 1):
				for xx in range(maxi(x - radius, 0), mini(x + radius, w - 1) + 1):
					var j := yy * w + xx
					if bg[j] == 0 and band[j] == 0:
						sum_r += d[j * 4]
						sum_g += d[j * 4 + 1]
						sum_b += d[j * 4 + 2]
						n += 1
			if n > 0:
				break
		if n == 0:
			continue
		var fr := float(sum_r) / n
		var fg := float(sum_g) / n
		var fb := float(sum_b) / n
		var ar := fr - br
		var ag := fg - bg_green
		var ab := fb - bb
		if maxf(maxf(absf(ar), absf(ag)), absf(ab)) < tol:
			continue
		var o := i * 4
		var pr := d[o]
		var pg := d[o + 1]
		var pb := d[o + 2]
		var alpha := clampf(((pr - br) * ar + (pg - bg_green) * ag + (pb - bb) * ab) / (ar * ar + ag * ag + ab * ab), 0.0, 1.0)
		var t := clampf((alpha - SMOOTH_LO) / (SMOOTH_HI - SMOOTH_LO), 0.0, 1.0)
		out[o + 3] = int(round(t * t * (3.0 - 2.0 * t) * d[o + 3]))
		if alpha < 0.02:
			out[o] = clampi(int(round(fr)), 0, 255)
			out[o + 1] = clampi(int(round(fg)), 0, 255)
			out[o + 2] = clampi(int(round(fb)), 0, 255)
		else:
			out[o] = clampi(int(round((pr - br * (1.0 - alpha)) / alpha)), 0, 255)
			out[o + 1] = clampi(int(round((pg - bg_green * (1.0 - alpha)) / alpha)), 0, 255)
			out[o + 2] = clampi(int(round((pb - bb * (1.0 - alpha)) / alpha)), 0, 255)
		touch[i] = 1

	# 5. Colour bleed. Level one: transparent pixels that touch a visible one; then BLEED - 1 more steps outwards.
	var seen := PackedByteArray()
	seen.resize(count)
	var frontier := PackedInt32Array()
	for i in range(count):
		if touch[i] == 0 or out[i * 4 + 3] != 0:
			continue
		var x := i % w
		var y := i / w
		var source := -1
		if x > 0 and out[(i - 1) * 4 + 3] != 0:
			source = i - 1
		elif x < w - 1 and out[(i + 1) * 4 + 3] != 0:
			source = i + 1
		elif y > 0 and out[(i - w) * 4 + 3] != 0:
			source = i - w
		elif y < h - 1 and out[(i + w) * 4 + 3] != 0:
			source = i + w
		if source >= 0:
			seen[i] = 1
			frontier.append(i)
			out[i * 4] = out[source * 4]
			out[i * 4 + 1] = out[source * 4 + 1]
			out[i * 4 + 2] = out[source * 4 + 2]
	for step in range(BLEED - 1):
		var next := PackedInt32Array()
		for i in frontier:
			var x := i % w
			var y := i / w
			for neighbour in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
				if neighbour >= 0 and out[neighbour * 4 + 3] == 0 and seen[neighbour] == 0:
					seen[neighbour] = 1
					next.append(neighbour)
					out[neighbour * 4] = out[i * 4]
					out[neighbour * 4 + 1] = out[i * 4 + 1]
					out[neighbour * 4 + 2] = out[i * 4 + 2]
		frontier = next
	for i in range(count):
		if out[i * 4 + 3] == 0 and seen[i] == 0:
			out[i * 4] = br
			out[i * 4 + 1] = bg_green
			out[i * 4 + 2] = bb

	# 6. Trim to the picture's box.
	var solid := 0
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in range(h):
		for x in range(w):
			if out[(y * w + x) * 4 + 3] > SOLID:
				solid += 1
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
				if y < min_y:
					min_y = y
				if y > max_y:
					max_y = y
	if solid < MIN_OPAQUE * count:
		return {"result": "empty"}
	var result := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
	var margin := int(round(TRIM_MARGIN * maxi(w, h)))
	var left := maxi(min_x - margin, 0)
	var upper := maxi(min_y - margin, 0)
	var right := mini(max_x + margin, w - 1)
	var lower := mini(max_y + margin, h - 1)
	var crop_area := (right - left + 1) * (lower - upper + 1)
	if crop_area < (1.0 - TRIM_GAIN) * count:
		result = result.get_region(Rect2i(left, upper, right - left + 1, lower - upper + 1))
	return {"result": "keyed", "image": result, "background": "#%02x%02x%02x" % [br, bg_green, bb]}
