// ============================================================================
// adder4.v : three 4-bit adder architectures + a selector wrapper
//   adder4_rca : ripple-carry adder (chain of full adders)
//   adder4_cla : carry-lookahead adder (two-level generate/propagate logic)
//   adder4_ks  : Kogge-Stone parallel-prefix adder (log2(4) = 2 prefix levels)
//   adder4     : wrapper, architecture chosen by parameter ADDER_ARCH
// ============================================================================
`timescale 1ns/1ps
`include "alu4_defs.vh"

/* verilator lint_off DECLFILENAME */  // several adder variants share one file

// ---------------------------------------------------------------- RCA -------
module adder4_rca (
    input  wire [3:0] x,
    input  wire [3:0] y,
    input  wire       ci,
    output wire [3:0] s,
    output wire       co
);
    // carry chain: bit-wise ripple, not a real combinational loop
    /* verilator lint_off UNOPTFLAT */
    wire [4:0] c;
    /* verilator lint_on UNOPTFLAT */
    assign c[0] = ci;
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_fa
            wire p = x[i] ^ y[i];
            assign s[i]   = p ^ c[i];
            assign c[i+1] = (x[i] & y[i]) | (p & c[i]);
        end
    endgenerate
    assign co = c[4];
endmodule

// ---------------------------------------------------------------- CLA -------
module adder4_cla (
    input  wire [3:0] x,
    input  wire [3:0] y,
    input  wire       ci,
    output wire [3:0] s,
    output wire       co
);
    wire [3:0] g = x & y;   // generate
    wire [3:0] p = x ^ y;   // propagate
    wire c1, c2, c3, c4;

    assign c1 = g[0] | (p[0] & ci);
    assign c2 = g[1] | (p[1] & g[0]) | (p[1] & p[0] & ci);
    assign c3 = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0])
                     | (p[2] & p[1] & p[0] & ci);
    assign c4 = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1])
                     | (p[3] & p[2] & p[1] & g[0])
                     | (p[3] & p[2] & p[1] & p[0] & ci);

    assign s  = p ^ {c3, c2, c1, ci};
    assign co = c4;
endmodule

// ---------------------------------------------------------------- KS --------
module adder4_ks (
    input  wire [3:0] x,
    input  wire [3:0] y,
    input  wire       ci,
    output wire [3:0] s,
    output wire       co
);
    wire [3:0] g = x & y;
    wire [3:0] p = x ^ y;

    // Fold the carry-in into bit 0 generate
    wire       g0c = g[0] | (p[0] & ci);

    // Prefix level 1 (span 1)
    wire [3:0] G1;
    wire [3:2] P1;                    // only the spans that are used later
    assign G1[0] = g0c;
    assign G1[1] = g[1] | (p[1] & g0c);
    assign G1[2] = g[2] | (p[2] & g[1]); assign P1[2] = p[2] & p[1];
    assign G1[3] = g[3] | (p[3] & g[2]); assign P1[3] = p[3] & p[2];

    // Prefix level 2 (span 2)
    wire [3:0] G2;
    assign G2[0] = G1[0];
    assign G2[1] = G1[1];
    assign G2[2] = G1[2] | (P1[2] & G1[0]);
    assign G2[3] = G1[3] | (P1[3] & G1[1]);

    // Carries: c[i+1] = G2[i]
    assign s  = p ^ {G2[2], G2[1], G2[0], ci};
    assign co = G2[3];
endmodule

// ---------------------------------------------------------------- wrapper ---
module adder4 #(
    parameter ADDER_ARCH = `ARCH_CLA
) (
    input  wire [3:0] x,
    input  wire [3:0] y,
    input  wire       ci,
    output wire [3:0] s,
    output wire       co
);
    generate
        if (ADDER_ARCH == `ARCH_RCA) begin : g_rca
            adder4_rca u (.x(x), .y(y), .ci(ci), .s(s), .co(co));
        end else if (ADDER_ARCH == `ARCH_KS) begin : g_ks
            adder4_ks  u (.x(x), .y(y), .ci(ci), .s(s), .co(co));
        end else begin : g_cla
            adder4_cla u (.x(x), .y(y), .ci(ci), .s(s), .co(co));
        end
    endgenerate
endmodule
/* verilator lint_on DECLFILENAME */
