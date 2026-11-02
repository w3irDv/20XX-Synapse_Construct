<#
.SYNOPSIS
  Build a Synapse AI-only ISO from a clean Melee NTSC 1.02 ISO (vanilla, hybrid.64, Akaneia, SSBM ACE, or
  an eligible unknown GALE01 ISO). Needs nothing but Windows PowerShell 5.1+ and ..\common.

.DESCRIPTION
  The rules it applies, for players and modders: ..\BUILD_DETAILS.md (steps S0-S9, checks G/B/V, plans P1-P3,
  -CheckBuilt K1-K8).
  The source ISO is never modified: the output is written as <output>.part and renamed when verified.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-SynapseIso.ps1 -SourceIso "D:\isos\Melee.iso"
.EXAMPLE
  .\Build-SynapseIso.ps1 -SourceIso .\akaneia.iso -OutputIso .\akaneia.aionly.iso -Force
.EXAMPLE
  .\Build-SynapseIso.ps1 -SourceIso .\hybrid.64.iso -CheckOnly
.EXAMPLE
  .\Build-SynapseIso.ps1 -CheckBuilt .\Melee.aionly.iso
.EXAMPLE
  .\Build-SynapseIso.ps1 -AddKnownBase ".\some mod.iso" -BuiltIso ".\some mod.aionly.iso"

  An unknown ISO that passes every check is offered a build at a prompt (or built with -AllowUnknownBase).
  Building never adds it to the known list: -AddKnownBase does, into ..\common\known_dols.local.tsv (outside
  SHA256SUMS), only after re-checking the original, -CheckBuilt on the built ISO, matching its DOL to the one
  built from the original, and a boot test the user confirms.

  Exit codes: 0 ok | 1 usage | 2 release integrity / unreadable input | 3 ineligible base or -CheckBuilt failure
              4 unknown DOL without -AllowUnknownBase | 5 disk space / no placement | 6 write or read-back failure
#>
param(
    [string]$SourceIso,
    [string]$OutputIso,
    [string]$Profile = 'auto',
    [switch]$AllowUnknownBase,
    [switch]$CheckOnly,
    [switch]$Force,
    [string]$Common,
    [string]$CheckBuilt,
    [string]$AddKnownBase,
    [string]$BuiltIso
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------------------------------ constants
$MAGIC_GC      = 0xC2339F3DL
$MEX_CAVE_LO   = 0x8032C65CL
$MEX_CAVE_HI   = 0x8032EA80L
$APPLOADER_HI  = 0x81200000L
$MEM1_TOP      = 0x81800000L
$BI2_SIZE      = [int64]0x2000
$STATIC_FST_LIMIT = [int64]0x7F40          # align32(FST max) <= this keeps static payloads below the ceiling
$BYTES_PER_FILE   = 24                     # average FST cost of one added file (BUILD_DETAILS.md 4)
$script:ClassKey = 'S2'; $script:ClassLow = $false   # set by Get-ClassifiedProfile
$LOCAL_KNOWN   = 'known_dols.local.tsv'      # bases added with -AddKnownBase (in -Common, outside SHA256SUMS)
$VANILLA_ENTRY = 0x8000522CL
$HYBRID_ENTRY  = 0x80484800L
$HYBRID_TEXT_END = 0x80486600L
$ALT_GAME_IDS  = @('GHME01')                 # besides GALE01: accepted only for a known_dols.tsv row with that game_id (hybrid.64 v3.2 vanilla build)

$script:Failed = 0
$script:PartFile = $null
$script:Plain = New-Object System.Collections.ArrayList    # plain-language explanations, printed once at the end
$script:Report = $null                                      # report block for an unknown DOL

# Plain-language messages for players, keyed by check ID or outcome. The wording is shared by the three
# release scripts: keep it identical in release/linux and release/macos.
$PLAYER = @{
    'G1'      = "The file can't be read, or it is too small to be a Melee disc image."
    'G2'      = "This isn't a plain GameCube disc image (it may be compressed: .nkit, .rvz, .ciso, .wbfs). In Dolphin, right-click the game > Convert File... > ISO, then try again."
    'G3'      = "This isn't Melee NTSC 1.02 (the US/Japanese version 1.02). PAL and versions 1.00/1.01 aren't supported."
    'G3id'    = "This disc's game ID is accepted only for the exact ISOs this release lists (hybrid.64's vanilla build is one). This copy isn't one of them: start from the original, unmodified ISO."
    'G4'      = "The disc image looks truncated or damaged. Dump or download it again."
    'G5'      = "The disc image looks truncated or damaged. Dump or download it again."
    'B1'      = "Another mod already changes how this game starts up, so Synapse can't be added on top of it."
    'B1inj'   = "This ISO already contains the Synapse AI. Start again from your original ISO (the one without it)."
    'B2'      = "This mod's game code is laid out differently from what Synapse needs; it can't be added safely."
    'B3'      = "This mod's game code is laid out differently from what Synapse needs; it can't be added safely."
    'B4'      = "This mod's game code is laid out differently from what Synapse needs; it can't be added safely."
    'B5'      = "This mod's game code is laid out differently from what Synapse needs; it can't be added safely."
    'B6'      = "Another mod already changes game code that the Synapse AI needs, so the two can't be combined (20XX is one such mod)."
    'B7'      = "This mod uses the memory area that Synapse needs on Akaneia/ACE-style ISOs; it can't be added safely."
    'B8'      = "This mod's game code doesn't match the kind of ISO it looks like; it can't be added safely."
    'B9'      = "This ISO has more added content (stages, characters, files) than the AI can fit next to on this base (vanilla / hybrid.64). Remove some content, or use an Akaneia/ACE-based ISO, which has no such limit."
    'B10'     = "This mod changes game code that the AI relies on; they are probably not compatible."
    'S2'      = "This ISO's game code isn't a kind Synapse knows how to modify."
    'DECLINED' = "Nothing was built: you answered n. To build it later, run it again and answer y, then test the result in Dolphin before relying on it."
    'S2-20XX' = "This is the 20XX Hack Pack: it already has the 20XX AI and its own CPU menus, so this release doesn't modify it."
    'K2none'  = "This ISO doesn't contain the Synapse AI from this release (it was never added, or another tool removed it)."
    'K2bad'   = "The Synapse AI inside this ISO is damaged: another tool changed it. Rebuild from your copy without Synapse."
    'K3'      = "Another tool changed how the game starts up, so the Synapse AI no longer loads. Rebuild from your copy without Synapse."
    'K4'      = "Part of the game this ISO needs to start was removed by another tool. Rebuild from your copy without Synapse."
    'K5'      = "Another mod now changes game code that the AI needs. Rebuild from your copy without Synapse, without that mod."
    'K6'      = "Another mod now uses the memory area the AI needs. Rebuild from your copy without Synapse, without that mod."
    'K7'      = "This ISO will freeze at startup: too much content was added after Synapse. Add the content to your copy without Synapse and build again; if that copy is refused too, there is too much content for this base."
    'USAGE'   = "The command was not understood. See README.md for the options."
    'PROFILE' = "This ISO was recognised, and the -Profile you chose doesn't match it. Leave -Profile out."
    'EXISTS'  = "The output file already exists. Add -Force to replace it, or choose another -OutputIso."
    'OUTDIR'  = "The folder for the output file doesn't exist."
    'RELEASE' = "The release files are incomplete, damaged, or were edited. Download or copy the whole release folder again."
    'READ'    = "The file can't be read (wrong path, or it is in use)."
    'SPACE'   = "There isn't enough free disk space for the new ISO. Free some space or choose another -OutputIso."
    'WRITE'   = "Writing the new ISO failed and the incomplete file was deleted. Check the disk and run again."
    'UNKNOWN-ELIGIBLE'   = "This ISO's game code was changed by the mod you're using, and this release hasn't been tested with it. It looks compatible. To build it anyway, run it again and answer y to the question (or add -AllowUnknownBase), then test the result in Dolphin before relying on it."
    'UNKNOWN-INELIGIBLE' = "This ISO's game code was changed by the mod you're using, and it isn't compatible with Synapse (see the reasons above)."
    'OK-CHECK-KNOWN'     = "This ISO is supported. Run the same command without -CheckOnly to build it."
    'OK-CHECK-UNKNOWN'   = "This ISO looks compatible but hasn't been tested with Synapse. You can build it; test it in Dolphin before relying on it."
    'OK-BUILT-KNOWN'     = "Done: your new ISO with the Synapse AI is ready (path above). Your original ISO was not changed."
    'OK-BUILT-UNKNOWN'   = "Done, but this mod has never been tested with Synapse: test the new ISO in Dolphin (steps above) before relying on it, and please report the result (REPORT block above)."
    'OK-CHECKBUILT'      = "This ISO still contains a working Synapse AI."
}

# ------------------------------------------------------------------------------------------------ helpers
function Explain([string]$key) {
    if ($PLAYER.ContainsKey($key) -and -not $script:Plain.Contains($PLAYER[$key])) { [void]$script:Plain.Add($PLAYER[$key]) }
}
function Fail([int]$code, [string]$msg, [string]$key = '') {
    if ($key) { Explain $key }
    $e = New-Object System.Exception $msg
    $e.Data['code'] = $code
    throw $e
}
function Say([string]$tag, [string]$msg) { Write-Host ("[{0}] {1}" -f $tag, $msg) }
function Pass([string]$id, [string]$msg) { Say 'PASS' ("{0} {1}" -f $id, $msg) }
function Info([string]$msg) { Say 'INFO' $msg }
function Bad([string]$id, [string]$msg, [string]$key = '') {
    $script:Failed++; Say 'FAIL' ("{0} {1}" -f $id, $msg)
    if ($key) { Explain $key } else { Explain $id }
    if ($null -ne $script:Report -and $script:Report.FailedIds -notcontains $id) { $script:Report.FailedIds += $id }
}
function Check([string]$id, [bool]$ok, [string]$msg) { if ($ok) { Pass $id $msg } else { Bad $id $msg }; return $ok }
function Hex([int64]$v) { '0x{0:X8}' -f $v }
function Align([int64]$x, [int64]$a) { ($x + $a - 1) -band (-bnot ($a - 1)) }
function BE32([byte[]]$b, [int]$o) {
    return ([int64]$b[$o] -shl 24) -bor ([int64]$b[$o+1] -shl 16) -bor ([int64]$b[$o+2] -shl 8) -bor [int64]$b[$o+3]
}
function Set-BE32([byte[]]$b, [int]$o, [int64]$v) {
    $b[$o]   = [byte](($v -shr 24) -band 0xFF); $b[$o+1] = [byte](($v -shr 16) -band 0xFF)
    $b[$o+2] = [byte](($v -shr 8) -band 0xFF);  $b[$o+3] = [byte]($v -band 0xFF)
}
function HexStr([byte[]]$b) { ([BitConverter]::ToString($b)).Replace('-', '') }
function Sha256-Bytes([byte[]]$b, [int]$off = 0, [int]$len = -1) {
    if ($len -lt 0) { $len = $b.Length - $off }
    $h = [Security.Cryptography.SHA256]::Create()
    try { return (HexStr ($h.ComputeHash($b, $off, $len))).ToLower() } finally { $h.Dispose() }
}
function Sha256-File([string]$p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() }
function Full([string]$p) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p) }
function Read-Bytes($fs, [int64]$off, [int]$n) {
    $buf = New-Object byte[] $n
    [void]$fs.Seek($off, [IO.SeekOrigin]::Begin)
    $got = 0
    while ($got -lt $n) {
        $r = $fs.Read($buf, $got, $n - $got)
        if ($r -le 0) { Fail 2 ("unexpected end of file reading {0} bytes at {1}" -f $n, (Hex $off)) 'READ' }
        $got += $r
    }
    return ,$buf
}
function Read-Table([string]$path) {
    $rows = @()
    foreach ($ln in [IO.File]::ReadAllLines($path)) {
        $l = $ln.TrimEnd("`r")
        if ($l -eq '' -or $l.StartsWith('#')) { continue }
        $rows += ,($l -split "`t")
    }
    return ,$rows
}

