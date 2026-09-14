; ============================================================================
; CE-150 ROM Capture -- Sharp PC-1500 / PC-1500A
;
; Copies the CE-150 plotter/printer's 8KB system ROM (&A000-&BFFF) into a RAM
; buffer and computes a 16-bit additive checksum over it. Single-purpose --
; mirrors only the "capture" half of PC-1600-ROM/dumper/pc1600-rom-dumper.asm.
; There is no on-PC-1500 equivalent of that program's SEND_PAGE/CSNDA serial
; code: no ML-callable CE-158 byte-send entry point is documented anywhere in
; this project's corpus (CE-158's RS-232C support is exposed only as BASIC
; command-table extensions -- SETCOM/SETDEV/CSAVE M -- auto-selected via the
; PV bank-select signal when the interpreter dispatches those tokens). Export
; therefore happens entirely from BASIC after this routine returns, via
; CE-158's own CSAVE M redirect -- see ce150-capture.bas and README.md.
;
; Requires a 16k memory module at &0000: the 8KB ROM alone doesn't fit in the
; PC-1500A's ~1KB machine-language area (&7C01-&7FFF), let alone the plain
; PC-1500's. CE-150 must be physically attached when this runs. It can be
; swapped for a CE-158/CE-158X afterwards to send the captured buffer -- the
; buffer, once written, survives the swap: it's ordinary RAM at &0000-&3FFF,
; untouched by whatever module is plugged into the separate &8000-&BFFF
; peripheral slot that CE-150/CE-158 both occupy.
;
; Entry:  CALL &112, N   -- N is unused as input; returns the 16-bit additive
;                            checksum of the captured buffer (mod 65536).
;
; PV must be 0 for the CE-150's ROM window to answer at &A000-&BFFF (Memory-
; Architecture/PU-PV-Signals.md; confirmed against Calc-U-1600's own
; Ce150Card, whose ROM read is explicitly gated `!a.pv`). The system ROM
; uses PV constantly for its own BASIC-extension-table banking, so this
; follows the documented save/restore pattern (PU-PV-Signals.md SS7) around
; the read instead of just RPV-and-leave-it.
; ============================================================================

CE150_ROM_START .equ 0xA000
CE150_PAGES     .equ 0x20          ; 32 pages x 256 bytes = 8192 bytes (8KB)
PV_BYTE         .equ 0x79D0        ; system ROM's own PV-state shadow, bit 0

            .area   CODE (ABS)
            .org    0x112          ; accounts for the 197-byte BASIC reserve
                                    ; plus this 16k module's own firmware
                                    ; reserve -- see README.md for the NEW
                                    ; offset that must be used ahead of this
                                    ; (which additionally protects CODE+BUFFER)

; ============================================================================
CAPTURE:
            lda     (PV_BYTE)       ; save the system ROM's own PV-byte...
            sta     (SAVED_PV)
            rpv                     ; ...then force PV=0 for the ROM read

            ldi     xh,>CE150_ROM_START
            ldi     xl,<CE150_ROM_START
            ldi     yh,>BUFFER
            ldi     yl,<BUFFER

            ldi     a,0x00
            sta     (CHK_H)
            sta     (CHK_L)

            ldi     a,CE150_PAGES
            sta     (PAGE_CNT)

; ----------------------------------------------------------------------
; OUTER: one 256-byte page per pass, PAGE_CNT counts pages remaining.
; INNER: LIN/SIN copies one byte (X->Y), then folds it into the running
;        16-bit checksum (REC first -- ADC must not see a stale carry
;        left over from an unrelated earlier branch).
; ----------------------------------------------------------------------
OUTER:
            ldi     ul,0xFF         ; lop runs ul+1 = 256 times per page
INNER:
            lin     x               ; a = (x), x++  (byte to copy)
            sin     y               ; (y) = a, y++  (store into buffer)

            rec                     ; C=0 -- clean add, no stale carry-in
            adc     (CHK_L)         ; a = byte + CHK_L
            sta     (CHK_L)
            bcr     NO_CARRY        ; C=0 -- no overflow into high byte
            lda     (CHK_H)
            inc     a
            sta     (CHK_H)
NO_CARRY:
            lop     ul,INNER

            lda     (PAGE_CNT)
            dec     a
            sta     (PAGE_CNT)
            bzs     DONE            ; a==0 -- just finished the last page
            jmp     OUTER

; ============================================================================
; Done -- restore PV (see the entry-point note above), then return the
; checksum via X (CALL addr, N convention: C=1 on RTN writes X back into
; the BASIC numeric variable).
DONE:
            lda     (SAVED_PV)
            bii     a,0x01          ; Z=1 if bit 0 clear -- PV should stay 0
            bzs     PV_RESTORED     ; already 0 (RPV above) -- nothing to do
            spv                     ; bit 0 was 1 -- restore PV=1
PV_RESTORED:
            lda     (CHK_H)
            sta     xh
            lda     (CHK_L)
            sta     xl
            sec
            rtn

; ---- scratch / result ----
CHK_H:      .db     0x00
CHK_L:      .db     0x00
PAGE_CNT:   .db     0x00
SAVED_PV:   .db     0x00

; ---- 8KB capture buffer (uninitialized) ----
BUFFER:     .blkb   0x2000
