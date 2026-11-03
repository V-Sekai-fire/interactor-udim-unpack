# interactor-udim-unpack

`udim.elf` unpacks UDIM tiles inside a godot-sandbox guest. It is the algorithm of
[V-Sekai/fbx-udim-unpack](https://github.com/V-Sekai/fbx-udim-unpack) (`UdimUnpack.cpp`, `CalculateUdimTile` and
`CalculateUdimPart`) with no FBX SDK, and it is independent of `usd.elf`. Give it UVs and the corner count of each polygon;
it returns one tile id per polygon and the UVs folded back into 0-1.

## Tile edges

A UDIM tile id is the polygon's UV bounding box turned into a number, and the edges are where it gets hard.

- If the box fits in one tile, the id is `1001 + 10 * vPart + uPart` (1001 = U and V in 0-1, 1002 = one tile right, 1011 = one tile up).
  A polygon in a tile above 1001 has its UVs put back into 0-1 with `uv -= floor(uv)`.
- If the UV range is over one tile, the polygon is not a UDIM polygon: tile `-1`, UVs untouched.
- A vertex stored just below an integer (within 0.001) while its polygon reaches past it is rounded into the next tile, as upstream does.
  Like upstream, that boundary case leaves the vertex itself at 0.9995 while its neighbours wrap, so the polygon's UVs are not re-centred.
- A double-precision engine needs a double-precision guest (`.sandbox_variant` reads `SBXV 28000000`), so there are two builds.
- The host marshaller refuses empty packed arrays inside a returned Array, which is why an error is a string.

## The three calls

The guest keeps upstream's behaviour, boundary case included, and exposes three calls (one vmcall each):

| Call | Returns |
|---|---|
| `version()` | String |
| `udim_unpack(PackedFloat32Array uvs, PackedInt32Array counts)` | `[tiles, uvs]`: one tile id per polygon, UVs back in 0-1. On a count mismatch: `[error string]` |
| `gate(int planted)` | `PASS: ...` for `planted == 0`; `planted != 0` must report `FAIL` (the planted control) |

`uvs` is `u, v` per corner; `counts` is the number of corners per polygon (3 for every triangle).

The gate is a known-answer check on a fixed mesh of six triangles. Its control is planted in the input: `gate(1)` moves one triangle a
tile to the right and leaves the expected answer alone, so the real unpack returns a different tile and the gate must report `FAIL`.
CI does the same at the build level with a real input: the other precision's ELF is checked and must fail. The ELF is a build
product, so it is not committed: ship the CI artifact.

## Build, test, ship

**Build** (macOS, the riscv64-sysroot toolchain):

```
cd <riscv64-sysroot checkout>
pixi exec -s clangxx -s lld -s cmake -s ninja -- sh -c 'cmake -S <this repo>/guest/udim -B <build dir> -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DDOUBLE_PRECISION=ON -DCMAKE_TOOLCHAIN_FILE=<sysroot>/toolchain.cmake \
  -DSANDBOX_API=<contract-guest-runtime>/vendor/sandbox-api && cmake --build <build dir>'
```

`-DDOUBLE_PRECISION=ON` is needed for a double-precision engine (check `.sandbox_variant` reads `SBXV 28000000`).
The built file is `<build dir>/udim`; rename it `udim.elf`. Do not commit the ELF.

**Tests** (`tests/`, Godot scripts run with the double editor):

- `udim_check.gd <udim.elf> <out.txt>`: loads the ELF, runs `gate(0)` (PASS), `gate(1)` (FAIL), a real call and a count mismatch.
- `udim_fbx.gd <udim.elf> <model.fbx> <out.txt>`: tile histogram for every mesh of an FBX.
- `uv_islands.gd <model.fbx> <mesh name> <out.txt> [grid]`: UV island count, 3D area against UV area per island, and a rasterised overlap test.

Run as `godot --headless --path <project> -s res://<script>.gd -- <args>` in a project where the `Sandbox` class is registered.

**CI:** `.github/workflows/guest.yml` builds `udim.elf` on a clean runner in single and double precision against a pinned
contract-guest-runtime and the riscv64 sysroot, shape-checks each (`tests/check_elf.sh`), and runs a control: the other
precision's check must fail. The ELFs are uploaded as artifacts.

**Not done:** running the gate in a sandbox host, and the translated-versus-interpreted byte check (no repository builds that host in
CI yet). Locally the `.sandbox_variant` size is confirmed only by the engine loading the ELF.
