// ============================================================================
// alu4_base_core.v : unprotected reference ALU (no error detection)
// ----------------------------------------------------------------------------
// Wraps the plain datapath with the same port list as alu4_sc_core so that
// all designs share one testbench, one synthesis flow and one fault campaign.
// err / err_vec are tied to 0: every functional error is silent.
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

module alu4_base_core #(
    parameter ADDER_ARCH = `ARCH_CLA,
    parameter DP_STYLE   = 0           // 0 conventional, 1 bit-sliced datapath
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

    assign err     = 1'b0;
    assign err_vec = 4'b0000;
endmodule
