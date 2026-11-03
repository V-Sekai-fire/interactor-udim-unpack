#!/bin/sh
# Shape check for a built udim ELF: static RISC-V, the three API names, and the .sandbox_variant size for its precision.
# usage: check_elf.sh <elf> <single|double>
set -e
ELF="$1"
case "$2" in
  single) WORD=18000000 ;;  # Variant is 24 bytes
  double) WORD=28000000 ;;  # Variant is 40 bytes
  *) echo "precision must be single or double" >&2; exit 2 ;;
esac
file "$ELF" | grep -q "RISC-V"
file "$ELF" | grep -q "statically linked"
for fn in version udim_unpack gate; do
  strings "$ELF" | grep -qx "$fn" || { echo "missing API name: $fn" >&2; exit 1; }
done
readelf -x .sandbox_variant "$ELF" | grep -q "53425856 $WORD" || { echo "wrong .sandbox_variant for $2" >&2; exit 1; }
echo "ok: $2"
