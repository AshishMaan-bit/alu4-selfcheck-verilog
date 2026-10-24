// ============================================================================
// alu4_checker.v : configurable concurrent error-detection (CED) checker
// ----------------------------------------------------------------------------
// The checker observes only the ALU *inputs* (a, b, op, cin) and the ALU
// *outputs* (r, c, v, z, n). It never taps internal datapath nets, so a fault
// inside the datapath cannot corrupt the prediction. It has its own opcode
// decoder and is kept as a separate hierarchy during synthesis so that the
// tool cannot share logic between the datapath and its checker.
//
// Arithmetic class (ADD ADC SUB SBB INC DEC), selected by ARITH_CHK:
//   ARITH_CHK = 0 (RES3) : residue-modulo-3 code. Predicted |a + y + ci|_3 is
//                          compared with |{c, r}|_3 (16 = 1 mod 3).
//   ARITH_CHK = 1 (INV)  : inverse-operation check. The checker computes
//                          r + ~y + ~ci, which must equal {~c, a} exactly
//                          (because a + y + ci = 16c + r).
//   In both cases the overflow flag V is recomputed.
// Logic class (AND OR NOR), selected by LOGIC_CHK:
//   LOGIC_CHK = 0 (DUP)  : diverse duplication (De Morgan forms) + compare.
//   LOGIC_CHK = 1 (PAR)  : parity prediction: p(a&b) = ^(a&b),
//                          p(a|b) = pa ^ pb ^ p(a&b), p(~(a|b)) = p(a|b).
// Parity class (XOR NOT SHL SHR ASR ROL ROR): parity prediction of {r, c};
//   rotates additionally check C against the wrapped-around result bit.
// All ops: Z and N are recomputed from r; C and V must be 0 where unused.
//
//  err_vec[0] arithmetic   err_vec[1] logic   err_vec[2] parity   err_vec[3] Z/N
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