# ---- DOL model ----------------------------------------------------------------------------------------
function Get-Slots([byte[]]$d) {
    $s = @()
    for ($i = 0; $i -lt 18; $i++) {
        $sz = BE32 $d (0x90 + 4*$i)
        if ($sz -ne 0) { $s += [pscustomobject]@{ Slot = $i; Off = (BE32 $d (4*$i)); Va = (BE32 $d (0x48 + 4*$i)); Size = $sz } }
    }
    return ,$s
}
function Get-DolSize([byte[]]$hdr) {
    $m = [int64]0
    for ($i = 0; $i -lt 18; $i++) {
        $sz = BE32 $hdr (0x90 + 4*$i)
        if ($sz -ne 0) { $e = (BE32 $hdr (4*$i)) + $sz; if ($e -gt $m) { $m = $e } }
    }
    return $m
}
function Get-Window([byte[]]$d, $slots, [int64]$va, [int]$n) {   # bytes at [va, va+n) if inside one loaded section
    foreach ($s in $slots) {
        if ($s.Va -le $va -and ($va + $n) -le ($s.Va + $s.Size)) {
            $w = New-Object byte[] $n
            [Array]::Copy($d, [int]($s.Off + $va - $s.Va), $w, 0, $n)
            return ,$w
        }
    }
    return $null
}
function Get-Word([byte[]]$d, $slots, [int64]$va) {
    $w = Get-Window $d $slots $va 4
    if ($null -eq $w) { return $null }
    return (BE32 $w 0)
}
function Get-Ceiling([int64]$fstMax) { $MEM1_TOP - (Align $fstMax 32) - $BI2_SIZE }

# ---- ISO model ----------------------------------------------------------------------------------------
function Open-Iso([string]$path, [string]$who) {
    # G1-G5 + DOL + FST. Returns a hashtable with everything the steps need; the stream stays open.
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail 2 ("{0} not found: {1}" -f $who, $path) 'READ' }
    try { $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read) }
    catch { Fail 2 ("cannot open {0}: {1}" -f $path, $_.Exception.Message) 'READ' }
    $iso = @{ Path = $path; Fs = $fs; Size = [int64]$fs.Length }
    if (-not (Check 'G1' ($iso.Size -ge 0x2460) ("{0} readable, {1} B" -f (Split-Path -Leaf $path), $iso.Size))) { Fail 3 'image too small' }
    $h = Read-Bytes $fs 0 0x2460
    $iso.Head = $h
    if (-not (Check 'G2' ((BE32 $h 0x1C) -eq $MAGIC_GC) ("GameCube magic at 0x01C = {0}" -f (Hex (BE32 $h 0x1C))))) {
        Fail 3 'not a plain GameCube image (NKit/RVZ/WBFS/CISO?): convert it to .iso with Dolphin first' }
    $gid = [Text.Encoding]::ASCII.GetString($h, 0, 6)
    if (-not (Check 'G3' (($gid -eq 'GALE01' -or $ALT_GAME_IDS -contains $gid) -and $h[7] -eq 2) ("game ID {0}, revision {1} (need GALE01 rev 2{2})" -f $gid, $h[7], $(if ($gid -eq 'GALE01') { '' } else { '; ' + $gid + ' only for a listed ISO' })))) {
        Fail 3 'not Melee NTSC 1.02' }
    $iso.GameId = $gid
    $iso.DolOff = BE32 $h 0x420; $iso.FstOff = BE32 $h 0x424; $iso.FstSize = BE32 $h 0x428; $iso.FstMax = BE32 $h 0x42C
    $iso.AppEnd = [int64]0x2460 + (BE32 $h 0x2454) + (BE32 $h 0x2458)
    $g4 = ($iso.DolOff + 0x100 -le $iso.Size) -and ($iso.FstOff + $iso.FstSize -le $iso.Size) -and `
          ($iso.AppEnd -le $iso.Size) -and ($iso.FstSize -le $iso.FstMax) -and ($iso.FstSize -ge 12)
    if (-not (Check 'G4' $g4 ("DOL {0}, FST {1} ({2} B, max {3} B), apploader end {4} inside the image" -f `
            (Hex $iso.DolOff), (Hex $iso.FstOff), $iso.FstSize, $iso.FstMax, (Hex $iso.AppEnd)))) { Fail 3 'truncated or corrupt image' }
    # FST: file extents
    $F = Read-Bytes $fs $iso.FstOff ([int]$iso.FstSize)
    $iso.Fst = $F
    $n = BE32 $F 8
    $files = New-Object System.Collections.ArrayList
    $over = 0
    for ($i = 1; $i -lt $n; $i++) {
        $o = 12 * $i
        if ($o + 12 -gt $F.Length) { break }
        if ($F[$o] -eq 0) {
            $fo = BE32 $F ($o + 4); $fz = BE32 $F ($o + 8)
            if ($fz -gt 0) {
                [void]$files.Add([pscustomobject]@{ Start = $fo; End = $fo + $fz })
                if ($fo + $fz -gt $iso.Size) { $over++ }
            }
        }
    }
    $iso.Files = $files
    if (-not (Check 'G5' ($over -eq 0 -and 12 * $n -le $F.Length) ("{0} FST entries, {1} files, all inside the image" -f $n, $files.Count))) {
        Fail 3 'truncated image (files past the end)' }
    # DOL
    $hdr = Read-Bytes $fs $iso.DolOff 0x100
    $iso.DolSize = Get-DolSize $hdr
    if ($iso.DolSize -le 0x100 -or $iso.DolOff + $iso.DolSize -gt $iso.Size) { Fail 3 ("DOL at {0} runs past the end of the image" -f (Hex $iso.DolOff)) 'G4' }
    $iso.Dol = Read-Bytes $fs $iso.DolOff ([int]$iso.DolSize)
    $iso.Slots = Get-Slots $iso.Dol
    $iso.DolSha = Sha256-Bytes $iso.Dol
    return $iso
}

