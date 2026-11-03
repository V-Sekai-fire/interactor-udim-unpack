extends SceneTree
# UV islands of one FBX mesh: count, UV bbox, 3D vs UV area, and island overlap in UV space (rasterised).
# usage: godot --headless --path <proj> -s res://uv_islands.gd -- <model.fbx> <mesh name> <out.txt> [grid=2048]
const KEY_Q := 1.0e6
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var grid := int(a[3]) if a.size() > 3 else 2048
	var doc := FBXDocument.new()
	var st := FBXState.new()
	doc.append_from_file(a[0], st)
	var scene: Node = doc.generate_scene(st)
	var mesh: ArrayMesh = null
	var stack: Array = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.name == a[1] and n.mesh is ArrayMesh:
			mesh = n.mesh
		stack.append_array(n.get_children())
	var out := FileAccess.open(a[2], FileAccess.WRITE)
	if mesh == null:
		out.store_line("mesh not found: " + a[1])
		quit(1)
		return
	# triangles: UV corners and 3D positions
	var uvs: Array = []
	var pos: Array = []
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var n: int = idx.size() if idx != null and idx.size() > 0 else vv.size()
		for t in n / 3:
			var tu: Array = []
			var tp: Array = []
			for k in 3:
				var vi: int = idx[t * 3 + k] if idx != null and idx.size() > 0 else t * 3 + k
				tu.append(uv[vi])
				tp.append(vv[vi])
			uvs.append(tu)
			pos.append(tp)
	var nt := uvs.size()
	# union-find over quantised UV corner keys
	var key_id := {}
	var par := PackedInt32Array()
	var corner := PackedInt32Array()
	for t in nt:
		for k in 3:
			var u: Vector2 = uvs[t][k]
			var key := Vector2i(roundi(u.x * KEY_Q), roundi(u.y * KEY_Q))
			if not key_id.has(key):
				key_id[key] = par.size()
				par.append(par.size())
			corner.append(key_id[key])
	for t in nt:
		_union(par, corner[t * 3], corner[t * 3 + 1])
		_union(par, corner[t * 3 + 1], corner[t * 3 + 2])
	var isl := {}
	var tri_island := PackedInt32Array()
	for t in nt:
		var r := _find(par, corner[t * 3])
		if not isl.has(r):
			isl[r] = isl.size()
		tri_island.append(isl[r])
	var ni := isl.size()
	var uv_area := PackedFloat64Array()
	var a3 := PackedFloat64Array()
	var cnt := PackedInt32Array()
	var lo: Array = []
	var hi: Array = []
	for i in ni:
		uv_area.append(0.0)
		a3.append(0.0)
		cnt.append(0)
		lo.append(Vector2(1e9, 1e9))
		hi.append(Vector2(-1e9, -1e9))
	for t in nt:
		var i := tri_island[t]
		var u0: Vector2 = uvs[t][0]
		var u1: Vector2 = uvs[t][1]
		var u2: Vector2 = uvs[t][2]
		uv_area[i] += absf((u1 - u0).cross(u2 - u0)) * 0.5
		a3[i] += ((pos[t][1] - pos[t][0]).cross(pos[t][2] - pos[t][0])).length() * 0.5
		cnt[i] += 1
		for u in [u0, u1, u2]:
			lo[i] = Vector2(minf(lo[i].x, u.x), minf(lo[i].y, u.y))
			hi[i] = Vector2(maxf(hi[i].x, u.x), maxf(hi[i].y, u.y))
	# rasterise: per pixel, the first island seen; a different island on the same pixel counts as overlap
	var owner := PackedInt32Array()
	owner.resize(grid * grid)
	owner.fill(-1)
	var overlap := PackedByteArray()
	overlap.resize(grid * grid)
	var covered := 0
	var over_px := 0
	var over_pair := {}
	for t in nt:
		var i := tri_island[t]
		var p0: Vector2 = uvs[t][0] * grid
		var p1: Vector2 = uvs[t][1] * grid
		var p2: Vector2 = uvs[t][2] * grid
		var x0 := maxi(0, int(floor(minf(p0.x, minf(p1.x, p2.x)))))
		var x1 := mini(grid - 1, int(ceil(maxf(p0.x, maxf(p1.x, p2.x)))))
		var y0 := maxi(0, int(floor(minf(p0.y, minf(p1.y, p2.y)))))
		var y1 := mini(grid - 1, int(ceil(maxf(p0.y, maxf(p1.y, p2.y)))))
		var den := (p1.y - p2.y) * (p0.x - p2.x) + (p2.x - p1.x) * (p0.y - p2.y)
		if absf(den) < 1e-12:
			continue
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var px := Vector2(x + 0.5, y + 0.5)
				var l0 := ((p1.y - p2.y) * (px.x - p2.x) + (p2.x - p1.x) * (px.y - p2.y)) / den
				var l1 := ((p2.y - p0.y) * (px.x - p2.x) + (p0.x - p2.x) * (px.y - p2.y)) / den
				var l2 := 1.0 - l0 - l1
				if l0 < 0.0 or l1 < 0.0 or l2 < 0.0:
					continue
				var o := owner[y * grid + x]
				if o == -1:
					owner[y * grid + x] = i
					covered += 1
				elif o != i and overlap[y * grid + x] == 0:
					overlap[y * grid + x] = 1
					over_px += 1
					var pk := Vector2i(mini(o, i), maxi(o, i))
					over_pair[pk] = over_pair.get(pk, 0) + 1
	out.store_line("mesh %s: %d triangles, %d UV islands, grid %d" % [a[1], nt, ni, grid])
	out.store_line("covered pixels %d (%.1f %% of atlas), pixels shared by two islands %d (%.2f %% of covered), island pairs overlapping %d" % [covered, 100.0 * covered / (grid * grid), over_px, 100.0 * over_px / maxf(covered, 1), over_pair.size()])
	var order: Array = range(ni)
	order.sort_custom(func(p, q): return cnt[p] > cnt[q])
	for r in order.slice(0, 12):
		var ratio := a3[r] / maxf(uv_area[r], 1e-12)
		out.store_line("island %3d: %5d tris, uv bbox (%.3f,%.3f)-(%.3f,%.3f), uv area %.4f, 3D area %.4f m2-ish, 3D/UV %.2f" % [r, cnt[r], lo[r].x, lo[r].y, hi[r].x, hi[r].y, uv_area[r], a3[r], ratio])
	out.close()
	quit(0)
func _find(par: PackedInt32Array, x: int) -> int:
	while par[x] != x:
		par[x] = par[par[x]]
		x = par[x]
	return x
func _union(par: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(par, a)
	var rb := _find(par, b)
	if ra != rb:
		par[ra] = rb
