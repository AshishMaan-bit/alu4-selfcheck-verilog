// ============================================================================
// tb_alu4_fault_demo.v : RTL-level fault-injection demonstration
// ----------------------------------------------------------------------------
// Two copies of the self-checking ALU (proposed configuration: bit-sliced
// datapath, CLA adder, inverse-op + parity checker) receive identical stimulus.
// 'gold' is always fault-free. In 'dut', a single stuck-at fault is injected
// with force/release during each phase. For every vector we record whether the
// DUT output word {r,c,v,z,n} is corrupted and whether the checker raised err.
//
//   phase 0 : no fault                                  (mixed opcodes)
//   phase 1 : CLA internal carry c2 stuck-at-0           (arithmetic opcodes)
//   phase 2 : adder operand-mux bit y[1] stuck-at-1      (arithmetic opcodes)
//   phase 3 : result bit r[1] stuck-at-1                 (AND/OR/NOR)
//   phase 4 : result bit r[2] stuck-at-0                 (XOR/NOT/shift/rotate)
//   phase 5 : carry flag c stuck-at-1                    (all opcodes)
//   phase 6 : zero flag z stuck-at-0                     (all opcodes)
//   phase 7 : no fault (recovery check after release)    (mixed opcodes)
// A VCD waveform is written to sim/waves/fault_demo.vcd.
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

module tb_alu4_fault_demo;
    reg  [3:0] a, b, op;
    reg        cin;
    reg  [2:0] phase;

    wire [3:0] r_d, r_g, ev_d, ev_g;
    wire       c_d, v_d, z_d, n_d, err_d;
    wire       c_g, v_g, z_g, n_g, err_g;

    alu4_sc_core #(.ADDER_ARCH(1)) dut (
        .a(a), .b(b), .op(op), .cin(cin),
        .r(r_d), .c(c_d), .v(v_d), .z(z_d), .n(n_d), .err(err_d), .err_vec(ev_d));

    alu4_sc_core #(.ADDER_ARCH(1)) gold (
        .a(a), .b(b), .op(op), .cin(cin),
        .r(r_g), .c(c_g), .v(v_g), .z(z_g), .n(n_g), .err(err_g), .err_vec(ev_g));

    wire corrupted = ({r_d, c_d, v_d, z_d, n_d} !== {r_g, c_g, v_g, z_g, n_g});

    integer seed;
    integer k;
    integer n_vec [0:7];
    integer n_cor [0:7];
    integer n_det [0:7];
    integer n_sdc [0:7];
    integer n_fa  [0:7];

    // pick an opcode from a class: 0 any, 1 arith, 2 dup, 3 parity
    function [3:0] pick_op;
        input integer cls;
        input integer rnd;
        reg [3:0] t;
        begin
            t = rnd[3:0];
            case (cls)
                1: pick_op = t % 6;                       // 0..5
                2: pick_op = `OP_AND + (t % 3);           // 6..8 -> AND OR XOR
                3: pick_op = `OP_XOR + (t % 8);           // 8..15
                default: pick_op = t;
            endcase
            if (cls == 2 && pick_op == `OP_XOR) pick_op = `OP_NOR;
        end
    endfunction

    task run_phase;
        input [2:0] ph;
        input integer cls;
        input integer nv;
        integer j;
        begin
            phase = ph;
            for (j = 0; j < nv; j = j + 1) begin
                op  = pick_op(cls, $random(seed));
                a   = $random(seed);
                b   = $random(seed);
                cin = $random(seed);
                #5;
                n_vec[ph] = n_vec[ph] + 1;
                if (corrupted)              n_cor[ph] = n_cor[ph] + 1;
                if (corrupted &&  err_d)    n_det[ph] = n_det[ph] + 1;
                if (corrupted && !err_d)    n_sdc[ph] = n_sdc[ph] + 1;
                if (!corrupted && err_d)    n_fa[ph]  = n_fa[ph]  + 1;
                $display("%6t ph%0d op=%h a=%h b=%h ci=%b | dut r=%h c%b v%b z%b n%b | gold r=%h c%b v%b z%b n%b | err=%b ev=%b %s",
                    $time, ph, op, a, b, cin, r_d, c_d, v_d, z_d, n_d,
                    r_g, c_g, v_g, z_g, n_g, err_d, ev_d,
                    corrupted ? (err_d ? "<- CORRUPT, DETECTED" : "<- CORRUPT, MISSED")
                              : (err_d ? "<- false alarm" : ""));
                #5;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/waves/fault_demo.vcd");
        $dumpvars(0, tb_alu4_fault_demo);
        seed = 2026;
        for (k = 0; k < 8; k = k + 1) begin
            n_vec[k] = 0; n_cor[k] = 0; n_det[k] = 0; n_sdc[k] = 0; n_fa[k] = 0;
        end
        a = 0; b = 0; op = 0; cin = 0; phase = 0;

        run_phase(0, 0, 24);

        force dut.g_bs.u_dp.u_add.g_cla.u.c2 = 1'b0;
        run_phase(1, 1, 24);
        release dut.g_bs.u_dp.u_add.g_cla.u.c2;

        force dut.g_bs.u_dp.y[1] = 1'b1;
        run_phase(2, 1, 24);
        release dut.g_bs.u_dp.y[1];

        force dut.r[1] = 1'b1;
        run_phase(3, 2, 24);
        release dut.r[1];

        force dut.r[2] = 1'b0;
        run_phase(4, 3, 24);
        release dut.r[2];

        force dut.c = 1'b1;
        run_phase(5, 0, 24);
        release dut.c;

        force dut.z = 1'b0;
        run_phase(6, 0, 24);
        release dut.z;

        run_phase(7, 0, 24);

        $display("");
        $display("phase | vectors | corrupted | detected | missed(SDC) | false-alarm");
        for (k = 0; k < 8; k = k + 1)
            $display("  %0d   |   %3d   |    %3d    |   %3d    |     %3d     |    %3d",
                     k, n_vec[k], n_cor[k], n_det[k], n_sdc[k], n_fa[k]);
        $finish;
    end
endmodule