module alu4_checker #(
    parameter ARITH_CHK = 1,   // 0 = residue-3, 1 = inverse operation
    parameter LOGIC_CHK = 1    // 0 = diverse duplication, 1 = parity prediction
) (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire [3:0] op,
    input  wire       cin,
    input  wire [3:0] r,
    input  wire       c,
    input  wire       v,
    input  wire       z,
    input  wire       n,
    output wire       err,
    output wire [3:0] err_vec
);
    // ---------------- residue-3 helper functions (used when ARITH_CHK = 0) ---
    // residue of a 2-bit value: 3 -> 0
    function [1:0] res2;
        input [1:0] x;
        res2 = (x == 2'b11) ? 2'b00 : x;
    endfunction
    // modulo-3 addition of two residues in {0,1,2}
    function [1:0] add3;
        input [1:0] p, q;
        case ({p, q})
            4'b00_00: add3 = 2'd0;  4'b00_01: add3 = 2'd1;  4'b00_10: add3 = 2'd2;
            4'b01_00: add3 = 2'd1;  4'b01_01: add3 = 2'd2;  4'b01_10: add3 = 2'd0;
            4'b10_00: add3 = 2'd2;  4'b10_01: add3 = 2'd0;  4'b10_10: add3 = 2'd1;
            default : add3 = 2'd0;
        endcase
    endfunction
    // 4 = 1 (mod 3)  ->  |x|3 = |x[1:0]|3 + |x[3:2]|3
    function [1:0] res4;
        input [3:0] x;
        res4 = add3(res2(x[1:0]), res2(x[3:2]));
    endfunction

    // ---------------- independent opcode decode ----------------------------
    wire is_add = (op == `OP_ADD);
    wire is_adc = (op == `OP_ADC);
    wire is_sub = (op == `OP_SUB);
    wire is_sbb = (op == `OP_SBB);
    wire is_inc = (op == `OP_INC);
    wire is_dec = (op == `OP_DEC);
    wire is_and = (op == `OP_AND);
    wire is_or  = (op == `OP_OR );
    wire is_xor = (op == `OP_XOR);
    wire is_nor = (op == `OP_NOR);
    wire is_not = (op == `OP_NOT);
    wire is_shl = (op == `OP_SHL);
    wire is_shr = (op == `OP_SHR);
    wire is_asr = (op == `OP_ASR);
    wire is_rol = (op == `OP_ROL);
    wire is_ror = (op == `OP_ROR);

    wire is_arith = is_add | is_adc | is_sub | is_sbb | is_inc | is_dec;
    wire is_logic = is_and | is_or  | is_nor;

    // ---------------- predicted adder operand and carry-in -------------------
    //   ADD/ADC: y = b    SUB/SBB: y = ~b    INC: y = 0    DEC: y = 1111
    wire       add_like = is_add | is_adc;
    wire       sub_like = is_sub | is_sbb;
    wire [3:0] y_p  = ({4{add_like}} & b) | ({4{sub_like}} & ~b) | {4{is_dec}};
    wire       ci_p = (is_adc & cin) | is_sub | (is_sbb & ~cin) | is_inc;
    wire v_pred = (a[3] ~^ y_p[3]) & (r[3] ^ a[3]);

    // ---------------- ARITH check -------------------------------------------
    wire arith_bad;
    generate
        if (ARITH_CHK == 0) begin : g_res3
            wire [1:0] res_pred = add3(add3(res4(a), res4(y_p)), {1'b0, ci_p});
            wire [1:0] res_act  = add3(res4(r), {1'b0, c});          // 16 = 1 mod 3
            assign arith_bad = (res_pred != res_act);
        end else begin : g_inv
            // a + y + ci = 16c + r   <=>   r + ~y + ~ci = {~c, a}
            wire [4:0] inv = {1'b0, r} + {1'b0, ~y_p} + {4'b0000, ~ci_p};
            assign arith_bad = (inv != {~c, a});
        end
    endgenerate
    wire e_arith = is_arith & (arith_bad | (v != v_pred));

    // ---------------- parity terms ------------------------------------------
    wire pa    = ^a;
    wire pb    = ^b;
    wire pr    = ^r;
    wire p_and = ^(a & b);

    // ---------------- shared parity comparator -----------------------------
    // Parity of {r, C-if-a-data-bit-was-shifted-out} vs. predicted parity:
    //   XOR: pa^pb    NOT, SHL, SHR, ROL, ROR: pa    ASR: pa^a[3]
    //   (LOGIC_CHK = 1 only)  AND: p(a&b)    OR, NOR: pa^pb^p(a&b)
    //   because a|b = a^b^(a&b) and NOR inverts 4 bits (parity unchanged).
    wire shift_out = is_shl | is_shr | is_asr;          // C carries a data bit out
    wire p_pred_np = is_xor ? (pa ^ pb) : (is_asr ? (pa ^ a[3]) : pa);
    wire p_pred    = (LOGIC_CHK != 0 && is_and)             ? p_and :
                     (LOGIC_CHK != 0 && (is_or | is_nor))   ? (pa ^ pb ^ p_and) :
                                                              p_pred_np;
    wire par_bad   = (pr ^ (shift_out & c)) != p_pred;

    // ---------------- PARITY class (XOR NOT SHL SHR ASR ROL ROR) -----------
    wire par_extra = v | ((is_xor | is_not) & c)       // C, V must be 0
                   | (is_rol & (c != r[0]))            // rotate: C = wrapped bit
                   | (is_ror & (c != r[3]));
    wire is_parcl  = is_xor | is_not | is_shl | is_shr | is_asr | is_rol | is_ror;
    wire e_par     = is_parcl & (par_bad | par_extra);

    // ---------------- LOGIC class (AND OR NOR) ------------------------------
    wire logic_bad;
    generate
        if (LOGIC_CHK == 0) begin : g_dup
            // diverse duplication: De Morgan forms, bit-wise compare
            wire [3:0] na = ~a, nb = ~b;
            wire [3:0] dup_ref = is_and ? ~(na | nb) :        // a & b
                                 is_or  ? ~(na & nb) :        // a | b
                                          (na & nb);          // ~(a | b)
            assign logic_bad = (r != dup_ref);
        end else begin : g_par
            // parity prediction through the shared comparator above
            assign logic_bad = par_bad;
        end
    endgenerate
    wire e_logic = is_logic & (logic_bad | c | v);

    // ---------------- Z / N re-computation ----------------------------------
    wire e_flag = (z != ~|r) | (n != r[3]);

    assign err_vec = {e_flag, e_par, e_logic, e_arith};
    assign err     = |err_vec;
endmodule
