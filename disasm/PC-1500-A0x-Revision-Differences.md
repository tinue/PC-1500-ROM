# PC-1500 system ROM — what changed from A01 to A03 to A04

Sources: the dumps `PC-1500-A0x.BIN` (PC-1500-ROM, `dumps/a0x/`), byte-compared, and the
annotated sources `PC-1500-A0x.asm` for every changed region. All three
revisions are 16 KB at C000–FFFF. None of them adds or removes a routine, moves a vector or
changes a table: each fix is patched in place, and the bytes it needs come from
shortening nearby code (see *How the patches were made room for*).

| | Changed bytes | Changed regions (bytes within 4 of each other merged) |
|---|---|---|
| A01 → A03 | 163 | 30 |
| A03 → A04 | 151 | 8 |

Many changed bytes are only branch offsets that moved because code next to them moved.

**Evidence column:** *emulator* = reproduced with the same BASIC snippet on all three ROMs in
[Calc-U-1600](https://github.com/tinue/Calc-U-1600) (`headless/pc1500_cli --preset`, `model: PC-1500:A0x`); the snippets are under
*Reproduction*. *code* = read from the disassembly only, not reproduced.

## A01 → A03

### BASIC behaviour

| Where | What was wrong in A01 | What A03 does | Evidence |
|---|---|---|---|
| D133 COMPARE_STR | String `<=` and `>=`: at the first differing character the routine shifted the operator bits once more and, if the "equal" bit was still set, **jumped back into the compare loop** instead of deciding. So `"AZ"<="BA"` and `"BA">="AZ"` were decided by the *later* characters, and came out false. `<`, `>`, `=`, `<>` were not affected. | The extra `SHR / BZR` is replaced by three NOPs, so the result is decided at the first differing character. | emulator: 8 comparisons give 83 (01010011) on A01, 243 (11110011, correct) on A03/A04 |
| F997 TOK_INBUF_5 | Converting typed input into a value (INPUT, DEF key): if something follows the value (`5)`, `5,6` to `INPUT A`), the routine returned an error with whatever was left in UH, so the machine showed **`ERROR 0`**. | On that path it now sets UH = 01 first, so you get **ERROR 1**. An error from the expression evaluator itself still passes through with its own code. The success path returns without `LDI A,55H` (the byte is reused for this fix). | emulator: `ERROR 0` (A01) vs `ERROR 1` (A03) |
| C57D–C59D DEFKEY_EVAL | DEF + key, when no label matches: the not-found path stepped Y by one byte (`INC Y`) and then took the error code from whatever UH held. | Steps Y with `VEJ (C0)`, which skips a 1-byte character or a 2-byte token, then sets UH = 0B (ERROR 11) explicitly. | code. A01 and A03 both show ERROR 11 for a plain missing label in the emulator, so the A01 symptom needs a token after the key text |
| CCDE INIT_IBUF_R | The routine that puts CR at the right end of the input buffer (7BFE/7BFF) worked through **Y**. Its header (Schlieker, A04) says it returns **X** = 7BFF. Both callers (ENTER at CCEC, DEF key at C538) hold the program pointer in Y, so A01 overwrote it. | Uses X, as documented. | code |
| CD1E (ENTER, non-program line) | The "nothing to execute" test compared A (leftover) with XL. | `CPI XL,B0`: tokenized line still empty (X at 7BB0) → warm start. Makes room for this by testing the PRO bit through V after `ROL` (`BVR`) instead of another `ROL / BCR`. | code |
| D33B LINE_SEARCH_11 | Forward search for a GOTO/GOSUB target (target ≥ current line): looked for the CR that ends the current line starting **at** Y. If Y already pointed at the next line, that line was skipped (or a 0DH line-number or length byte was taken for the line end). | `DEC Y` before the scan (VMJ (20)), so the scan sees the CR even when Y is one past it. | code. Ordinary GOTO/GOSUB/ON/IF THEN forms give the same results on A01 and A03 in the emulator, so the bad case needs Y one past the CR |
| D39D RES_VAR_SPACE | Out-of-memory check when creating a variable: accepted a new variable whose bottom byte touched the program-end byte. | Checks with X−1, so one free byte always separates the variables from the program. (The two bytes for this come from loading CURVARADD with `VEJ (F4)` instead of two `LDA`s.) | code |
| CF13 TXFR_RSV_TXT | Copying a RESERVE-key text: a text of exactly 26 characters (the maximum) was copied and **then got a 00 written after it**, one byte past the 26-byte limit. Longer texts were cut to 26 without a 00. | Length ≥ 26 → copy 26, no 00; length < 26 → copy and terminate. | code |
| D2A0 LAST_LINE_2_INBUF | Copying a program line into the 80-byte input buffer (LIST, ↑/↓, BREAK line) used its length byte − 1 as the count. A length byte of 0 meant 256 bytes copied from 7BB0 on. | Masks the count with 7FH (at most 128 bytes). The error exit for a list-protected line in a ROM module (module header +07 bit 7, UH = 1F) now also leaves through the common tail that pops A and restores Y. | code |
| C443 BASIC_INT_8 | After the line-end trace call (VMJ (3E), which can enter a peripheral ROM's TRACE vector at module header +1D), the interpreter went straight to "next statement" (C40C). | Resumes three bytes earlier at C409, VMJ (04): it first checks that the statement really ended (ERROR 1 otherwise). | code |
| CA1D (power-on with ARUN) | When a program starts itself with ARUN at power-on, A01 set the BUSY annunciator with `ORI (784E),01`. That address is in the CPU stack area, not the LCD: **BUSY did not light**, and a stale stack byte got bit 0 set. | `ORI (764E),01`, the annunciator byte, as at the three other places that set BUSY (C8D5, CACF, CCC3). | code (the wrong address is unambiguous) |

### Editor and display

| Where | A01 | A03 | Evidence |
|---|---|---|---|
| CA64 CL key | — | New entry `BCR +1 / VEJ (F2)`: entered with C = 0, CL clears the LCD first. The unused `LDA (INBUFPTR_L)` is dropped. | code |
| CC28 cursor ← (entry from → at CBEC) | — | That entry now clears the LCD (VEJ (F2)) before the edit position is moved. `DEC A / CPA (INBUFPTR_L)` moved to a new 3-byte subroutine at DCAE (CMP_A_IBUF_PTR). In A01 those bytes were dead. | code |
| DC7E ↑/↓ in RUN mode (show a program line while the key is held) | On release: DISPARAM was restored **before** the saved display, and the "back to editor" test read DISPARAM bit 6. | Restores the display first, then DISPARAM with bit 5 cleared; tests bits 6–7 of the saved value. | code |

### Power-on, auto power off and the keyboard wait

| Where | A01 | A03 | Evidence |
|---|---|---|---|
| E08D–E0CF RESET (RAM/module scan) | The power-on scan of pages 0000–6FFF (write 5A/A5 to test for RAM, look for 55H module headers) kept its 5-byte result table in **7A30–7A34 (AR-S)**. | Table moved to **7A10–7A14 (AR-Y)**. That area holds only the auto-off signature A0…AF, which RESET has already checked at E034. AR-S also holds the stack pointer that AUTO_OFF saves (7A30/7A31, read back at E147). The scan logic itself is unchanged. | code |
| E2B7 WAIT_4_KB keyboard hook | If 79D4 = 55H, key input is handed to an external routine, with bit 0 of the address selecting the PV bank. A01 fetched the address with `VEJ (F4)` from 79D5, which loads **U**, then jumped with `STX P` to **X**. The jump went to whatever X held. | `VEJ (CC) 5B`: loads **X** from 785B/785C, then jumps. The vector moved from 79D5/79D6 to 785B/785C. No system, CE-150 or CE-158 ROM writes either location: this is a hook for external software. BASWORD uses it and tests for it with `PEEK &E2B9` = 56 (see below). | code |
| E2F4, E33D WAIT_4_KB exits | The "no key" exit (WAITNOKEYS) and the BREAK exit jumped into the tail of the key decoder (`ANI (U),7D / RTN`). That tail is meant for U = 764E, to clear the SHIFT and DEF annunciators. On these two paths U = F8xx–FFxx (key-repeat counter), so it ANDed a byte in ROM (no effect) and returned a **random Z flag**. | Both exits end in their own `REC/SEC / RTN`. | code |
| D037 INBUF_CLR_3 | Clear input buffer: fill count 4FH → 80 bytes, 7BB0–7BFF. | Fill count 50H → **81 bytes, 7BB0–7C00**. Every clear (CL, ENTER, …) also writes CR at 7C00, one past the buffer. See *Hardware* below. | code. The Ref corpus confirms the CR at 7C00 on real machines (PEEK &7C00 = 13 after CL) |

## A03 → A04

All A04 changes are in the BASIC interpreter. Five of the eight were reproduced in the emulator.

| Where | What was wrong in A03 (and A01) | What A04 does | Evidence |
|---|---|---|---|
| C5BD–C5CA IF | IF tested the **sign** of the condition: a negative value counted as **false** (BCD: sign bit of 7A01; integer: bit 15). So `IF -1`, `IF NOT A` (= −1), `IF B` with B = −5 and `IF -1 AND -1` all skipped the THEN part. Only positive non-zero values were true. | Checks only for zero: any non-zero value is true. | emulator: 7 conditions give 4 (only `IF 5` true) on A01/A03, 126 (correct) on A04 |
| C6C9–C6FD NEXT | NEXT tested **before** adding the step: compare variable with limit, then add, then loop. The body therefore ran once more with the variable already past the limit when the step doesn't land on it exactly, and the variable ended at the limit instead of limit + step. `FOR J=0 TO 10 STEP 3` ran 5 times (J = 0, 3, 6, 9, **12**). | Adds the step first, then compares (equal → loop again, past the limit in the step's direction → exit). The same loop runs 4 times; after `FOR I=1 TO 3` I is 4, after `FOR H=5 TO 1 STEP -2` H is −1. | emulator: `3 3 5 12 12 3 1` (A01/A03) vs `3 4 4 12 9 3-1` (A04) |
| D61C ARX_2_INT, VEJ (D0) range code 04 | If AR-X already held an **integer with bit 15 set** (a negative result of NOT/AND/OR), range check 04 returned with `VZS (4E)` **without loading the value into U**. The caller then used garbage. Code 04 is used by NOT, AND/OR (D973, D97A), FOR's TO and STEP, and CALL. | Loads U from the integer and converts AR-X, as on the normal path. | emulator: `NOT NOT 0` = −31233 and `NOT (5 OR -8)` = −31233 on A01/A03; 0 and 2 on A04 |
| DAC0 EVAL_USING | `USING <expr>` where the expression is not a plain "no string" case (e.g. an undimensioned `Q$(3)`): the error exit RTN_2_DA (VMJ (4A)) pops Y from the stack, but this path had not pushed it yet. The program pointer was garbage and the error was wrong. | Pushes X (the saved program pointer) before the test, so the exit pops the right value. | emulator: `PRINT USING Q$(3);5` gives ERROR 1 with Y = 0100 on A03, ERROR 6 (correct) on A04 |
| C941–C94C INPUT | INPUT set the "waiting for input" bits (BREAKPARAM \|= 50H) **before** opening the LCD for the prompt. If that failed (**ERROR 32**, graphic cursor at columns 152–155), the error was raised with the machine still marked as waiting for INPUT. | Opens the LCD first (error raised before any state changes), then sets the bits. | code |
| D5BD–D5D5 DEFAULT_VAR | Auto-creating an element of the extended default array A(n) (only when 7879 bit 7 allows it, otherwise ERROR 21): after RES_VAR_SPACE, only the low byte of the new variable's pointer was loaded into U, and X was backed up 3 bytes. | Loads the whole pointer (`VEJ (F4)` 7883) and backs X up 5 bytes, to the new entry's start. The 7879 test is shortened (`VEJ (CC) / SHL`) to make room. | code. Normal BASIC raises ERROR 6 for undimensioned A(28) on all three, so this path is not reachable from plain BASIC |
| F3AE–F3CC SIN/COS/TAN | The sign of the angle was taken off **after** the DEG/GRAD → radian conversion and rounding. | Takes the sign off first (VMJ (6C) + PSH A), converts the magnitude, normalizes with `VEJ (E8)` (absolute value). Error exits are adjusted to pop the sign. | code. About 25 test angles (negative, large, tiny, multiples of 90°/100g, DEG/RAD/GRAD) give identical results on A03 and A04 |
| EF8E | — | Only the jump into BCMD_SIN_3 follows the 4-byte move above. | — |

## Hardware: does any fix depend on, or work around, the hardware?

**No change works around a hardware fault.** None of the three revisions touches the I/O
initialisation table (E168), the LH5810 or CE-150 port setup, the reset delays (E006–E01C),
the keyboard scan, the beeper, the cassette code, the timer, the OFF sequence or the PV/PU
bank-switching routines. Every fix corrects the ROM's own logic. So the revisions don't
patch around a chip bug or a board revision.

Four changes touch hardware-facing code, and one of them behaves differently depending on the
model:

1. **D037, the CR at 7C00 (A03, kept in A04): the effect depends on the model.** On the plain
   PC-1500 the system RAM at 7800–7FFF only decodes A0–A9 (two TC5514s, no A10), so
   **7C00 is the same cell as 7800**, the deepest byte of the CPU stack area 7800–784F.
   From A03 on, every input-buffer clear writes 0DH into 7800. This is harmless in
   practice: the stack grows down from 784F and reaches 7800 only at full depth.
   On the PC-1500A (a full 2K×8 HM6116 at that position) 7C00 is real, separate RAM. That is
   why its machine-language area starts at **7C01**, not 7C00 (reference corpus
   Sharp1500-1600-Ref, `PC-1500/Memory-Architecture/PC-1500-Address-Decoding.md` §2.3/§4). The fix was not made
   for the PC-1500A: it is already in A03. The PC-1500A, which shipped with A04, simply
   inherits it. Which routine needs the CR sentinel is not pinned down here. The Ref note
   names the tokenizer's unbounded scan, but ENTER already puts a CR at 7BFF (INIT_IBUF_R)
   before tokenizing. The editor's cursor code, which reads (Y) at the cursor and compares
   it with 0DH (e.g. CBD2), is the other candidate when the cursor stands behind character 80.
2. **CA1D, BUSY annunciator (A03):** a wrong-address fix. A01 wrote into stack RAM instead of
   the LCD annunciator byte 764E, so the display just didn't show BUSY during an ARUN start.
3. **E2B7, keyboard hook with PV bank select (A03):** the hook selects the bank of its target
   with the PV flip-flop (`RPV`/`SPV` from bit 0 of the address). A01 jumped through the
   wrong register, so the hook could not work in A01, whatever hardware was attached. A03
   also moved the vector to 785B/785C, so external software written for an A01 hook address
   would not run on A03/A04. No Sharp ROM in this corpus sets it; its known user is BASWORD
   (see *BASWORD needs the A03 keyboard hook*).
4. **E08D–E0CF, power-on memory scan (A03):** this is the code that finds RAM and ROM modules,
   but only its scratch table moved (AR-S → AR-Y). Detection is identical in all three.

None of the A03 → A04 changes involves hardware. A04 is what the PC-1500A shipped with, but
nothing in the A04 delta is specific to the PC-1500A's different RAM decoding or connector
wiring. All eight are BASIC-interpreter fixes.

## BASWORD needs the A03 keyboard hook

BASWORD (Christophe Gottheimer, 1986–2013, GPL v2; <http://www.pc1500.com/basword.html>,
`basword.zip`) is a BASIC keyword manager: a machine-code program loaded into RAM (CE-161/163,
CE-159, CE-155 or CE-151 / PC-1500A) that adds, removes, lists and moves user BASIC
instructions at run time (`BASWORD +"ERN";"5E0680N"`: name, token &F0cc, routine address,
mode). Its README says it "requires a new ROM" and gives the test `PEEK &E2B9` = 56. That
byte is in the E2B7 hook:

| ROM | E2B7–E2B9 | PEEK &E2B9 | BASWORD |
|---|---|---|---|
| A01 | `F4 79 D5` (VEJ (F4) 79D5) | 213 | no |
| A03 | `CC 5B 38` (VEJ (CC) 5B / NOP) | 56 | yes |
| A04 | `CC 5B 38` | 56 | yes |

**Why a RAM keyword table needs the hook, when the CE-150 and CE-158 don't:**

- *Executing and listing* a user token works on every revision. For an &F0xx token,
  TOK_PROCESS (FA89) starts at the table in **OPN_TBL (79D1)** = (PV << 7) | (table high
  byte >> 1). It accepts any 2K boundary with the 55H marker at xx00, RAM included, and steps
  down through the other tables with DEC_OPN (FA58). A token found in no table gives ERROR 27,
  which is what BASWORD documents for a removed keyword. BASWORD's install points 79D1 at its
  own table: `POKE &79D1,&04` for the table at &0800 (image at &00C5). The `OPN` command
  writes the same byte (E49A), so 79D1 is the OPN device's token table, not a device code;
  the source's name `OPN` is now `OPN_TBL`.
- *Turning typed text into tokens* is the problem. The table search used for that
  (TOK_TABL_SRCH, E4A8) only looks for tables at B800, B000, …, 8800 in both PV banks,
  which is where the CE-150 and CE-158 ROMs sit. A table in RAM below 8000 is never found
  there.
- So BASWORD installs a keyboard driver through the hook: `POKE &785B,&05,&88` (driver at
  &0588, even address = PV 0) and `POKE &79D4,&55`. The driver converts BASWORD's own
  keywords on ENTER (`B!` → BASWORD) and adds auto-repeat, a SHIFT-INS insert mode and DEF
  editing keys.
- On A01 the hook loads the vector into U and jumps through X, and it reads 79D5/79D6 rather
  than 785B/785C, so the driver can't be entered. Hence "not compatible" and the author's
  offer of a "special ROM".

That the ROM's ENTER tokenizer can't reach RAM tables by itself is inferred from E4A8's
search range and from BASWORD needing the driver for it. The tokenizer (F9C7) was not
traced step by step.

## How the patches were made room for

Since nothing moves, each fix had to fit into the bytes of the routine it fixes. The bytes
were freed by shorter equivalents:
`LDA (ab)` ×2 → `VEJ (F4) ab` (D3A5, D5CE); `ROL / BCR` → `BVR` (CD29);
`BII (78xx),80 / BZS` → `VEJ (CC) xx / SHL / BCR` (D5BD); `SJP ARX_2_BCD_ABS` → `VEJ (E8) / NOP` (F3C8).
A01's unused bytes at DCAE–DCB5 became CMP_A_IBUF_PTR in A03. Several fixes leave NOPs
behind (C592, D133–D135, D33E, E2B9, E33E, C5CA, F3C9).

## Reproduction

Run with Calc-U-1600: `headless/pc1500_cli --preset X.pc1500 3000000`, the preset being
`model: PC-1500:A01` (or A03/A04), then `key: cl`, `type: NEW0`, the lines below, `key: mode`, `type: RUN`, `wait:`.
The `'` remarks give the expected display; don't type them.

```
10 A$="AZ":B$="BA":C$="AB":D$="AC":R=0          ' string compare -> 243 (A01: 83)
20 IF A$<=B$ LET R=R+1
30 R=R*2:IF A$<B$ LET R=R+1
40 R=R*2:IF B$>=A$ LET R=R+1
50 R=R*2:IF B$>A$ LET R=R+1
60 R=R*2:IF A$>=B$ LET R=R+1
70 R=R*2:IF B$<=A$ LET R=R+1
80 R=R*2:IF C$<>D$ LET R=R+1
90 R=R*2:IF C$=C$ LET R=R+1:PRINT R
```

```
10 INPUT A:PRINT A            ' answer 5)  -> A01: ERROR 0, A03/A04: ERROR 1
```

```
5 R=0:A=0:B=-5                ' IF with negative values -> 126 (A01/A03: 4)
10 IF -1 LET R=R+1
20 R=R*2:IF B LET R=R+1
30 R=R*2:IF NOT A LET R=R+1
40 R=R*2:IF -1 AND -1 LET R=R+1
50 R=R*2:IF 5 LET R=R+1
60 R=R*2:IF -0.5 LET R=R+1
70 R=R*2:IF A LET R=R+1:PRINT R
```

```
10 N=0:FOR I=1 TO 3:N=N+1:NEXT I                  ' A04: 3 4 4 12 9 3-1
20 M=0:FOR J=0 TO 10 STEP 3:M=M+1:L=J:NEXT J      ' A01/A03: 3 3 5 12 12 3 1
30 K=0:FOR H=5 TO 1 STEP -2:K=K+1:NEXT H
90 PRINT N;I;M;J;L;K;H
```

```
10 A=NOT NOT 0:B=NOT (5 OR -8):PRINT A;B          ' A04: 0 2, A01/A03: -31233 -31233
```

```
10 PRINT USING Q$(3);5        ' A04: ERROR 6, A03: ERROR 1
```

(FOR loops on the PC-1500 take integers only: a fractional STEP gives ERROR 19.)
