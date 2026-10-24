// ============================================================================
// tb_alu4_top.v : clocked testbench for the registered wrapper alu4_sc_top
// ----------------------------------------------------------------------------
//  1. reset, then 300 random operations with random 'en' bubbles; every
//     valid output is compared with the reference model (2-cycle latency).
//  2. a stuck-at-1 fault is forced on the KS adder's internal G1[2] node for
//     40 cycles; err_now / err_sticky / err_count behaviour is checked.
//  3. fault released, clr_err pulsed, 100 more fault-free operations.
// Waveform: sim/waves/top.vcd
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

module tb_alu4_top;
    reg        clk = 1'b0, rst_n = 1'b0, en = 1'b0, clr_err = 1'b0;
    reg  [3:0] a = 0, b = 0, op = 0;
    reg        cin = 0;
    wire [3:0] r_q, err_vec_q;
    wire       c_q, v_q, z_q, n_q, valid_q, err_now, err_sticky;
    wire [7:0] err_count;

    alu4_sc_top #(.ADDER_ARCH(2)) dut (
        .clk(clk), .rst_n(rst_n), .en(en), .clr_err(clr_err),
        .a(a), .b(b), .op(op), .cin(cin),
        .r_q(r_q), .c_q(c_q), .v_q(v_q), .z_q(z_q), .n_q(n_q),
        .valid_q(valid_q), .err_now(err_now), .err_vec_q(err_vec_q),
        .err_sticky(err_sticky), .err_count(err_count));

    always #5 clk = ~clk;      // 100 MHz

    `include "alu4_ref.vh"

    // 2-deep expected-value pipeline (matches in-reg + out-reg latency)
    reg [7:0] exp_d1, exp_d2;
    reg       vld_d1, vld_d2;
    always @(posedge clk) begin
        exp_d1 <= alu4_ref(op, a, b, cin);  vld_d1 <= en;
        exp_d2 <= exp_d1;                    vld_d2 <= vld_d1;
    end

    integer seed = 7, i;
    integer n_chk = 0, n_bad = 0, n_bad_flagged = 0, n_alarm = 0;
    reg     fault_on = 1'b0;

    // sample 1 ns after the edge so that valid_q and the outputs are the
    // values produced by this edge
    always @(posedge clk) begin
        #1;
        if (rst_n && valid_q) begin
        n_chk = n_chk + 1;
        if ({r_q, c_q, v_q, z_q, n_q} !== exp_d2) begin
            n_bad = n_bad + 1;
            if (err_now) n_bad_flagged = n_bad_flagged + 1;
            if (!fault_on) $display("%t ERROR: unexpected mismatch without fault: got %h exp %h", $time, {r_q, c_q, v_q, z_q, n_q}, exp_d2);
        end
        if (err_now) n_alarm = n_alarm + 1;
        end
    end

    task drive_random;
        begin
            @(negedge clk);
            en  = ($random(seed) % 8) != 0;     // ~12% bubbles
            op  = $random(seed); a = $random(seed); b = $random(seed); cin = $random(seed);
        end
    endtask

    integer chk_before, bad_before, alarm_before;
    initial begin
        $dumpfile("sim/waves/top.vcd");
        $dumpvars(0, tb_alu4_top);
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // ---- phase 1: fault-free ----------------------------------------
        for (i = 0; i < 300; i = i + 1) drive_random;
        @(negedge clk); en = 0; repeat (3) @(negedge clk);
        $display("phase1 fault-free : checked=%0d mismatches=%0d alarms=%0d sticky=%b count=%0d",
                 n_chk, n_bad, n_alarm, err_sticky, err_count);
        if (n_bad != 0 || n_alarm != 0 || err_sticky != 0) $display("PHASE1 FAIL");
        else                                               $display("PHASE1 PASS");

        // ---- phase 2: inject stuck-at-1 in the KS prefix tree ------------
        chk_before = n_chk; bad_before = n_bad; alarm_before = n_alarm;
        fault_on = 1'b1;
        force dut.u_core.g_bs.u_dp.u_add.g_ks.u.G1[2] = 1'b1;
        for (i = 0; i < 40; i = i + 1) begin
            @(negedge clk); en = 1; op = `OP_ADD + ($random(seed) & 3);
            a = $random(seed); b = $random(seed); cin = $random(seed);
        end
        @(negedge clk); en = 0; repeat (3) @(negedge clk);
        release dut.u_core.g_bs.u_dp.u_add.g_ks.u.G1[2];
        fault_on = 1'b0;
        $display("phase2 G1[2] SA1  : checked=%0d corrupted=%0d flagged=%0d alarms=%0d sticky=%b count=%0d",
                 n_chk - chk_before, n_bad - bad_before, n_bad_flagged,
                 n_alarm - alarm_before, err_sticky, err_count);
        if (n_bad_flagged == n_bad - bad_before && err_sticky && err_count == n_alarm - alarm_before)
            $display("PHASE2 PASS (every corrupted word flagged, sticky/count consistent)");
        else
            $display("PHASE2 NOTE: some corrupted words were not flagged");

        // ---- phase 3: clear and recover ---------------------------------
        @(negedge clk); clr_err = 1; @(negedge clk); clr_err = 0;
        chk_before = n_chk; bad_before = n_bad; alarm_before = n_alarm;
        for (i = 0; i < 100; i = i + 1) drive_random;
        @(negedge clk); en = 0; repeat (3) @(negedge clk);
        $display("phase3 recovered  : checked=%0d mismatches=%0d alarms=%0d sticky=%b count=%0d",
                 n_chk - chk_before, n_bad - bad_before, n_alarm - alarm_before, err_sticky, err_count);
        if (n_bad == bad_before && n_alarm == alarm_before && !err_sticky) $display("PHASE3 PASS");
        else                                                                $display("PHASE3 FAIL");
        $finish;
    end
endmodule
