// ============================================================================
// alu4_sc_core.v : self-checking 4-bit ALU = functional datapath + CED checker
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

module alu4_sc_core #(
    parameter ADDER_ARCH = `ARCH_CLA,
    parameter DP_STYLE   = 1,          // 0 conventional, 1 bit-sliced datapath
    parameter ARITH_CHK  = 1,          // 0 residue-3, 1 inverse operation
    parameter LOGIC_CHK  = 1           // 0 duplication, 1 parity prediction
) (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire [3:0] op,
    input  wire       cin,
    output wire [3:0] r,
    output wire       c,
    output wire       v,
    output wire       z,
    output wire       n,
    output wire       err,
    output wire [3:0] err_vec
);
    generate
        if (DP_STYLE == 1) begin : g_bs
            alu4_datapath_bs #(.ADDER_ARCH(ADDER_ARCH)) u_dp (
                .a(a), .b(b), .op(op), .cin(cin),
                .r(r), .c(c), .v(v), .z(z), .n(n));
        end else begin : g_conv
            alu4_datapath #(.ADDER_ARCH(ADDER_ARCH)) u_dp (
                .a(a), .b(b), .op(op), .cin(cin),
                .r(r), .c(c), .v(v), .z(z), .n(n));
        end
    endgenerate

    alu4_checker #(.ARITH_CHK(ARITH_CHK), .LOGIC_CHK(LOGIC_CHK)) u_chk (
        .a(a), .b(b), .op(op), .cin(cin),
        .r(r), .c(c), .v(v), .z(z), .n(n),
        .err(err), .err_vec(err_vec)
    );
endmodule