# ---- release/common ----------------------------------------------------------------------------------
function Load-Common([string]$dir) {
    $sums = Join-Path $dir 'SHA256SUMS'
    if (-not (Test-Path -LiteralPath $sums)) { Fail 2 ("release data not found: {0} (use -Common <dir>)" -f $sums) 'RELEASE' }
    $n = 0
    foreach ($ln in [IO.File]::ReadAllLines($sums)) {
        $l = $ln.TrimEnd("`r"); if ($l -eq '') { continue }
        $hash = $l.Substring(0, 64).ToLower(); $rel = $l.Substring(66)
        $p = Join-Path $dir ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $p)) { Fail 2 ("release file missing: {0}" -f $rel) 'RELEASE' }
        if ((Sha256-File $p) -ne $hash) { Fail 2 ("release file corrupted or edited: {0} (SHA-256 mismatch)" -f $rel) 'RELEASE' }
        $n++
    }
    Pass 'S0' ("release data {0}: {1} files match SHA256SUMS" -f $dir, $n)
    $c = @{ Dir = $dir; Profiles = @{}; Known = @{}; Hooks = @(); Fps = @() }
    foreach ($r in (Read-Table (Join-Path $dir 'profiles.tsv'))) {
        $top = $null; if ($r[9] -ne '-') { $top = [Convert]::ToInt64($r[9], 16) }
        $c.Profiles[$r[0]] = [pscustomobject]@{ Name = $r[0]; File = $r[1]; Size = [int64]$r[2]; Sha = $r[3].ToLower()
            Va = [Convert]::ToInt64($r[4], 16); NewEntry = [Convert]::ToInt64($r[5], 16); ExpEntry = [Convert]::ToInt64($r[6], 16)
            Placement = $r[7]; MexCave = ($r[8] -eq '1'); StaticTop = $top }
    }
    foreach ($r in (Read-Table (Join-Path $dir 'known_dols.tsv'))) {
        $gid = 'GALE01'; if ($r.Count -ge 6 -and $r[5]) { $gid = $r[5] }      # optional 6th column: a non-GALE01 disc
        $c.Known[$r[0].ToLower()] = [pscustomobject]@{ Profile = $r[1]; Name = $r[2]; OutSize = [int64]$r[3]; OutSha = $r[4].ToLower(); Local = $false; GameId = $gid }
    }
    $local = Join-Path $dir $LOCAL_KNOWN      # optional, added with -AddKnownBase; a release row wins over a local one
    if (Test-Path -LiteralPath $local) {
        $n = 0
        foreach ($r in (Read-Table $local)) {
            if ($r.Count -lt 5 -or $c.Known.ContainsKey($r[0].ToLower()) -or -not $c.Profiles.ContainsKey($r[1])) { continue }
            $c.Known[$r[0].ToLower()] = [pscustomobject]@{ Profile = $r[1]; Name = $r[2]; OutSize = [int64]$r[3]; OutSha = $r[4].ToLower(); Local = $true; GameId = 'GALE01' }
            $n++
        }
        Info ("{0}: {1} locally added base(s)" -f $LOCAL_KNOWN, $n)
    }
    foreach ($r in (Read-Table (Join-Path $dir 'hooks.tsv'))) {
        $c.Hooks += ,([pscustomobject]@{ Va = [Convert]::ToInt64($r[0], 16); Word = [Convert]::ToInt64($r[1], 16); Name = $r[2] })
    }
    foreach ($r in (Read-Table (Join-Path $dir 'fingerprints.tsv'))) {
        $c.Fps += ,([pscustomobject]@{ Name = $r[0]; Va = [Convert]::ToInt64($r[1], 16); Len = [int]$r[2]; Hex = $r[3].ToUpper() })
    }
    return $c
}
function Test-Interactive {   # a person at a console who can answer a prompt (double-click / drag-and-drop runs)
    try { return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) } catch { return $false }
}
function Ask-YesNo([string]$question) {
    Write-Host ($question + ' [y/N] ') -NoNewline   # not Read-Host's prompt, which appends ': '
    $a = Read-Host
    return ($a -match '^\s*(y|yes)\s*$')
}
function Add-LocalKnownDol([string]$dir, [string]$inSha, [string]$profile, [string]$name, [int64]$outSize, [string]$outSha) {
    # Appends a row to known_dols.local.tsv (not covered by SHA256SUMS: the release's own data stays as shipped). LF endings.
    $kd = Join-Path $dir $LOCAL_KNOWN
    $name = ($name -replace "[`t`r`n]", ' ').Trim()
    $text = ''
    if (Test-Path -LiteralPath $kd) { $text = [IO.File]::ReadAllText($kd) }
    else {
        $text = "# in_dol_sha256`tprofile`tbase_name`tout_dol_size`tout_dol_sha256`n" +
                "# Boot DOLs added on this machine with -AddKnownBase / --add-known-base (eligible, boot-tested by the user; not part of the release).`n"
    }
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`n" }
    $text += ("{0}`t{1}`t{2}`t{3}`t{4}`n" -f $inSha, $profile, $name, $outSize, $outSha)
    [IO.File]::WriteAllText($kd, $text, (New-Object Text.UTF8Encoding $false))
}
function Load-Section($c, $p) {
    $path = Join-Path $c.Dir ($p.File -replace '/', '\')
    $b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -ne $p.Size -or (Sha256-Bytes $b) -ne $p.Sha) { Fail 2 ("{0}: size/SHA-256 do not match profiles.tsv" -f $p.File) 'RELEASE' }
    Pass 'S0' ("section {0}: {1} B, SHA-256 matches profiles.tsv" -f $p.File, $b.Length)
    return ,$b
}

