#!/bin/zsh
# N64 RDP spike: builds the Mac command-line bench (mupen64plus + our glue with N64_RDP_SPIKE + cxd4 + paraLLEl-RDP)
# into build/n64rdp-spike/mac. Needs the sources in ThirdParty-src (see docs/n64-rdp-spike.md §How to rebuild).
# Usage: Spikes/N64RDP/build_mac.sh            then: build/n64rdp-spike/mac/n64rdp_bench Spikes/N64RDP/rom/n64_rdpbench.z64
set -e
cd "$(dirname "$0")/../.."
ROOT=$PWD
FREE=$(df -g ~ | awk 'NR==2 {print $4}')
if [ "$FREE" -lt 4 ]; then echo "error: less than 4 GB free ($FREE GB); not building"; exit 1; fi
L=/private/tmp/duo-build.lock; while [ -e $L ] && kill -0 $(cat $L) 2>/dev/null; do sleep 20; done; echo $$ > $L; trap 'rm -f $L' EXIT

OUT=$ROOT/build/n64rdp-spike/mac
M=$ROOT/Packages/CoreKit/Sources/MUPEN64
PRDP=$ROOT/ThirdParty-src/parallel-rdp-standalone
CXD4=$ROOT/ThirdParty-src/mupen64plus-rsp-cxd4
S=$ROOT/Spikes/N64RDP/src
mkdir -p $OUT/obj

COMMON=(-O2 -arch arm64 -mmacosx-version-min=26.0 -w -DNDEBUG)
MUPEN=(-I$M/glue/shim -I$M/glue/include -I$M/mupen64plus-core/src -I$M/mupen64plus-core/src/api
       -I$M/mupen64plus-core/subprojects -I$M/mupen64plus-core/subprojects/md5 -I$M/mupen64plus-core/subprojects/xxhash
       -DNO_ASM -DNOCRYPT -DNOUNCRYPT -fno-strict-aliasing -DN64_RDP_SPIKE -I$S)
RDPINC=(-I$PRDP/parallel-rdp -I$PRDP/volk -I$PRDP/vulkan -I$PRDP/vulkan-headers/include -I$PRDP/util -include $S/volk_rename.h)

jobs=()
# mupen64plus-core + rsp-hle + glue (same file set and flags as CoreKit's MUPEN64 target, plus N64_RDP_SPIKE)
for f in $(cd $M && find mupen64plus-core/src mupen64plus-core/subprojects rsp-hle/src glue/src glue/units -name '*.c' \
           ! -path 'rsp-hle/src/plugin.c' ! -path 'mupen64plus-core/src/main/main.c'); do
  jobs+=("clang -std=gnu11 ${COMMON[*]} ${MUPEN[*]} -c $M/$f -o $OUT/obj/m_${f//\//_}.o")
done
jobs+=("clang -std=gnu11 ${COMMON[*]} -O3 -DM64P_PLUGIN_API -I$CXD4 -I$M/mupen64plus-core/src/api -c $S/cxd4_unit.c -o $OUT/obj/cxd4.o")
jobs+=("clang -std=gnu11 ${COMMON[*]} ${MUPEN[*]} -c $S/rsp_dispatch.c -o $OUT/obj/rsp_dispatch.o")
jobs+=("clang -std=gnu11 ${COMMON[*]} ${MUPEN[*]} -I$ROOT/Spikes/N64RDP/bench -c $ROOT/Spikes/N64RDP/bench/bench_mac.c -o $OUT/obj/bench_mac.o")
jobs+=("clang -std=gnu11 ${COMMON[*]} ${MUPEN[*]} -I$ROOT/Spikes/N64RDP/bench -c $ROOT/Spikes/N64RDP/bench/bench_core.c -o $OUT/obj/bench_core.o")
jobs+=("clang -std=gnu11 ${COMMON[*]} ${RDPINC[*]} -c $PRDP/volk/volk.c -o $OUT/obj/volk.o")
jobs+=("clang++ -std=c++17 ${COMMON[*]} ${RDPINC[*]} -I$M/mupen64plus-core/src -I$M/mupen64plus-core/src/api -c $S/rdp_spike.cpp -o $OUT/obj/rdp_spike.o")
for f in $PRDP/parallel-rdp/*.cpp \
         $PRDP/vulkan/{buffer,buffer_pool,command_buffer,command_pool,context,cookie,descriptor_set,device,event_manager,fence,fence_manager,image,indirect_layout,memory_allocator,pipeline_event,query_pool,render_pass,sampler,semaphore,semaphore_manager,shader}.cpp \
         $PRDP/vulkan/texture/texture_format.cpp \
         $PRDP/util/{arena_allocator,logging,thread_id,aligned_alloc,timer,timeline_trace_file,environment,thread_name}.cpp; do
  n=${f#$PRDP/}; jobs+=("clang++ -std=c++17 ${COMMON[*]} ${RDPINC[*]} -c $f -o $OUT/obj/p_${n//\//_}.o")
done
printf '%s\0' "${jobs[@]}" | xargs -0 -P 8 -n 1 sh -c
clang++ -arch arm64 -mmacosx-version-min=26.0 $OUT/obj/*.o -lz -o $OUT/n64rdp_bench
echo "built $OUT/n64rdp_bench"
