#!/usr/bin/env python3
"""Decode ND-120 microcode words - extract CSIDBS, CSCOMM fields from specific addresses."""

# From CPU_PROC_32.v:
# s_csidbs_4_0[4:0] = s_csbits[41:37]
# s_cscomm_4_0[4:0] = s_csbits[36:32]

def decode_word(addr_oct, word_hex):
    w = int(word_hex, 16)
    csidbs = (w >> 37) & 0x1F
    cscomm = (w >> 32) & 0x1F

    # Other fields from the plan:
    # ALUF in bits [47:43] (5 bits)?
    # Let's check what bits 63:42 look like
    print(f"\nAddress o{addr_oct}  word={word_hex}")
    print(f"  bits[63:32] = {(w>>32):032b}")
    print(f"  bits[31:0]  = {w & 0xFFFFFFFF:032b}")
    print(f"  CSIDBS[4:0] = bits[41:37] = {csidbs:05b} = {csidbs} decimal = o{csidbs:02o}")
    print(f"  CSCOMM[4:0] = bits[36:32] = {cscomm:05b} = {cscomm} decimal = o{cscomm:02o}")

    # Also show other known fields
    # From the microprogrammer's guide / known bit assignments
    # Try to extract fields by examining known words
    return csidbs, cscomm

# Known microcode words from the raw EPROM dumps (Code/Microcode/AM27256_4513{2,3}L.bin)
# o000016: IDBS,PANEL COMM,LDLC T,JMP T.HOLD PANEL
decode_word("000016", "0x1B800080800040FF")

# o002001: MACL: IDBS,ARQ COMM,SIOC T.NEXT T.HOLD 30120
decode_word("002001", "0x3280018082292001")

# o002105 from plan: ALUF A+Q, CONDENABL T,NEXT / T,JMP o02155, IDBS ALU
decode_word("002105", "0x20000000B480046D")

# Check the LDLCN decode: COMM = 01111 = 15 = o17
# For o000016 we expect CSCOMM = o17
print("\nExpected: o000016 CSCOMM = o17 (=15, LDLC), CSIDBS = PANEL")
print("Expected: o002001 CSCOMM = SIOC (some value), CSIDBS = ARQ")

# From session summary LDLCN decode:
# LDLCN fires when: ~COMM[4] & COMM[3] & COMM[2] & COMM[1] & COMM[0] & LCS_n
# = COMM[4:0] = 01111 = 15 = o17
print("\nLDLC COMM value = 0b01111 = 15 = o17")

# Now find IDBS=PANEL from CSIDBS value
# For o000016: CSIDBS from bits[41:37]
w = int("0x1B800080800040FF", 16)
b41_37 = (w >> 37) & 0x1F
print(f"\no000016 CSIDBS = {b41_37} = o{b41_37:02o}")

# Verify by computing bits manually
print(f"\nWord = {w:#018x}")
for start in range(0, 64, 8):
    byte_val = (w >> start) & 0xFF
    print(f"  bits[{start+7}:{start}] = {byte_val:08b} = {byte_val:#04x}")