# ---- checks shared by the build (B) and -CheckBuilt (K) ----------------------------------------------
function Test-Hooks($iso, $c, [string]$id) {
    $bad = @()
    foreach ($h in $c.Hooks) {
        $w = Get-Word $iso.Dol $iso.Slots $h.Va
        if ($null -eq $w -or $w -ne $h.Word) {
            $f = 'unmapped'; if ($null -ne $w) { $f = Hex $w }
            $bad += ("{0} {1} holds {2}, expected {3}" -f $h.Name, (Hex $h.Va), $f, (Hex $h.Word))
        }
    }
    if ($bad.Count -eq 0) { Pass $id ("{0} hook sites hold their stock words" -f $c.Hooks.Count) }
    else { foreach ($x in $bad) { Bad $id ("hook taken: {0}" -f $x) } }
    return ($bad.Count -eq 0)
}
function Get-MexCave($iso) { Get-Window $iso.Dol $iso.Slots $MEX_CAVE_LO ([int]($MEX_CAVE_HI - $MEX_CAVE_LO)) }
function Test-AllZero([byte[]]$b) { foreach ($x in $b) { if ($x -ne 0) { return $false } }; return $true }
function Get-Headroom($p, $iso) {
    if ($p.Placement -ne 'static') { return 'unlimited (dynamic)' }
    $hb = $STATIC_FST_LIMIT - (Align $iso.FstMax 32)
    if ($hb -lt 0) { return ("{0} B (OVER THE LIMIT)" -f $hb) }
    return ("{0:N0} B (~{1} files at {2} B each)" -f $hb, [math]::Floor($hb / $BYTES_PER_FILE), $BYTES_PER_FILE)
}
function Test-Ceiling($p, $iso, [string]$id) {
    $ceil = Get-Ceiling $iso.FstMax
    return (Check $id ($ceil -ge $p.StaticTop) ("static ceiling {0} (FST max {1} B) >= {2} (end of the A4 block)" -f `
        (Hex $ceil), $iso.FstMax, (Hex $p.StaticTop)))
}

function Test-DiscFile($iso, [string]$name) {   # $name in the FST name table (NUL-separated names; the table starts at 12 x entry count)
    $st = 12 * (BE32 $iso.Fst 8)
    $t = [char]0 + [Text.Encoding]::GetEncoding(28591).GetString($iso.Fst, $st, $iso.Fst.Length - $st)
    return ($t.IndexOf([char]0 + $name + [char]0, [StringComparison]::Ordinal) -ge 0)
}
function Get-ClassifiedProfile($iso, $c) {   # BUILD_DETAILS.md 2 -> profile or $null; sets $script:ClassKey / $script:ClassLow
    $script:ClassKey = 'S2'; $script:ClassLow = $false
    $entry = BE32 $iso.Dol 0xE0
    if ($entry -eq $VANILLA_ENTRY) {
        $mxdt = Test-DiscFile $iso 'MxDt.dat'; $aieng = Test-DiscFile $iso 'AI_Engine.bin'
        Info ("disc marks: MxDt.dat {0} (m-ex data file), AI_Engine.bin {1} (20XX AI file)" -f $(if ($mxdt) { 'yes' } else { 'no' }), $(if ($aieng) { 'yes' } else { 'no' }))
        $cave = Get-MexCave $iso
        if ($null -ne $cave -and (Test-AllZero $cave)) {
            if (-not $mxdt -or $aieng) { $script:ClassLow = $true; Info 'low confidence: the m-ex cave is empty, but the disc marks are not those of an m-ex ISO' }
            return 'mex'
        }
        if ($aieng) {
            Info '20XX Hack Pack (AI_Engine.bin on the disc, m-ex cave holds code): it already runs the 20XX AI'
            $script:ClassKey = 'S2-20XX'
            return $null
        }
        if ($mxdt) { $script:ClassLow = $true; Info 'low confidence: MxDt.dat is on the disc, but the m-ex cave holds code' }
        return 'vanilla'          # vanilla family; B9 then says whether its FST fits the static layout
    }
    if ($entry -eq $HYBRID_ENTRY) {
        foreach ($s in $iso.Slots) { if ($s.Slot -le 6 -and $s.Va -eq $HYBRID_ENTRY -and ($s.Va + $s.Size) -le $HYBRID_TEXT_END) { return 'hybrid64' } }
    }
    Info ("entry point {0}: another loader owns the boot (already injected, or another DOL mod)" -f (Hex $entry))
    return $null
}

function Test-Base($iso, $c, $p, [bool]$unknown) {   # S3: B1-B10
    $d = $iso.Dol; $entry = BE32 $d 0xE0
    [void](Check 'B1' ($entry -eq $p.ExpEntry) ("DOL entry {0}, expected {1}" -f (Hex $entry), (Hex $p.ExpEntry)))
    $free = @(0..6 | Where-Object { (BE32 $d (0x90 + 4*$_)) -eq 0 })
    $slot = -1; if ($free.Count -gt 0) { $slot = $free[0] }
    [void](Check 'B2' ($slot -ge 0) ("free text slot: {0}" -f $(if ($slot -ge 0) { $slot } else { 'none' })))
    $lo = $p.Va; $hi = $p.Va + $p.Size
    $clash = @($iso.Slots | Where-Object { $lo -lt ($_.Va + $_.Size) -and $_.Va -lt $hi } | ForEach-Object { $_.Slot })
    [void](Check 'B3' ($clash.Count -eq 0) ("section [{0}, {1}) overlaps {2}" -f (Hex $lo), (Hex $hi), $(if ($clash.Count) { "slot(s) $($clash -join ',')" } else { 'no loaded section' })))
    $bss = BE32 $d 0xD8; $bsz = BE32 $d 0xDC
    [void](Check 'B4' ($bss -le $lo -and $hi -le ($bss + $bsz) -and $hi -le $APPLOADER_HI) ("section inside bss [{0}, {1}) and below {2}" -f (Hex $bss), (Hex ($bss + $bsz)), (Hex $APPLOADER_HI)))
    $inText = @($iso.Slots | Where-Object { $_.Slot -le 6 -and $_.Va -le $p.ExpEntry -and $p.ExpEntry -lt ($_.Va + $_.Size) })
    [void](Check 'B5' ($inText.Count -gt 0) ("chain target {0} lies in a loaded text section" -f (Hex $p.ExpEntry)))
    [void](Test-Hooks $iso $c 'B6')
    $cave = Get-MexCave $iso
    if ($p.MexCave) {
        [void](Check 'B7' ($null -ne $cave -and (Test-AllZero $cave)) ("m-ex cave [{0}, {1}) mapped and all zero" -f (Hex $MEX_CAVE_LO), (Hex $MEX_CAVE_HI)))
    } else {
        [void](Check 'B8' ($null -eq $cave -or -not (Test-AllZero $cave)) "m-ex cave not all zero (vanilla-family DOL)")
    }
    if ($p.Placement -eq 'static') { [void](Test-Ceiling $p $iso 'B9') }
    if ($unknown) {
        $bad = @()
        foreach ($f in $c.Fps) {
            $w = Get-Window $d $iso.Slots $f.Va $f.Len
            if ($null -eq $w -or (HexStr $w) -ne $f.Hex) { $bad += $f.Name }
        }
        if ($bad.Count -eq 0) { Pass 'B10' ("{0} fingerprint windows match" -f $c.Fps.Count) }
        else { Bad 'B10' ("fingerprints differ: {0}" -f ($bad -join ', ')) }
    }
    return $slot
}

# ---- S4 / S6 -----------------------------------------------------------------------------------------
function New-Dol([byte[]]$old, [int64]$oldSize, [byte[]]$sec, $p, [int]$slot) {
    $secOff = Align $oldSize 32
    $newSize = Align ($secOff + $sec.Length) 32
    $new = New-Object byte[] $newSize
    [Array]::Copy($old, 0, $new, 0, $oldSize)
    [Array]::Copy($sec, 0, $new, $secOff, $sec.Length)
    Set-BE32 $new (4*$slot) $secOff
    Set-BE32 $new (0x48 + 4*$slot) $p.Va
    Set-BE32 $new (0x90 + 4*$slot) $sec.Length
    Set-BE32 $new 0xE0 $p.NewEntry
    return ,$new
}
function Get-Gaps($occ, [int64]$limit) {
    $g = @(); $cur = [int64]0
    foreach ($e in ($occ | Sort-Object Start, End)) {
        if ($e.Start -gt $cur) { $g += ,([pscustomobject]@{ Start = (Align $cur 32); End = $e.Start }) }
        if ($e.End -gt $cur) { $cur = $e.End }
    }
    $g += ,([pscustomobject]@{ Start = (Align $cur 32); End = $limit })
    return ,@($g | Where-Object { $_.End -gt $_.Start })
}
function Get-NextOccupied([int64]$x, $occ, [int64]$isoSize) {
    $m = $isoSize
    foreach ($e in $occ) { if ($e.Start -ge $x -and $e.Start -lt $m) { $m = $e.Start } }
    return $m
}
function Ext([int64]$a, [int64]$b) { [pscustomobject]@{ Start = $a; End = $b } }
function Get-Plan($iso, [int64]$newSize) {   # plans P1-P3
    $fixed = New-Object System.Collections.ArrayList
    [void]$fixed.Add((Ext 0 0x2440)); [void]$fixed.Add((Ext 0x2440 $iso.AppEnd))
    foreach ($f in $iso.Files) { [void]$fixed.Add($f) }
    $fstExt = Ext $iso.FstOff ($iso.FstOff + $iso.FstSize)
    $withFst = @($fixed) + @($fstExt)
    if ($iso.DolOff + $newSize -le (Get-NextOccupied $iso.DolOff $withFst $iso.Size)) {
        return [pscustomobject]@{ Plan = 'P1'; Dol = $iso.DolOff; Fst = $iso.FstOff }
    }
    if ($iso.DolOff + $newSize -le (Get-NextOccupied $iso.DolOff @($fixed) $iso.Size)) {
        $occ = @($fixed) + @(Ext $iso.DolOff ($iso.DolOff + $newSize))
        $need = Align $iso.FstSize 32
        $fit = @((Get-Gaps $occ $iso.Size) | Where-Object { ($_.End - $_.Start) -ge $need })
        if ($fit.Count -gt 0) { $fst = $fit[0].Start } else { $fst = Align (($occ | Measure-Object End -Maximum).Maximum) 32 }
        return [pscustomobject]@{ Plan = 'P2'; Dol = $iso.DolOff; Fst = [int64]$fst }
    }
    $fit = @((Get-Gaps $withFst $iso.Size) | Where-Object { ($_.End - $_.Start) -ge $newSize })
    if ($fit.Count -gt 0) { $dol = $fit[0].Start } else { $dol = Align (($withFst | Measure-Object End -Maximum).Maximum) 0x8000 }
    return [pscustomobject]@{ Plan = 'P3'; Dol = [int64]$dol; Fst = $iso.FstOff }
}

# ---- report ------------------------------------------------------------------------------------------
function Show-BootChecklist([string]$profile) {
    Write-Host ''
    Write-Host 'Boot check (Dolphin; MMU on, Fastmem off):'
    Write-Host '  1. VS mode, set a CPU to type 4 (any level): it attacks and wavedashes.'
    Write-Host '  2. Z + D-Up opens the CPU config menu; the D-pad changes the CPU type (toast).'
    if ($profile -eq 'vanilla') { Write-Host '  3. Tournament Mode still starts from the main menu.' }
    Write-Host 'Adding stages or characters: add them BEFORE injecting, keep the un-injected copy, and run'
    Write-Host '  -CheckBuilt <iso> after any later change (BUILD_DETAILS.md 4).'
}

function Find-ReleaseSection($iso, $c) {   # a text slot holding one of this release's sections (by address + size)
    foreach ($s in $iso.Slots) {
        if ($s.Slot -gt 6) { continue }
        foreach ($p in $c.Profiles.Values) {
            if ($s.Va -eq $p.Va -and $s.Size -eq $p.Size) { return [pscustomobject]@{ Slot = $s; Profile = $p } }
        }
    }
    return $null
}

function Show-Report([int]$code) {   # a block the user can copy when reporting an untested ISO
    $r = $script:Report
    $rid = '(unknown)'
    try { $rid = (Sha256-File (Join-Path $Common 'SHA256SUMS')).Substring(0, 12) } catch { }
    $checks = $r.Checks
    if ($r.FailedIds.Count -gt 0) { $checks = 'failed: ' + ($r.FailedIds -join ', ') }
    Write-Host ''
    Write-Host '== REPORT (untested ISO: copy this block when you report how it went)'
    Write-Host ('  release data : ' + $rid)
    Write-Host ('  iso          : {0} ({1} B)' -f $r.Iso, $r.Size)
    Write-Host ('  game code    : SHA-256 {0} (not in known_dols.tsv)' -f $r.DolSha)
    Write-Host ('  profile      : ' + $r.Profile)
    Write-Host ('  checks       : ' + $checks)
    Write-Host ('  plan         : ' + $r.Plan)
    Write-Host ('  exit code    : ' + $code)
    if ($code -eq 0 -and $r.Output -ne '-') {
        Write-Host '  boot test    : <fill in: boots? CPU at type 4 attacks and wavedashes? Z+D-Up menu opens? the mod''s own features still work?>'
    }
    Write-Host '  Please open an issue titled "Tested ISO: mod_name" and paste this block. Thank you!'
    Write-Host '  https://github.com/w3irDv/20XX-Synapse_Construct/issues/new'
}

# ================================================================================================= modes
function Test-GameId($iso, $c, [bool]$built) {
    # G3, second half: a disc whose game ID isn't GALE01 is accepted only for a known_dols.tsv row with that game_id
    # (hybrid.64's vanilla build, GHME01). A source must BE that row's boot DOL; a built ISO needs the release to list the id.
    if ($iso.GameId -eq 'GALE01') { return }
    if ($built) {
        $ok = @($c.Known.Values | Where-Object { $_.GameId -eq $iso.GameId }).Count -gt 0
        $msg = "game ID {0}: this release lists a base with that game ID" -f $iso.GameId
    } else {
        $k = $null; if ($c.Known.ContainsKey($iso.DolSha)) { $k = $c.Known[$iso.DolSha] }
        $ok = ($null -ne $k -and $k.GameId -eq $iso.GameId)
        if ($ok) { $msg = "game ID {0}: boot DOL is the listed '{1}'" -f $iso.GameId, $k.Name }
        else { $msg = "game ID {0}: boot DOL is not a listed ISO" -f $iso.GameId }
    }
    if ($ok) { Pass 'G3' $msg } else { Bad 'G3' $msg 'G3id'; Fail 3 ("game ID {0} is accepted only for a listed ISO" -f $iso.GameId) }
}

function Invoke-CheckBuilt([string]$path, $c) {   # BUILD_DETAILS.md 5: K1-K8, read-only
    Write-Host ("== -CheckBuilt {0}" -f $path)
    $iso = Open-Iso $path 'ISO'
    try {
        Test-GameId $iso $c $true
        Pass 'K1' 'G1-G5 passed'
        $found = $null; $foundSlot = $null
        foreach ($s in $iso.Slots) {
            if ($s.Slot -gt 6) { continue }
            # Profiles can share address and size (vanilla and mex: 0x80484800, same length), so the slot is
            # damaged only when it matches a candidate's address and size but none of their SHA-256s.
            $cand = @($c.Profiles.Values | Where-Object { $s.Va -eq $_.Va -and $s.Size -eq $_.Size })
            if ($cand.Count -eq 0) { continue }
            $sha = Sha256-Bytes $iso.Dol ([int]$s.Off) ([int]$s.Size)
            $hit = @($cand | Where-Object { $sha -eq $_.Sha })
            if ($hit.Count) { $found = $hit[0]; $foundSlot = $s }
            else { Bad 'K2' -key 'K2bad' -msg ("slot {0} at {1} has the size of the {2} section but its SHA-256 differs: the section is damaged" -f $s.Slot, (Hex $s.Va), (($cand | ForEach-Object { $_.Name }) -join ' / ')) }
        }
        $padded = Align $iso.DolSize 32
        $full = $iso.Dol
        if ($iso.DolOff + $padded -le $iso.Size) { $full = Read-Bytes $iso.Fs $iso.DolOff ([int]$padded) }
        $sha = Sha256-Bytes $full
        $asBuilt = $false
        foreach ($k in $c.Known.Values) { if ($k.OutSha -eq $sha) { $asBuilt = $true } }
        if ($null -eq $found) {
            if ($script:Failed -eq 0) { Bad 'K2' -key 'K2none' -msg 'no Synapse AI-only section from this release in the DOL (not built by this release, or a tool rewrote the DOL)' }
            if ($asBuilt) { Info 'K8 DOL as built' } else { Info 'K8 DOL differs from the build (another tool edited it, or not built by this release)' }
            return $null
        }
        Pass 'K2' ("slot {0}: the {1} section ({2} B at {3}), SHA-256 matches" -f $foundSlot.Slot, $found.Name, $found.Size, (Hex $found.Va))
        $entry = BE32 $iso.Dol 0xE0
        [void](Check 'K3' ($entry -eq $found.NewEntry) ("DOL entry {0}, expected {1} (the Synapse stub)" -f (Hex $entry), (Hex $found.NewEntry)))
        $inText = @($iso.Slots | Where-Object { $_.Slot -le 6 -and $_.Va -le $found.ExpEntry -and $found.ExpEntry -lt ($_.Va + $_.Size) })
        [void](Check 'K4' ($inText.Count -gt 0) ("chain target {0} still lies in a loaded text section" -f (Hex $found.ExpEntry)))
        [void](Test-Hooks $iso $c 'K5')
        if ($found.MexCave) {
            $cave = Get-MexCave $iso
            [void](Check 'K6' ($null -ne $cave -and (Test-AllZero $cave)) ("m-ex cave [{0}, {1}) still all zero" -f (Hex $MEX_CAVE_LO), (Hex $MEX_CAVE_HI)))
        }
        if ($found.Placement -eq 'static') {
            if (-not (Test-Ceiling $found $iso 'K7')) {
                Write-Host '       THIS ISO WILL HANG AT BOOT: the FST grew past the static limit after the injection.'
                Write-Host '       Re-inject from the un-injected modded copy (it will be refused too: too much content for'
                Write-Host '       the static layout of this base, BUILD_DETAILS.md 4).'
            }
        }
        if ($asBuilt) { Info 'K8 DOL as built' } else { Info 'K8 DOL differs from the build (another tool edited it; K2-K6 decide whether that matters)' }
        Info ("profile {0}; FST {1} B (max {2} B); content headroom: {3}" -f $found.Name, $iso.FstSize, $iso.FstMax, (Get-Headroom $found $iso))
        return [pscustomobject]@{ Profile = $found.Name; DolSha = $sha; DolSize = $full.Length }
    } finally { $iso.Fs.Dispose() }
}

function Invoke-AddKnownBase([string]$srcPath, [string]$builtPath, $c) {
    # Adds an UNKNOWN but eligible source DOL to known_dols.local.tsv. Refuses unless: the source passes every S3 check
    # (B1-B10, fingerprints included), the built ISO passes -CheckBuilt (K1-K7), the built ISO's DOL is exactly the one
    # this release makes from the source, and the user confirms a boot test of that built ISO.
    Write-Host ("== -AddKnownBase {0}" -f $srcPath)
    $iso = Open-Iso $srcPath 'source ISO'
    try {
        Test-GameId $iso $c $false
        if ($c.Known.ContainsKey($iso.DolSha)) {
            $k = $c.Known[$iso.DolSha]
            Pass 'S2' ("boot DOL SHA-256 {0} is already known: '{1}' (profile {2}{3}); nothing to add" -f $iso.DolSha, $k.Name, $k.Profile, $(if ($k.Local) { ", $LOCAL_KNOWN" } else { '' }))
            return
        }
        $inj = Find-ReleaseSection $iso $c
        if ($null -ne $inj) {
            Bad 'B1' -key 'B1inj' -msg ("this ISO already carries the Synapse {0} section: -AddKnownBase takes the ORIGINAL ISO (without Synapse); the built one goes in -BuiltIso" -f $inj.Profile.Name)
            Fail 3 'the source is an injected ISO'
        }
        if ($Profile -ne 'auto') { $pname = $Profile; Info ("profile forced: {0}" -f $pname) }
        else { $pname = Get-ClassifiedProfile $iso $c }
        if (-not $pname) { Bad 'S2' 'no profile applies to this DOL: ineligible' $script:ClassKey; Fail 3 'ineligible base: not added' 'UNKNOWN-INELIGIBLE' }
        Info ("unknown boot DOL {0} B, SHA-256 {1}: profile {2}" -f $iso.DolSize, $iso.DolSha, $pname)
        $p = $c.Profiles[$pname]
        $sec = Load-Section $c $p
        $slot = Test-Base $iso $c $p $true
        if ($script:Failed -gt 0) { Fail 3 ("the source failed {0} check(s) for profile {1}: not added" -f $script:Failed, $pname) 'UNKNOWN-INELIGIBLE' }
        $new = New-Dol $iso.Dol $iso.DolSize $sec $p $slot
        $newSha = Sha256-Bytes $new
        Info ("this release builds a {0} B DOL with SHA-256 {1} from it" -f $new.Length, $newSha)
    } finally { $iso.Fs.Dispose() }

    Write-Host ''
    $b = Invoke-CheckBuilt $builtPath $c
    if ($script:Failed -gt 0 -or $null -eq $b) { Fail 3 'the built ISO failed -CheckBuilt: not added' }
    $same = ($b.Profile -eq $pname -and $b.DolSha -eq $newSha -and $b.DolSize -eq $new.Length)
    if (-not (Check 'R1' $same ("built ISO DOL ({0} B, SHA-256 {1}, profile {2}) is the one built from the source" -f $b.DolSize, $b.DolSha, $b.Profile))) {
        Fail 3 'the built ISO was not built from this source ISO by this release (or was changed afterwards): not added' }

    if (-not (Test-Interactive)) { Fail 1 '-AddKnownBase asks you to confirm a boot test: run it from a console' 'USAGE' }
    Write-Host ''
    Write-Host ("Boot-test {0} first (Dolphin; MMU on, Fastmem off):" -f (Split-Path -Leaf $builtPath))
    Write-Host '  it boots; a type-4 CPU attacks and wavedashes; Z + D-Up opens the menu; the mod''s own features still work.'
    if (-not (Ask-YesNo 'Did the built ISO pass that boot test?')) { Info 'not confirmed: nothing added'; return }
    $bname = '{0} (added locally {1:yyyy-MM-dd})' -f [IO.Path]::GetFileNameWithoutExtension($srcPath), (Get-Date)
    Add-LocalKnownDol $c.Dir $iso.DolSha $pname $bname $new.Length $newSha
    Pass 'R2' ("added to {0}: '{1}', profile {2}" -f (Join-Path $c.Dir $LOCAL_KNOWN), $bname, $pname)
    Write-Host 'Builds from this ISO are now treated as known, and their new DOL is checked byte for byte.'
    Write-Host 'If you can, please also open an issue titled "Tested ISO: mod_name" with the REPORT block of the build,'
    Write-Host 'so the ISO can be added for everyone in a later release. Thank you!'
    Write-Host '  https://github.com/w3irDv/20XX-Synapse_Construct/issues/new'
}

function Invoke-Build($c) {
    $src = Full $SourceIso
    Write-Host ("== source {0}" -f $src)
    $iso = Open-Iso $src 'source ISO'
    try {
        Test-GameId $iso $c $false
        # ---- S2: profile
        $known = $null
        if ($c.Known.ContainsKey($iso.DolSha)) { $known = $c.Known[$iso.DolSha] }
        $unknown = ($null -eq $known)
        if (-not $unknown) {
            Pass 'S2' ("boot DOL {0} B, SHA-256 {1}: known base '{2}'{3} -> profile {4}" -f $iso.DolSize, $iso.DolSha, $known.Name, `
                $(if ($known.Local) { " (added locally, $LOCAL_KNOWN)" } else { '' }), $known.Profile)
            if ($Profile -ne 'auto' -and $Profile -ne $known.Profile) {
                Fail 1 ("-Profile {0} contradicts the known DOL (profile {1})" -f $Profile, $known.Profile) 'PROFILE' }
            $pname = $known.Profile
        } else {
            $inj = Find-ReleaseSection $iso $c
            if ($null -ne $inj) {
                Bad 'B1' -key 'B1inj' -msg ("DOL entry {0}: this ISO already carries the Synapse {1} section (slot {2}); start from the original, un-injected ISO" -f `
                    (Hex (BE32 $iso.Dol 0xE0)), $inj.Profile.Name, $inj.Slot.Slot)
                Fail 3 'already injected'
            }
            Info ("boot DOL {0} B, SHA-256 {1}: UNKNOWN (not in known_dols.tsv)" -f $iso.DolSize, $iso.DolSha)
            $script:Report = [pscustomobject]@{ Iso = (Split-Path -Leaf $src); Size = $iso.Size; DolSha = $iso.DolSha
                Profile = '(none)'; Checks = 'failed'; FailedIds = @(); Plan = '-'; Output = '-' }
            if ($Profile -ne 'auto') { $pname = $Profile; Info ("profile forced: {0}" -f $pname) }
            else { $pname = Get-ClassifiedProfile $iso $c; if ($pname) { Info ("classified as profile {0} (BUILD_DETAILS.md 2)" -f $pname) } }
            if (-not $pname) {
                Bad 'S2' 'no profile applies to this DOL: ineligible' $script:ClassKey
                if ($AllowUnknownBase) { Fail 3 'ineligible base' 'UNKNOWN-INELIGIBLE' } else { Fail 4 'unknown DOL, and ineligible' 'UNKNOWN-INELIGIBLE' }
            }
        }
        $p = $c.Profiles[$pname]
        if ($unknown) { $script:Report.Profile = $pname }
        $sec = Load-Section $c $p
        # ---- S3
        $slot = Test-Base $iso $c $p $unknown
        if ($unknown -and -not $AllowUnknownBase) {
            if ($script:Failed -gt 0) { Fail 4 ("unknown DOL, and ineligible: it failed {0} check(s) for profile {1}" -f $script:Failed, $pname) 'UNKNOWN-INELIGIBLE' }
            Info 'eligible, but unproven: building it needs your confirmation (or -AllowUnknownBase), then a boot test (BUILD_DETAILS.md 3)'
            $script:Report.Checks = 'all passed'
            # Only an ELIGIBLE unknown DOL reaches this prompt. Building never registers it: that is -AddKnownBase, after a boot test.
            $go = $false; $asked = $false
            if (-not $CheckOnly -and (Test-Interactive)) {
                $asked = $true
                Write-Host ''
                Write-Host 'This ISO is not in the list of tested ISOs, but it passed every compatibility check.'
                Write-Host 'The checks prove the AI can be installed safely, not that it works with this mod: boot-test the result.'
                if ($script:ClassLow) { Write-Host ('The guess ({0}) is uncertain: the marks above disagree. Answer n unless you know it is {0}.' -f $pname) }
                $go = Ask-YesNo ("Build it anyway, as profile {0}?" -f $pname)
            }
            if ($asked -and -not $go) {   # the user's choice, not a failure: no ERROR line, no REPORT block
                Info 'not built: you answered n (nothing was written)'
                $script:Report = $null
                $e = New-Object System.Exception 'declined'; $e.Data['code'] = 4; $e.Data['quiet'] = $true
                Explain 'DECLINED'; throw $e
            }
            if (-not $go) { Fail 4 'unknown DOL: re-run with -AllowUnknownBase to build it' 'UNKNOWN-ELIGIBLE' }
            Info 'building the unknown DOL (confirmed at the prompt)'
        }
        if ($script:Failed -gt 0) {
            if ($unknown) { Explain 'UNKNOWN-INELIGIBLE' }
            Fail 3 ("the base failed {0} check(s): not eligible for profile {1}" -f $script:Failed, $pname)
        }
        if ($unknown) { $script:Report.Checks = 'all passed' }
        # ---- S4 / S5
        $new = New-Dol $iso.Dol $iso.DolSize $sec $p $slot
        $newSha = Sha256-Bytes $new
        if (-not $unknown) {
            if (-not (Check 'S5' ($newSha -eq $known.OutSha -and $new.Length -eq $known.OutSize) ("new DOL {0} B, SHA-256 {1} = known_dols.tsv" -f $new.Length, $newSha))) {
                Fail 6 'the new DOL differs from the expected one' 'WRITE' }
        } else {
            $ns = Get-Slots $new; $secOff = Align $iso.DolSize 32
            $ok = ((BE32 $new 0xE0) -eq $p.NewEntry) -and ((BE32 $new (4*$slot)) -eq $secOff) -and ((BE32 $new (0x48 + 4*$slot)) -eq $p.Va) -and `
                  ((BE32 $new (0x90 + 4*$slot)) -eq $sec.Length) -and ((Sha256-Bytes $new ([int]$secOff) $sec.Length) -eq $p.Sha) -and ($ns.Count -eq $iso.Slots.Count + 1)
            for ($i = 0; $i -lt 18 -and $ok; $i++) {
                if ($i -eq $slot) { continue }
                foreach ($o in @((4*$i), (0x48 + 4*$i), (0x90 + 4*$i))) { if ((BE32 $new $o) -ne (BE32 $iso.Dol $o)) { $ok = $false } }
            }
            if (-not (Check 'S5' $ok ("new DOL {0} B re-parses: slot {1} = section at {2}, entry {3}, other slots unchanged" -f $new.Length, $slot, (Hex $p.Va), (Hex $p.NewEntry)))) {
                Fail 6 'the new DOL does not re-parse as written' 'WRITE' }
        }
        # ---- S6
        $plan = Get-Plan $iso $new.Length
        $outSize = $iso.Size
        if ($plan.Dol + $new.Length -gt $outSize) { $outSize = $plan.Dol + $new.Length }
        if ($plan.Fst -ne $iso.FstOff -and $plan.Fst + (Align $iso.FstSize 32) -gt $outSize) { $outSize = $plan.Fst + (Align $iso.FstSize 32) }
        Pass 'S6' ("plan {0}: DOL at {1} ({2} B), FST at {3}; output {4} B" -f $plan.Plan, (Hex $plan.Dol), $new.Length, (Hex $plan.Fst), $outSize)
        $headroom = Get-Headroom $p $iso
        if ($unknown) { $script:Report.Plan = $plan.Plan }
        if ($CheckOnly) {
            if ($unknown) { Explain 'OK-CHECK-UNKNOWN' } else { Explain 'OK-CHECK-KNOWN' }
            Write-Host ''
            Write-Host ("== check only: ELIGIBLE  profile {0} ({1} DOL), plan {2}, content headroom {3}" -f $pname, $(if ($unknown) { 'unknown' } else { 'known' }), $plan.Plan, $headroom)
            Write-Host 'nothing written.'
            return
        }
        # ---- G6
        if ($OutputIso) { $out = Full $OutputIso } else {
            $dir = Split-Path -Parent $src; $base = [IO.Path]::GetFileNameWithoutExtension($src)
            $out = Join-Path $dir ($base + '.aionly.iso')
        }
        if ($out -eq $src) { Fail 1 'the output path is the source path' 'USAGE' }
        if ((Test-Path -LiteralPath $out) -and -not $Force) { Fail 1 ("output exists: {0} (use -Force)" -f $out) 'EXISTS' }
        $outDir = Split-Path -Parent $out
        if (-not (Test-Path -LiteralPath $outDir -PathType Container)) { Fail 1 ("output folder does not exist: {0}" -f $outDir) 'OUTDIR' }
        $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($out))
        $needBytes = $outSize + 64MB
        if (-not (Check 'G6' ($drive.AvailableFreeSpace -ge $needBytes) ("output {0}; free space {1:N0} MB, need {2:N0} MB" -f $out, ($drive.AvailableFreeSpace / 1MB), ($needBytes / 1MB)))) {
            Fail 5 'not enough disk space' 'SPACE' }
        # ---- S7 (the FST bytes are already in memory: $iso.Fst)
        $part = $out + '.part'
        $script:PartFile = $part
        if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }
        Write-Host ("copying the source ISO ({0:N0} MB)..." -f ($iso.Size / 1MB))
        Copy-Item -LiteralPath $src -Destination $part
        $ws = $null
        for ($try = 1; $null -eq $ws; $try++) {
            try { $ws = [IO.File]::Open($part, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
            catch { if ($try -ge 10) { Fail 6 ("cannot open {0} for writing: {1}" -f $part, $_.Exception.Message) 'WRITE' }; Start-Sleep -Milliseconds 500 }
        }
        try {
            [void]$ws.Seek($plan.Dol, [IO.SeekOrigin]::Begin); $ws.Write($new, 0, $new.Length)
            if ($plan.Fst -ne $iso.FstOff) {
                $fp = New-Object byte[] (Align $iso.FstSize 32)
                [Array]::Copy($iso.Fst, 0, $fp, 0, $iso.FstSize)
                [void]$ws.Seek($plan.Fst, [IO.SeekOrigin]::Begin); $ws.Write($fp, 0, $fp.Length)
            }
            $hw = New-Object byte[] 8
            Set-BE32 $hw 0 $plan.Dol; Set-BE32 $hw 4 $plan.Fst
            [void]$ws.Seek(0x420, [IO.SeekOrigin]::Begin); $ws.Write($hw, 0, 8)
            $ws.Flush($true)
        } finally { $ws.Dispose() }
        Pass 'S7' ("wrote the DOL at {0}{1}, header [0x420]={2} [0x424]={3}" -f (Hex $plan.Dol), `
            $(if ($plan.Fst -ne $iso.FstOff) { ", the FST at $(Hex $plan.Fst)" } else { '' }), (Hex $plan.Dol), (Hex $plan.Fst))
        # ---- S8
        $vs = [IO.File]::Open($part, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $vh = Read-Bytes $vs 0 0x440
            $v1 = $true
            foreach ($o in @(0, 1, 2, 3, 4, 5, 6, 7)) { if ($vh[$o] -ne $iso.Head[$o]) { $v1 = $false } }
            foreach ($o in @(0x1C, 0x428, 0x42C)) { if ((BE32 $vh $o) -ne (BE32 $iso.Head $o)) { $v1 = $false } }
            [void](Check 'V1' $v1 'disc ID, magic, FST size and FST max size unchanged')
            $vd = Read-Bytes $vs (BE32 $vh 0x420) $new.Length
            [void](Check 'V2' ((Sha256-Bytes $vd) -eq $newSha -and (Get-DolSize $vd) + 32 -gt $new.Length) ("DOL at {0} reads back with SHA-256 {1}" -f (Hex (BE32 $vh 0x420)), $newSha))
            $vf = Read-Bytes $vs (BE32 $vh 0x424) ([int]$iso.FstSize)
            [void](Check 'V3' ((Sha256-Bytes $vf) -eq (Sha256-Bytes $iso.Fst)) ("FST at {0} reads back unchanged" -f (Hex (BE32 $vh 0x424))))
            $sorted = @($iso.Files | Sort-Object Start)
            $v4 = $true
            foreach ($f in @($sorted[0], $sorted[-1])) {
                $n = [int][math]::Min($f.End - $f.Start, 1MB)
                if ((Sha256-Bytes (Read-Bytes $vs $f.Start $n)) -ne (Sha256-Bytes (Read-Bytes $iso.Fs $f.Start $n))) { $v4 = $false }
            }
            [void](Check 'V4' $v4 ("first and last file ({0}, {1}) read back identical" -f (Hex $sorted[0].Start), (Hex $sorted[-1].Start)))
            [void](Check 'V5' ($vs.Length -eq $outSize) ("output size {0} B = planned {1} B" -f $vs.Length, $outSize))
        } finally { $vs.Dispose() }
        if ($script:Failed -gt 0) { Fail 6 'read-back verification failed' 'WRITE' }
        Move-Item -LiteralPath $part -Destination $out -Force
        $script:PartFile = $null
        # ---- S9
        Write-Host ''
        Write-Host '== DONE'
        Write-Host ("  output    : {0} ({1:N0} B)" -f $out, $outSize)
        Write-Host ("  profile   : {0} ({1} DOL{2})" -f $pname, $(if ($unknown) { 'unknown' } else { 'known' }), $(if ($unknown) { ' - boot-test it before relying on it' } else { '' }))
        Write-Host ("  plan      : {0}  DOL at {1}, FST at {2}" -f $plan.Plan, (Hex $plan.Dol), (Hex $plan.Fst))
        Write-Host ("  headroom  : {0}" -f $headroom)
        Show-BootChecklist $pname
        if ($unknown) {
            Write-Host 'Once it passes the boot check, you can add this ISO to the tested list on this machine:'
            Write-Host ('  "{0}" -AddKnownBase "{1}" -BuiltIso "{2}"' -f (Join-Path $PSScriptRoot 'Build-SynapseIso.cmd'), $src, $out)
        }
        if ($unknown) { $script:Report.Output = $out; Explain 'OK-BUILT-UNKNOWN' } else { Explain 'OK-BUILT-KNOWN' }
    } finally { $iso.Fs.Dispose() }
}

# ================================================================================================= main
$code = 0
try {
    if (-not $Common) { $Common = Join-Path $PSScriptRoot '..\common' }
    $Common = Full $Common
    if ($CheckBuilt) {
        if ($SourceIso -or $OutputIso -or $Profile -ne 'auto' -or $AllowUnknownBase -or $CheckOnly -or $Force -or $AddKnownBase -or $BuiltIso) {
            Fail 1 '-CheckBuilt can only be combined with -Common' 'USAGE' }
    } elseif ($AddKnownBase) {
        if (-not $BuiltIso) { Fail 1 '-AddKnownBase <original iso> needs -BuiltIso <the iso built from it and boot-tested>' 'USAGE' }
        if ($SourceIso -or $OutputIso -or $AllowUnknownBase -or $CheckOnly -or $Force) {
            Fail 1 '-AddKnownBase can only be combined with -BuiltIso, -Profile and -Common' 'USAGE' }
        if (@('auto', 'vanilla', 'hybrid64', 'mex') -notcontains $Profile) { Fail 1 ("bad -Profile '{0}' (auto|vanilla|hybrid64|mex)" -f $Profile) 'USAGE' }
    } else {
        if ($BuiltIso) { Fail 1 '-BuiltIso goes with -AddKnownBase' 'USAGE' }
        if (-not $SourceIso) { Fail 1 'usage: Build-SynapseIso.ps1 -SourceIso <iso> [-OutputIso <iso>] [-Profile auto|vanilla|hybrid64|mex] [-AllowUnknownBase] [-CheckOnly] [-Force] [-Common <dir>]  |  -CheckBuilt <iso>  |  -AddKnownBase <original iso> -BuiltIso <built iso>' 'USAGE' }
        if (@('auto', 'vanilla', 'hybrid64', 'mex') -notcontains $Profile) { Fail 1 ("bad -Profile '{0}' (auto|vanilla|hybrid64|mex)" -f $Profile) 'USAGE' }
        if ($CheckOnly -and ($OutputIso -or $Force)) { Fail 1 '-CheckOnly writes nothing: drop -OutputIso / -Force' 'USAGE' }
    }
    $c = Load-Common $Common
    if ($CheckBuilt) {
        $null = Invoke-CheckBuilt (Full $CheckBuilt) $c
        if ($script:Failed -gt 0) { Fail 3 ("{0} check(s) failed" -f $script:Failed) }
        Write-Host '== -CheckBuilt: OK (still bootable as built)'
        Explain 'OK-CHECKBUILT'
    } elseif ($AddKnownBase) {
        Invoke-AddKnownBase (Full $AddKnownBase) (Full $BuiltIso) $c
    } else {
        Invoke-Build $c
    }
} catch {
    $code = 2
    if ($_.Exception.Data.Contains('code')) { $code = [int]$_.Exception.Data['code'] }
    elseif ($null -ne $script:PartFile) { $code = 6 }
    if (-not $_.Exception.Data.Contains('quiet')) { Write-Host ("ERROR: {0}" -f $_.Exception.Message) }
    if (-not $_.Exception.Data.Contains('code')) { Write-Host ("  at {0}" -f ($_.InvocationInfo.PositionMessage -replace "`r?`n", ' ')) }
} finally {
    if ($null -ne $script:PartFile -and (Test-Path -LiteralPath $script:PartFile)) {
        Remove-Item -LiteralPath $script:PartFile -Force -ErrorAction SilentlyContinue
        Write-Host ("removed the partial output {0}" -f $script:PartFile)
    }
}
if ($null -ne $script:Report) { Show-Report $code }
if ($script:Plain.Count -gt 0) {
    Write-Host ''
    Write-Host '== Recap'
    foreach ($t in $script:Plain) { Write-Host ('>> ' + $t) }
}
exit $code
