# Sharp CE-150 ROM dump

This contains a dump of the Sharp CE-150 plotter/printer's 8KB system ROM
(&A000-&BFFF), plus the tool used to produce it. Captured directly from a
PC-1500A with a CE-150 and a CE-158X (Jeff Birt's modern CE-158 replacement)
both attached, over the CE-158X's USB serial port (labeled **U1**).

**Despite the repo's name, only the CE-150 ROM is dumped here.** The
PC-1500/PC-1500A's own system ROM and the CE-158's ROM already have public
sources and don't need a fresh dump:
[Jeff-Birt/Sharp_PC-1500_ROM_Disassembly](https://github.com/Jeff-Birt/Sharp_PC-1500_ROM_Disassembly)
(`Original_ROMs/`, PC-1500 system ROM revisions A01/A03/A04) and
[Jeff-Birt/Sharp_CE-158](https://github.com/Jeff-Birt/Sharp_CE-158)
(`CE-158_ROM_ORIG.bin`). The CE-150 ROM was the one genuine gap -- Jeff-Birt's
repo only has a symbol table (`lib/CE-150.lib`) for it, not the binary.

## Contents

| File | What it is |
|---|---|
| `dumper/ce150-capture.asm` | LH5801 assembly source for the capture routine (sdas dialect) |
| `dumper/ce150-capture.bin` | Assembled machine-language binary, ready to load at `&112` |
| `dumper/ce150-capture.bas` | On-device BASIC driver: runs the capture, prints the checksum, exports it |
| `dumper/ce150-capture-test.pc1500a` | Calc-U-1600 preset -- capture-logic-only regression test, see below |
| `dumps/CE-150.BIN` | The CE-150 ROM dump, 8192 bytes |

## Verification

```
eb9aa5156c6849890b137799efc50a4b  dumps/CE-150.BIN
```

The check made during capture: the 16-bit additive sum computed on the
PC-1500A itself (`CALL &112, N`, printed by `ce150-capture.bas` before
sending) and the 16-bit sum `SharpDataExchange --raw` reports on receipt
agree -- both `0x9339`.

**This dump is byte-for-byte identical** to the (previously real-hardware-
*unverified*) `CE-150.ROM` bundled with the `Calc-U-1600` emulator project
(same md5) -- confirmed directly, see "Emulator verification" below.

## How the dump was made

### 1. Assemble `dumper/ce150-capture.asm`

Requires `sdaslh5801`/`sdld`/`makebin` from the `sdcc-pc1500` project (see
this project's `pc1500-build` skill for the exact pipeline). If you already
have `dumper/ce150-capture.bin`, this step can be skipped.

```sh
cd dumper
sdaslh5801 -plosgff ce150-capture.asm
printf -- "-muwx\n-i ce150-capture\nce150-capture.rel\n\n-e\n" > ce150-capture.lnk
sdld -nf ce150-capture
makebin -p -o 0x0112 ce150-capture.ihx ce150-capture.bin
```

### 2. Why a 16k memory module, and why `&112`

CE-150's 8KB ROM doesn't fit in the PC-1500A's ~1KB machine-language area
(&7C01-&7FFF), let alone the plain PC-1500's -- so this requires **a
PC-1500 or PC-1500A with a 16k memory module at &0000** (e.g. CE-1638/
CE-163F/CE-163X). `.org 0x112` is the code's load address; it already
accounts for the 197-byte BASIC reserve plus that module's own firmware
reserve (this exact offset appears as a worked example in
`SharpPC1500Reference/Assembly-Programming/LH5801_Guide.md`: `NEW &112 ;
protect first 112 bytes from BASIC` -- confirmed against a real CE-163F: its
own bootstrap firmware patches `BASPRG_ST`/`BASPRG_END`/`BASPRG_EDT` to
`&0112` once at boot, i.e. it performs the equivalent of `NEW &112` in
software). Layout, from the assembled `.sym`:

| Symbol | Address | Meaning |
|---|---|---|
| `CAPTURE` | `&112` | Entry point -- `CALL &112, N` |
| `BUFFER` | `&166` | 8192-byte captured ROM image (`&166`-`&2165`) |
| end of block | `&2166` | First byte free for BASIC -- `NEW &2166` |

### 3. CE-150 and CE-158X are both attached the whole time

Both place their own system ROM in the same &8000-&BFFF window
(`SharpPC1500Reference/Peripherals/CE-150-Hardware.md`,
`Memory-Architecture/PU-PV-Signals.md`), but real PC-1500 peripherals
daisy-chain through a pass-through connector, and CE-150/CE-158X were
attached simultaneously for this dump -- **no module swap between capture
and export.** `PU-PV-Signals.md` §5: "PV selects which is visible when both
are connected." `CAPTURE` forces PV=0 to read CE-150's ROM (see next
point); BASIC's own PV-banking (the system ROM's &E234 routine, called
automatically around every access to a peripheral's BASIC-extension token
table) switches PV back to CE-158's side when `SETDEV`/`CSAVE M` dispatch
to it -- `CAPTURE`'s own PV save/restore is careful not to fight with that.

`CAPTURE` saves the system ROM's own PV-byte (&79D0), forces PV=0 for the
ROM read, and restores it before returning -- the documented safe pattern
(`PU-PV-Signals.md` §7), not a bare `RPV` left in place. PV=0 is required:
confirmed directly against Calc-U-1600's own `Ce150Card`
(`Core/Connector/Ce150Card.hpp`), whose ROM read is gated `!a.pv`.

### 4. Load the program and driver onto the PC-1500A

```
NEW &2166
```
(protects code + buffer). Then, on the device, `SETDEV U1,CI,CO` then
`CLOADM`; on the PC:
```sh
java -jar SharpDataExchange.jar put --start-address 0x112 dumper/ce150-capture.bin
```
Then on the device `CLOAD`; on the PC:
```sh
java -jar SharpDataExchange.jar put dumper/ce150-capture.bas
```

### 5. Run it and capture the ROM

There is no ML-callable CE-158 byte-send routine anywhere in this project's
corpus -- CE-158's RS-232C support is exposed only as BASIC command-table
extensions (`SETCOM`/`SETDEV`/`CSAVE`/`CSAVE M`/`PRINT#`), auto-selected via
PV when the interpreter dispatches those tokens. `ce150-capture.bas` uses
`CSAVE M address1,address2` (`SharpBasicReference/CE-150-Reference.md`),
which with `SETDEV CO` declared is redirected over RS-232C instead of
cassette -- independently confirmed working end to end in
`SharpDataExchange/MANUAL.md`'s own PC-1500 section.

On the PC, start the receiver **before** running the BASIC program (the
PC-1500 doesn't buffer -- `ce150-capture.bas`'s own `INPUT A$` pause right
before `CSAVE M` gives time to do this):

```sh
java -jar SharpDataExchange.jar get --device pc1500 --raw dumps/CE-150.BIN
```

`--raw` detects the CE-158 serial header, strips it, and prints the 16-bit
checksum of the stripped 8192-byte payload directly:

```
Detected PC1500 header — stripped from raw dump
Saved 8192 bytes to CE-150.BIN
Checksum (16-bit sum): 0x9339
```

On the device, `RUN` `ce150-capture.bas`: it captures, prints the checksum
(compare against the value `SharpDataExchange` prints -- they should match,
confirmed above), then waits for Enter before sending.

## Emulator verification (capture logic only)

`pc1500emu` is retired for this project -- all emulator verification here
uses **Calc-U-1600** (`headless/pc1500_cli`), not `pc1500preset`/`pc1500emu`.

`dumper/ce150-capture-test.pc1500a` runs the capture against Calc-U-1600's
own bundled `roms/CE-150.ROM` (a `plotter: ce150` attachment maps real ROM
bytes into &A000-&BFFF for PV=0 reads -- `Core/Connector/Ce150Card.hpp`).
That file was, until this dump, an **unverified community dump**
(`Calc-U-1600/roms/README.md`) -- it's now confirmed byte-for-byte
identical to `dumps/CE-150.BIN` above (same md5).

Run from the `Calc-U-1600` checkout (so its bundled `roms/` and the
software-defined-card catalog resolve):

```sh
./headless/pc1500_cli --preset ../PC-1500-ROM/dumper/ce150-capture-test.pc1500a \
    --modules-dir build/Debug/Calc-U-1600.app/Contents/Resources --dump-basic 2000000
```

The test script POKEs the checksum's two bytes (read back from `CAPTURE`'s
own `CHK_H`/`CHK_L` scratch bytes via `PEEK`) into the start of the BASIC
program area, since the CLI has no generic memory-peek flag but `--dump-basic`
already prints that range. Look for `2166: 93 39 ...` in the "program area"
dump -- confirmed matching with both `modulespec: CE-1638` and
`modulespec: CE-163F`.
