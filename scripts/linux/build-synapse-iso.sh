#!/usr/bin/env bash
# build-synapse-iso.sh - build a Synapse AI-only ISO from a clean Melee NTSC 1.02 ISO (vanilla, hybrid.64,
# Akaneia, SSBM ACE, or an eligible unknown GALE01 ISO). Needs bash 4+, coreutils, a POSIX awk and ../common.
#
# The rules it applies, for players and modders: ../BUILD_DETAILS.md (steps S0-S9, checks G/B/V, plans P1-P3,
# --check-built K1-K8);
# a line-by-line port of release/windows/Build-SynapseIso.ps1. The source ISO is never modified: the output
# is written as <output>.part and renamed when verified.
#
#   ./build-synapse-iso.sh --source ~/isos/Melee.iso
#   ./build-synapse-iso.sh --source akaneia.iso --output akaneia.aionly.iso --force
#   ./build-synapse-iso.sh --source hybrid.64.iso --check-only
#   ./build-synapse-iso.sh --check-built Melee.aionly.iso
#   ./build-synapse-iso.sh --add-known-base "some mod.iso" --built-iso "some mod.aionly.iso"
#
# An unknown ISO that passes every check is offered a build at a prompt (or built with --allow-unknown-base).
# Building never adds it to the known list: --add-known-base does, into ../common/known_dols.local.tsv (outside
# SHA256SUMS), only after re-checking the original, --check-built on the built ISO, matching its DOL to the one
# built from the original, and a boot test the user confirms.
#
# Exit codes: 0 ok | 1 usage | 2 release integrity / unreadable input | 3 ineligible base or --check-built failure
#             4 unknown DOL, not built (no --allow-unknown-base, prompt declined or impossible)
#             5 disk space / no placement | 6 write or read-back failure
#
# Portability: only bash, coreutils (cp dd od stat sha256sum df mktemp mv rm head tail tr wc), a POSIX awk
# (mawk, busybox awk) and sort. Every number is kept in decimal; awk never formats one with %d (mawk 1.3.3
# saturates it at 2^31-1), it prints them with %.0f.

set -eEuo pipefail
export LC_ALL=C

# ------------------------------------------------------------------------------------------------ constants
MAGIC_GC=$((0xC2339F3D))
MEX_CAVE_LO=$((0x8032C65C))
MEX_CAVE_HI=$((0x8032EA80))
APPLOADER_HI=$((0x81200000))
MEM1_TOP=$((0x81800000))
BI2_SIZE=$((0x2000))
STATIC_FST_LIMIT=$((0x7F40))        # align32(FST max) <= this keeps static payloads below the ceiling
BYTES_PER_FILE=24                   # average FST cost of one added file (BUILD_DETAILS.md 4)
VANILLA_ENTRY=$((0x8000522C))
HYBRID_ENTRY=$((0x80484800))
HYBRID_TEXT_END=$((0x80486600))
ALT_GAME_IDS=' GHME01 '            # besides GALE01: accepted only for a known_dols.tsv row with that game_id (hybrid.64 v3.2 vanilla build)
MIB=$((1024 * 1024))
CLASS='' CLASS_KEY=S2 CLASS_LOW=0 HAS_MXDT=0 HAS_AIENG=0   # set by classify / disc_marks
LOCAL_KNOWN=known_dols.local.tsv    # bases added with --add-known-base (in --common, outside SHA256SUMS)

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SELF=$(basename -- "${BASH_SOURCE[0]}")

FAILED=0
PART=''                 # the <output>.part being written (deleted on any failure)
TMP=''                  # temp dir (deleted on exit)
PLAIN=()                # plain-language explanations, printed once at the end
REPORT=0                # 1 once the report block for an unknown DOL is due
R_ISO='' R_SIZE='' R_DOLSHA='' R_PROFILE='(none)' R_CHECKS='failed' R_PLAN='-' R_OUTPUT='-'
R_FAILED=()
OK=1                    # result of the last check()

# Plain-language messages for players, keyed by check ID or outcome. The wording is shared by the three
# release scripts: keep it identical in release/windows and release/macos.
declare -A PLAYER=(
    ['G1']="The file can't be read, or it is too small to be a Melee disc image."
    ['G2']="This isn't a plain GameCube disc image (it may be compressed: .nkit, .rvz, .ciso, .wbfs). In Dolphin, right-click the game > Convert File... > ISO, then try again."
    ['G3']="This isn't Melee NTSC 1.02 (the US/Japanese version 1.02). PAL and versions 1.00/1.01 aren't supported."
    ['G3id']="This disc's game ID is accepted only for the exact ISOs this release lists (hybrid.64's vanilla build is one). This copy isn't one of them: start from the original, unmodified ISO."
    ['G4']="The disc image looks truncated or damaged. Dump or download it again."
    ['G5']="The disc image looks truncated or damaged. Dump or download it again."
    ['B1']="Another mod already changes how this game starts up, so Synapse can't be added on top of it."
    ['B1inj']="This ISO already contains the Synapse AI. Start again from your original ISO (the one without it)."
    ['B2']="This mod's game code is laid out differently from what Synapse needs; it can't be added safely."
    ['B3']="This mod's game code is laid out differently from what Synapse needs; it can't be added safely."
    ['B4']="This mod's game code is laid out differently from what Synapse needs; it can't be added safely."
    ['B5']="This mod's game code is laid out differently from what Synapse needs; it can't be added safely."
    ['B6']="Another mod already changes game code that the Synapse AI needs, so the two can't be combined (20XX is one such mod)."
    ['B7']="This mod uses the memory area that Synapse needs on Akaneia/ACE-style ISOs; it can't be added safely."
    ['B8']="This mod's game code doesn't match the kind of ISO it looks like; it can't be added safely."
    ['B9']="This ISO has more added content (stages, characters, files) than the AI can fit next to on this base (vanilla / hybrid.64). Remove some content, or use an Akaneia/ACE-based ISO, which has no such limit."
    ['B10']="This mod changes game code that the AI relies on; they are probably not compatible."
    ['S2']="This ISO's game code isn't a kind Synapse knows how to modify."
    ['DECLINED']="Nothing was built: you answered n. To build it later, run it again and answer y, then test the result in Dolphin before relying on it."
    ['S2-20XX']="This is the 20XX Hack Pack: it already has the 20XX AI and its own CPU menus, so this release doesn't modify it."
    ['K2none']="This ISO doesn't contain the Synapse AI from this release (it was never added, or another tool removed it)."
    ['K2bad']="The Synapse AI inside this ISO is damaged: another tool changed it. Rebuild from your copy without Synapse."
    ['K3']="Another tool changed how the game starts up, so the Synapse AI no longer loads. Rebuild from your copy without Synapse."
    ['K4']="Part of the game this ISO needs to start was removed by another tool. Rebuild from your copy without Synapse."
    ['K5']="Another mod now changes game code that the AI needs. Rebuild from your copy without Synapse, without that mod."
    ['K6']="Another mod now uses the memory area the AI needs. Rebuild from your copy without Synapse, without that mod."
    ['K7']="This ISO will freeze at startup: too much content was added after Synapse. Add the content to your copy without Synapse and build again; if that copy is refused too, there is too much content for this base."
    ['USAGE']="The command was not understood. See README.md for the options."
    ['PROFILE']="This ISO was recognised, and the --profile you chose doesn't match it. Leave --profile out."
    ['EXISTS']="The output file already exists. Add --force to replace it, or choose another --output."
    ['OUTDIR']="The folder for the output file doesn't exist."
    ['RELEASE']="The release files are incomplete, damaged, or were edited. Download or copy the whole release folder again."
    ['READ']="The file can't be read (wrong path, or it is in use)."
    ['SPACE']="There isn't enough free disk space for the new ISO. Free some space or choose another --output."
    ['WRITE']="Writing the new ISO failed and the incomplete file was deleted. Check the disk and run again."
    ['UNKNOWN-ELIGIBLE']="This ISO's game code was changed by the mod you're using, and this release hasn't been tested with it. It looks compatible. To build it anyway, run it again and answer y to the question (or add --allow-unknown-base), then test the result in Dolphin before relying on it."
    ['UNKNOWN-INELIGIBLE']="This ISO's game code was changed by the mod you're using, and it isn't compatible with Synapse (see the reasons above)."
    ['OK-CHECK-KNOWN']="This ISO is supported. Run the same command without --check-only to build it."
    ['OK-CHECK-UNKNOWN']="This ISO looks compatible but hasn't been tested with Synapse. You can build it; test it in Dolphin before relying on it."
    ['OK-BUILT-KNOWN']="Done: your new ISO with the Synapse AI is ready (path above). Your original ISO was not changed."
    ['OK-BUILT-UNKNOWN']="Done, but this mod has never been tested with Synapse: test the new ISO in Dolphin (steps above) before relying on it, and please report the result (REPORT block above)."
    ['OK-CHECKBUILT']="This ISO still contains a working Synapse AI."
)

USAGE_LINE="usage: $SELF --source <iso> [--output <iso>] [--profile auto|vanilla|hybrid64|mex] [--allow-unknown-base] [--check-only] [--force] [--common <dir>]  |  --check-built <iso>  |  --add-known-base <original iso> --built-iso <built iso>"

