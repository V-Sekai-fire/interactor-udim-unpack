extends SceneTree
# usage: godot --headless --path <proj> -s res://udim_check.gd -- <udim.elf>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var sb = ClassDB.instantiate("Sandbox")
	sb.memory_max = 256
	sb.references_max = 4096
	sb.allocations_max = 1000000
	root.add_child(sb)
	sb.load_buffer(FileAccess.get_file_as_bytes(a[0]))
	var out := FileAccess.open(a[1], FileAccess.WRITE)
	out.store_line("version: " + str(sb.vmcall("version")))
	out.store_line("gate(0): " + str(sb.vmcall("gate", 0)))
	out.store_line("gate(1) planted: " + str(sb.vmcall("gate", 1)))
	# real call: one triangle in 1002, one in 1001, one bad count
	var uvs := PackedFloat32Array([1.25, 0.25, 1.75, 0.25, 1.5, 0.75, 0.25, 0.25, 0.75, 0.25, 0.5, 0.75])
	var r = sb.vmcall("udim_unpack", uvs, PackedInt32Array([3, 3]))
	out.store_line("unpack tiles: " + str(r[0]) + " uvs: " + str(r[1]))
	var bad = sb.vmcall("udim_unpack", uvs, PackedInt32Array([3, 4]))
	out.store_line("mismatched counts -> size " + str(bad.size()) + ": " + str(bad[0]))
	out.close()
	quit(0)
