// ============================================================================
// alu4_defs.vh : opcode map for the self-checking 4-bit ALU
// ----------------------------------------------------------------------------
// Opcode classes (used by the concurrent error-detection checker):
//   ARITH  (residue-3 code)      : ADD ADC SUB SBB INC DEC
//   DUP    (diverse duplication) : AND OR NOR
//   PARITY (parity prediction)   : XOR NOT SHL SHR ASR ROL ROR
// ============================================================================
`ifndef ALU4_DEFS_VH
`define ALU4_DEFS_VH

`define OP_ADD 4'h0   // R = A + B
`define OP_ADC 4'h1   // R = A + B + Cin
`define OP_SUB 4'h2   // R = A - B          (C = 1 means "no borrow")
`define OP_SBB 4'h3   // R = A - B - Cin    (C = 1 means "no borrow")
`define OP_INC 4'h4   // R = A + 1
`define OP_DEC 4'h5   // R = A - 1
`define OP_AND 4'h6   // R = A & B
`define OP_OR  4'h7   // R = A | B
`define OP_XOR 4'h8   // R = A ^ B
`define OP_NOR 4'h9   // R = ~(A | B)
`define OP_NOT 4'hA   // R = ~A
`define OP_SHL 4'hB   // R = A << 1,  C = A[3]
`define OP_SHR 4'hC   // R = A >> 1,  C = A[0]   (logical)
`define OP_ASR 4'hD   // R = A >>> 1, C = A[0]   (arithmetic)
`define OP_ROL 4'hE   // R = {A[2:0],A[3]}, C = A[3]
`define OP_ROR 4'hF   // R = {A[0],A[3:1]}, C = A[0]

// Adder architecture selector (parameter ADDER_ARCH)
`define ARCH_RCA 0    // ripple-carry
`define ARCH_CLA 1    // carry-lookahead
`define ARCH_KS  2    // Kogge-Stone parallel prefix

`endif
