// UDIM unpack: the algorithm of V-Sekai/fbx-udim-unpack (UdimUnpack.cpp, c. CalculateUdimTile / CalculateUdimPart),
// ported to plain C++ with no FBX SDK. Per polygon: take the UV bounding box; if it fits one tile, the tile id is
// 1001 + 10 * vPart + uPart; a polygon in a tile above 1001 gets its UVs put back into 0-1 with uv -= floor(uv).
// A polygon whose UV range exceeds one tile is not a UDIM polygon: tile -1, UVs untouched.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace udim {

constexpr double kBoundaryTolerance = 0.001; // upstream: kBoundaryTolerance

// Upstream CalculateUdimPart. A vertex meant to sit on U = 1.0 but stored as 0.999999 must not drag a polygon into the
// tile to its left: if min is within the tolerance below the next integer and max is past it, round up.
inline int part(double mn, double mx) {
	int i = static_cast<int>(mn);
	if (static_cast<double>(i) + 1.0 - mn <= kBoundaryTolerance && mx > i + 1.0) {
		++i;
	}
	return i;
}

// Upstream CalculateUdimTile; -1 when the range is over one tile or the U part is past the ninth tile.
inline int tile(double min_u, double min_v, double max_u, double max_v) {
	if ((max_u - min_u) > (1.0 + kBoundaryTolerance) || (max_v - min_v) > (1.0 + kBoundaryTolerance)) {
		return -1;
	}
	const int u_part = part(min_u, max_u);
	const int v_part = part(min_v, max_v);
	if (u_part > 9) {
		return -1;
	}
	return 1001 + v_part * 10 + u_part;
}

struct Result {
	std::vector<int32_t> tiles; // one per polygon
	std::vector<float> uvs; // two floats per corner, same layout as the input
	bool ok = false; // false when the corner counts do not match the UV count
};

// uvs: u, v per corner. counts: corners per polygon. UVs are read as double; the output keeps the input layout.
inline Result unpack(const std::vector<float> &uvs, const std::vector<int32_t> &counts) {
	Result r;
	int64_t total = 0;
	for (int32_t c : counts) {
		if (c < 0) {
			return r;
		}
		total += c;
	}
	if (total * 2 != static_cast<int64_t>(uvs.size())) {
		return r;
	}
	r.uvs = uvs;
	r.tiles.reserve(counts.size());
	int64_t base = 0;
	for (int32_t c : counts) {
		if (c == 0) {
			r.tiles.push_back(-1);
			continue;
		}
		double min_u = uvs[base * 2], max_u = min_u, min_v = uvs[base * 2 + 1], max_v = min_v;
		for (int32_t k = 1; k < c; ++k) {
			const double u = uvs[(base + k) * 2], v = uvs[(base + k) * 2 + 1];
			min_u = std::min(min_u, u);
			max_u = std::max(max_u, u);
			min_v = std::min(min_v, v);
			max_v = std::max(max_v, v);
		}
		const int t = tile(min_u, min_v, max_u, max_v);
		r.tiles.push_back(t);
		if (t > 1001) {
			for (int32_t k = 0; k < c; ++k) {
				const double u = uvs[(base + k) * 2], v = uvs[(base + k) * 2 + 1];
				r.uvs[(base + k) * 2] = static_cast<float>(u - std::floor(u));
				r.uvs[(base + k) * 2 + 1] = static_cast<float>(v - std::floor(v));
			}
		}
		base += c;
	}
	r.ok = true;
	return r;
}

} // namespace udim
