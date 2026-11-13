#!/bin/zsh
# N64 speed test on the Mac: builds a command-line bench from CoreKit's MUPEN64 sources (mupen64plus + glue +
# glue/rdp: paraLLEl-RDP + cxd4) into build/n64rdp-spike/mac. Vulkan comes from a macOS libMoltenVK.dylib in
# ThirdParty-src/moltenvk/macos (see docs/n64-rdp-spike.md §How to rebuild).
# Usage: Spikes/N64RDP/build_mac.sh
#   N64RDP_ROOT=$PWD build/n64rdp-spike/mac/n64rdp_bench Packages/CoreKit/Sources/N64Core/Resources/n64_rdpbench.z64
set -e
cd "$(dirname "$0")/../.."
ROOT=$PWD
FREE=$(df -g ~ | awk 'NR==2 {print $4}')
if [ "$FREE" -lt 4 ]; then echo "error: less than 4 GB free ($FREE GB); not building"; exit 1; fi
L=/private/tmp/duo-build.lock; while [ -e $L ] && kill -0 $(cat $L) 2>/dev/null; do sleep 20; done; echo $$ > $L; trap 'rm -f $L' EXIT

OUT=$ROOT/build/n64rdp-spike/mac
M=$ROOT/Packages/CoreKit/Sources/MUPEN64
P=$M/parallel-rdp
mkdir -p $OUT/obj

COMMON=(-O2 -arch arm64 -mmacosx-version-min=26.0 -w -DNDEBUG)
INC=(-I$M/glue/shim -I$M/glue/include -I$M/mupen64plus-core/src -I$M/mupen64plus-core/src/api
     -I$M/mupen64plus-core/subprojects -I$M/mupen64plus-core/subprojects/md5 -I$M/mupen64plus-core/subprojects/xxhash
     -I$P/parallel-rdp -I$P/volk -I$P/vulkan -I$P/vulkan-headers/include -I$P/util
     -DNO_ASM -DNOCRYPT -DNOUNCRYPT -fno-strict-aliasing)

jobs=()
# the same file set as CoreKit's MUPEN64 target
for f in $(cd $M && find mupen64plus-core/src mupen64plus-core/subprojects rsp-hle/src glue/src glue/units glue/rdp \
           \( -name '*.c' -o -name '*.cpp' \) ! -path 'rsp-hle/src/plugin.c' ! -path 'mupen64plus-core/src/main/main.c'); do
  case $f in
    *.cpp) jobs+=("clang++ -std=c++17 ${COMMON[*]} ${INC[*]} -c $M/$f -o $OUT/obj/m_${f//\//_}.o") ;;
    *)     jobs+=("clang -std=gnu11 ${COMMON[*]} ${INC[*]} -c $M/$f -o $OUT/obj/m_${f//\//_}.o") ;;
  esac
done
jobs+=("clang -std=gnu11 ${COMMON[*]} ${INC[*]} -c $ROOT/Spikes/N64RDP/bench/bench_mac.c -o $OUT/obj/bench_mac.o")
printf '%s\0' "${jobs[@]}" | xargs -0 -P 8 -n 1 sh -c
clang++ -arch arm64 -mmacosx-version-min=26.0 $OUT/obj/*.o -lz -o $OUT/n64rdp_bench
echo "built $OUT/n64rdp_bench"
