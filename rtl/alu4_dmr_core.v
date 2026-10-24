// ============================================================================
// alu4_dmr_core.v : duplication-with-comparison (DMR) reference design
// ----------------------------------------------------------------------------
// Classical CED baseline used for comparison: two identical copies of the
// datapath and an equality comparator on all 8 output bits. Same port list as
// alu4_sc_core so that the same testbenches and fault campaign can be used.
// err_vec[0] = comparator mismatch, err_vec[3:1] = 0.
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

module alu4_dmr_core #(
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
    output wire       n,
    output wire       err,
    output wire [3:0] err_vec
);
    wire [3:0] r2;
    wire       c2, v2, z2, n2;

    alu4_datapath #(.ADDER_ARCH(ADDER_ARCH)) u_dp (
        .a(a), .b(b), .op(op), .cin(cin),
        .r(r), .c(c), .v(v), .z(z), .n(n));

    alu4_datapath #(.ADDER_ARCH(ADDER_ARCH)) u_dp2 (
        .a(a), .b(b), .op(op), .cin(cin),
        .r(r2), .c(c2), .v(v2), .z(z2), .n(n2));

    assign err     = ({r, c, v, z, n} != {r2, c2, v2, z2, n2});
    assign err_vec = {3'b000, err};
endmodule
