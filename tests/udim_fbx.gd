extends SceneTree
# usage: godot --headless --path <proj> -s res://udim_fbx.gd -- <udim.elf> <model.fbx> <out.txt>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var sb = ClassDB.instantiate("Sandbox")
	sb.memory_max = 512
	sb.references_max = 4096
	sb.allocations_max = 1000000
	root.add_child(sb)
	sb.load_buffer(FileAccess.get_file_as_bytes(a[0]))
	var doc := FBXDocument.new()
	var st := FBXState.new()
	doc.append_from_file(a[1], st)
	var scene: Node = doc.generate_scene(st)
	var out := FileAccess.open(a[2], FileAccess.WRITE)
	var rows: Array = []
	_walk(scene, rows)
	for r in rows:
		var m: ArrayMesh = r[1]
		var tiles := {}
		var tris := 0
		var umin := 1e30
		var umax := -1e30
		var vmin := 1e30
		var vmax := -1e30
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var uv = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			if uv == null:
				continue
			var flat := PackedFloat32Array()
			var counts := PackedInt32Array()
			var n: int = idx.size() if idx != null and idx.size() > 0 else uv.size()
			for k in n:
				var vi: int = idx[k] if idx != null and idx.size() > 0 else k
				flat.append(uv[vi].x)
				flat.append(uv[vi].y)
				umin = minf(umin, uv[vi].x); umax = maxf(umax, uv[vi].x)
				vmin = minf(vmin, uv[vi].y); vmax = maxf(vmax, uv[vi].y)
			for t in n / 3:
				counts.append(3)
			var res = sb.vmcall("udim_unpack", flat, counts)
			if res.size() == 2:
				for t in res[0]:
					tiles[t] = tiles.get(t, 0) + 1
				tris += res[0].size()
		out.store_line("%s: %d triangles, uv range u %.3f..%.3f v %.3f..%.3f, tiles %s" % [r[0], tris, umin, umax, vmin, vmax, str(tiles)])
	out.close()
	quit(0)
func _walk(n: Node, rows: Array) -> void:
	if n is MeshInstance3D and n.mesh is ArrayMesh:
		rows.append([n.name, n.mesh])
	for c in n.get_children():
		_walk(c, rows)