# ------------------------------------------------------------------------------------------------ exit paths
explain() {   # add a plain-words line once (by text, like the Windows script)
    local key=$1 t x
    if [ -z "${PLAYER[$key]+x}" ]; then return 0; fi
    t=${PLAYER[$key]}
    for x in "${PLAIN[@]+"${PLAIN[@]}"}"; do
        if [ "$x" = "$t" ]; then return 0; fi
    done
    PLAIN+=("$t")
}
finish() {    # the single exit point: partial output, report block, plain words
    local code=$1 t
    trap - ERR
    if [ -n "$PART" ] && [ -e "$PART" ]; then
        rm -f -- "$PART" 2>/dev/null || true
        echo "removed the partial output $PART"
    fi
    PART=''
    if [ "$REPORT" = 1 ]; then show_report "$code"; fi
    if [ "${#PLAIN[@]}" -gt 0 ]; then
        echo ''
        echo '== Recap'
        for t in "${PLAIN[@]}"; do echo ">> $t"; done
    fi
    exit "$code"
}
die() {       # die <code> <message> [plain-words key]
    if [ -n "${3:-}" ]; then explain "$3"; fi
    echo "ERROR: $2"
    finish "$1"
}
on_err() {    # an unexpected command failure (set -e): exit 2, or 6 once <out>.part exists
    local rc=$1 line=$2 cmd=$3
    if [ "${BASH_SUBSHELL:-0}" -gt 0 ]; then exit "$rc"; fi
    local code=2
    if [ -n "$PART" ]; then code=6; fi
    echo "ERROR: a command failed (status $rc)"
    echo "  at line $line: $cmd"
    finish "$code"
}
on_exit() {
    if [ -n "$PART" ] && [ -e "$PART" ]; then rm -f -- "$PART" 2>/dev/null || true; fi
    if [ -n "$TMP" ] && [ -d "$TMP" ]; then rm -rf -- "$TMP" 2>/dev/null || true; fi
}
trap 'on_err $? $LINENO "$BASH_COMMAND"' ERR
trap on_exit EXIT
trap 'echo "interrupted"; finish 130' INT TERM

# ------------------------------------------------------------------------------------------------ output
say()  { echo "[$1] $2"; }
pass() { say PASS "$1 $2"; }
info() { say INFO "$1"; }
bad() {       # bad <id> <message> [plain-words key]
    local id=$1 x seen=0
    FAILED=$((FAILED + 1))
    say FAIL "$id $2"
    if [ -n "${3:-}" ]; then explain "$3"; else explain "$id"; fi
    if [ "$REPORT" = 1 ]; then
        for x in "${R_FAILED[@]+"${R_FAILED[@]}"}"; do
            if [ "$x" = "$id" ]; then seen=1; fi
        done
        if [ "$seen" = 0 ]; then R_FAILED+=("$id"); fi
    fi
    return 0
}
check() {     # check <id> <1|0> <message>; the result is left in $OK (never fails under set -e)
    OK=$2
    if [ "$OK" = 1 ]; then pass "$1" "$3"; else bad "$1" "$3"; fi
}
hx() { printf '0x%08X' "$1"; }
commas() {    # 1459978240 -> 1,459,978,240 (into $COMMAS)
    local n=$1 s='' sign=''
    if [ "$n" -lt 0 ]; then sign='-'; n=$((-n)); fi
    while [ "$n" -ge 1000 ]; do
        s=$(printf ',%03d' $((n % 1000)))$s
        n=$((n / 1000))
    done
    COMMAS="$sign$n$s"
}
align() { echo $(( ($1 + $2 - 1) / $2 * $2 )); }

