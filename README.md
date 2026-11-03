# interactor-udim-unpack

`udim.elf`: the UDIM unpack algorithm of [V-Sekai/fbx-udim-unpack](https://github.com/V-Sekai/fbx-udim-unpack) (`UdimUnpack.cpp`,
`CalculateUdimTile` and `CalculateUdimPart`) as a godot-sandbox guest, with no FBX SDK. It is independent of `usd.elf`.

For each polygon it takes the UV bounding box. If the box fits in one tile, the tile id is `1001 + 10 * vPart + uPart`
(1001 = U and V in 0-1, 1002 = one tile right, 1011 = one tile up). A polygon in a tile above 1001 has its UVs put back
into 0-1 with `uv -= floor(uv)`. A polygon whose UV range is over one tile is not a UDIM polygon: tile `-1`, UVs untouched.
A vertex stored just below an integer (within 0.001) while its polygon reaches past it is rounded into the next tile, as upstream does.
Like upstream, that boundary case leaves the vertex itself at 0.9995 while its neighbours wrap, so the polygon's UVs are not re-centred.

## API (one vmcall each)

| Call | Returns |
|---|---|
| `version()` | String |
| `udim_unpack(PackedFloat32Array uvs, PackedInt32Array counts)` | `[tiles, uvs]`: one tile id per polygon, UVs back in 0-1. On a count mismatch: `[error string]` |
| `gate(int planted)` | `PASS: ...` for `planted == 0`; `planted != 0` must report `FAIL` (the planted control) |

`uvs` is `u, v` per corner; `counts` is the number of corners per polygon (3 for every triangle). Empty packed arrays inside a
returned Array are refused by the host marshaller, which is why an error is a string.

## Build (macOS, the riscv64-sysroot toolchain)

```
cd <riscv64-sysroot checkout>
pixi exec -s clangxx -s lld -s cmake -s ninja -- sh -c 'cmake -S <this repo>/guest/udim -B <build dir> -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DDOUBLE_PRECISION=ON -DCMAKE_TOOLCHAIN_FILE=<sysroot>/toolchain.cmake \
  -DSANDBOX_API=<contract-guest-runtime>/vendor/sandbox-api && cmake --build <build dir>'
```

`-DDOUBLE_PRECISION=ON` is needed for a double-precision engine (check `.sandbox_variant` reads `SBXV 28000000`).
The built file is `<build dir>/udim`; rename it `udim.elf`. Do not commit the ELF: ship the CI artifact.

## Tests (`tests/`, Godot scripts run with the double editor)

- `udim_check.gd <udim.elf> <out.txt>`: loads the ELF, runs `gate(0)` (PASS), `gate(1)` (FAIL), a real call and a count mismatch.
- `udim_fbx.gd <udim.elf> <model.fbx> <out.txt>`: tile histogram for every mesh of an FBX.
- `uv_islands.gd <model.fbx> <mesh name> <out.txt> [grid]`: UV island count, 3D area against UV area per island, and a rasterised overlap test.

Run as `godot --headless --path <project> -s res://<script>.gd -- <args>` in a project where the `Sandbox` class is registered.

## Measured (2026-11-03, Nutty Mapley SHINANO FBX)

All 12 garment meshes sit in tile 1001 with UVs inside 0-1, so the unpack is a no-op there. The skirt has 11 UV islands (one of
3,432 triangles) and no two islands overlap in UV space (0 shared pixels on a 2048 grid).

## CI

`.github/workflows/guest.yml` builds `udim.elf` on a clean runner in single and double precision against a pinned
contract-guest-runtime and the riscv64 sysroot, shape-checks each (`tests/check_elf.sh`), and runs a control: the other
precision's check must fail. The ELFs are uploaded as artifacts.

## Not done

Running the gate in a sandbox host, and the translated-versus-interpreted byte check (no repository builds that host in CI yet). Locally the `.sandbox_variant`
size is confirmed only by the engine loading the ELF.
