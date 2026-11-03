extends SceneTree
# Export the largest UV island of an FBX mesh as OBJ: one vertex per UV key (3D position), faces by UV topology; also authored UV per vertex as vt.
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
	var vid := {}
	var vlist: Array = []
	var flist: Array = []
	for t in nt:
		if _find(par, corner[t * 3]) != big:
			continue
		var f: Array = []
		for k in 3:
			var c := corner[t * 3 + k]
			if not vid.has(c):
				vid[c] = vlist.size()
				vlist.append([pos[t][k], uvs[t][k]])
			f.append(vid[c] + 1)
		flist.append(f)
	var out := FileAccess.open(a[2], FileAccess.WRITE)
	for v in vlist:
		out.store_line("v %.9f %.9f %.9f" % [v[0].x, v[0].y, v[0].z])
	for v in vlist:
		out.store_line("vt %.9f %.9f" % [v[1].x, v[1].y])
	for f in flist:
		out.store_line("f %d/%d %d/%d %d/%d" % [f[0], f[0], f[1], f[1], f[2], f[2]])
	out.close()
	print("island: ", vlist.size(), " vertices, ", flist.size(), " triangles")
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
