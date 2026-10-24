// ============================================================================
// alu4_ref.vh : independent behavioural reference model (testbench only)
// Returns {r[3:0], c, v, z, n}. Written with integer arithmetic so that it
// shares no structure with the RTL adder / operand-mux equations.
// ============================================================================
function [7:0] alu4_ref;
    input [3:0] op_i, a_i, b_i;
    input       cin_i;
    integer ua, ub, sa, sb, sres;
    reg [3:0] er;
    reg       ec, evf, ez, en;
    begin
        ua = a_i;  ub = b_i;
        sa = (ua > 7) ? ua - 16 : ua;
        sb = (ub > 7) ? ub - 16 : ub;
        sres = 0; ec = 1'b0; evf = 1'b0;
        case (op_i)
            `OP_ADD: begin er = ua + ub;         ec = (ua + ub) > 15;         sres = sa + sb;         end
            `OP_ADC: begin er = ua + ub + cin_i; ec = (ua + ub + cin_i) > 15; sres = sa + sb + cin_i; end
            `OP_SUB: begin er = ua - ub;         ec = (ua >= ub);             sres = sa - sb;         end
            `OP_SBB: begin er = ua - ub - cin_i; ec = (ua >= ub + cin_i);     sres = sa - sb - cin_i; end
            `OP_INC: begin er = ua + 1;          ec = (ua == 15);             sres = sa + 1;          end
            `OP_DEC: begin er = ua - 1;          ec = (ua != 0);              sres = sa - 1;          end
            `OP_AND: er = a_i & b_i;
            `OP_OR : er = a_i | b_i;
            `OP_XOR: er = a_i ^ b_i;
            `OP_NOR: er = ~(a_i | b_i);
            `OP_NOT: er = ~a_i;
            `OP_SHL: begin er = {a_i[2:0], 1'b0};  ec = a_i[3]; end
            `OP_SHR: begin er = {1'b0, a_i[3:1]};  ec = a_i[0]; end
            `OP_ASR: begin er = $signed(a_i) >>> 1; ec = a_i[0]; end
            `OP_ROL: begin er = {a_i[2:0], a_i[3]}; ec = a_i[3]; end
            `OP_ROR: begin er = {a_i[0], a_i[3:1]}; ec = a_i[0]; end
            default: er = 4'h0;
        endcase
        if (op_i <= `OP_DEC) evf = (sres > 7) || (sres < -8);
        ez = (er == 4'h0);
        en = er[3];
        alu4_ref = {er, ec, evf, ez, en};
    end
endfunction
