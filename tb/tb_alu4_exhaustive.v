// ============================================================================
// tb_alu4_exhaustive.v : exhaustive self-checking testbench
// ----------------------------------------------------------------------------
// Applies all 2^13 = 8192 input combinations (16 opcodes x 16 A x 16 B x Cin)
// and compares r, c, v, z, n with the independent behavioural reference model
// in tb/alu4_ref.vh. In the fault-free design the checker output 'err' must
// never assert (no false alarms).
//
// Compile-time options:
//   -DGATE=<module>  : DUT is a synthesised gate-level netlist (no parameter)
//   -DDMR            : DUT is the duplication-with-comparison reference core
//   -DVEC_FILE="..." : write every vector + response to a text file
//   -Ptb_alu4_exhaustive.ADDER_ARCH=<0|1|2> : adder architecture (RTL only)
//   -Ptb_alu4_exhaustive.DP_STYLE=<0|1>     : 0 conventional, 1 bit-sliced datapath
//   -Ptb_alu4_exhaustive.ARITH_CHK=<0|1>    : 0 residue-3, 1 inverse operation
//   -Ptb_alu4_exhaustive.LOGIC_CHK=<0|1>    : 0 duplication, 1 parity
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

module tb_alu4_exhaustive;
    parameter ADDER_ARCH = 1;
    parameter DP_STYLE   = 1;
    parameter ARITH_CHK  = 1;
    parameter LOGIC_CHK  = 1;

    reg  [3:0] a, b, op;
    reg        cin;
    wire [3:0] r, ev;
    wire       c, v, z, n, err;

`ifdef GATE
    `GATE dut (                       // -DGATE=<netlist module name>
`elsif DMR
    alu4_dmr_core #(.ADDER_ARCH(ADDER_ARCH)) dut (
`else
    alu4_sc_core #(.ADDER_ARCH(ADDER_ARCH), .DP_STYLE(DP_STYLE),
                  .ARITH_CHK(ARITH_CHK), .LOGIC_CHK(LOGIC_CHK)) dut (
`endif
        .a(a), .b(b), .op(op), .cin(cin),
        .r(r), .c(c), .v(v), .z(z), .n(n), .err(err), .err_vec(ev)
    );

    `include "alu4_ref.vh"

    integer i, vec, n_fail, n_err, n_sdc, fd;
    integer fail_op [0:15];
    reg [7:0] exp;
    initial begin
        n_fail = 0; n_err = 0; n_sdc = 0; vec = 0;
        for (i = 0; i < 16; i = i + 1) fail_op[i] = 0;
`ifdef VEC_FILE
        fd = $fopen(`VEC_FILE, "w");
        $fdisplay(fd, "# op a b cin | r c v z n err err_vec");
`endif
        for (i = 0; i < 8192; i = i + 1) begin
            {op, a, b, cin} = i[12:0];
            #1;
            exp = alu4_ref(op, a, b, cin);
            if ({r, c, v, z, n} !== exp) begin
                n_fail = n_fail + 1;
                fail_op[op] = fail_op[op] + 1;
                if (err !== 1'b1) n_sdc = n_sdc + 1;
                if (n_fail <= 10)
                    $display("MISMATCH op=%h a=%h b=%h cin=%b : dut r=%h c%b v%b z%b n%b | ref r=%h c%b v%b z%b n%b | err=%b",
                             op, a, b, cin, r, c, v, z, n,
                             exp[7:4], exp[3], exp[2], exp[1], exp[0], err);
            end
            if (err !== 1'b0) n_err = n_err + 1;
`ifdef VEC_FILE
            $fdisplay(fd, "%h %h %h %b | %h %b %b %b %b %b %b", op, a, b, cin, r, c, v, z, n, err, ev);
`endif
            vec = vec + 1;
        end
`ifdef VEC_FILE
        $fclose(fd);
`endif
        $display("------------------------------------------------------------");
`ifdef GATE
        $display(" DUT              : gate-level netlist");
`else
`ifdef DMR
        $display(" DUT              : RTL DMR core, ADDER_ARCH = %0d", ADDER_ARCH);
`else
        $display(" DUT              : RTL SC core, ADDER_ARCH = %0d, DP_STYLE = %0d, ARITH_CHK = %0d, LOGIC_CHK = %0d",
                 ADDER_ARCH, DP_STYLE, ARITH_CHK, LOGIC_CHK);
`endif
`endif
        $display(" vectors applied  : %0d", vec);
        for (i = 0; i < 16; i = i + 1)
            if (fail_op[i] != 0) $display("   op %h : %0d mismatches", i, fail_op[i]);
        $display(" functional fails : %0d", n_fail);
        $display(" err asserted     : %0d", n_err);
        $display(" undetected fails : %0d", n_sdc);
        if (n_fail == 0 && n_err == 0) $display(" RESULT: PASS");
        else                           $display(" RESULT: FAIL");
        $display("------------------------------------------------------------");
        $finish;
    end
endmodule