# ------------------------------------------------------------------------------------------------ byte I/O
fsize() { stat -c %s -- "$1"; }
sha256_file() { sha256sum < "$1" | cut -d' ' -f1; }
u32_at() {    # u32_at <file> <offset> -> $U32 (big-endian)
    local a=0 b=0 c=0 d=0
    read -r a b c d < <(od -An -v -tu1 -j "$2" -N 4 -- "$1") || true
    U32=$(( (${a:-0} << 24) | (${b:-0} << 16) | (${c:-0} << 8) | ${d:-0} ))
}
u32_list() {  # u32_list <file> <offset> <count> -> array U32S
    mapfile -t U32S < <(od -An -v -tu1 -j "$2" -N $((4 * $3)) -- "$1" | awk '
        { for (i = 1; i <= NF; i++) b[n++] = $i }
        END { for (i = 0; i + 3 < n; i += 4) printf "%.0f\n", ((b[i]*256 + b[i+1])*256 + b[i+2])*256 + b[i+3] }')
}
hex_at() {    # hex_at <file> <offset> <n> -> $HEXB (uppercase hex, no spaces)
    HEXB=$(od -An -v -tx1 -j "$2" -N "$3" -- "$1" | tr -d ' \n' | tr 'a-f' 'A-F')
}
extract() {   # extract <file> <offset> <length> <dest>: any (unaligned) range, length-checked
    local f=$1 off=$2 len=$3 dest=$4 got
    set +o pipefail                     # head -c closes the pipe early: tail's SIGPIPE is expected
    tail -c +"$((off + 1))" -- "$f" 2>/dev/null | head -c "$len" > "$dest"
    set -o pipefail
    got=$(fsize "$dest")
    if [ "$got" != "$len" ]; then die 2 "unexpected end of file reading $len bytes at $(hx "$off")" READ; fi
}
sha256_range() {   # sha256_range <file> <offset> <length> -> $SHA
    extract "$1" "$2" "$3" "$TMP/range.bin"
    SHA=$(sha256_file "$TMP/range.bin")
}
all_zero() {  # all_zero <file> <offset> <length> -> $ZERO (1|0)
    extract "$1" "$2" "$3" "$TMP/zero.bin"
    local nz
    nz=$(tr -d '\000' < "$TMP/zero.bin" | wc -c)
    if [ $((nz)) -eq 0 ]; then ZERO=1; else ZERO=0; fi
}
put_u32() {   # put_u32 <file> <offset> <value>: write a big-endian word in place (offset % 4 == 0)
    local f=$1 off=$2 v=$3
    printf "$(printf '\\%03o\\%03o\\%03o\\%03o' $(( (v >> 24) & 255 )) $(( (v >> 16) & 255 )) $(( (v >> 8) & 255 )) $(( v & 255 )))" |
        dd of="$f" bs=4 seek=$((off / 4)) conv=notrunc 2>/dev/null
}
write_at() {  # write_at <file> <blob> <offset>: copy a whole file in place, the largest block size the offset allows
    local f=$1 blob=$2 off=$3 bs=65536
    while [ "$bs" -gt 1 ] && [ $((off % bs)) -ne 0 ]; do bs=$((bs / 2)); done
    dd if="$blob" of="$f" bs="$bs" seek=$((off / bs)) conv=notrunc 2>"$TMP/dd.err"
}
pad_zeros() { # pad_zeros <file> <n>
    if [ "$2" -gt 0 ]; then head -c "$2" /dev/zero >> "$1"; fi
}
abspath() {   # -> $ABS (like PowerShell's unresolved full path; existing folders are resolved)
    local p=$1 d b
    case $p in /*) ;; *) p="$PWD/$p" ;; esac
    d=$(dirname -- "$p"); b=$(basename -- "$p")
    if [ -d "$d" ]; then d=$(cd -- "$d" && pwd -P); fi
    ABS="${d%/}/$b"
}

# ---- DOL model ----------------------------------------------------------------------------------------
parse_hdr() { # parse_hdr <file> <offset>: the 0x100-byte DOL header -> H_OFF H_VA H_SZ H_SLOTS H_BSS H_BSZ H_ENTRY H_SIZE
    local i e
    u32_list "$1" "$2" 57
    H_OFF=() H_VA=() H_SZ=() H_SLOTS=()
    H_SIZE=0
    for ((i = 0; i < 18; i++)); do
        H_OFF[i]=${U32S[i]}; H_VA[i]=${U32S[18 + i]}; H_SZ[i]=${U32S[36 + i]}
        if [ "${H_SZ[i]}" -ne 0 ]; then
            H_SLOTS+=("$i")
            e=$(( H_OFF[i] + H_SZ[i] ))
            if [ "$e" -gt "$H_SIZE" ]; then H_SIZE=$e; fi
        fi
    done
    H_BSS=${U32S[54]}; H_BSZ=${U32S[55]}; H_ENTRY=${U32S[56]}
}
win_fo() {    # win_fo <va> <n> -> $WIN = DOL file offset of [va, va+n) if inside one loaded section, else -1
    local va=$1 n=$2 i
    WIN=-1
    for i in "${D_SLOTS[@]}"; do
        if [ "${D_VA[i]}" -le "$va" ] && [ $((va + n)) -le $(( D_VA[i] + D_SZ[i] )) ]; then
            WIN=$(( D_OFF[i] + va - D_VA[i] )); return 0
        fi
    done
}
ceiling() { echo $(( MEM1_TOP - $(align "$1" 32) - BI2_SIZE )); }

# ---- ISO model ----------------------------------------------------------------------------------------
open_iso() {  # G1-G5 + DOL + FST
    local path=$1 who=$2 hb gid='' i c
    if [ ! -f "$path" ]; then die 2 "$who not found: $path" READ; fi
    if [ ! -r "$path" ]; then die 2 "cannot open $path: permission denied" READ; fi
    ISO=$path
    ISO_SIZE=$(fsize "$path")
    check G1 $(( ISO_SIZE >= 0x2460 )) "$(basename -- "$path") readable, $ISO_SIZE B"
    if [ "$OK" = 0 ]; then die 3 'image too small'; fi
    read -r -a hb < <(od -An -v -tu1 -N 8 -- "$path")
    for ((i = 0; i < 6; i++)); do
        c=${hb[i]}
        if [ "$c" -ge 32 ] && [ "$c" -le 126 ]; then gid+=$(printf "\\$(printf '%03o' "$c")"); else gid+='?'; fi
    done
    u32_at "$path" $((0x1C))
    check G2 $(( U32 == MAGIC_GC )) "GameCube magic at 0x01C = $(hx "$U32")"
    if [ "$OK" = 0 ]; then die 3 'not a plain GameCube image (NKit/RVZ/WBFS/CISO?): convert it to .iso with Dolphin first'; fi
    local g3=0
    local g3note=''
    if [ "$gid" != GALE01 ]; then g3note="; $gid only for a listed ISO"; fi
    if { [ "$gid" = GALE01 ] || [[ "$ALT_GAME_IDS" == *" $gid "* ]]; } && [ "${hb[7]}" -eq 2 ]; then g3=1; fi
    check G3 $g3 "game ID $gid, revision ${hb[7]} (need GALE01 rev 2$g3note)"
    if [ "$OK" = 0 ]; then die 3 'not Melee NTSC 1.02'; fi
    GAME_ID=$gid
    HEAD_HEX=$(od -An -v -tx1 -N 8 -- "$path" | tr -d ' \n')
    u32_list "$path" $((0x420)) 4
    DOL_OFF=${U32S[0]} FST_OFF=${U32S[1]} FST_SIZE=${U32S[2]} FST_MAX=${U32S[3]}
    u32_list "$path" $((0x2454)) 2
    APP_END=$(( 0x2460 + U32S[0] + U32S[1] ))
    local g4=0
    if [ $((DOL_OFF + 0x100)) -le "$ISO_SIZE" ] && [ $((FST_OFF + FST_SIZE)) -le "$ISO_SIZE" ] &&
       [ "$APP_END" -le "$ISO_SIZE" ] && [ "$FST_SIZE" -le "$FST_MAX" ] && [ "$FST_SIZE" -ge 12 ]; then g4=1; fi
    check G4 $g4 "DOL $(hx "$DOL_OFF"), FST $(hx "$FST_OFF") ($FST_SIZE B, max $FST_MAX B), apploader end $(hx "$APP_END") inside the image"
    if [ "$OK" = 0 ]; then die 3 'truncated or corrupt image'; fi
    # FST: file extents (the FST bytes are kept in $TMP/fst.bin for S7)
    extract "$path" "$FST_OFF" "$FST_SIZE" "$TMP/fst.bin"
    : > "$TMP/files"
    local cnt nfiles over whole
    read -r cnt nfiles over whole < <(od -An -v -tu1 -- "$TMP/fst.bin" | awk -v isz="$ISO_SIZE" -v ext="$TMP/files" '
        function be(o) { return ((b[o]*256 + b[o+1])*256 + b[o+2])*256 + b[o+3] }
        { for (i = 1; i <= NF; i++) b[n++] = $i }
        END {
            cnt = be(8); files = 0; over = 0
            for (e = 1; e < cnt; e++) {
                o = 12 * e
                if (o + 12 > n) break
                if (b[o] == 0) {
                    fo = be(o + 4); fz = be(o + 8)
                    if (fz > 0) {
                        files++
                        printf "%.0f %.0f\n", fo, fo + fz > ext
                        if (fo + fz > isz) over++
                    }
                }
            }
            close(ext)
            printf "%.0f %.0f %.0f %d\n", cnt, files, over, (12 * cnt <= n) ? 1 : 0
        }')
    FST_COUNT=$cnt FILE_COUNT=$nfiles
    sort -n -k1,1 -k2,2 "$TMP/files" > "$TMP/files.sorted"
    local g5=0
    if [ "$over" -eq 0 ] && [ "$whole" = 1 ]; then g5=1; fi
    check G5 $g5 "$cnt FST entries, $nfiles files, all inside the image"
    if [ "$OK" = 0 ]; then die 3 'truncated image (files past the end)'; fi
    # DOL
    extract "$path" "$DOL_OFF" 256 "$TMP/dol.hdr"
    parse_hdr "$TMP/dol.hdr" 0
    DOL_SIZE=$H_SIZE
    if [ "$DOL_SIZE" -le 256 ] || [ $((DOL_OFF + DOL_SIZE)) -gt "$ISO_SIZE" ]; then
        die 3 "DOL at $(hx "$DOL_OFF") runs past the end of the image" G4
    fi
    extract "$path" "$DOL_OFF" "$DOL_SIZE" "$TMP/dol.bin"
    D_OFF=("${H_OFF[@]}") D_VA=("${H_VA[@]}") D_SZ=("${H_SZ[@]}") D_SLOTS=("${H_SLOTS[@]}")
    D_BSS=$H_BSS D_BSZ=$H_BSZ D_ENTRY=$H_ENTRY
    DOL_SHA=$(sha256_file "$TMP/dol.bin")
}

# ---- release/common ----------------------------------------------------------------------------------
read_table() {   # read_table <file> -> ROWS (one tab-separated line per row; comments and blank lines dropped)
    local l
    ROWS=()
    while IFS= read -r l || [ -n "$l" ]; do
        l=${l%$'\r'}
        if [ -z "$l" ] || [ "${l:0:1}" = '#' ]; then continue; fi
        ROWS+=("$l")
    done < "$1"
}
load_common() {
    local dir=$1 sums="$1/SHA256SUMS" l hash rel n=0 r
    if [ ! -f "$sums" ]; then die 2 "release data not found: $sums (use --common <dir>)" RELEASE; fi
    while IFS= read -r l || [ -n "$l" ]; do
        l=${l%$'\r'}
        if [ -z "$l" ]; then continue; fi
        hash=$(printf '%s' "${l:0:64}" | tr 'A-F' 'a-f'); rel=${l:66}
        if [ ! -f "$dir/$rel" ]; then die 2 "release file missing: $rel" RELEASE; fi
        if [ "$(sha256_file "$dir/$rel")" != "$hash" ]; then die 2 "release file corrupted or edited: $rel (SHA-256 mismatch)" RELEASE; fi
        n=$((n + 1))
    done < "$sums"
    pass S0 "release data $dir: $n files match SHA256SUMS"
    # profiles (in file order)
    P_NAMES=()
    declare -gA P_FILE=() P_SIZE=() P_SHA=() P_VA=() P_NEW=() P_EXP=() P_PLACE=() P_MEX=() P_TOP=()
    read_table "$dir/profiles.tsv"
    for r in "${ROWS[@]}"; do
        IFS=$'\t' read -r -a f <<< "$r"
        P_NAMES+=("${f[0]}")
        P_FILE[${f[0]}]=${f[1]}; P_SIZE[${f[0]}]=$((f[2])); P_SHA[${f[0]}]=$(printf '%s' "${f[3]}" | tr 'A-F' 'a-f')
        P_VA[${f[0]}]=$((f[4])); P_NEW[${f[0]}]=$((f[5])); P_EXP[${f[0]}]=$((f[6]))
        P_PLACE[${f[0]}]=${f[7]}; P_MEX[${f[0]}]=${f[8]}
        if [ "${f[9]}" = '-' ]; then P_TOP[${f[0]}]=''; else P_TOP[${f[0]}]=$((f[9])); fi
    done
    # known DOLs
    declare -gA K_PROFILE=() K_NAME=() K_OUTSIZE=() K_OUTSHA=() K_LOCAL=() K_GAMEID=()
    local k
    read_table "$dir/known_dols.tsv"
    for r in "${ROWS[@]}"; do
        IFS=$'\t' read -r -a f <<< "$r"
        k=$(printf '%s' "${f[0]}" | tr 'A-F' 'a-f')
        K_PROFILE[$k]=${f[1]}; K_NAME[$k]=${f[2]}; K_OUTSIZE[$k]=$((f[3]))
        K_OUTSHA[$k]=$(printf '%s' "${f[4]}" | tr 'A-F' 'a-f'); K_LOCAL[$k]=0
        K_GAMEID[$k]=${f[5]:-GALE01}   # optional 6th column: a non-GALE01 disc
    done
    if [ -f "$dir/$LOCAL_KNOWN" ]; then   # optional, added with --add-known-base; a release row wins over a local one
        n=0
        read_table "$dir/$LOCAL_KNOWN"
        for r in "${ROWS[@]+"${ROWS[@]}"}"; do
            IFS=$'\t' read -r -a f <<< "$r"
            if [ "${#f[@]}" -lt 5 ] || [ -z "${P_FILE[${f[1]}]+x}" ]; then continue; fi
            k=$(printf '%s' "${f[0]}" | tr 'A-F' 'a-f')
            if [ -n "${K_PROFILE[$k]+x}" ]; then continue; fi
            K_PROFILE[$k]=${f[1]}; K_NAME[$k]=${f[2]}; K_OUTSIZE[$k]=$((f[3]))
            K_OUTSHA[$k]=$(printf '%s' "${f[4]}" | tr 'A-F' 'a-f'); K_LOCAL[$k]=1; K_GAMEID[$k]=GALE01
            n=$((n + 1))
        done
        info "$LOCAL_KNOWN: $n locally added base(s)"
    fi
    # hooks, fingerprints
    HK_VA=() HK_WORD=() HK_NAME=()
    read_table "$dir/hooks.tsv"
    for r in "${ROWS[@]}"; do
        IFS=$'\t' read -r -a f <<< "$r"
        HK_VA+=($((f[0]))); HK_WORD+=($((f[1]))); HK_NAME+=("${f[2]}")
    done
    FP_NAME=() FP_VA=() FP_LEN=() FP_HEX=()
    read_table "$dir/fingerprints.tsv"
    for r in "${ROWS[@]}"; do
        IFS=$'\t' read -r -a f <<< "$r"
        FP_NAME+=("${f[0]}"); FP_VA+=($((f[1]))); FP_LEN+=($((f[2])))
        FP_HEX+=("$(printf '%s' "${f[3]}" | tr 'a-f' 'A-F')")
    done
}
load_section() {   # -> $SEC (path of the verified section file)
    local p=$1 len sha
    SEC="$COMMON/${P_FILE[$p]}"
    if [ ! -f "$SEC" ]; then die 2 "${P_FILE[$p]}: size/SHA-256 do not match profiles.tsv" RELEASE; fi
    len=$(fsize "$SEC"); sha=$(sha256_file "$SEC")
    if [ "$len" -ne "${P_SIZE[$p]}" ] || [ "$sha" != "${P_SHA[$p]}" ]; then
        die 2 "${P_FILE[$p]}: size/SHA-256 do not match profiles.tsv" RELEASE
    fi
    pass S0 "section ${P_FILE[$p]}: $len B, SHA-256 matches profiles.tsv"
}

# ---- checks shared by the build (B) and --check-built (K) -------------------------------------------
test_hooks() {     # test_hooks <id>
    local id=$1 i nbad=0 w msgs=()
    for i in "${!HK_VA[@]}"; do
        win_fo "${HK_VA[i]}" 4
        if [ "$WIN" -lt 0 ]; then
            msgs+=("${HK_NAME[i]} $(hx "${HK_VA[i]}") holds unmapped, expected $(hx "${HK_WORD[i]}")")
        else
            u32_at "$TMP/dol.bin" "$WIN"
            if [ "$U32" -ne "${HK_WORD[i]}" ]; then
                msgs+=("${HK_NAME[i]} $(hx "${HK_VA[i]}") holds $(hx "$U32"), expected $(hx "${HK_WORD[i]}")")
            fi
        fi
    done
    if [ "${#msgs[@]}" -eq 0 ]; then pass "$id" "${#HK_VA[@]} hook sites hold their stock words"
    else for w in "${msgs[@]}"; do bad "$id" "hook taken: $w"; done; fi
}
mex_cave() {       # -> $CAVE: 'unmapped', 'zero' or 'used'
    win_fo "$MEX_CAVE_LO" $((MEX_CAVE_HI - MEX_CAVE_LO))
    if [ "$WIN" -lt 0 ]; then CAVE=unmapped; return 0; fi
    all_zero "$TMP/dol.bin" "$WIN" $((MEX_CAVE_HI - MEX_CAVE_LO))
    if [ "$ZERO" = 1 ]; then CAVE=zero; else CAVE=used; fi
}
headroom() {       # headroom <profile> -> $HEADROOM
    local hb
    if [ "${P_PLACE[$1]}" != static ]; then HEADROOM='unlimited (dynamic)'; return 0; fi
    hb=$(( STATIC_FST_LIMIT - $(align "$FST_MAX" 32) ))
    if [ "$hb" -lt 0 ]; then HEADROOM="$hb B (OVER THE LIMIT)"; return 0; fi
    commas "$hb"
    HEADROOM="$COMMAS B (~$((hb / BYTES_PER_FILE)) files at $BYTES_PER_FILE B each)"
}
test_ceiling() {   # test_ceiling <profile> <id>
    local ceil
    ceil=$(ceiling "$FST_MAX")
    check "$2" $(( ceil >= P_TOP[$1] )) "static ceiling $(hx "$ceil") (FST max $FST_MAX B) >= $(hx "${P_TOP[$1]}") (end of the A4 block)"
}
in_text() {        # in_text <va> -> $INTEXT (1 if va lies in a loaded text section)
    local i
    INTEXT=0
    for i in "${D_SLOTS[@]}"; do
        if [ "$i" -le 6 ] && [ "${D_VA[i]}" -le "$1" ] && [ "$1" -lt $(( D_VA[i] + D_SZ[i] )) ]; then INTEXT=1; fi
    done
}

disc_marks() {     # MxDt.dat (m-ex data file) / AI_Engine.bin (20XX AI file) in the FST name table -> HAS_MXDT HAS_AIENG (0/1)
    local hex
    # the name table starts at 12 x entry count; every name ends with a NUL (a leading ' 00' covers the first one).
    # Whitespace is squeezed so GNU, BSD and busybox od all give ' xx xx ...' (whole bytes: no nibble misalignment).
    hex=$({ printf ' 00 '; od -An -v -tx1 -j $((12 * FST_COUNT)) -- "$TMP/fst.bin"; printf ' '; } | tr -s ' \n' '  ')
    HAS_MXDT=0 HAS_AIENG=0
    case $hex in *' 00 4d 78 44 74 2e 64 61 74 00 '*) HAS_MXDT=1 ;; esac
    case $hex in *' 00 41 49 5f 45 6e 67 69 6e 65 2e 62 69 6e 00 '*) HAS_AIENG=1 ;; esac
}

classify() {       # BUILD_DETAILS.md 2 -> $CLASS (profile name, or empty); $CLASS_KEY (plain words if empty), $CLASS_LOW
    local i yn1=no yn2=no
    CLASS='' CLASS_KEY=S2 CLASS_LOW=0
    if [ "$D_ENTRY" -eq "$VANILLA_ENTRY" ]; then
        disc_marks
        if [ "$HAS_MXDT" = 1 ]; then yn1=yes; fi
        if [ "$HAS_AIENG" = 1 ]; then yn2=yes; fi
        info "disc marks: MxDt.dat $yn1 (m-ex data file), AI_Engine.bin $yn2 (20XX AI file)"
        mex_cave
        if [ "$CAVE" = zero ]; then
            if [ "$HAS_MXDT" = 0 ] || [ "$HAS_AIENG" = 1 ]; then
                CLASS_LOW=1; info 'low confidence: the m-ex cave is empty, but the disc marks are not those of an m-ex ISO'
            fi
            CLASS=mex; return 0
        fi
        if [ "$HAS_AIENG" = 1 ]; then
            info '20XX Hack Pack (AI_Engine.bin on the disc, m-ex cave holds code): it already runs the 20XX AI'
            CLASS_KEY=S2-20XX; return 0
        fi
        if [ "$HAS_MXDT" = 1 ]; then CLASS_LOW=1; info 'low confidence: MxDt.dat is on the disc, but the m-ex cave holds code'; fi
        CLASS=vanilla; return 0       # vanilla family; B9 then says whether its FST fits the static layout
    fi
    if [ "$D_ENTRY" -eq "$HYBRID_ENTRY" ]; then
        for i in "${D_SLOTS[@]}"; do
            if [ "$i" -le 6 ] && [ "${D_VA[i]}" -eq "$HYBRID_ENTRY" ] && [ $(( D_VA[i] + D_SZ[i] )) -le "$HYBRID_TEXT_END" ]; then
                CLASS=hybrid64; return 0
            fi
        done
    fi
    info "entry point $(hx "$D_ENTRY"): another loader owns the boot (already injected, or another DOL mod)"
}

test_base() {      # S3: B1-B10 -> $SLOT (first free text slot, -1 if none)
    local p=$1 unknown=$2 i lo hi clash='' s nbad=0 badfp='' fhex
    check B1 $(( D_ENTRY == P_EXP[$p] )) "DOL entry $(hx "$D_ENTRY"), expected $(hx "${P_EXP[$p]}")"
    SLOT=-1
    for ((i = 0; i <= 6; i++)); do
        if [ "${D_SZ[i]}" -eq 0 ]; then SLOT=$i; break; fi
    done
    if [ "$SLOT" -ge 0 ]; then s=$SLOT; else s=none; fi
    check B2 $(( SLOT >= 0 )) "free text slot: $s"
    lo=${P_VA[$p]}; hi=$(( P_VA[$p] + P_SIZE[$p] ))
    for i in "${D_SLOTS[@]}"; do
        if [ "$lo" -lt $(( D_VA[i] + D_SZ[i] )) ] && [ "${D_VA[i]}" -lt "$hi" ]; then clash+="${clash:+,}$i"; fi
    done
    if [ -n "$clash" ]; then s="slot(s) $clash"; else s='no loaded section'; fi
    check B3 $([ -z "$clash" ] && echo 1 || echo 0) "section [$(hx "$lo"), $(hx "$hi")) overlaps $s"
    check B4 $(( D_BSS <= lo && hi <= D_BSS + D_BSZ && hi <= APPLOADER_HI )) "section inside bss [$(hx "$D_BSS"), $(hx $((D_BSS + D_BSZ)))) and below $(hx "$APPLOADER_HI")"
    in_text "${P_EXP[$p]}"
    check B5 "$INTEXT" "chain target $(hx "${P_EXP[$p]}") lies in a loaded text section"
    test_hooks B6
    mex_cave
    if [ "${P_MEX[$p]}" = 1 ]; then
        check B7 $([ "$CAVE" = zero ] && echo 1 || echo 0) "m-ex cave [$(hx "$MEX_CAVE_LO"), $(hx "$MEX_CAVE_HI")) mapped and all zero"
    else
        check B8 $([ "$CAVE" != zero ] && echo 1 || echo 0) "m-ex cave not all zero (vanilla-family DOL)"
    fi
    if [ "${P_PLACE[$p]}" = static ]; then test_ceiling "$p" B9; fi
    if [ "$unknown" = 1 ]; then
        for i in "${!FP_NAME[@]}"; do
            win_fo "${FP_VA[i]}" "${FP_LEN[i]}"
            fhex=''
            if [ "$WIN" -ge 0 ]; then hex_at "$TMP/dol.bin" "$WIN" "${FP_LEN[i]}"; fhex=$HEXB; fi
            if [ "$WIN" -lt 0 ] || [ "$fhex" != "${FP_HEX[i]}" ]; then badfp+="${badfp:+, }${FP_NAME[i]}"; fi
        done
        if [ -z "$badfp" ]; then pass B10 "${#FP_NAME[@]} fingerprint windows match"
        else bad B10 "fingerprints differ: $badfp"; fi
    fi
}

# ---- S4 / S6 -----------------------------------------------------------------------------------------
new_dol() {        # new_dol <profile> <slot> -> $TMP/new.dol, $NEW_SIZE, $SEC_OFF
    local p=$1 slot=$2 len
    SEC_OFF=$(align "$DOL_SIZE" 32)
    cp -- "$TMP/dol.bin" "$TMP/new.dol"
    pad_zeros "$TMP/new.dol" $((SEC_OFF - DOL_SIZE))
    cat -- "$SEC" >> "$TMP/new.dol"
    len=$(fsize "$TMP/new.dol")
    NEW_SIZE=$(align "$len" 32)
    pad_zeros "$TMP/new.dol" $((NEW_SIZE - len))
    put_u32 "$TMP/new.dol" $((4 * slot)) "$SEC_OFF"
    put_u32 "$TMP/new.dol" $((0x48 + 4 * slot)) "${P_VA[$p]}"
    put_u32 "$TMP/new.dol" $((0x90 + 4 * slot)) "${P_SIZE[$p]}"
    put_u32 "$TMP/new.dol" $((0xE0)) "${P_NEW[$p]}"
}
get_plan() {       # plans P1-P3 -> PLAN PLAN_DOL PLAN_FST
    # fixed extents: boot.bin + bi2, the apploader, every file of size > 0; the old DOL counts as free
    { echo "0 $((0x2440))"; echo "$((0x2440)) $APP_END"; cat "$TMP/files"; } | sort -n -k1,1 -k2,2 > "$TMP/fixed"
    read -r PLAN PLAN_DOL PLAN_FST < <(awk -v dol="$DOL_OFF" -v nsz="$1" -v fo="$FST_OFF" -v fs="$FST_SIZE" -v isz="$ISO_SIZE" '
        function a32(x, a) { return int((x + a - 1) / a) * a }
        function nextocc(x, xs, usex,   m, i) {          # first extent start >= x (fixed [+ extra]), else the ISO size
            m = isz
            for (i = 0; i < n; i++) if (s[i] >= x && s[i] < m) m = s[i]
            if (usex && xs >= x && xs < m) m = xs
            return m
        }
        function visit(a, b) {
            if (found) return
            if (a > cur) { ga = a32(cur, 32); if (a > ga && a - ga >= need) { found = 1; fit = ga } }
            if (b > cur) cur = b
        }
        function firstgap(xs, xe, nd,   i, done) {     # first gap >= nd over fixed + [xs, xe), sorted by start; -1 if none
            need = nd; cur = 0; found = 0; fit = -1; done = 0
            for (i = 0; i < n; i++) {
                if (!done && (xs < s[i] || (xs == s[i] && xe <= e[i]))) { visit(xs, xe); done = 1 }
                visit(s[i], e[i])
            }
            if (!done) visit(xs, xe)
            if (!found) { ga = a32(cur, 32); if (isz > ga && isz - ga >= need) { found = 1; fit = ga } }
            return fit
        }
        function maxend(xe,   m, i) { m = xe; for (i = 0; i < n; i++) if (e[i] > m) m = e[i]; return m }
        { s[n] = $1; e[n] = $2; n++ }
        END {
            if (dol + nsz <= nextocc(dol, fo, 1)) { printf "P1 %.0f %.0f\n", dol, fo; exit }
            if (dol + nsz <= nextocc(dol, 0, 0)) {
                g = firstgap(dol, dol + nsz, a32(fs, 32))
                if (g < 0) g = a32(maxend(dol + nsz), 32)
                printf "P2 %.0f %.0f\n", dol, g; exit
            }
            g = firstgap(fo, fo + fs, nsz)
            if (g < 0) g = a32(maxend(fo + fs), 32768)
            printf "P3 %.0f %.0f\n", g, fo
        }' "$TMP/fixed")
}

# ---- report ------------------------------------------------------------------------------------------
show_boot_checklist() {
    echo ''
    echo 'Boot check (Dolphin; MMU on, Fastmem off):'
    echo '  1. VS mode, set a CPU to type 4 (any level): it attacks and wavedashes.'
    echo '  2. Z + D-Up opens the CPU config menu; the D-pad changes the CPU type (toast).'
    if [ "$1" = vanilla ]; then echo '  3. Tournament Mode still starts from the main menu.'; fi
    echo 'Adding stages or characters: add them BEFORE injecting, keep the un-injected copy, and run'
    echo '  --check-built <iso> after any later change (BUILD_DETAILS.md 4).'
}
find_release_section() {   # a text slot holding one of this release's sections (by address + size) -> $INJ_P $INJ_SLOT
    local i p
    INJ_P='' INJ_SLOT=-1
    for i in "${D_SLOTS[@]}"; do
        if [ "$i" -gt 6 ]; then continue; fi
        for p in "${P_NAMES[@]}"; do
            if [ "${D_VA[i]}" -eq "${P_VA[$p]}" ] && [ "${D_SZ[i]}" -eq "${P_SIZE[$p]}" ]; then INJ_P=$p; INJ_SLOT=$i; return 0; fi
        done
    done
}
show_report() {    # a block the user can copy when reporting an untested ISO
    local code=$1 rid='(unknown)' checks=$R_CHECKS x
    if [ -f "$COMMON/SHA256SUMS" ]; then rid=$(sha256sum < "$COMMON/SHA256SUMS" | cut -c1-12) || rid='(unknown)'; fi
    if [ "${#R_FAILED[@]}" -gt 0 ]; then
        checks='failed: '
        for x in "${!R_FAILED[@]}"; do
            if [ "$x" -gt 0 ]; then checks+=', '; fi
            checks+=${R_FAILED[x]}
        done
    fi
    echo ''
    echo '== REPORT (untested ISO: copy this block when you report how it went)'
    echo "  release data : $rid"
    echo "  iso          : $R_ISO ($R_SIZE B)"
    echo "  game code    : SHA-256 $R_DOLSHA (not in known_dols.tsv)"
    echo "  profile      : $R_PROFILE"
    echo "  checks       : $checks"
    echo "  plan         : $R_PLAN"
    echo "  exit code    : $code"
    if [ "$code" -eq 0 ] && [ "$R_OUTPUT" != '-' ]; then
        echo "  boot test    : <fill in: boots? CPU at type 4 attacks and wavedashes? Z+D-Up menu opens? the mod's own features still work?>"
    fi
    echo '  Please open an issue titled "Tested ISO: mod_name" and paste this block. Thank you!'
    echo '  https://github.com/w3irDv/20XX-Synapse_Engine/issues/new'
}

# ================================================================================================= modes
test_game_id() {   # test_game_id <source|built>: G3, second half (hybrid.64's vanilla build, GHME01)
    # A disc whose game ID isn't GALE01 is accepted only for a known_dols.tsv row with that game_id: a source must BE
    # that row's boot DOL; a built ISO needs the release to list the id.
    local k ok=0 msg
    if [ "$GAME_ID" = GALE01 ]; then return 0; fi
    if [ "$1" = built ]; then
        for k in "${!K_GAMEID[@]}"; do if [ "${K_GAMEID[$k]}" = "$GAME_ID" ]; then ok=1; fi; done
        msg="game ID $GAME_ID: this release lists a base with that game ID"
    else
        if [ -n "${K_PROFILE[$DOL_SHA]+x}" ] && [ "${K_GAMEID[$DOL_SHA]}" = "$GAME_ID" ]; then ok=1; fi
        if [ "$ok" = 1 ]; then msg="game ID $GAME_ID: boot DOL is the listed '${K_NAME[$DOL_SHA]}'"
        else msg="game ID $GAME_ID: boot DOL is not a listed ISO"; fi
    fi
    if [ "$ok" = 1 ]; then pass G3 "$msg"; else bad G3 "$msg" G3id; die 3 "game ID $GAME_ID is accepted only for a listed ISO"; fi
}
check_built() {    # BUILD_DETAILS.md 5: K1-K8, read-only -> CB_FOUND (profile, '' if none), CB_SHA / CB_SIZE (padded DOL)
    local path=$1 i p found='' fslot=-1 padded sha asbuilt=0 k cand hit
    CB_FOUND='' CB_SHA='' CB_SIZE=0
    echo "== --check-built $path"
    open_iso "$path" ISO
    test_game_id built
    pass K1 'G1-G5 passed'
    for i in "${D_SLOTS[@]}"; do
        if [ "$i" -gt 6 ]; then continue; fi
        # Profiles can share address and size (vanilla and mex: 0x80484800, same length), so the slot is
        # damaged only when it matches a candidate's address and size but none of their SHA-256s.
        cand='' hit=''
        for p in "${P_NAMES[@]}"; do
            if [ "${D_VA[i]}" -eq "${P_VA[$p]}" ] && [ "${D_SZ[i]}" -eq "${P_SIZE[$p]}" ]; then
                if [ -z "$cand" ]; then sha256_range "$TMP/dol.bin" "${D_OFF[i]}" "${D_SZ[i]}"; cand=$p; else cand="$cand / $p"; fi
                if [ -z "$hit" ] && [ "$SHA" = "${P_SHA[$p]}" ]; then hit=$p; fi
            fi
        done
        if [ -n "$hit" ]; then found=$hit; fslot=$i
        elif [ -n "$cand" ]; then bad K2 "slot $i at $(hx "${D_VA[i]}") has the size of the $cand section but its SHA-256 differs: the section is damaged" K2bad; fi
    done
    padded=$(align "$DOL_SIZE" 32)
    if [ $((DOL_OFF + padded)) -le "$ISO_SIZE" ]; then sha256_range "$ISO" "$DOL_OFF" "$padded"; sha=$SHA
    else sha=$DOL_SHA; fi
    for k in "${!K_OUTSHA[@]}"; do
        if [ "${K_OUTSHA[$k]}" = "$sha" ]; then asbuilt=1; fi
    done
    if [ -z "$found" ]; then
        if [ "$FAILED" -eq 0 ]; then bad K2 'no Synapse AI-only section from this release in the DOL (not built by this release, or a tool rewrote the DOL)' K2none; fi
        if [ "$asbuilt" = 1 ]; then info 'K8 DOL as built'; else info 'K8 DOL differs from the build (another tool edited it, or not built by this release)'; fi
        return 0
    fi
    pass K2 "slot $fslot: the $found section (${P_SIZE[$found]} B at $(hx "${P_VA[$found]}")), SHA-256 matches"
    check K3 $(( D_ENTRY == P_NEW[$found] )) "DOL entry $(hx "$D_ENTRY"), expected $(hx "${P_NEW[$found]}") (the Synapse stub)"
    in_text "${P_EXP[$found]}"
    check K4 "$INTEXT" "chain target $(hx "${P_EXP[$found]}") still lies in a loaded text section"
    test_hooks K5
    if [ "${P_MEX[$found]}" = 1 ]; then
        mex_cave
        check K6 $([ "$CAVE" = zero ] && echo 1 || echo 0) "m-ex cave [$(hx "$MEX_CAVE_LO"), $(hx "$MEX_CAVE_HI")) still all zero"
    fi
    if [ "${P_PLACE[$found]}" = static ]; then
        test_ceiling "$found" K7
        if [ "$OK" = 0 ]; then
            echo '       THIS ISO WILL HANG AT BOOT: the FST grew past the static limit after the injection.'
            echo '       Re-inject from the un-injected modded copy (it will be refused too: too much content for'
            echo '       the static layout of this base, BUILD_DETAILS.md 4).'
        fi
    fi
    if [ "$asbuilt" = 1 ]; then info 'K8 DOL as built'; else info 'K8 DOL differs from the build (another tool edited it; K2-K6 decide whether that matters)'; fi
    headroom "$found"
    info "profile $found; FST $FST_SIZE B (max $FST_MAX B); content headroom: $HEADROOM"
    CB_FOUND=$found CB_SHA=$sha
    if [ $((DOL_OFF + padded)) -le "$ISO_SIZE" ]; then CB_SIZE=$padded; else CB_SIZE=$DOL_SIZE; fi
}

ask_yes_no() {     # ask_yes_no <question> -> 0 on y/yes
    local a=''
    read -r -p "$1 [y/N] " a || a=''
    case $a in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

add_known_base() {   # --add-known-base: an UNKNOWN but eligible source DOL -> $COMMON/known_dols.local.tsv
    # Refuses unless: the source passes every S3 check (B1-B10, fingerprints included), the built ISO passes
    # --check-built (K1-K7), the built ISO's DOL is exactly the one this release makes from the source, and the
    # user confirms a boot test of that built ISO.
    local src=$1 built=$2 pname in_sha newsha newsize same=0 bname kd
    echo "== --add-known-base $src"
    open_iso "$src" 'source ISO'
    test_game_id source
    if [ -n "${K_PROFILE[$DOL_SHA]+x}" ]; then
        local where=''
        if [ "${K_LOCAL[$DOL_SHA]}" = 1 ]; then where=", $LOCAL_KNOWN"; fi
        pass S2 "boot DOL SHA-256 $DOL_SHA is already known: '${K_NAME[$DOL_SHA]}' (profile ${K_PROFILE[$DOL_SHA]}$where); nothing to add"
        return 0
    fi
    find_release_section
    if [ -n "$INJ_P" ]; then
        bad B1 "this ISO already carries the Synapse $INJ_P section: --add-known-base takes the ORIGINAL ISO (without Synapse); the built one goes in --built-iso" B1inj
        die 3 'the source is an injected ISO'
    fi
    if [ "$PROFILE" != auto ]; then pname=$PROFILE; info "profile forced: $pname"
    else classify; pname=$CLASS; fi
    if [ -z "$pname" ]; then bad S2 'no profile applies to this DOL: ineligible' "$CLASS_KEY"; die 3 'ineligible base: not added' UNKNOWN-INELIGIBLE; fi
    info "unknown boot DOL $DOL_SIZE B, SHA-256 $DOL_SHA: profile $pname"
    load_section "$pname"
    test_base "$pname" 1
    if [ "$FAILED" -gt 0 ]; then die 3 "the source failed $FAILED check(s) for profile $pname: not added" UNKNOWN-INELIGIBLE; fi
    new_dol "$pname" "$SLOT"
    newsha=$(sha256_file "$TMP/new.dol"); newsize=$NEW_SIZE; in_sha=$DOL_SHA
    info "this release builds a $newsize B DOL with SHA-256 $newsha from it"

    echo ''
    check_built "$built"
    if [ "$FAILED" -gt 0 ] || [ -z "$CB_FOUND" ]; then die 3 'the built ISO failed --check-built: not added'; fi
    if [ "$CB_FOUND" = "$pname" ] && [ "$CB_SHA" = "$newsha" ] && [ "$CB_SIZE" -eq "$newsize" ]; then same=1; fi
    check R1 $same "built ISO DOL ($CB_SIZE B, SHA-256 $CB_SHA, profile $CB_FOUND) is the one built from the source"
    if [ "$OK" = 0 ]; then die 3 'the built ISO was not built from this source ISO by this release (or was changed afterwards): not added'; fi

    if [ ! -t 0 ]; then die 1 '--add-known-base asks you to confirm a boot test: run it from a terminal' USAGE; fi
    echo ''
    echo "Boot-test $(basename -- "$built") first (Dolphin; MMU on, Fastmem off):"
    echo "  it boots; a type-4 CPU attacks and wavedashes; Z + D-Up opens the menu; the mod's own features still work."
    if ! ask_yes_no 'Did the built ISO pass that boot test?'; then info 'not confirmed: nothing added'; return 0; fi
    bname=$(basename -- "$src"); bname="${bname%.*} (added locally $(date +%Y-%m-%d))"
    bname=$(printf '%s' "$bname" | tr '\t\r\n' '   ')
    kd="$COMMON/$LOCAL_KNOWN"
    if [ ! -f "$kd" ]; then
        printf '# in_dol_sha256\tprofile\tbase_name\tout_dol_size\tout_dol_sha256\n# Boot DOLs added on this machine with -AddKnownBase / --add-known-base (eligible, boot-tested by the user; not part of the release).\n' > "$kd"
    elif [ -s "$kd" ] && [ "$(tail -c 1 -- "$kd" | od -An -tx1 | tr -d ' ')" != 0a ]; then
        printf '\n' >> "$kd"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$in_sha" "$pname" "$bname" "$newsize" "$newsha" >> "$kd"
    pass R2 "added to $kd: '$bname', profile $pname"
    echo 'Builds from this ISO are now treated as known, and their new DOL is checked byte for byte.'
    echo 'If you can, please also open an issue titled "Tested ISO: mod_name" with the REPORT block of the build,'
    echo 'so the ISO can be added for everyone in a later release. Thank you!'
    echo '  https://github.com/w3irDv/20XX-Synapse_Engine/issues/new'
}

build() {
    local src unknown=1 pname='' known_p='' i o ok newsha ns out outdir needb freek outsize kind note try
    abspath "$SOURCE"; src=$ABS
    echo "== source $src"
    open_iso "$src" 'source ISO'
    test_game_id source
    # ---- S2: profile
    if [ -n "${K_PROFILE[$DOL_SHA]+x}" ]; then unknown=0; known_p=${K_PROFILE[$DOL_SHA]}; fi
    if [ "$unknown" = 0 ]; then
        local where=''
        if [ "${K_LOCAL[$DOL_SHA]}" = 1 ]; then where=" (added locally, $LOCAL_KNOWN)"; fi
        pass S2 "boot DOL $DOL_SIZE B, SHA-256 $DOL_SHA: known base '${K_NAME[$DOL_SHA]}'$where -> profile $known_p"
        if [ "$PROFILE" != auto ] && [ "$PROFILE" != "$known_p" ]; then
            die 1 "--profile $PROFILE contradicts the known DOL (profile $known_p)" PROFILE
        fi
        pname=$known_p
    else
        find_release_section
        if [ -n "$INJ_P" ]; then
            bad B1 "DOL entry $(hx "$D_ENTRY"): this ISO already carries the Synapse $INJ_P section (slot $INJ_SLOT); start from the original, un-injected ISO" B1inj
            die 3 'already injected'
        fi
        info "boot DOL $DOL_SIZE B, SHA-256 $DOL_SHA: UNKNOWN (not in known_dols.tsv)"
        REPORT=1; R_ISO=$(basename -- "$src"); R_SIZE=$ISO_SIZE; R_DOLSHA=$DOL_SHA
        if [ "$PROFILE" != auto ]; then pname=$PROFILE; info "profile forced: $pname"
        else
            classify; pname=$CLASS
            if [ -n "$pname" ]; then info "classified as profile $pname (BUILD_DETAILS.md 2)"; fi
        fi
        if [ -z "$pname" ]; then
            bad S2 'no profile applies to this DOL: ineligible' "$CLASS_KEY"
            if [ "$ALLOW_UNKNOWN" = 1 ]; then die 3 'ineligible base' UNKNOWN-INELIGIBLE; else die 4 'unknown DOL, and ineligible' UNKNOWN-INELIGIBLE; fi
        fi
    fi
    if [ "$unknown" = 1 ]; then R_PROFILE=$pname; fi
    load_section "$pname"
    # ---- S3
    test_base "$pname" "$unknown"
    if [ "$unknown" = 1 ] && [ "$ALLOW_UNKNOWN" = 0 ]; then
        if [ "$FAILED" -gt 0 ]; then die 4 "unknown DOL, and ineligible: it failed $FAILED check(s) for profile $pname" UNKNOWN-INELIGIBLE; fi
        info 'eligible, but unproven: building it needs your confirmation (or --allow-unknown-base), then a boot test (BUILD_DETAILS.md 3)'
        R_CHECKS='all passed'
        # Only an ELIGIBLE unknown DOL reaches this prompt. Building never registers it: that is --add-known-base, after a boot test.
        local go=0 asked=0
        if [ "$CHECK_ONLY" = 0 ] && [ -t 0 ]; then
            asked=1
            echo ''
            echo 'This ISO is not in the list of tested ISOs, but it passed every compatibility check.'
            echo 'The checks prove the AI can be installed safely, not that it works with this mod: boot-test the result.'
            if [ "$CLASS_LOW" = 1 ]; then echo "The guess ($pname) is uncertain: the marks above disagree. Answer n unless you know it is $pname."; fi
            if ask_yes_no "Build it anyway, as profile $pname?"; then go=1; fi
        fi
        if [ "$asked" = 1 ] && [ "$go" = 0 ]; then   # the user's choice, not a failure: no ERROR line, no REPORT block
            info 'not built: you answered n (nothing was written)'
            REPORT=0; explain DECLINED; finish 4
        fi
        if [ "$go" = 0 ]; then die 4 'unknown DOL: re-run with --allow-unknown-base to build it' UNKNOWN-ELIGIBLE; fi
        info 'building the unknown DOL (confirmed at the prompt)'
    fi
    if [ "$FAILED" -gt 0 ]; then
        if [ "$unknown" = 1 ]; then explain UNKNOWN-INELIGIBLE; fi
        die 3 "the base failed $FAILED check(s): not eligible for profile $pname"
    fi
    if [ "$unknown" = 1 ]; then R_CHECKS='all passed'; fi
    # ---- S4 / S5
    new_dol "$pname" "$SLOT"
    newsha=$(sha256_file "$TMP/new.dol")
    if [ "$unknown" = 0 ]; then
        ok=0
        if [ "$newsha" = "${K_OUTSHA[$DOL_SHA]}" ] && [ "$NEW_SIZE" -eq "${K_OUTSIZE[$DOL_SHA]}" ]; then ok=1; fi
        check S5 $ok "new DOL $NEW_SIZE B, SHA-256 $newsha = known_dols.tsv"
        if [ "$OK" = 0 ]; then die 6 'the new DOL differs from the expected one' WRITE; fi
    else
        parse_hdr "$TMP/new.dol" 0
        ok=1
        if [ "$H_ENTRY" -ne "${P_NEW[$pname]}" ] || [ "${H_OFF[SLOT]}" -ne "$SEC_OFF" ] || [ "${H_VA[SLOT]}" -ne "${P_VA[$pname]}" ] ||
           [ "${H_SZ[SLOT]}" -ne "${P_SIZE[$pname]}" ] || [ "${#H_SLOTS[@]}" -ne $(( ${#D_SLOTS[@]} + 1 )) ]; then ok=0; fi
        if [ "$ok" = 1 ]; then
            sha256_range "$TMP/new.dol" "$SEC_OFF" "${P_SIZE[$pname]}"
            if [ "$SHA" != "${P_SHA[$pname]}" ]; then ok=0; fi
        fi
        for ((i = 0; i < 18 && ok == 1; i++)); do
            if [ "$i" -eq "$SLOT" ]; then continue; fi
            if [ "${H_OFF[i]}" -ne "${D_OFF[i]}" ] || [ "${H_VA[i]}" -ne "${D_VA[i]}" ] || [ "${H_SZ[i]}" -ne "${D_SZ[i]}" ]; then ok=0; fi
        done
        check S5 $ok "new DOL $NEW_SIZE B re-parses: slot $SLOT = section at $(hx "${P_VA[$pname]}"), entry $(hx "${P_NEW[$pname]}"), other slots unchanged"
        if [ "$OK" = 0 ]; then die 6 'the new DOL does not re-parse as written' WRITE; fi
    fi
    # ---- S6
    get_plan "$NEW_SIZE"
    outsize=$ISO_SIZE
    if [ $((PLAN_DOL + NEW_SIZE)) -gt "$outsize" ]; then outsize=$((PLAN_DOL + NEW_SIZE)); fi
    if [ "$PLAN_FST" -ne "$FST_OFF" ] && [ $((PLAN_FST + $(align "$FST_SIZE" 32))) -gt "$outsize" ]; then
        outsize=$((PLAN_FST + $(align "$FST_SIZE" 32)))
    fi
    pass S6 "plan $PLAN: DOL at $(hx "$PLAN_DOL") ($NEW_SIZE B), FST at $(hx "$PLAN_FST"); output $outsize B"
    headroom "$pname"
    if [ "$unknown" = 1 ]; then R_PLAN=$PLAN; kind=unknown; else kind=known; fi
    if [ "$CHECK_ONLY" = 1 ]; then
        if [ "$unknown" = 1 ]; then explain OK-CHECK-UNKNOWN; else explain OK-CHECK-KNOWN; fi
        echo ''
        echo "== check only: ELIGIBLE  profile $pname ($kind DOL), plan $PLAN, content headroom $HEADROOM"
        echo 'nothing written.'
        return 0
    fi
    # ---- G6
    if [ -n "$OUTPUT" ]; then abspath "$OUTPUT"; out=$ABS
    else
        local base
        base=$(basename -- "$src"); base=${base%.*}
        out="$(dirname -- "$src")/$base.aionly.iso"
    fi
    if [ "$out" = "$src" ]; then die 1 'the output path is the source path' USAGE; fi
    if [ -e "$out" ] && [ "$FORCE" = 0 ]; then die 1 "output exists: $out (use --force)" EXISTS; fi
    outdir=$(dirname -- "$out")
    if [ ! -d "$outdir" ]; then die 1 "output folder does not exist: $outdir" OUTDIR; fi
    freek=$(df -Pk -- "$outdir" | awk 'NR == 2 { print $4 }')
    needb=$((outsize + 64 * MIB))
    commas $(( (freek * 1024 + MIB / 2) / MIB )); local freemb=$COMMAS
    commas $(( (needb + MIB / 2) / MIB ))
    check G6 $(( freek * 1024 >= needb )) "output $out; free space $freemb MB, need $COMMAS MB"
    if [ "$OK" = 0 ]; then die 5 'not enough disk space' SPACE; fi
    # ---- S7 (the FST bytes were read at S1: $TMP/fst.bin)
    PART="$out.part"
    rm -f -- "$PART"
    commas $(( (ISO_SIZE + MIB / 2) / MIB ))
    echo "copying the source ISO ($COMMAS MB)..."
    cp -- "$src" "$PART"
    for ((try = 1; ; try++)); do       # an antivirus can briefly lock a fresh copy on a Windows drive
        if write_at "$PART" "$TMP/new.dol" "$PLAN_DOL"; then break; fi
        if [ "$try" -ge 10 ]; then die 6 "cannot write $PART: $(cat "$TMP/dd.err")" WRITE; fi
        sleep 1
    done
    note=''
    if [ "$PLAN_FST" -ne "$FST_OFF" ]; then
        cp -- "$TMP/fst.bin" "$TMP/fst.pad"
        pad_zeros "$TMP/fst.pad" $(( $(align "$FST_SIZE" 32) - FST_SIZE ))
        write_at "$PART" "$TMP/fst.pad" "$PLAN_FST"
        note=", the FST at $(hx "$PLAN_FST")"
    fi
    put_u32 "$PART" $((0x420)) "$PLAN_DOL"
    put_u32 "$PART" $((0x424)) "$PLAN_FST"
    sync
    pass S7 "wrote the DOL at $(hx "$PLAN_DOL")$note, header [0x420]=$(hx "$PLAN_DOL") [0x424]=$(hx "$PLAN_FST")"
    # ---- S8
    local v1=1 vdol vfst f1 f2 fe1 fe2 n v4=1 a b
    if [ "$(od -An -v -tx1 -N 8 -- "$PART" | tr -d ' \n')" != "$HEAD_HEX" ]; then v1=0; fi
    u32_at "$PART" $((0x1C));  if [ "$U32" -ne "$MAGIC_GC" ]; then v1=0; fi
    u32_at "$PART" $((0x428)); if [ "$U32" -ne "$FST_SIZE" ]; then v1=0; fi
    u32_at "$PART" $((0x42C)); if [ "$U32" -ne "$FST_MAX" ]; then v1=0; fi
    check V1 $v1 'disc ID, magic, FST size and FST max size unchanged'
    u32_at "$PART" $((0x420)); vdol=$U32
    sha256_range "$PART" "$vdol" "$NEW_SIZE"
    parse_hdr "$TMP/range.bin" 0
    check V2 $([ "$SHA" = "$newsha" ] && [ $((H_SIZE + 32)) -gt "$NEW_SIZE" ] && echo 1 || echo 0) "DOL at $(hx "$vdol") reads back with SHA-256 $newsha"
    u32_at "$PART" $((0x424)); vfst=$U32
    sha256_range "$PART" "$vfst" "$FST_SIZE"
    check V3 $([ "$SHA" = "$(sha256_file "$TMP/fst.bin")" ] && echo 1 || echo 0) "FST at $(hx "$vfst") reads back unchanged"
    read -r f1 fe1 < "$TMP/files.sorted"
    read -r f2 fe2 < <(tail -n 1 "$TMP/files.sorted")
    for o in "$f1 $fe1" "$f2 $fe2"; do
        read -r a b <<< "$o"
        n=$((b - a)); if [ "$n" -gt "$MIB" ]; then n=$MIB; fi
        sha256_range "$PART" "$a" "$n"; local s1=$SHA
        sha256_range "$src" "$a" "$n"
        if [ "$s1" != "$SHA" ]; then v4=0; fi
    done
    check V4 $v4 "first and last file ($(hx "$f1"), $(hx "$f2")) read back identical"
    local psize
    psize=$(fsize "$PART")
    check V5 $(( psize == outsize )) "output size $psize B = planned $outsize B"
    if [ "$FAILED" -gt 0 ]; then die 6 'read-back verification failed' WRITE; fi
    mv -f -- "$PART" "$out"
    PART=''
    # ---- S9
    echo ''
    echo '== DONE'
    commas "$outsize"
    echo "  output    : $out ($COMMAS B)"
    if [ "$unknown" = 1 ]; then echo "  profile   : $pname (unknown DOL - boot-test it before relying on it)"
    else echo "  profile   : $pname (known DOL)"; fi
    echo "  plan      : $PLAN  DOL at $(hx "$PLAN_DOL"), FST at $(hx "$PLAN_FST")"
    echo "  headroom  : $HEADROOM"
    show_boot_checklist "$pname"
    if [ "$unknown" = 1 ]; then
        echo 'Once it passes the boot check, you can add this ISO to the tested list on this machine:'
        echo "  \"$SCRIPT_DIR/$SELF\" --add-known-base \"$src\" --built-iso \"$out\""
    fi
    if [ "$unknown" = 1 ]; then R_OUTPUT=$out; explain OK-BUILT-UNKNOWN; else explain OK-BUILT-KNOWN; fi
}

# ================================================================================================= main
SOURCE='' OUTPUT='' PROFILE=auto ALLOW_UNKNOWN=0 CHECK_ONLY=0 FORCE=0 COMMON='' CHECK_BUILT='' ADD_KNOWN='' BUILT_ISO=''
need_value() { if [ "$2" -lt 2 ]; then die 1 "option $1 needs a value" USAGE; fi; }
while [ "$#" -gt 0 ]; do
    case $1 in
        --source)              need_value "$1" "$#"; SOURCE=$2; shift 2 ;;
        --source=*)            SOURCE=${1#*=}; shift ;;
        --output)              need_value "$1" "$#"; OUTPUT=$2; shift 2 ;;
        --output=*)            OUTPUT=${1#*=}; shift ;;
        --profile)             need_value "$1" "$#"; PROFILE=$2; shift 2 ;;
        --profile=*)           PROFILE=${1#*=}; shift ;;
        --common)              need_value "$1" "$#"; COMMON=$2; shift 2 ;;
        --common=*)            COMMON=${1#*=}; shift ;;
        --check-built)         need_value "$1" "$#"; CHECK_BUILT=$2; shift 2 ;;
        --check-built=*)       CHECK_BUILT=${1#*=}; shift ;;
        --add-known-base)      need_value "$1" "$#"; ADD_KNOWN=$2; shift 2 ;;
        --add-known-base=*)    ADD_KNOWN=${1#*=}; shift ;;
        --built-iso)           need_value "$1" "$#"; BUILT_ISO=$2; shift 2 ;;
        --built-iso=*)         BUILT_ISO=${1#*=}; shift ;;
        --allow-unknown-base)  ALLOW_UNKNOWN=1; shift ;;
        --check-only)          CHECK_ONLY=1; shift ;;
        --force)               FORCE=1; shift ;;
        -h|--help)             echo "$USAGE_LINE"; echo 'See README.md next to this script.'; exit 0 ;;
        *)                     die 1 "unknown option or argument: $1 ($USAGE_LINE)" USAGE ;;
    esac
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/synapse.XXXXXX")
if [ -z "$COMMON" ]; then COMMON="$SCRIPT_DIR/../common"; fi
if [ -d "$COMMON" ]; then COMMON=$(cd -- "$COMMON" && pwd -P); else abspath "$COMMON"; COMMON=$ABS; fi
if [ -n "$CHECK_BUILT" ]; then
    if [ -n "$SOURCE" ] || [ -n "$OUTPUT" ] || [ "$PROFILE" != auto ] || [ "$ALLOW_UNKNOWN" = 1 ] || [ "$CHECK_ONLY" = 1 ] || [ "$FORCE" = 1 ] ||
       [ -n "$ADD_KNOWN" ] || [ -n "$BUILT_ISO" ]; then
        die 1 '--check-built can only be combined with --common' USAGE
    fi
elif [ -n "$ADD_KNOWN" ]; then
    if [ -z "$BUILT_ISO" ]; then die 1 '--add-known-base <original iso> needs --built-iso <the iso built from it and boot-tested>' USAGE; fi
    if [ -n "$SOURCE" ] || [ -n "$OUTPUT" ] || [ "$ALLOW_UNKNOWN" = 1 ] || [ "$CHECK_ONLY" = 1 ] || [ "$FORCE" = 1 ]; then
        die 1 '--add-known-base can only be combined with --built-iso, --profile and --common' USAGE
    fi
    case $PROFILE in auto|vanilla|hybrid64|mex) ;; *) die 1 "bad --profile '$PROFILE' (auto|vanilla|hybrid64|mex)" USAGE ;; esac
else
    if [ -n "$BUILT_ISO" ]; then die 1 '--built-iso goes with --add-known-base' USAGE; fi
    if [ -z "$SOURCE" ]; then die 1 "$USAGE_LINE" USAGE; fi
    case $PROFILE in auto|vanilla|hybrid64|mex) ;; *) die 1 "bad --profile '$PROFILE' (auto|vanilla|hybrid64|mex)" USAGE ;; esac
    if [ "$CHECK_ONLY" = 1 ] && { [ -n "$OUTPUT" ] || [ "$FORCE" = 1 ]; }; then die 1 '--check-only writes nothing: drop --output / --force' USAGE; fi
fi
load_common "$COMMON"
if [ -n "$CHECK_BUILT" ]; then
    abspath "$CHECK_BUILT"
    check_built "$ABS"
    if [ "$FAILED" -gt 0 ]; then die 3 "$FAILED check(s) failed"; fi
    echo '== --check-built: OK (still bootable as built)'
    explain OK-CHECKBUILT
elif [ -n "$ADD_KNOWN" ]; then
    abspath "$ADD_KNOWN"; ak_src=$ABS
    abspath "$BUILT_ISO"
    add_known_base "$ak_src" "$ABS"
else
    build
fi
finish 0
