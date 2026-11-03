extends SceneTree
# Per-triangle stretch of the authored UV against 3D for the largest UV island of an FBX mesh.
# s1,s2 = singular values of the map UV -> 3D (per triangle); isotropy = s2/s1; area scale = s1*s2.
# usage: -- <model.fbx> <mesh name> <out.txt>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
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
	# islands by quantised UV key (as in uv_islands.gd)
	var key_id := {}
	var par := PackedInt32Array()
	var corner := PackedInt32Array()
	for t in nt:
		for k in 3:
			var u: Vector2 = uvs[t][k]
			var key := Vector2i(roundi(u.x * 1.0e6), roundi(u.y * 1.0e6))
			if not key_id.has(key):
				key_id[key] = par.size()
				par.append(par.size())
			corner.append(key_id[key])
	for t in nt:
		_union(par, corner[t * 3], corner[t * 3 + 1])
		_union(par, corner[t * 3 + 1], corner[t * 3 + 2])
	var cnt := {}
	for t in nt:
		var r := _find(par, corner[t * 3])
		cnt[r] = cnt.get(r, 0) + 1
	var big := -1
	var best := 0
	for r in cnt:
		if cnt[r] > best:
			best = cnt[r]
			big = r
	var iso := PackedFloat64Array()
	var asc := PackedFloat64Array()
	var uv_tot := 0.0
	var a3_tot := 0.0
	for t in nt:
		if _find(par, corner[t * 3]) != big:
			continue
		var e1u: Vector2 = uvs[t][1] - uvs[t][0]
		var e2u: Vector2 = uvs[t][2] - uvs[t][0]
		var e1: Vector3 = pos[t][1] - pos[t][0]
		var e2: Vector3 = pos[t][2] - pos[t][0]
		var det := e1u.x * e2u.y - e1u.y * e2u.x
		if absf(det) < 1e-14:
			continue
		# Jacobian J (3x2) = [e1 e2] * inv([e1u e2u])
		var i00 := e2u.y / det
		var i01 := -e2u.x / det
		var i10 := -e1u.y / det
		var i11 := e1u.x / det
		var ju: Vector3 = e1 * i00 + e2 * i10
		var jv: Vector3 = e1 * i01 + e2 * i11
		# singular values of [ju jv]: eigenvalues of the 2x2 J^T J
		var aa := ju.dot(ju)
		var bb := ju.dot(jv)
		var cc := jv.dot(jv)
		var tr := aa + cc
		var disc := sqrt(maxf(tr * tr * 0.25 - (aa * cc - bb * bb), 0.0))
		var l1 := tr * 0.5 + disc
		var l2 := maxf(tr * 0.5 - disc, 0.0)
		iso.append(sqrt(l2 / maxf(l1, 1e-30)))
		asc.append(sqrt(l1 * l2))
		uv_tot += absf(det) * 0.5
		a3_tot += e1.cross(e2).length() * 0.5
	iso.sort()
	asc.sort()
	var n2 := iso.size()
	var out := FileAccess.open(a[2], FileAccess.WRITE)
	out.store_line("mesh %s, largest UV island: %d triangles" % [a[1], n2])
	out.store_line("isotropy s2/s1 (1 = pure scale, no shear or anisotropic stretch): p5 %.3f median %.3f p95-low... min %.3f" % [iso[int(n2 * 0.05)], iso[n2 / 2], iso[0]])
	out.store_line("area scale (3D area per UV area, per triangle): p5 %.3f median %.3f p95 %.3f max %.3f" % [asc[int(n2 * 0.05)], asc[n2 / 2], asc[int(n2 * 0.95)], asc[n2 - 1]])
	out.store_line("whole island: UV area %.5f, 3D area %.5f, uniform scale %.4f (linear) " % [uv_tot, a3_tot, sqrt(a3_tot / uv_tot)])
	var med := asc[n2 / 2]
	var within10 := 0
	var iso90 := 0
	for k in n2:
		if absf(asc[k] / med - 1.0) <= 0.1:
			within10 += 1
		if iso[k] >= 0.9:
			iso90 += 1
	out.store_line("triangles with area scale within 10 %% of the median: %.1f %%; with isotropy >= 0.9: %.1f %%" % [100.0 * within10 / n2, 100.0 * iso90 / n2])
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
