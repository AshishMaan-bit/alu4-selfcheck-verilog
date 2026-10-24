// ============================================================================
// alu4_datapath.v : functional 4-bit ALU (16 operations, 4 status flags)
// ----------------------------------------------------------------------------
//  a, b   : 4-bit operands         op  : 4-bit opcode (see alu4_defs.vh)
//  cin    : carry / borrow input   r   : 4-bit result
//  c      : carry (add), not-borrow (sub), shifted-out bit (shift/rotate)
//  v      : signed overflow (arithmetic ops only, else 0)
//  z      : zero flag              n   : negative flag (= r[3])
// The adder architecture is selected by ADDER_ARCH (0 RCA, 1 CLA, 2 KS).
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

module alu4_datapath #(
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
    // ---------------- adder operand conditioning ---------------------------
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
        .x(a), .y(y), .ci(ci), .s(sum), .co(cout)
    );

    // signed overflow of x + y + ci
    wire ovf = (a[3] ~^ y[3]) & (sum[3] ^ a[3]);

    // ---------------- result / flag selection ------------------------------
    reg [3:0] r_i;
    reg       c_i, v_i;
    always @* begin
        c_i = 1'b0;
        v_i = 1'b0;
        case (op)
            `OP_ADD, `OP_ADC, `OP_SUB,
            `OP_SBB, `OP_INC, `OP_DEC: begin r_i = sum; c_i = cout; v_i = ovf; end
            `OP_AND: r_i = a & b;
            `OP_OR : r_i = a | b;
            `OP_XOR: r_i = a ^ b;
            `OP_NOR: r_i = ~(a | b);
            `OP_NOT: r_i = ~a;
            `OP_SHL: begin r_i = {a[2:0], 1'b0}; c_i = a[3]; end
            `OP_SHR: begin r_i = {1'b0, a[3:1]}; c_i = a[0]; end
            `OP_ASR: begin r_i = {a[3], a[3:1]}; c_i = a[0]; end
            `OP_ROL: begin r_i = {a[2:0], a[3]}; c_i = a[3]; end
            `OP_ROR: begin r_i = {a[0], a[3:1]}; c_i = a[0]; end
            default: r_i = 4'h0;
        endcase
    end

    assign r = r_i;
    assign c = c_i;
    assign v = v_i;
    assign z = ~|r_i;
    assign n = r_i[3];
endmodule
