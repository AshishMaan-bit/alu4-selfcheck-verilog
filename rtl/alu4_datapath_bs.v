// ============================================================================
// alu4_datapath_bs.v : bit-sliced, sharing-free 4-bit ALU datapath
// ----------------------------------------------------------------------------
// Functionally identical to alu4_datapath, but structured for parity-based
// concurrent error detection:
//
//   * every result bit r[i] is produced by its own slice (alu4_rslice) that
//     contains its OWN opcode decoder, logic unit and output multiplexer;
//   * the carry flag and the overflow flag have their own slices;
//   * the adder (with its operand conditioning) is the only logic shared
//     between bits, and its outputs are used only by arithmetic opcodes,
//     which are checked exactly by the inverse-operation / residue checker.
//
// Each slice is synthesised as a separate hierarchy (keep_hierarchy), so the
// optimiser cannot share gates between bits. Consequently any single
// stuck-at fault inside a slice can corrupt at most ONE output bit while a
// non-arithmetic opcode is executing - an odd (single-bit) error that parity
// prediction is guaranteed to detect. Without this restriction, shared gates
// (e.g. a common decoded select line) can flip two result bits at once and
// escape the parity check.
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

/* verilator lint_off DECLFILENAME */  // slice modules live in this file

// ---------------------------------------------------------------- r slice ---
module alu4_rslice #(
    parameter BIT = 0                  // which result bit this slice makes
) (
    input  wire [3:0] op,
    input  wire       ai,              // a[BIT]
    input  wire       bi,              // b[BIT]
    input  wire       si,              // adder sum[BIT]
    input  wire       a_dn,            // a[BIT-1] (wraps to a[3] for BIT = 0)
    input  wire       a_up,            // a[BIT+1] (wraps to a[0] for BIT = 3)
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire       a_msb,           // a[3] (sign bit, used by BIT = 3 only)
    /* verilator lint_on UNUSEDSIGNAL */
    output reg        ri
);
    always @* begin
        case (op)
            `OP_ADD, `OP_ADC, `OP_SUB,
            `OP_SBB, `OP_INC, `OP_DEC: ri = si;
            `OP_AND: ri = ai & bi;
            `OP_OR : ri = ai | bi;
            `OP_XOR: ri = ai ^ bi;
            `OP_NOR: ri = ~(ai | bi);
            `OP_NOT: ri = ~ai;
            `OP_SHL: ri = (BIT == 0) ? 1'b0  : a_dn;
            `OP_SHR: ri = (BIT == 3) ? 1'b0  : a_up;
            `OP_ASR: ri = (BIT == 3) ? a_msb : a_up;
            `OP_ROL: ri = a_dn;
            `OP_ROR: ri = a_up;
            default: ri = 1'b0;
        endcase
    end
endmodule

// ---------------------------------------------------------------- C slice ---
module alu4_cslice (
    input  wire [3:0] op,
    input  wire       a0,
    input  wire       a3,
    input  wire       cout,
    output reg        c
);
    always @* begin
        case (op)
            `OP_ADD, `OP_ADC, `OP_SUB,
            `OP_SBB, `OP_INC, `OP_DEC: c = cout;
            `OP_SHL, `OP_ROL:          c = a3;
            `OP_SHR, `OP_ASR, `OP_ROR: c = a0;
            default:                   c = 1'b0;
        endcase
    end
endmodule

// ---------------------------------------------------------------- V slice ---
module alu4_vslice (
    input  wire [3:0] op,
    input  wire       a3,
    input  wire       y3,
    input  wire       s3,
    output wire       v
);
    wire is_arith = (op == `OP_ADD) | (op == `OP_ADC) | (op == `OP_SUB) |
                    (op == `OP_SBB) | (op == `OP_INC) | (op == `OP_DEC);
    assign v = is_arith & (a3 ~^ y3) & (s3 ^ a3);
endmodule

// ---------------------------------------------------------------- top -------
module alu4_datapath_bs #(
    parameter ADDER_ARCH = `ARCH_CLA
) (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire [3:0] op,
    input  wire       cin,
    output wire [3:0] r,
    output wire       c,
    output wire       v,
    output wire       z,
    output wire       n
);
    // ---------------- adder with operand conditioning (shared) -------------
    reg  [3:0] y;
    reg        ci;
    always @* begin
        case (op)
            `OP_ADD: begin y = b;     ci = 1'b0; end
            `OP_ADC: begin y = b;     ci = cin;  end
            `OP_SUB: begin y = ~b;    ci = 1'b1; end
            `OP_SBB: begin y = ~b;    ci = ~cin; end
            `OP_INC: begin y = 4'h0;  ci = 1'b1; end
            `OP_DEC: begin y = 4'hF;  ci = 1'b0; end
            default: begin y = b;     ci = 1'b0; end
        endcase
    end

    wire [3:0] sum;
    wire       cout;
    adder4 #(.ADDER_ARCH(ADDER_ARCH)) u_add (
        .x(a), .y(y), .ci(ci), .s(sum), .co(cout));

    // ---------------- one independent slice per output bit -----------------
    alu4_rslice #(.BIT(0)) u_r0 (.op(op), .ai(a[0]), .bi(b[0]), .si(sum[0]),
                                 .a_dn(a[3]), .a_up(a[1]), .a_msb(a[3]), .ri(r[0]));
    alu4_rslice #(.BIT(1)) u_r1 (.op(op), .ai(a[1]), .bi(b[1]), .si(sum[1]),
                                 .a_dn(a[0]), .a_up(a[2]), .a_msb(a[3]), .ri(r[1]));
    alu4_rslice #(.BIT(2)) u_r2 (.op(op), .ai(a[2]), .bi(b[2]), .si(sum[2]),
                                 .a_dn(a[1]), .a_up(a[3]), .a_msb(a[3]), .ri(r[2]));
    alu4_rslice #(.BIT(3)) u_r3 (.op(op), .ai(a[3]), .bi(b[3]), .si(sum[3]),
                                 .a_dn(a[2]), .a_up(a[0]), .a_msb(a[3]), .ri(r[3]));

    alu4_cslice u_c (.op(op), .a0(a[0]), .a3(a[3]), .cout(cout), .c(c));
    alu4_vslice u_v (.op(op), .a3(a[3]), .y3(y[3]), .s3(sum[3]), .v(v));

    assign z = ~|r;
    assign n = r[3];
endmodule
/* verilator lint_on DECLFILENAME */
