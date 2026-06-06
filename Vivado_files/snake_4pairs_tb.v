// ============================================================
// snake_4pairs_tb.v  -  4 specific sequence pairs from dataset
// ============================================================
// M=104 (100 bases padded to next multiple of T=8)
// E=5  T=8  Y=4  CHAR_W=3
// DNA encoding: A=000 C=001 G=010 T=011 B=100(pad)
//
// Pair 1: R=TGAGACC...  Q=AAAAAAAA...  (different)
// Pair 2: R=TACAAGT...  Q=AAAAAAAA...  (different)
// Pair 3: R=AAAAAAA...  Q=AAAAAAAA...  (identical)
// Pair 4: R=GAAAAAA...  Q=AAAAAAAA...  (nearly identical)
// ============================================================

`timescale 1ns/1ps

module snake_4pairs_tb;

    localparam E      = 5;
    localparam T      = 8;
    localparam Y      = 4;
    localparam M      = 104;
    localparam CHAR_W = 3;
    localparam SEQ_LEN = 100;
    localparam Q_TOT  = M + 2*E;
    localparam CLK_HALF = 5;

    localparam [CHAR_W-1:0] BA = 3'b000;
    localparam [CHAR_W-1:0] BC = 3'b001;
    localparam [CHAR_W-1:0] BG = 3'b010;
    localparam [CHAR_W-1:0] BT = 3'b011;
    localparam [CHAR_W-1:0] BB = 3'b100;

    reg                        clk, rst, start_i;
    wire                       done_o, accept_o;
    reg  [M*CHAR_W-1:0]        ref_i;
    reg  [Q_TOT*CHAR_W-1:0]    query_i;

    snake_on_chip_top #(.E(E),.T(T),.Y(Y),.M(M),.CHAR_W(CHAR_W)) DUT (
        .clk(clk),.rst(rst),.start_i(start_i),
        .done_o(done_o),.accept_o(accept_o),
        .ref_i(ref_i),.query_i(query_i)
    );

    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    integer fail_count, pass_count, timeout_c;
    integer total_accepted, total_rejected;

    task reset_dut;
        begin
            rst=1; start_i=0;
            repeat(4) @(posedge clk);
            rst=0; @(posedge clk); #1;
        end
    endtask

    // Pad ref to M with B after SEQ_LEN real bases
    task pad_ref;
        integer k;
        begin
            for (k = SEQ_LEN; k < M; k = k+1)
                ref_i[k*CHAR_W +: CHAR_W] = BB;
        end
    endtask

    // Pad query: left E B's, real bases at E..E+SEQ_LEN-1,
    // then B's to E+M, then right E B's
    task pad_query;
        integer k;
        begin
            for (k = 0; k < E; k = k+1)
                query_i[k*CHAR_W +: CHAR_W] = BB;
            for (k = SEQ_LEN; k < M; k = k+1)
                query_i[(E+k)*CHAR_W +: CHAR_W] = BB;
            for (k = E+M; k < Q_TOT; k = k+1)
                query_i[k*CHAR_W +: CHAR_W] = BB;
        end
    endtask

    task run_and_check;
        input integer tid;
        input integer exp_accept;
        begin
            @(posedge clk); #1;
            start_i=1; @(posedge clk); #1; start_i=0;
            timeout_c=0;
            while (!done_o && timeout_c<1000) begin
                @(posedge clk); #1; timeout_c=timeout_c+1;
            end
            if (!done_o) begin
                $display("FAIL #%0d: timeout", tid);
                fail_count=fail_count+1;
            end else if (accept_o !== exp_accept[0]) begin
                $display("FAIL #%0d: accept=%0d expected=%0d (cycles=%0d)",
                         tid, accept_o, exp_accept, timeout_c);
                fail_count=fail_count+1;
                if (accept_o) total_accepted=total_accepted+1;
                else          total_rejected=total_rejected+1;
            end else begin
                $display("PASS #%0d: %s (cycles=%0d)",
                         tid, accept_o ? "ACCEPT" : "REJECT", timeout_c);
                pass_count=pass_count+1;
                if (accept_o) total_accepted=total_accepted+1;
                else          total_rejected=total_rejected+1;
            end
            repeat(5) @(posedge clk); #1;
        end
    endtask

    initial begin
        fail_count=0; pass_count=0;
        total_accepted=0; total_rejected=0;
        clk=0; rst=1; start_i=0; ref_i=0; query_i=0;

        $display("============================================================");
        $display("  Snake-on-Chip  4-Pair Dataset TB");
        $display("  E=%0d T=%0d Y=%0d M=%0d SEQ_LEN=%0d", E,T,Y,M,SEQ_LEN);
        $display("  A=000 C=001 G=010 T=011 B=100(pad)");
        $display("  ACCEPT if total_obstacles <= E=%0d", E);
        $display("============================================================");

        repeat(4) @(posedge clk); rst=0; @(posedge clk); #1;

        // =========================================================
        // Pair 1
        // R: TGAGACCCTGTGTCTACAAAAAGTAAAAAAATCTGGCATGGTGGCACACACCT
        //    GTAGTCCTAGATACTCAGGAGGTCAAGGCAGGAAGATTGCTTAAACC
        // Q: AAAAAAAAAAAATGAAAAAATAAAAAGTTATCTGGGCATGGTGGCACACACCT
        //    GTAGTCCCAGCTACTGAGGAGGCTGAGGCAGGAAGATTGCTTAAACC
        // Expected: REJECT (very different start regions)
        // =========================================================
        $display("\n--- Pair 1 ---");
        $display("  R: TGAGACCCTGTGTCTACAAAAAGTAAAAAAATCTGGCATGGTGG...");
        $display("  Q: AAAAAAAAAAAATGAAAAAATAAAAAGTTATCTGGGCATGGTGG...");
        reset_dut();
        // Load ref
        ref_i[  0*CHAR_W+:CHAR_W]=BT; ref_i[  1*CHAR_W+:CHAR_W]=BG;
        ref_i[  2*CHAR_W+:CHAR_W]=BA; ref_i[  3*CHAR_W+:CHAR_W]=BG;
        ref_i[  4*CHAR_W+:CHAR_W]=BA; ref_i[  5*CHAR_W+:CHAR_W]=BC;
        ref_i[  6*CHAR_W+:CHAR_W]=BC; ref_i[  7*CHAR_W+:CHAR_W]=BC;
        ref_i[  8*CHAR_W+:CHAR_W]=BT; ref_i[  9*CHAR_W+:CHAR_W]=BG;
        ref_i[ 10*CHAR_W+:CHAR_W]=BT; ref_i[ 11*CHAR_W+:CHAR_W]=BG;
        ref_i[ 12*CHAR_W+:CHAR_W]=BT; ref_i[ 13*CHAR_W+:CHAR_W]=BC;
        ref_i[ 14*CHAR_W+:CHAR_W]=BT; ref_i[ 15*CHAR_W+:CHAR_W]=BA;
        ref_i[ 16*CHAR_W+:CHAR_W]=BC; ref_i[ 17*CHAR_W+:CHAR_W]=BA;
        ref_i[ 18*CHAR_W+:CHAR_W]=BA; ref_i[ 19*CHAR_W+:CHAR_W]=BA;
        ref_i[ 20*CHAR_W+:CHAR_W]=BA; ref_i[ 21*CHAR_W+:CHAR_W]=BA;
        ref_i[ 22*CHAR_W+:CHAR_W]=BG; ref_i[ 23*CHAR_W+:CHAR_W]=BT;
        ref_i[ 24*CHAR_W+:CHAR_W]=BA; ref_i[ 25*CHAR_W+:CHAR_W]=BA;
        ref_i[ 26*CHAR_W+:CHAR_W]=BA; ref_i[ 27*CHAR_W+:CHAR_W]=BA;
        ref_i[ 28*CHAR_W+:CHAR_W]=BA; ref_i[ 29*CHAR_W+:CHAR_W]=BA;
        ref_i[ 30*CHAR_W+:CHAR_W]=BA; ref_i[ 31*CHAR_W+:CHAR_W]=BT;
        ref_i[ 32*CHAR_W+:CHAR_W]=BC; ref_i[ 33*CHAR_W+:CHAR_W]=BT;
        ref_i[ 34*CHAR_W+:CHAR_W]=BG; ref_i[ 35*CHAR_W+:CHAR_W]=BG;
        ref_i[ 36*CHAR_W+:CHAR_W]=BC; ref_i[ 37*CHAR_W+:CHAR_W]=BA;
        ref_i[ 38*CHAR_W+:CHAR_W]=BT; ref_i[ 39*CHAR_W+:CHAR_W]=BG;
        ref_i[ 40*CHAR_W+:CHAR_W]=BG; ref_i[ 41*CHAR_W+:CHAR_W]=BT;
        ref_i[ 42*CHAR_W+:CHAR_W]=BG; ref_i[ 43*CHAR_W+:CHAR_W]=BG;
        ref_i[ 44*CHAR_W+:CHAR_W]=BC; ref_i[ 45*CHAR_W+:CHAR_W]=BA;
        ref_i[ 46*CHAR_W+:CHAR_W]=BC; ref_i[ 47*CHAR_W+:CHAR_W]=BA;
        ref_i[ 48*CHAR_W+:CHAR_W]=BC; ref_i[ 49*CHAR_W+:CHAR_W]=BC;
        ref_i[ 50*CHAR_W+:CHAR_W]=BT; ref_i[ 51*CHAR_W+:CHAR_W]=BG;
        ref_i[ 52*CHAR_W+:CHAR_W]=BT; ref_i[ 53*CHAR_W+:CHAR_W]=BA;
        ref_i[ 54*CHAR_W+:CHAR_W]=BG; ref_i[ 55*CHAR_W+:CHAR_W]=BT;
        ref_i[ 56*CHAR_W+:CHAR_W]=BC; ref_i[ 57*CHAR_W+:CHAR_W]=BC;
        ref_i[ 58*CHAR_W+:CHAR_W]=BT; ref_i[ 59*CHAR_W+:CHAR_W]=BA;
        ref_i[ 60*CHAR_W+:CHAR_W]=BG; ref_i[ 61*CHAR_W+:CHAR_W]=BA;
        ref_i[ 62*CHAR_W+:CHAR_W]=BT; ref_i[ 63*CHAR_W+:CHAR_W]=BA;
        ref_i[ 64*CHAR_W+:CHAR_W]=BC; ref_i[ 65*CHAR_W+:CHAR_W]=BT;
        ref_i[ 66*CHAR_W+:CHAR_W]=BC; ref_i[ 67*CHAR_W+:CHAR_W]=BA;
        ref_i[ 68*CHAR_W+:CHAR_W]=BG; ref_i[ 69*CHAR_W+:CHAR_W]=BG;
        ref_i[ 70*CHAR_W+:CHAR_W]=BA; ref_i[ 71*CHAR_W+:CHAR_W]=BG;
        ref_i[ 72*CHAR_W+:CHAR_W]=BG; ref_i[ 73*CHAR_W+:CHAR_W]=BT;
        ref_i[ 74*CHAR_W+:CHAR_W]=BC; ref_i[ 75*CHAR_W+:CHAR_W]=BA;
        ref_i[ 76*CHAR_W+:CHAR_W]=BA; ref_i[ 77*CHAR_W+:CHAR_W]=BG;
        ref_i[ 78*CHAR_W+:CHAR_W]=BG; ref_i[ 79*CHAR_W+:CHAR_W]=BC;
        ref_i[ 80*CHAR_W+:CHAR_W]=BA; ref_i[ 81*CHAR_W+:CHAR_W]=BG;
        ref_i[ 82*CHAR_W+:CHAR_W]=BG; ref_i[ 83*CHAR_W+:CHAR_W]=BA;
        ref_i[ 84*CHAR_W+:CHAR_W]=BA; ref_i[ 85*CHAR_W+:CHAR_W]=BG;
        ref_i[ 86*CHAR_W+:CHAR_W]=BA; ref_i[ 87*CHAR_W+:CHAR_W]=BT;
        ref_i[ 88*CHAR_W+:CHAR_W]=BT; ref_i[ 89*CHAR_W+:CHAR_W]=BG;
        ref_i[ 90*CHAR_W+:CHAR_W]=BC; ref_i[ 91*CHAR_W+:CHAR_W]=BT;
        ref_i[ 92*CHAR_W+:CHAR_W]=BT; ref_i[ 93*CHAR_W+:CHAR_W]=BA;
        ref_i[ 94*CHAR_W+:CHAR_W]=BA; ref_i[ 95*CHAR_W+:CHAR_W]=BA;
        ref_i[ 96*CHAR_W+:CHAR_W]=BC; ref_i[ 97*CHAR_W+:CHAR_W]=BC;
        ref_i[ 98*CHAR_W+:CHAR_W]=BT; ref_i[ 99*CHAR_W+:CHAR_W]=BT;
        pad_ref();
        // Load query (with left E=5 B padding)
        query_i[ 0*CHAR_W+:CHAR_W]=BB; query_i[ 1*CHAR_W+:CHAR_W]=BB;
        query_i[ 2*CHAR_W+:CHAR_W]=BB; query_i[ 3*CHAR_W+:CHAR_W]=BB;
        query_i[ 4*CHAR_W+:CHAR_W]=BB;
        // Q bases at positions E..E+99
        query_i[ 5*CHAR_W+:CHAR_W]=BA; query_i[ 6*CHAR_W+:CHAR_W]=BA;
        query_i[ 7*CHAR_W+:CHAR_W]=BA; query_i[ 8*CHAR_W+:CHAR_W]=BA;
        query_i[ 9*CHAR_W+:CHAR_W]=BA; query_i[10*CHAR_W+:CHAR_W]=BA;
        query_i[11*CHAR_W+:CHAR_W]=BA; query_i[12*CHAR_W+:CHAR_W]=BA;
        query_i[13*CHAR_W+:CHAR_W]=BA; query_i[14*CHAR_W+:CHAR_W]=BA;
        query_i[15*CHAR_W+:CHAR_W]=BA; query_i[16*CHAR_W+:CHAR_W]=BA;
        query_i[17*CHAR_W+:CHAR_W]=BT; query_i[18*CHAR_W+:CHAR_W]=BG;
        query_i[19*CHAR_W+:CHAR_W]=BA; query_i[20*CHAR_W+:CHAR_W]=BA;
        query_i[21*CHAR_W+:CHAR_W]=BA; query_i[22*CHAR_W+:CHAR_W]=BA;
        query_i[23*CHAR_W+:CHAR_W]=BA; query_i[24*CHAR_W+:CHAR_W]=BA;
        query_i[25*CHAR_W+:CHAR_W]=BT; query_i[26*CHAR_W+:CHAR_W]=BA;
        query_i[27*CHAR_W+:CHAR_W]=BA; query_i[28*CHAR_W+:CHAR_W]=BA;
        query_i[29*CHAR_W+:CHAR_W]=BA; query_i[30*CHAR_W+:CHAR_W]=BA;
        query_i[31*CHAR_W+:CHAR_W]=BG; query_i[32*CHAR_W+:CHAR_W]=BT;
        query_i[33*CHAR_W+:CHAR_W]=BT; query_i[34*CHAR_W+:CHAR_W]=BA;
        query_i[35*CHAR_W+:CHAR_W]=BT; query_i[36*CHAR_W+:CHAR_W]=BC;
        query_i[37*CHAR_W+:CHAR_W]=BT; query_i[38*CHAR_W+:CHAR_W]=BG;
        query_i[39*CHAR_W+:CHAR_W]=BG; query_i[40*CHAR_W+:CHAR_W]=BG;
        query_i[41*CHAR_W+:CHAR_W]=BC; query_i[42*CHAR_W+:CHAR_W]=BA;
        query_i[43*CHAR_W+:CHAR_W]=BT; query_i[44*CHAR_W+:CHAR_W]=BG;
        query_i[45*CHAR_W+:CHAR_W]=BG; query_i[46*CHAR_W+:CHAR_W]=BT;
        query_i[47*CHAR_W+:CHAR_W]=BG; query_i[48*CHAR_W+:CHAR_W]=BG;
        query_i[49*CHAR_W+:CHAR_W]=BC; query_i[50*CHAR_W+:CHAR_W]=BA;
        query_i[51*CHAR_W+:CHAR_W]=BC; query_i[52*CHAR_W+:CHAR_W]=BA;
        query_i[53*CHAR_W+:CHAR_W]=BC; query_i[54*CHAR_W+:CHAR_W]=BC;
        query_i[55*CHAR_W+:CHAR_W]=BT; query_i[56*CHAR_W+:CHAR_W]=BG;
        query_i[57*CHAR_W+:CHAR_W]=BT; query_i[58*CHAR_W+:CHAR_W]=BA;
        query_i[59*CHAR_W+:CHAR_W]=BG; query_i[60*CHAR_W+:CHAR_W]=BT;
        query_i[61*CHAR_W+:CHAR_W]=BC; query_i[62*CHAR_W+:CHAR_W]=BC;
        query_i[63*CHAR_W+:CHAR_W]=BC; query_i[64*CHAR_W+:CHAR_W]=BA;
        query_i[65*CHAR_W+:CHAR_W]=BG; query_i[66*CHAR_W+:CHAR_W]=BC;
        query_i[67*CHAR_W+:CHAR_W]=BT; query_i[68*CHAR_W+:CHAR_W]=BA;
        query_i[69*CHAR_W+:CHAR_W]=BC; query_i[70*CHAR_W+:CHAR_W]=BT;
        query_i[71*CHAR_W+:CHAR_W]=BG; query_i[72*CHAR_W+:CHAR_W]=BA;
        query_i[73*CHAR_W+:CHAR_W]=BG; query_i[74*CHAR_W+:CHAR_W]=BG;
        query_i[75*CHAR_W+:CHAR_W]=BA; query_i[76*CHAR_W+:CHAR_W]=BG;
        query_i[77*CHAR_W+:CHAR_W]=BG; query_i[78*CHAR_W+:CHAR_W]=BC;
        query_i[79*CHAR_W+:CHAR_W]=BA; query_i[80*CHAR_W+:CHAR_W]=BG;
        query_i[81*CHAR_W+:CHAR_W]=BG; query_i[82*CHAR_W+:CHAR_W]=BA;
        query_i[83*CHAR_W+:CHAR_W]=BA; query_i[84*CHAR_W+:CHAR_W]=BG;
        query_i[85*CHAR_W+:CHAR_W]=BA; query_i[86*CHAR_W+:CHAR_W]=BT;
        query_i[87*CHAR_W+:CHAR_W]=BT; query_i[88*CHAR_W+:CHAR_W]=BG;
        query_i[89*CHAR_W+:CHAR_W]=BC; query_i[90*CHAR_W+:CHAR_W]=BT;
        query_i[91*CHAR_W+:CHAR_W]=BT; query_i[92*CHAR_W+:CHAR_W]=BA;
        query_i[93*CHAR_W+:CHAR_W]=BA; query_i[94*CHAR_W+:CHAR_W]=BA;
        query_i[95*CHAR_W+:CHAR_W]=BC; query_i[96*CHAR_W+:CHAR_W]=BC;
        query_i[97*CHAR_W+:CHAR_W]=BT; query_i[98*CHAR_W+:CHAR_W]=BT;
        query_i[99*CHAR_W+:CHAR_W]=BB; // Q is 99 chars so last is B
        pad_query();
        run_and_check(1, 0);  // REJECT expected

        // =========================================================
        // Pair 2
        // R: TACAAGTATTGAGTCCATGCTTTCAATTCTTCCCAGGGTTGGAATTGCCGGCT
        //    CACACAGCAATTCTATATTTAACTTTTTTTTTTTTTTTTTTAGATGG
        // Q: AAAAAAAAAAAAAGAAAAGAAAAGAAAAAAGAAAAGAAAAAGAAATACAGTAAC
        //    GTGAAATCGAGCTACTTCTAACTTTTTTTTTTTTTTTTTTAGACGGA
        // Expected: REJECT
        // =========================================================
        $display("\n--- Pair 2 ---");
        $display("  R: TACAAGTATTGAGTCCATGCTTTCAATTCTTCCCAGGGTTGG...");
        $display("  Q: AAAAAAAAAAAAAGAAAAGAAAAGAAAAAAGAAAAGAAAAAGA...");
        reset_dut();
        // R: T A C A A G T A T T G A G T C C A T G C T T T C A A T T C T T C C C A G G G T T G G A A T T G C C G G C T C A C A C A G C A A T T C T A T A T T T A A C T T T T T T T T T T T T T T T T T A G A T G G
        begin : r2
            ref_i[  0*CHAR_W+:CHAR_W]=BT; ref_i[  1*CHAR_W+:CHAR_W]=BA;
            ref_i[  2*CHAR_W+:CHAR_W]=BC; ref_i[  3*CHAR_W+:CHAR_W]=BA;
            ref_i[  4*CHAR_W+:CHAR_W]=BA; ref_i[  5*CHAR_W+:CHAR_W]=BG;
            ref_i[  6*CHAR_W+:CHAR_W]=BT; ref_i[  7*CHAR_W+:CHAR_W]=BA;
            ref_i[  8*CHAR_W+:CHAR_W]=BT; ref_i[  9*CHAR_W+:CHAR_W]=BT;
            ref_i[ 10*CHAR_W+:CHAR_W]=BG; ref_i[ 11*CHAR_W+:CHAR_W]=BA;
            ref_i[ 12*CHAR_W+:CHAR_W]=BG; ref_i[ 13*CHAR_W+:CHAR_W]=BT;
            ref_i[ 14*CHAR_W+:CHAR_W]=BC; ref_i[ 15*CHAR_W+:CHAR_W]=BC;
            ref_i[ 16*CHAR_W+:CHAR_W]=BA; ref_i[ 17*CHAR_W+:CHAR_W]=BT;
            ref_i[ 18*CHAR_W+:CHAR_W]=BG; ref_i[ 19*CHAR_W+:CHAR_W]=BC;
            ref_i[ 20*CHAR_W+:CHAR_W]=BT; ref_i[ 21*CHAR_W+:CHAR_W]=BT;
            ref_i[ 22*CHAR_W+:CHAR_W]=BT; ref_i[ 23*CHAR_W+:CHAR_W]=BC;
            ref_i[ 24*CHAR_W+:CHAR_W]=BA; ref_i[ 25*CHAR_W+:CHAR_W]=BA;
            ref_i[ 26*CHAR_W+:CHAR_W]=BT; ref_i[ 27*CHAR_W+:CHAR_W]=BT;
            ref_i[ 28*CHAR_W+:CHAR_W]=BC; ref_i[ 29*CHAR_W+:CHAR_W]=BT;
            ref_i[ 30*CHAR_W+:CHAR_W]=BT; ref_i[ 31*CHAR_W+:CHAR_W]=BC;
            ref_i[ 32*CHAR_W+:CHAR_W]=BC; ref_i[ 33*CHAR_W+:CHAR_W]=BC;
            ref_i[ 34*CHAR_W+:CHAR_W]=BA; ref_i[ 35*CHAR_W+:CHAR_W]=BG;
            ref_i[ 36*CHAR_W+:CHAR_W]=BG; ref_i[ 37*CHAR_W+:CHAR_W]=BG;
            ref_i[ 38*CHAR_W+:CHAR_W]=BT; ref_i[ 39*CHAR_W+:CHAR_W]=BT;
            ref_i[ 40*CHAR_W+:CHAR_W]=BG; ref_i[ 41*CHAR_W+:CHAR_W]=BG;
            ref_i[ 42*CHAR_W+:CHAR_W]=BA; ref_i[ 43*CHAR_W+:CHAR_W]=BA;
            ref_i[ 44*CHAR_W+:CHAR_W]=BT; ref_i[ 45*CHAR_W+:CHAR_W]=BT;
            ref_i[ 46*CHAR_W+:CHAR_W]=BG; ref_i[ 47*CHAR_W+:CHAR_W]=BC;
            ref_i[ 48*CHAR_W+:CHAR_W]=BC; ref_i[ 49*CHAR_W+:CHAR_W]=BG;
            ref_i[ 50*CHAR_W+:CHAR_W]=BG; ref_i[ 51*CHAR_W+:CHAR_W]=BC;
            ref_i[ 52*CHAR_W+:CHAR_W]=BT; ref_i[ 53*CHAR_W+:CHAR_W]=BC;
            ref_i[ 54*CHAR_W+:CHAR_W]=BA; ref_i[ 55*CHAR_W+:CHAR_W]=BC;
            ref_i[ 56*CHAR_W+:CHAR_W]=BA; ref_i[ 57*CHAR_W+:CHAR_W]=BC;
            ref_i[ 58*CHAR_W+:CHAR_W]=BA; ref_i[ 59*CHAR_W+:CHAR_W]=BG;
            ref_i[ 60*CHAR_W+:CHAR_W]=BC; ref_i[ 61*CHAR_W+:CHAR_W]=BA;
            ref_i[ 62*CHAR_W+:CHAR_W]=BA; ref_i[ 63*CHAR_W+:CHAR_W]=BT;
            ref_i[ 64*CHAR_W+:CHAR_W]=BT; ref_i[ 65*CHAR_W+:CHAR_W]=BC;
            ref_i[ 66*CHAR_W+:CHAR_W]=BT; ref_i[ 67*CHAR_W+:CHAR_W]=BA;
            ref_i[ 68*CHAR_W+:CHAR_W]=BT; ref_i[ 69*CHAR_W+:CHAR_W]=BA;
            ref_i[ 70*CHAR_W+:CHAR_W]=BT; ref_i[ 71*CHAR_W+:CHAR_W]=BT;
            ref_i[ 72*CHAR_W+:CHAR_W]=BT; ref_i[ 73*CHAR_W+:CHAR_W]=BA;
            ref_i[ 74*CHAR_W+:CHAR_W]=BA; ref_i[ 75*CHAR_W+:CHAR_W]=BC;
            ref_i[ 76*CHAR_W+:CHAR_W]=BT; ref_i[ 77*CHAR_W+:CHAR_W]=BT;
            ref_i[ 78*CHAR_W+:CHAR_W]=BT; ref_i[ 79*CHAR_W+:CHAR_W]=BT;
            ref_i[ 80*CHAR_W+:CHAR_W]=BT; ref_i[ 81*CHAR_W+:CHAR_W]=BT;
            ref_i[ 82*CHAR_W+:CHAR_W]=BT; ref_i[ 83*CHAR_W+:CHAR_W]=BT;
            ref_i[ 84*CHAR_W+:CHAR_W]=BT; ref_i[ 85*CHAR_W+:CHAR_W]=BT;
            ref_i[ 86*CHAR_W+:CHAR_W]=BT; ref_i[ 87*CHAR_W+:CHAR_W]=BT;
            ref_i[ 88*CHAR_W+:CHAR_W]=BT; ref_i[ 89*CHAR_W+:CHAR_W]=BT;
            ref_i[ 90*CHAR_W+:CHAR_W]=BT; ref_i[ 91*CHAR_W+:CHAR_W]=BT;
            ref_i[ 92*CHAR_W+:CHAR_W]=BT; ref_i[ 93*CHAR_W+:CHAR_W]=BA;
            ref_i[ 94*CHAR_W+:CHAR_W]=BG; ref_i[ 95*CHAR_W+:CHAR_W]=BA;
            ref_i[ 96*CHAR_W+:CHAR_W]=BT; ref_i[ 97*CHAR_W+:CHAR_W]=BG;
            ref_i[ 98*CHAR_W+:CHAR_W]=BG; ref_i[ 99*CHAR_W+:CHAR_W]=BB; // 99 chars
            pad_ref();
        end
        // Q: A(12) A G A A A G A A A A G A A A A A G A A A A G A A A T A C A G T A A C G T G A A A T C G A G C T A C T T C T A A C T T T T T T T T T T T T T T T T T A G A C G G A
        begin : q2
            query_i[ 0*CHAR_W+:CHAR_W]=BB; query_i[ 1*CHAR_W+:CHAR_W]=BB;
            query_i[ 2*CHAR_W+:CHAR_W]=BB; query_i[ 3*CHAR_W+:CHAR_W]=BB;
            query_i[ 4*CHAR_W+:CHAR_W]=BB;
            query_i[ 5*CHAR_W+:CHAR_W]=BA; query_i[ 6*CHAR_W+:CHAR_W]=BA;
            query_i[ 7*CHAR_W+:CHAR_W]=BA; query_i[ 8*CHAR_W+:CHAR_W]=BA;
            query_i[ 9*CHAR_W+:CHAR_W]=BA; query_i[10*CHAR_W+:CHAR_W]=BA;
            query_i[11*CHAR_W+:CHAR_W]=BA; query_i[12*CHAR_W+:CHAR_W]=BA;
            query_i[13*CHAR_W+:CHAR_W]=BA; query_i[14*CHAR_W+:CHAR_W]=BA;
            query_i[15*CHAR_W+:CHAR_W]=BA; query_i[16*CHAR_W+:CHAR_W]=BA;
            query_i[17*CHAR_W+:CHAR_W]=BA; query_i[18*CHAR_W+:CHAR_W]=BG;
            query_i[19*CHAR_W+:CHAR_W]=BA; query_i[20*CHAR_W+:CHAR_W]=BA;
            query_i[21*CHAR_W+:CHAR_W]=BA; query_i[22*CHAR_W+:CHAR_W]=BG;
            query_i[23*CHAR_W+:CHAR_W]=BA; query_i[24*CHAR_W+:CHAR_W]=BA;
            query_i[25*CHAR_W+:CHAR_W]=BA; query_i[26*CHAR_W+:CHAR_W]=BA;
            query_i[27*CHAR_W+:CHAR_W]=BG; query_i[28*CHAR_W+:CHAR_W]=BA;
            query_i[29*CHAR_W+:CHAR_W]=BA; query_i[30*CHAR_W+:CHAR_W]=BA;
            query_i[31*CHAR_W+:CHAR_W]=BA; query_i[32*CHAR_W+:CHAR_W]=BA;
            query_i[33*CHAR_W+:CHAR_W]=BG; query_i[34*CHAR_W+:CHAR_W]=BA;
            query_i[35*CHAR_W+:CHAR_W]=BA; query_i[36*CHAR_W+:CHAR_W]=BA;
            query_i[37*CHAR_W+:CHAR_W]=BG; query_i[38*CHAR_W+:CHAR_W]=BA;
            query_i[39*CHAR_W+:CHAR_W]=BA; query_i[40*CHAR_W+:CHAR_W]=BA;
            query_i[41*CHAR_W+:CHAR_W]=BA; query_i[42*CHAR_W+:CHAR_W]=BA;
            query_i[43*CHAR_W+:CHAR_W]=BG; query_i[44*CHAR_W+:CHAR_W]=BA;
            query_i[45*CHAR_W+:CHAR_W]=BA; query_i[46*CHAR_W+:CHAR_W]=BA;
            query_i[47*CHAR_W+:CHAR_W]=BT; query_i[48*CHAR_W+:CHAR_W]=BA;
            query_i[49*CHAR_W+:CHAR_W]=BC; query_i[50*CHAR_W+:CHAR_W]=BA;
            query_i[51*CHAR_W+:CHAR_W]=BG; query_i[52*CHAR_W+:CHAR_W]=BT;
            query_i[53*CHAR_W+:CHAR_W]=BA; query_i[54*CHAR_W+:CHAR_W]=BA;
            query_i[55*CHAR_W+:CHAR_W]=BC; query_i[56*CHAR_W+:CHAR_W]=BG;
            query_i[57*CHAR_W+:CHAR_W]=BT; query_i[58*CHAR_W+:CHAR_W]=BG;
            query_i[59*CHAR_W+:CHAR_W]=BA; query_i[60*CHAR_W+:CHAR_W]=BA;
            query_i[61*CHAR_W+:CHAR_W]=BA; query_i[62*CHAR_W+:CHAR_W]=BT;
            query_i[63*CHAR_W+:CHAR_W]=BC; query_i[64*CHAR_W+:CHAR_W]=BG;
            query_i[65*CHAR_W+:CHAR_W]=BA; query_i[66*CHAR_W+:CHAR_W]=BG;
            query_i[67*CHAR_W+:CHAR_W]=BC; query_i[68*CHAR_W+:CHAR_W]=BT;
            query_i[69*CHAR_W+:CHAR_W]=BA; query_i[70*CHAR_W+:CHAR_W]=BC;
            query_i[71*CHAR_W+:CHAR_W]=BT; query_i[72*CHAR_W+:CHAR_W]=BT;
            query_i[73*CHAR_W+:CHAR_W]=BC; query_i[74*CHAR_W+:CHAR_W]=BT;
            query_i[75*CHAR_W+:CHAR_W]=BA; query_i[76*CHAR_W+:CHAR_W]=BA;
            query_i[77*CHAR_W+:CHAR_W]=BC; query_i[78*CHAR_W+:CHAR_W]=BT;
            query_i[79*CHAR_W+:CHAR_W]=BT; query_i[80*CHAR_W+:CHAR_W]=BT;
            query_i[81*CHAR_W+:CHAR_W]=BT; query_i[82*CHAR_W+:CHAR_W]=BT;
            query_i[83*CHAR_W+:CHAR_W]=BT; query_i[84*CHAR_W+:CHAR_W]=BT;
            query_i[85*CHAR_W+:CHAR_W]=BT; query_i[86*CHAR_W+:CHAR_W]=BT;
            query_i[87*CHAR_W+:CHAR_W]=BT; query_i[88*CHAR_W+:CHAR_W]=BT;
            query_i[89*CHAR_W+:CHAR_W]=BT; query_i[90*CHAR_W+:CHAR_W]=BT;
            query_i[91*CHAR_W+:CHAR_W]=BT; query_i[92*CHAR_W+:CHAR_W]=BT;
            query_i[93*CHAR_W+:CHAR_W]=BT; query_i[94*CHAR_W+:CHAR_W]=BA;
            query_i[95*CHAR_W+:CHAR_W]=BG; query_i[96*CHAR_W+:CHAR_W]=BA;
            query_i[97*CHAR_W+:CHAR_W]=BC; query_i[98*CHAR_W+:CHAR_W]=BG;
            query_i[99*CHAR_W+:CHAR_W]=BG; query_i[100*CHAR_W+:CHAR_W]=BA;
            pad_query();
        end
        run_and_check(2, 0);  // REJECT expected

        // =========================================================
        // Pair 3: Identical sequences
        // R = Q = AAAAAAAAAAAAAAAAAAGGAATATTCCTTTTCCAGGATTATTATGAAGAT
        //         TCAATAAAACCATGTTTATTAAGTGTTAAGCACAGTGCCTGGCACATAA
        // Expected: ACCEPT (identical → 0 obstacles)
        // =========================================================
        $display("\n--- Pair 3 (identical) ---");
        $display("  R=Q: AAAAAAAAAAAAAAAAAAGGAATATTCCTTTTCCAGGATT...");
        reset_dut();
        begin : r3
            // A(18) G G A A T A T T C C T T T T C C A G G A T T A T T A T G A A G A T T C A A T A A A A C C A T G T T T A T T A A G T G T T A A G C A C A G T G C C T G G C A C A T A A
            ref_i[ 0*CHAR_W+:CHAR_W]=BA; ref_i[ 1*CHAR_W+:CHAR_W]=BA;
            ref_i[ 2*CHAR_W+:CHAR_W]=BA; ref_i[ 3*CHAR_W+:CHAR_W]=BA;
            ref_i[ 4*CHAR_W+:CHAR_W]=BA; ref_i[ 5*CHAR_W+:CHAR_W]=BA;
            ref_i[ 6*CHAR_W+:CHAR_W]=BA; ref_i[ 7*CHAR_W+:CHAR_W]=BA;
            ref_i[ 8*CHAR_W+:CHAR_W]=BA; ref_i[ 9*CHAR_W+:CHAR_W]=BA;
            ref_i[10*CHAR_W+:CHAR_W]=BA; ref_i[11*CHAR_W+:CHAR_W]=BA;
            ref_i[12*CHAR_W+:CHAR_W]=BA; ref_i[13*CHAR_W+:CHAR_W]=BA;
            ref_i[14*CHAR_W+:CHAR_W]=BA; ref_i[15*CHAR_W+:CHAR_W]=BA;
            ref_i[16*CHAR_W+:CHAR_W]=BA; ref_i[17*CHAR_W+:CHAR_W]=BA;
            ref_i[18*CHAR_W+:CHAR_W]=BG; ref_i[19*CHAR_W+:CHAR_W]=BG;
            ref_i[20*CHAR_W+:CHAR_W]=BA; ref_i[21*CHAR_W+:CHAR_W]=BA;
            ref_i[22*CHAR_W+:CHAR_W]=BT; ref_i[23*CHAR_W+:CHAR_W]=BA;
            ref_i[24*CHAR_W+:CHAR_W]=BT; ref_i[25*CHAR_W+:CHAR_W]=BT;
            ref_i[26*CHAR_W+:CHAR_W]=BC; ref_i[27*CHAR_W+:CHAR_W]=BC;
            ref_i[28*CHAR_W+:CHAR_W]=BT; ref_i[29*CHAR_W+:CHAR_W]=BT;
            ref_i[30*CHAR_W+:CHAR_W]=BT; ref_i[31*CHAR_W+:CHAR_W]=BT;
            ref_i[32*CHAR_W+:CHAR_W]=BC; ref_i[33*CHAR_W+:CHAR_W]=BC;
            ref_i[34*CHAR_W+:CHAR_W]=BA; ref_i[35*CHAR_W+:CHAR_W]=BG;
            ref_i[36*CHAR_W+:CHAR_W]=BG; ref_i[37*CHAR_W+:CHAR_W]=BA;
            ref_i[38*CHAR_W+:CHAR_W]=BT; ref_i[39*CHAR_W+:CHAR_W]=BT;
            ref_i[40*CHAR_W+:CHAR_W]=BA; ref_i[41*CHAR_W+:CHAR_W]=BT;
            ref_i[42*CHAR_W+:CHAR_W]=BT; ref_i[43*CHAR_W+:CHAR_W]=BA;
            ref_i[44*CHAR_W+:CHAR_W]=BT; ref_i[45*CHAR_W+:CHAR_W]=BG;
            ref_i[46*CHAR_W+:CHAR_W]=BA; ref_i[47*CHAR_W+:CHAR_W]=BA;
            ref_i[48*CHAR_W+:CHAR_W]=BG; ref_i[49*CHAR_W+:CHAR_W]=BA;
            ref_i[50*CHAR_W+:CHAR_W]=BT; ref_i[51*CHAR_W+:CHAR_W]=BT;
            ref_i[52*CHAR_W+:CHAR_W]=BC; ref_i[53*CHAR_W+:CHAR_W]=BA;
            ref_i[54*CHAR_W+:CHAR_W]=BA; ref_i[55*CHAR_W+:CHAR_W]=BT;
            ref_i[56*CHAR_W+:CHAR_W]=BA; ref_i[57*CHAR_W+:CHAR_W]=BA;
            ref_i[58*CHAR_W+:CHAR_W]=BA; ref_i[59*CHAR_W+:CHAR_W]=BA;
            ref_i[60*CHAR_W+:CHAR_W]=BC; ref_i[61*CHAR_W+:CHAR_W]=BC;
            ref_i[62*CHAR_W+:CHAR_W]=BA; ref_i[63*CHAR_W+:CHAR_W]=BT;
            ref_i[64*CHAR_W+:CHAR_W]=BG; ref_i[65*CHAR_W+:CHAR_W]=BT;
            ref_i[66*CHAR_W+:CHAR_W]=BT; ref_i[67*CHAR_W+:CHAR_W]=BT;
            ref_i[68*CHAR_W+:CHAR_W]=BA; ref_i[69*CHAR_W+:CHAR_W]=BT;
            ref_i[70*CHAR_W+:CHAR_W]=BT; ref_i[71*CHAR_W+:CHAR_W]=BA;
            ref_i[72*CHAR_W+:CHAR_W]=BA; ref_i[73*CHAR_W+:CHAR_W]=BG;
            ref_i[74*CHAR_W+:CHAR_W]=BT; ref_i[75*CHAR_W+:CHAR_W]=BG;
            ref_i[76*CHAR_W+:CHAR_W]=BT; ref_i[77*CHAR_W+:CHAR_W]=BT;
            ref_i[78*CHAR_W+:CHAR_W]=BA; ref_i[79*CHAR_W+:CHAR_W]=BA;
            ref_i[80*CHAR_W+:CHAR_W]=BG; ref_i[81*CHAR_W+:CHAR_W]=BC;
            ref_i[82*CHAR_W+:CHAR_W]=BA; ref_i[83*CHAR_W+:CHAR_W]=BC;
            ref_i[84*CHAR_W+:CHAR_W]=BA; ref_i[85*CHAR_W+:CHAR_W]=BG;
            ref_i[86*CHAR_W+:CHAR_W]=BT; ref_i[87*CHAR_W+:CHAR_W]=BG;
            ref_i[88*CHAR_W+:CHAR_W]=BC; ref_i[89*CHAR_W+:CHAR_W]=BC;
            ref_i[90*CHAR_W+:CHAR_W]=BT; ref_i[91*CHAR_W+:CHAR_W]=BG;
            ref_i[92*CHAR_W+:CHAR_W]=BG; ref_i[93*CHAR_W+:CHAR_W]=BC;
            ref_i[94*CHAR_W+:CHAR_W]=BA; ref_i[95*CHAR_W+:CHAR_W]=BC;
            ref_i[96*CHAR_W+:CHAR_W]=BA; ref_i[97*CHAR_W+:CHAR_W]=BT;
            ref_i[98*CHAR_W+:CHAR_W]=BA; ref_i[99*CHAR_W+:CHAR_W]=BA;
            pad_ref();
        end
        // Query = identical to ref, just with E=5 left padding
        begin : q3
            integer k;
            for (k = 0; k < E; k = k+1)
                query_i[k*CHAR_W +: CHAR_W] = BB;
            for (k = 0; k < SEQ_LEN; k = k+1)
                query_i[(E+k)*CHAR_W +: CHAR_W] = ref_i[k*CHAR_W +: CHAR_W];
            pad_query();
        end
        run_and_check(3, 1);  // ACCEPT expected (identical)

        // =========================================================
        // Pair 4
        // R: GAAAAAAAAAAAAATCCATTTTAAGGGGCACCAAGTTGTTAGCCTTCCAGGATG
        //    CTCACAGTTTTGGTCTAGCCCTGATCCTAGAGGGCAAATCACAGCA
        // Q: AAAAAAAAAAAAAATCCATTTTAAGGGGCACCAAGTTGTTAGCCTTCCAGGATG
        //    CTCACAGTTTTGGTCTAGCCCTGATCCTAGAGGGCAAATCACAGCG
        // Only 2 differences: pos0 G→A, pos99 A→G
        // Expected: ACCEPT
        // =========================================================
        $display("\n--- Pair 4 (2 differences) ---");
        $display("  R: GAAAAAAAAAAAAATCCATTTTAAGGGGCACCAAGTTGTTAGC...");
        $display("  Q: AAAAAAAAAAAAAATCCATTTTAAGGGGCACCAAGTTGTTAGC...");
        reset_dut();
        begin : r4
            ref_i[ 0*CHAR_W+:CHAR_W]=BG; // only difference at pos 0
            ref_i[ 1*CHAR_W+:CHAR_W]=BA; ref_i[ 2*CHAR_W+:CHAR_W]=BA;
            ref_i[ 3*CHAR_W+:CHAR_W]=BA; ref_i[ 4*CHAR_W+:CHAR_W]=BA;
            ref_i[ 5*CHAR_W+:CHAR_W]=BA; ref_i[ 6*CHAR_W+:CHAR_W]=BA;
            ref_i[ 7*CHAR_W+:CHAR_W]=BA; ref_i[ 8*CHAR_W+:CHAR_W]=BA;
            ref_i[ 9*CHAR_W+:CHAR_W]=BA; ref_i[10*CHAR_W+:CHAR_W]=BA;
            ref_i[11*CHAR_W+:CHAR_W]=BA; ref_i[12*CHAR_W+:CHAR_W]=BA;
            ref_i[13*CHAR_W+:CHAR_W]=BA; ref_i[14*CHAR_W+:CHAR_W]=BT;
            ref_i[15*CHAR_W+:CHAR_W]=BC; ref_i[16*CHAR_W+:CHAR_W]=BC;
            ref_i[17*CHAR_W+:CHAR_W]=BA; ref_i[18*CHAR_W+:CHAR_W]=BT;
            ref_i[19*CHAR_W+:CHAR_W]=BT; ref_i[20*CHAR_W+:CHAR_W]=BT;
            ref_i[21*CHAR_W+:CHAR_W]=BT; ref_i[22*CHAR_W+:CHAR_W]=BA;
            ref_i[23*CHAR_W+:CHAR_W]=BA; ref_i[24*CHAR_W+:CHAR_W]=BG;
            ref_i[25*CHAR_W+:CHAR_W]=BG; ref_i[26*CHAR_W+:CHAR_W]=BG;
            ref_i[27*CHAR_W+:CHAR_W]=BG; ref_i[28*CHAR_W+:CHAR_W]=BC;
            ref_i[29*CHAR_W+:CHAR_W]=BA; ref_i[30*CHAR_W+:CHAR_W]=BC;
            ref_i[31*CHAR_W+:CHAR_W]=BC; ref_i[32*CHAR_W+:CHAR_W]=BA;
            ref_i[33*CHAR_W+:CHAR_W]=BA; ref_i[34*CHAR_W+:CHAR_W]=BG;
            ref_i[35*CHAR_W+:CHAR_W]=BT; ref_i[36*CHAR_W+:CHAR_W]=BT;
            ref_i[37*CHAR_W+:CHAR_W]=BG; ref_i[38*CHAR_W+:CHAR_W]=BT;
            ref_i[39*CHAR_W+:CHAR_W]=BT; ref_i[40*CHAR_W+:CHAR_W]=BA;
            ref_i[41*CHAR_W+:CHAR_W]=BG; ref_i[42*CHAR_W+:CHAR_W]=BC;
            ref_i[43*CHAR_W+:CHAR_W]=BC; ref_i[44*CHAR_W+:CHAR_W]=BT;
            ref_i[45*CHAR_W+:CHAR_W]=BT; ref_i[46*CHAR_W+:CHAR_W]=BC;
            ref_i[47*CHAR_W+:CHAR_W]=BC; ref_i[48*CHAR_W+:CHAR_W]=BA;
            ref_i[49*CHAR_W+:CHAR_W]=BG; ref_i[50*CHAR_W+:CHAR_W]=BG;
            ref_i[51*CHAR_W+:CHAR_W]=BA; ref_i[52*CHAR_W+:CHAR_W]=BT;
            ref_i[53*CHAR_W+:CHAR_W]=BG; ref_i[54*CHAR_W+:CHAR_W]=BC;
            ref_i[55*CHAR_W+:CHAR_W]=BT; ref_i[56*CHAR_W+:CHAR_W]=BC;
            ref_i[57*CHAR_W+:CHAR_W]=BA; ref_i[58*CHAR_W+:CHAR_W]=BC;
            ref_i[59*CHAR_W+:CHAR_W]=BA; ref_i[60*CHAR_W+:CHAR_W]=BG;
            ref_i[61*CHAR_W+:CHAR_W]=BT; ref_i[62*CHAR_W+:CHAR_W]=BT;
            ref_i[63*CHAR_W+:CHAR_W]=BT; ref_i[64*CHAR_W+:CHAR_W]=BT;
            ref_i[65*CHAR_W+:CHAR_W]=BG; ref_i[66*CHAR_W+:CHAR_W]=BG;
            ref_i[67*CHAR_W+:CHAR_W]=BT; ref_i[68*CHAR_W+:CHAR_W]=BC;
            ref_i[69*CHAR_W+:CHAR_W]=BT; ref_i[70*CHAR_W+:CHAR_W]=BA;
            ref_i[71*CHAR_W+:CHAR_W]=BG; ref_i[72*CHAR_W+:CHAR_W]=BC;
            ref_i[73*CHAR_W+:CHAR_W]=BC; ref_i[74*CHAR_W+:CHAR_W]=BC;
            ref_i[75*CHAR_W+:CHAR_W]=BT; ref_i[76*CHAR_W+:CHAR_W]=BG;
            ref_i[77*CHAR_W+:CHAR_W]=BA; ref_i[78*CHAR_W+:CHAR_W]=BT;
            ref_i[79*CHAR_W+:CHAR_W]=BC; ref_i[80*CHAR_W+:CHAR_W]=BC;
            ref_i[81*CHAR_W+:CHAR_W]=BT; ref_i[82*CHAR_W+:CHAR_W]=BA;
            ref_i[83*CHAR_W+:CHAR_W]=BG; ref_i[84*CHAR_W+:CHAR_W]=BA;
            ref_i[85*CHAR_W+:CHAR_W]=BG; ref_i[86*CHAR_W+:CHAR_W]=BG;
            ref_i[87*CHAR_W+:CHAR_W]=BG; ref_i[88*CHAR_W+:CHAR_W]=BC;
            ref_i[89*CHAR_W+:CHAR_W]=BA; ref_i[90*CHAR_W+:CHAR_W]=BA;
            ref_i[91*CHAR_W+:CHAR_W]=BA; ref_i[92*CHAR_W+:CHAR_W]=BT;
            ref_i[93*CHAR_W+:CHAR_W]=BC; ref_i[94*CHAR_W+:CHAR_W]=BA;
            ref_i[95*CHAR_W+:CHAR_W]=BC; ref_i[96*CHAR_W+:CHAR_W]=BA;
            ref_i[97*CHAR_W+:CHAR_W]=BG; ref_i[98*CHAR_W+:CHAR_W]=BC;
            ref_i[99*CHAR_W+:CHAR_W]=BA; // pos99 = A in R
            pad_ref();
        end
        begin : q4
            integer k;
            // Left E padding
            for (k = 0; k < E; k = k+1)
                query_i[k*CHAR_W +: CHAR_W] = BB;
            // Copy ref but pos0 = A (not G), pos99 = G (not A)
            for (k = 0; k < SEQ_LEN; k = k+1)
                query_i[(E+k)*CHAR_W +: CHAR_W] = ref_i[k*CHAR_W +: CHAR_W];
            query_i[(E+0)*CHAR_W +: CHAR_W] = BA;  // pos0: G→A
            query_i[(E+99)*CHAR_W +: CHAR_W] = BG; // pos99: A→G
            pad_query();
        end
        run_and_check(4, 1);  // ACCEPT expected (only 2 differences)

        // =========================================================
        // Summary
        // =========================================================
        $display("\n============================================================");
        $display("  RESULTS SUMMARY");
        $display("============================================================");
        $display("  Total pairs     : 4");
        $display("  Accepted (ALIGN): %0d", total_accepted);
        $display("  Rejected (SKIP) : %0d", total_rejected);
        $display("  Tests passed    : %0d / 4", pass_count);
        $display("  Tests failed    : %0d / 4", fail_count);
        $display("  Filtering rate  : %0d / 4 pairs rejected",
                 total_rejected);
        if (fail_count == 0)
            $display("  >>> ALL PASSED <<<");
        else
            $display("  >>> FAILURES DETECTED <<<");
        $display("============================================================");
        $finish;
    end

endmodule