// udim.elf: UDIM unpack (the algorithm of V-Sekai/fbx-udim-unpack) as a godot-sandbox guest.
// The guest reads only its arguments and returns arrays; it has no file, socket or host-object access.
// Chain with usd.elf on the host: usd_mesh_uvs -> udim_unpack -> usd_write_mesh. Independent of usd.elf.
#include <api.hpp>
#include "udim.h"
#include <cstdio>
#include <string>
#include <vector>

static Variant version() {
	return Variant(String("udim 1 fbx-udim-unpack c.CalculateUdimTile"));
}

// uvs: u, v per corner; counts: corners per polygon (3 for every triangle).
// Returns [tiles, uvs]: one tile id per polygon (-1 = not a UDIM polygon), and the UVs with tile > 1001 put back in 0-1.
// On a count mismatch it returns a one-element array holding an error string.
static Variant udim_unpack(PackedFloat32Array uvs, PackedInt32Array counts) {
	const std::vector<float> u = uvs.fetch();
	const std::vector<int32_t> c = counts.fetch();
	udim::Result r = udim::unpack(u, c);
	if (!r.ok) {
		// Empty packed arrays inside a returned Array are refused by the host marshaller, so signal the error with a string.
		return Variant(Array::make(Variant(String("error: corner counts do not match the uv count"))));
	}
	return Variant(Array::make(Variant(PackedInt32Array(r.tiles)), Variant(PackedFloat32Array(r.uvs))));
}

// Known-answer gate. planted != 0 changes the expected tile of one case, so the gate must report FAIL.
static Variant gate(int64_t planted) {
	// Triangles: A in 1001, B in 1002, C in 1011, D over one tile (-1), E on the U=1 boundary with min 0.9995 (-> 1002),
	// F in 1012.
	const std::vector<float> uv = {
		0.1f, 0.1f, 0.9f, 0.1f, 0.5f, 0.9f, // A
		1.1f, 0.1f, 1.9f, 0.1f, 1.5f, 0.9f, // B
		0.2f, 1.2f, 0.8f, 1.2f, 0.5f, 1.8f, // C
		0.0f, 0.0f, 2.5f, 0.0f, 1.0f, 1.0f, // D
		0.9995f, 0.1f, 1.6f, 0.1f, 1.3f, 0.9f, // E
		1.2f, 1.2f, 1.8f, 1.2f, 1.5f, 1.8f, // F
	};
	const std::vector<int32_t> counts = { 3, 3, 3, 3, 3, 3 };
	std::vector<int32_t> expect = { 1001, 1002, 1011, -1, 1002, 1012 };
	if (planted != 0) {
		expect[1] = 1003;
	}
	const udim::Result r = udim::unpack(uv, counts);
	std::string line;
	bool pass = r.ok && r.tiles == expect;
	// B's UVs must land back in 0-1 (1.1 -> 0.1, 1.9 -> 0.9); D (-1) and A (1001) must be unchanged.
	if (pass) {
		const std::vector<float> &o = r.uvs;
		auto near = [](float a, float b) { return a > b - 1e-4f && a < b + 1e-4f; };
		pass = near(o[6], 0.1f) && near(o[8], 0.9f) && near(o[10], 0.5f) // B u
				&& near(o[0], 0.1f) // A unchanged
				&& near(o[18], 0.0f) && near(o[20], 2.5f); // D unchanged
	}
	char buf[160];
	std::snprintf(buf, sizeof buf, "%s: %zu polygons, planted=%lld", pass ? "PASS" : "FAIL", r.tiles.size(), (long long)planted);
	return Variant(String(std::string(buf)));
}

int main() {
	ADD_API_FUNCTION(version, "String", "", "udim guest version");
	ADD_API_FUNCTION(udim_unpack, "Array", "PackedFloat32Array uvs, PackedInt32Array counts", "UDIM tile per polygon and the UVs back in 0-1; returns [tiles, uvs]");
	ADD_API_FUNCTION(gate, "String", "int planted", "known-answer gate; planted != 0 must FAIL");
	return 0;
}
