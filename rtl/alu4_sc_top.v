// ============================================================================
// alu4_sc_top.v : registered integration wrapper for the self-checking ALU
// ----------------------------------------------------------------------------
//  * Operands are captured on the rising clock edge when 'en' is high.
//  * Results/flags are registered one cycle later (2-stage: in-reg, out-reg).
//  * err_now     : error flag of the current output word
//  * err_sticky  : set on the first error, cleared only by reset / clr_err
//  * err_count   : saturating 8-bit count of erroneous operations
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

module alu4_sc_top #(
    parameter ADDER_ARCH = `ARCH_CLA,
    parameter DP_STYLE   = 1,          // proposed configuration by default:
    parameter ARITH_CHK  = 1,          //   bit-sliced datapath, inverse-op
    parameter LOGIC_CHK  = 1           //   arithmetic check, parity elsewhere
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire       clr_err,
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire [3:0] op,
    input  wire       cin,
    output reg  [3:0] r_q,
    output reg        c_q,
    output reg        v_q,
    output reg        z_q,
    output reg        n_q,
    output reg        valid_q,
    output reg        err_now,
    output reg  [3:0] err_vec_q,
    output reg        err_sticky,
    output reg  [7:0] err_count
);
    // ---------------- input registers --------------------------------------
    reg [3:0] a_q, b_q, op_q;
    reg       cin_q, en_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_q <= 4'h0; b_q <= 4'h0; op_q <= 4'h0; cin_q <= 1'b0; en_q <= 1'b0;
        end else begin
            en_q <= en;
            if (en) begin
                a_q <= a; b_q <= b; op_q <= op; cin_q <= cin;
            end
        end
    end

    // ---------------- combinational self-checking core ---------------------
    wire [3:0] r, ev;
    wire       c, v, z, n, e;
    alu4_sc_core #(.ADDER_ARCH(ADDER_ARCH), .DP_STYLE(DP_STYLE),
                  .ARITH_CHK(ARITH_CHK), .LOGIC_CHK(LOGIC_CHK)) u_core (
        .a(a_q), .b(b_q), .op(op_q), .cin(cin_q),
        .r(r), .c(c), .v(v), .z(z), .n(n), .err(e), .err_vec(ev)
    );

    // ---------------- output registers + error bookkeeping -----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_q <= 4'h0; c_q <= 1'b0; v_q <= 1'b0; z_q <= 1'b0; n_q <= 1'b0;
            valid_q <= 1'b0; err_now <= 1'b0; err_vec_q <= 4'h0;
            err_sticky <= 1'b0; err_count <= 8'h00;
        end else begin
            valid_q <= en_q;
            if (en_q) begin
                r_q <= r; c_q <= c; v_q <= v; z_q <= z; n_q <= n;
                err_now   <= e;
                err_vec_q <= ev;
            end else begin
                err_now   <= 1'b0;
                err_vec_q <= 4'h0;
            end

            if (clr_err) begin
                err_sticky <= 1'b0;
                err_count  <= 8'h00;
            end else if (en_q & e) begin
                err_sticky <= 1'b1;
                if (err_count != 8'hFF) err_count <= err_count + 8'h01;
            end
        end
    end
endmodule
