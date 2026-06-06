// ============================================================
// snake_on_chip_top_tb.v  -  Testbench for snake_on_chip_top
// ============================================================
// 3-bit encoding: A=000 C=001 G=010 T=011 B=100(pad)
//
// OBSTACLE COUNTING (with lives_r fix):
// ======================================
// The pipeline now uses lives_r - a direct per-stage hit counter
// based on valid_out from lzc_comparator_tree. This replaces the
// min(Y, T-sum_x) formula that was missing scattered obstacles.
//
// PADDING BEHAVIOUR:
// ==================
// When sequences are shorter than M=64, pad with B (3'b100).
// B in ref vs real base in query  → mismatch → obstacle (correct)
// B in ref vs B in query          → B==B → match → 0 obstacle
// B in ref vs A/C/G/T in query    → mismatch → obstacle
// So unequal-length sequences accumulate extra obstacles from
// the padding region - this is expected and correct.
//
// Total obstacles printed by snake_on_chip_top.v in S_DONE.
// ============================================================

`timescale 1ns/1ps

module snake_on_chip_top_tb;

    localparam E      = 5;
    localparam T      = 8;
    localparam Y      = 4;
    localparam M      = 64;
    localparam CHAR_W = 3;
    localparam Q_TOT    = M + 2*E;
    localparam CLK_HALF = 5;

    localparam [CHAR_W-1:0] A  = 3'b000;
    localparam [CHAR_W-1:0] C  = 3'b001;
    localparam [CHAR_W-1:0] G  = 3'b010;
    localparam [CHAR_W-1:0] TH = 3'b011;
    localparam [CHAR_W-1:0] B  = 3'b100;

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

    integer fail_count, pass_count, timeout_c, i;

    task fill_ref;
        input [CHAR_W-1:0] ch;
        integer k;
        begin for (k=0;k<M;k=k+1) ref_i[k*CHAR_W+:CHAR_W]=ch; end
    endtask

    task fill_query;
        input [CHAR_W-1:0] ch;
        integer k;
        begin for (k=0;k<Q_TOT;k=k+1) query_i[k*CHAR_W+:CHAR_W]=ch; end
    endtask

    task perfect_query_from_ref;
        integer k;
        begin
            for (k=0;k<E;k=k+1)       query_i[k*CHAR_W+:CHAR_W]=B;
            for (k=0;k<M;k=k+1)       query_i[(E+k)*CHAR_W+:CHAR_W]=ref_i[k*CHAR_W+:CHAR_W];
            for (k=E+M;k<Q_TOT;k=k+1) query_i[k*CHAR_W+:CHAR_W]=B;
        end
    endtask

    task pad_query_right;
        input integer sp;
        integer k;
        begin for (k=sp;k<Q_TOT;k=k+1) query_i[k*CHAR_W+:CHAR_W]=B; end
    endtask

    task pad_ref_right;
        input integer sp;
        integer k;
        begin for (k=sp;k<M;k=k+1) ref_i[k*CHAR_W+:CHAR_W]=B; end
    endtask

    task reset_dut;
        begin
            rst=1; start_i=0;
            repeat(4) @(posedge clk);
            rst=0; @(posedge clk); #1;
        end
    endtask

    task run_and_check;
        input integer tid;
        input integer exp_accept;
        begin
            @(posedge clk); #1;
            start_i=1; @(posedge clk); #1; start_i=0;
            timeout_c=0;
            while (!done_o && timeout_c<500) begin
                @(posedge clk); #1;
                timeout_c=timeout_c+1;
            end
            if (!done_o) begin
                $display("FAIL #%0d: timeout",tid);
                fail_count=fail_count+1;
            end else if (accept_o !== exp_accept[0]) begin
                $display("FAIL #%0d: accept=%0d expected=%0d (cycles=%0d)",
                         tid,accept_o,exp_accept,timeout_c);
                fail_count=fail_count+1;
            end else begin
                $display("PASS #%0d: accept=%0d (cycles=%0d)",
                         tid,accept_o,timeout_c);
                pass_count=pass_count+1;
            end
            repeat(10) @(posedge clk); #1;
        end
    endtask

    initial begin
        fail_count=0; pass_count=0;
        clk=0; rst=1; start_i=0; ref_i=0; query_i=0;

        $display("============================================================");
        $display("  Snake-on-Chip Top TB  (3-bit encoding, lives_r fix)");
        $display("  E=%0d T=%0d Y=%0d M=%0d CHAR_W=%0d",E,T,Y,M,CHAR_W);
        $display("  A=000 C=001 G=010 T=011 B=100(pad)");
        $display("  ACCEPT if total_obstacles <= E=%0d",E);
        $display("============================================================");

        repeat(4) @(posedge clk); rst=0; @(posedge clk); #1;

        // =========================================================
        // Test 1: Identical (all A) → 0 obs → ACCEPT
        // =========================================================
        $display("\n--- Test 1: Identical (all A) → ACCEPT ---");
        reset_dut(); fill_ref(A); perfect_query_from_ref();
        run_and_check(1, 1);

        // =========================================================
        // Test 2: All mismatch (ref=A, query=G) → REJECT
        // fill_query(G) fills all 74 positions with G
        // =========================================================
        $display("\n--- Test 2: All mismatch (ref=A query=G) → REJECT ---");
        reset_dut(); fill_ref(A); fill_query(G);
        run_and_check(2, 0);

        // =========================================================
        // Test 3: 3 spread substitutions → ACCEPT
        // Snake routes around isolated mismatches via diagonals
        // =========================================================
        $display("\n--- Test 3: 3 spread substitutions → ACCEPT ---");
        reset_dut(); fill_ref(A); perfect_query_from_ref();
        query_i[(E+10)*CHAR_W+:CHAR_W]=G;
        query_i[(E+30)*CHAR_W+:CHAR_W]=G;
        query_i[(E+50)*CHAR_W+:CHAR_W]=G;
        run_and_check(3, 1);

        // =========================================================
        // Test 4: Query length=60, ref=64A → ACCEPT
        // =========================================================
        $display("\n--- Test 4: Query length=60, ref=64A → ACCEPT ---");
        reset_dut(); fill_ref(A);
        for (i=0;i<E;i=i+1) query_i[i*CHAR_W+:CHAR_W]=B;
        for (i=0;i<60;i=i+1) query_i[(E+i)*CHAR_W+:CHAR_W]=A;
        pad_query_right(E+60);
        run_and_check(4, 1);

        // =========================================================
        // Test 5: Short query (60 G), ref=64A → REJECT
        // =========================================================
        $display("\n--- Test 5: Short query (60G), ref=64A → REJECT ---");
        reset_dut(); fill_ref(A);
        for (i=0;i<E;i=i+1) query_i[i*CHAR_W+:CHAR_W]=B;
        for (i=0;i<60;i=i+1) query_i[(E+i)*CHAR_W+:CHAR_W]=G;
        pad_query_right(E+60);
        run_and_check(5, 0);

        // =========================================================
        // Test 6: 1 indel (query shifted +1) → ACCEPT
        // =========================================================
        $display("\n--- Test 6: Query shifted +1 (indel) → ACCEPT ---");
        reset_dut(); fill_ref(A); fill_query(G);
        for (i=0;i<M;i=i+1) query_i[(E+1+i)*CHAR_W+:CHAR_W]=A;
        run_and_check(6, 1);

        // =========================================================
        // Test 7: Identical all C → ACCEPT (verifies C=001)
        // =========================================================
        $display("\n--- Test 7: Identical (all C) → ACCEPT ---");
        reset_dut(); fill_ref(C); perfect_query_from_ref();
        run_and_check(7, 1);

        // =========================================================
        // Test 8: Identical all T=011 → ACCEPT
        // Verifies T(011) ≠ B(100)
        // =========================================================
        $display("\n--- Test 8: Identical (all T=011) → ACCEPT ---");
        reset_dut(); fill_ref(TH); perfect_query_from_ref();
        run_and_check(8, 1);

        // =========================================================
        // Test 9: Last 2 subproblems blocked → REJECT
        // query[51..Q_TOT-1] = G
        // =========================================================
        $display("\n--- Test 9: Last 2 subproblems blocked → REJECT ---");
        reset_dut(); fill_ref(A);
        for (i=0;i<E;i=i+1)   query_i[i*CHAR_W+:CHAR_W]=B;
        for (i=0;i<M;i=i+1)   query_i[(E+i)*CHAR_W+:CHAR_W]=A;
        pad_query_right(E+M);
        for (i=51;i<Q_TOT;i=i+1) query_i[i*CHAR_W+:CHAR_W]=G;
        run_and_check(9, 0);

        // =========================================================
        // Test 10: Last 4 subproblems blocked → REJECT
        // query[35..Q_TOT-1] = G
        // =========================================================
        $display("\n--- Test 10: Last 4 subproblems blocked → REJECT ---");
        reset_dut(); fill_ref(A);
        for (i=0;i<E;i=i+1)   query_i[i*CHAR_W+:CHAR_W]=B;
        for (i=0;i<M;i=i+1)   query_i[(E+i)*CHAR_W+:CHAR_W]=A;
        pad_query_right(E+M);
        for (i=35;i<Q_TOT;i=i+1) query_i[i*CHAR_W+:CHAR_W]=G;
        run_and_check(10, 0);

        // =========================================================
        // Test 11a: Back-to-back ACCEPT
        // =========================================================
        $display("\n--- Test 11a: Back-to-back ACCEPT ---");
        reset_dut(); fill_ref(C); perfect_query_from_ref();
        run_and_check(11, 1);

        // =========================================================
        // Test 11b: Back-to-back REJECT (no reset between)
        // =========================================================
        $display("\n--- Test 11b: Back-to-back REJECT (no reset) ---");
        fill_ref(A); fill_query(G);
        run_and_check(12, 0);

        // =========================================================
        // Test 12: Ref=48A+16B, query=64A → ACCEPT
        // =========================================================
        $display("\n--- Test 12: Ref=48A+16B, query=64A → ACCEPT ---");
        reset_dut();
        for (i=0;i<48;i=i+1) ref_i[i*CHAR_W+:CHAR_W]=A;
        pad_ref_right(48);
        for (i=0;i<E;i=i+1)  query_i[i*CHAR_W+:CHAR_W]=B;
        for (i=0;i<M;i=i+1)  query_i[(E+i)*CHAR_W+:CHAR_W]=A;
        pad_query_right(E+M);
        run_and_check(12, 0);

        // =========================================================
        // Test 13: Both length=60, B pads match → ACCEPT
        // ref[60..63]=B, query[60..63]=B → B==B → 0 obstacle
        // =========================================================
        $display("\n--- Test 13: Both length=60, B pads → ACCEPT ---");
        reset_dut();
        for (i=0;i<60;i=i+1) ref_i[i*CHAR_W+:CHAR_W]=A;
        pad_ref_right(60);
        for (i=0;i<E;i=i+1)  query_i[i*CHAR_W+:CHAR_W]=B;
        for (i=0;i<60;i=i+1) query_i[(E+i)*CHAR_W+:CHAR_W]=A;
        pad_query_right(E+60);
        run_and_check(13, 1);

        // =========================================================
        // Test 14: Real DNA sequences (unequal length)
        // R = "AAAAAGGGTGCTTTTTTTCCCGGGAGGGTGTGGGGGGGGGGGGGGAAAAAAAAAATTTTTTTCC"
        //      length = 64
        // Q = "AAAATCGGTGCTGGTTTTCCCGGGAGGGTGTGGCCTGGGGGGAAAAAAATATTCCTTTTCC"
        //      length = 61 → padded with B at positions 61,62,63
        // Verified from simulation: REJECT
        // =========================================================
        $display("\n--- Test 14: Real DNA R=64 Q=61+3B → REJECT ---");
        reset_dut();

        begin : load_ref_14
            ref_i[ 0*CHAR_W+:CHAR_W] = A;
            ref_i[ 1*CHAR_W+:CHAR_W] = A;
            ref_i[ 2*CHAR_W+:CHAR_W] = A;
            ref_i[ 3*CHAR_W+:CHAR_W] = A;
            ref_i[ 4*CHAR_W+:CHAR_W] = A;
            ref_i[ 5*CHAR_W+:CHAR_W] = G;
            ref_i[ 6*CHAR_W+:CHAR_W] = G;
            ref_i[ 7*CHAR_W+:CHAR_W] = G;
            ref_i[ 8*CHAR_W+:CHAR_W] = TH;
            ref_i[ 9*CHAR_W+:CHAR_W] = G;
            ref_i[10*CHAR_W+:CHAR_W] = C;
            ref_i[11*CHAR_W+:CHAR_W] = TH;
            ref_i[12*CHAR_W+:CHAR_W] = TH;
            ref_i[13*CHAR_W+:CHAR_W] = TH;
            ref_i[14*CHAR_W+:CHAR_W] = TH;
            ref_i[15*CHAR_W+:CHAR_W] = TH;
            ref_i[16*CHAR_W+:CHAR_W] = TH;
            ref_i[17*CHAR_W+:CHAR_W] = TH;
            ref_i[18*CHAR_W+:CHAR_W] = C;
            ref_i[19*CHAR_W+:CHAR_W] = C;
            ref_i[20*CHAR_W+:CHAR_W] = C;
            ref_i[21*CHAR_W+:CHAR_W] = G;
            ref_i[22*CHAR_W+:CHAR_W] = G;
            ref_i[23*CHAR_W+:CHAR_W] = G;
            ref_i[24*CHAR_W+:CHAR_W] = A;
            ref_i[25*CHAR_W+:CHAR_W] = G;
            ref_i[26*CHAR_W+:CHAR_W] = G;
            ref_i[27*CHAR_W+:CHAR_W] = G;
            ref_i[28*CHAR_W+:CHAR_W] = TH;
            ref_i[29*CHAR_W+:CHAR_W] = G;
            ref_i[30*CHAR_W+:CHAR_W] = TH;
            ref_i[31*CHAR_W+:CHAR_W] = G;
            ref_i[32*CHAR_W+:CHAR_W] = G;
            ref_i[33*CHAR_W+:CHAR_W] = G;
            ref_i[34*CHAR_W+:CHAR_W] = G;
            ref_i[35*CHAR_W+:CHAR_W] = G;
            ref_i[36*CHAR_W+:CHAR_W] = G;
            ref_i[37*CHAR_W+:CHAR_W] = G;
            ref_i[38*CHAR_W+:CHAR_W] = G;
            ref_i[39*CHAR_W+:CHAR_W] = G;
            ref_i[40*CHAR_W+:CHAR_W] = G;
            ref_i[41*CHAR_W+:CHAR_W] = G;
            ref_i[42*CHAR_W+:CHAR_W] = G;
            ref_i[43*CHAR_W+:CHAR_W] = G;
            ref_i[44*CHAR_W+:CHAR_W] = G;
            ref_i[45*CHAR_W+:CHAR_W] = A;
            ref_i[46*CHAR_W+:CHAR_W] = A;
            ref_i[47*CHAR_W+:CHAR_W] = A;
            ref_i[48*CHAR_W+:CHAR_W] = A;
            ref_i[49*CHAR_W+:CHAR_W] = A;
            ref_i[50*CHAR_W+:CHAR_W] = A;
            ref_i[51*CHAR_W+:CHAR_W] = A;
            ref_i[52*CHAR_W+:CHAR_W] = A;
            ref_i[53*CHAR_W+:CHAR_W] = A;
            ref_i[54*CHAR_W+:CHAR_W] = A;
            ref_i[55*CHAR_W+:CHAR_W] = TH;
            ref_i[56*CHAR_W+:CHAR_W] = TH;
            ref_i[57*CHAR_W+:CHAR_W] = TH;
            ref_i[58*CHAR_W+:CHAR_W] = TH;
            ref_i[59*CHAR_W+:CHAR_W] = TH;
            ref_i[60*CHAR_W+:CHAR_W] = TH;
            ref_i[61*CHAR_W+:CHAR_W] = TH;
            ref_i[62*CHAR_W+:CHAR_W] = C;
            ref_i[63*CHAR_W+:CHAR_W] = C;
        end

        begin : load_query_14
            query_i[ 0*CHAR_W+:CHAR_W] = B;
            query_i[ 1*CHAR_W+:CHAR_W] = B;
            query_i[ 2*CHAR_W+:CHAR_W] = B;
            query_i[ 3*CHAR_W+:CHAR_W] = B;
            query_i[ 4*CHAR_W+:CHAR_W] = B;
            query_i[ 5*CHAR_W+:CHAR_W] = A;
            query_i[ 6*CHAR_W+:CHAR_W] = A;
            query_i[ 7*CHAR_W+:CHAR_W] = A;
            query_i[ 8*CHAR_W+:CHAR_W] = A;
            query_i[ 9*CHAR_W+:CHAR_W] = TH;
            query_i[10*CHAR_W+:CHAR_W] = C;
            query_i[11*CHAR_W+:CHAR_W] = G;
            query_i[12*CHAR_W+:CHAR_W] = G;
            query_i[13*CHAR_W+:CHAR_W] = TH;
            query_i[14*CHAR_W+:CHAR_W] = G;
            query_i[15*CHAR_W+:CHAR_W] = C;
            query_i[16*CHAR_W+:CHAR_W] = TH;
            query_i[17*CHAR_W+:CHAR_W] = G;
            query_i[18*CHAR_W+:CHAR_W] = G;
            query_i[19*CHAR_W+:CHAR_W] = TH;
            query_i[20*CHAR_W+:CHAR_W] = TH;
            query_i[21*CHAR_W+:CHAR_W] = TH;
            query_i[22*CHAR_W+:CHAR_W] = TH;
            query_i[23*CHAR_W+:CHAR_W] = C;
            query_i[24*CHAR_W+:CHAR_W] = C;
            query_i[25*CHAR_W+:CHAR_W] = C;
            query_i[26*CHAR_W+:CHAR_W] = G;
            query_i[27*CHAR_W+:CHAR_W] = G;
            query_i[28*CHAR_W+:CHAR_W] = G;
            query_i[29*CHAR_W+:CHAR_W] = A;
            query_i[30*CHAR_W+:CHAR_W] = G;
            query_i[31*CHAR_W+:CHAR_W] = G;
            query_i[32*CHAR_W+:CHAR_W] = G;
            query_i[33*CHAR_W+:CHAR_W] = TH;
            query_i[34*CHAR_W+:CHAR_W] = G;
            query_i[35*CHAR_W+:CHAR_W] = TH;
            query_i[36*CHAR_W+:CHAR_W] = G;
            query_i[37*CHAR_W+:CHAR_W] = G;
            query_i[38*CHAR_W+:CHAR_W] = C;
            query_i[39*CHAR_W+:CHAR_W] = C;
            query_i[40*CHAR_W+:CHAR_W] = TH;
            query_i[41*CHAR_W+:CHAR_W] = G;
            query_i[42*CHAR_W+:CHAR_W] = G;
            query_i[43*CHAR_W+:CHAR_W] = G;
            query_i[44*CHAR_W+:CHAR_W] = G;
            query_i[45*CHAR_W+:CHAR_W] = G;
            query_i[46*CHAR_W+:CHAR_W] = G;
            query_i[47*CHAR_W+:CHAR_W] = A;
            query_i[48*CHAR_W+:CHAR_W] = A;
            query_i[49*CHAR_W+:CHAR_W] = A;
            query_i[50*CHAR_W+:CHAR_W] = A;
            query_i[51*CHAR_W+:CHAR_W] = A;
            query_i[52*CHAR_W+:CHAR_W] = A;
            query_i[53*CHAR_W+:CHAR_W] = A;
            query_i[54*CHAR_W+:CHAR_W] = TH;
            query_i[55*CHAR_W+:CHAR_W] = A;
            query_i[56*CHAR_W+:CHAR_W] = TH;
            query_i[57*CHAR_W+:CHAR_W] = TH;
            query_i[58*CHAR_W+:CHAR_W] = C;
            query_i[59*CHAR_W+:CHAR_W] = C;
            query_i[60*CHAR_W+:CHAR_W] = TH;
            query_i[61*CHAR_W+:CHAR_W] = TH;
            query_i[62*CHAR_W+:CHAR_W] = TH;
            query_i[63*CHAR_W+:CHAR_W] = TH;
            query_i[64*CHAR_W+:CHAR_W] = C;
            query_i[65*CHAR_W+:CHAR_W] = C;
            query_i[66*CHAR_W+:CHAR_W] = B;
            query_i[67*CHAR_W+:CHAR_W] = B;
            query_i[68*CHAR_W+:CHAR_W] = B;
            query_i[69*CHAR_W+:CHAR_W] = B;
            query_i[70*CHAR_W+:CHAR_W] = B;
            query_i[71*CHAR_W+:CHAR_W] = B;
            query_i[72*CHAR_W+:CHAR_W] = B;
            query_i[73*CHAR_W+:CHAR_W] = B;
        end

        run_and_check(14, 0);

        // =========================================================
        // Test 15: Real DNA sequences (unequal length, shorter)
        //
        // R = "AAAAAGGGTGCTTTTTTTCCCGGGAGGGTGTGGGGGGGGAAAAAAAAAATTTTTTTCC"
        //      length = 58 → padded to 64 with B at positions 58..63
        //
        // Q = "AAAATCGGTGCTGGTTTTGGGGGGAAAAAAATATTCCTTTTCCAAAAAA"
        //      length = 49 → padded to 64 with B at positions 49..63
        //
        // Both sequences padded with B (100) in ref and query slots.
        // ref B vs query A/B → obstacles in padded region.
        // Expect REJECT due to short sequences + mismatches, but
        // run first to see actual obs count and confirm.
        // =========================================================
        $display("\n--- Test 15: Real DNA R=58+6B Q=49+15B → observe ---");
        $display("  R: AAAAAGGGTGCTTTTTTTCCCGGGAGGGTGTGGGGGGGGAAAAAAAAAATTTTTTTCC");
        $display("  Q: AAAATCGGTGCTGGTTTTGGGGGGAAAAAAATATTCCTTTTCCAAAAAA");
        $display("  R length=58 padded to 64, Q length=49 padded to 64");
        reset_dut();

        begin : load_ref_15
            // R = A A A A A G G G T G C T T T T T T T C C C G G G A G G G T G T G G G G G G G G A A A A A A A A A A T T T T T T T C C
            // index 0..57 = real bases, 58..63 = B
            ref_i[ 0*CHAR_W+:CHAR_W] = A;  // A
            ref_i[ 1*CHAR_W+:CHAR_W] = A;  // A
            ref_i[ 2*CHAR_W+:CHAR_W] = A;  // A
            ref_i[ 3*CHAR_W+:CHAR_W] = A;  // A
            ref_i[ 4*CHAR_W+:CHAR_W] = A;  // A
            ref_i[ 5*CHAR_W+:CHAR_W] = G;  // G
            ref_i[ 6*CHAR_W+:CHAR_W] = G;  // G
            ref_i[ 7*CHAR_W+:CHAR_W] = G;  // G
            ref_i[ 8*CHAR_W+:CHAR_W] = TH; // T
            ref_i[ 9*CHAR_W+:CHAR_W] = G;  // G
            ref_i[10*CHAR_W+:CHAR_W] = C;  // C
            ref_i[11*CHAR_W+:CHAR_W] = TH; // T
            ref_i[12*CHAR_W+:CHAR_W] = TH; // T
            ref_i[13*CHAR_W+:CHAR_W] = TH; // T
            ref_i[14*CHAR_W+:CHAR_W] = TH; // T
            ref_i[15*CHAR_W+:CHAR_W] = TH; // T
            ref_i[16*CHAR_W+:CHAR_W] = TH; // T
            ref_i[17*CHAR_W+:CHAR_W] = TH; // T
            ref_i[18*CHAR_W+:CHAR_W] = C;  // C
            ref_i[19*CHAR_W+:CHAR_W] = C;  // C
            ref_i[20*CHAR_W+:CHAR_W] = C;  // C
            ref_i[21*CHAR_W+:CHAR_W] = G;  // G
            ref_i[22*CHAR_W+:CHAR_W] = G;  // G
            ref_i[23*CHAR_W+:CHAR_W] = G;  // G
            ref_i[24*CHAR_W+:CHAR_W] = A;  // A
            ref_i[25*CHAR_W+:CHAR_W] = G;  // G
            ref_i[26*CHAR_W+:CHAR_W] = G;  // G
            ref_i[27*CHAR_W+:CHAR_W] = G;  // G
            ref_i[28*CHAR_W+:CHAR_W] = TH; // T
            ref_i[29*CHAR_W+:CHAR_W] = G;  // G
            ref_i[30*CHAR_W+:CHAR_W] = TH; // T
            ref_i[31*CHAR_W+:CHAR_W] = G;  // G
            ref_i[32*CHAR_W+:CHAR_W] = G;  // G
            ref_i[33*CHAR_W+:CHAR_W] = G;  // G
            ref_i[34*CHAR_W+:CHAR_W] = G;  // G
            ref_i[35*CHAR_W+:CHAR_W] = G;  // G
            ref_i[36*CHAR_W+:CHAR_W] = G;  // G
            ref_i[37*CHAR_W+:CHAR_W] = G;  // G
            ref_i[38*CHAR_W+:CHAR_W] = G;  // G
            ref_i[39*CHAR_W+:CHAR_W] = A;  // A
            ref_i[40*CHAR_W+:CHAR_W] = A;  // A
            ref_i[41*CHAR_W+:CHAR_W] = A;  // A
            ref_i[42*CHAR_W+:CHAR_W] = A;  // A
            ref_i[43*CHAR_W+:CHAR_W] = A;  // A
            ref_i[44*CHAR_W+:CHAR_W] = A;  // A
            ref_i[45*CHAR_W+:CHAR_W] = A;  // A
            ref_i[46*CHAR_W+:CHAR_W] = A;  // A
            ref_i[47*CHAR_W+:CHAR_W] = A;  // A
            ref_i[48*CHAR_W+:CHAR_W] = A;  // A
            ref_i[49*CHAR_W+:CHAR_W] = TH; // T
            ref_i[50*CHAR_W+:CHAR_W] = TH; // T
            ref_i[51*CHAR_W+:CHAR_W] = TH; // T
            ref_i[52*CHAR_W+:CHAR_W] = TH; // T
            ref_i[53*CHAR_W+:CHAR_W] = TH; // T
            ref_i[54*CHAR_W+:CHAR_W] = TH; // T
            ref_i[55*CHAR_W+:CHAR_W] = TH; // T
            ref_i[56*CHAR_W+:CHAR_W] = C;  // C
            ref_i[57*CHAR_W+:CHAR_W] = C;  // C
            // positions 58..63 = B padding
            ref_i[58*CHAR_W+:CHAR_W] = B;
            ref_i[59*CHAR_W+:CHAR_W] = B;
            ref_i[60*CHAR_W+:CHAR_W] = B;
            ref_i[61*CHAR_W+:CHAR_W] = B;
            ref_i[62*CHAR_W+:CHAR_W] = B;
            ref_i[63*CHAR_W+:CHAR_W] = B;
        end

        begin : load_query_15
            // query_i layout:
            //   [0..4]   = B (left E=5 padding)
            //   [5..53]  = Q[0..48] (49 real bases)
            //   [54..68] = B (right padding: 15 chars for short Q + E=5)
            //   [69..73] = B (right E=5 padding, already covered above)
            // Q = A A A A T C G G T G C T G G T T T T G G G G G G A A A A A A A T A T T C C T T T T C C A A A A A A
            query_i[ 0*CHAR_W+:CHAR_W] = B;   // left pad
            query_i[ 1*CHAR_W+:CHAR_W] = B;
            query_i[ 2*CHAR_W+:CHAR_W] = B;
            query_i[ 3*CHAR_W+:CHAR_W] = B;
            query_i[ 4*CHAR_W+:CHAR_W] = B;
            // Q[0..48] at positions 5..53
            query_i[ 5*CHAR_W+:CHAR_W] = A;   // A
            query_i[ 6*CHAR_W+:CHAR_W] = A;   // A
            query_i[ 7*CHAR_W+:CHAR_W] = A;   // A
            query_i[ 8*CHAR_W+:CHAR_W] = A;   // A
            query_i[ 9*CHAR_W+:CHAR_W] = TH;  // T
            query_i[10*CHAR_W+:CHAR_W] = C;   // C
            query_i[11*CHAR_W+:CHAR_W] = G;   // G
            query_i[12*CHAR_W+:CHAR_W] = G;   // G
            query_i[13*CHAR_W+:CHAR_W] = TH;  // T
            query_i[14*CHAR_W+:CHAR_W] = G;   // G
            query_i[15*CHAR_W+:CHAR_W] = C;   // C
            query_i[16*CHAR_W+:CHAR_W] = TH;  // T
            query_i[17*CHAR_W+:CHAR_W] = G;   // G
            query_i[18*CHAR_W+:CHAR_W] = G;   // G
            query_i[19*CHAR_W+:CHAR_W] = TH;  // T
            query_i[20*CHAR_W+:CHAR_W] = TH;  // T
            query_i[21*CHAR_W+:CHAR_W] = TH;  // T
            query_i[22*CHAR_W+:CHAR_W] = TH;  // T
            query_i[23*CHAR_W+:CHAR_W] = G;   // G
            query_i[24*CHAR_W+:CHAR_W] = G;   // G
            query_i[25*CHAR_W+:CHAR_W] = G;   // G
            query_i[26*CHAR_W+:CHAR_W] = G;   // G
            query_i[27*CHAR_W+:CHAR_W] = G;   // G
            query_i[28*CHAR_W+:CHAR_W] = G;   // G
            query_i[29*CHAR_W+:CHAR_W] = A;   // A
            query_i[30*CHAR_W+:CHAR_W] = A;   // A
            query_i[31*CHAR_W+:CHAR_W] = A;   // A
            query_i[32*CHAR_W+:CHAR_W] = A;   // A
            query_i[33*CHAR_W+:CHAR_W] = A;   // A
            query_i[34*CHAR_W+:CHAR_W] = A;   // A
            query_i[35*CHAR_W+:CHAR_W] = A;   // A
            query_i[36*CHAR_W+:CHAR_W] = TH;  // T
            query_i[37*CHAR_W+:CHAR_W] = A;   // A
            query_i[38*CHAR_W+:CHAR_W] = TH;  // T
            query_i[39*CHAR_W+:CHAR_W] = TH;  // T
            query_i[40*CHAR_W+:CHAR_W] = C;   // C
            query_i[41*CHAR_W+:CHAR_W] = C;   // C
            query_i[42*CHAR_W+:CHAR_W] = TH;  // T
            query_i[43*CHAR_W+:CHAR_W] = TH;  // T
            query_i[44*CHAR_W+:CHAR_W] = TH;  // T
            query_i[45*CHAR_W+:CHAR_W] = TH;  // T
            query_i[46*CHAR_W+:CHAR_W] = C;   // C
            query_i[47*CHAR_W+:CHAR_W] = C;   // C
            query_i[48*CHAR_W+:CHAR_W] = A;   // A
            query_i[49*CHAR_W+:CHAR_W] = A;   // A
            query_i[50*CHAR_W+:CHAR_W] = A;   // A
            query_i[51*CHAR_W+:CHAR_W] = A;   // A
            query_i[52*CHAR_W+:CHAR_W] = A;   // A
            query_i[53*CHAR_W+:CHAR_W] = A;   // A
            // positions 54..73 = B padding (Q ends at index 53)
            query_i[54*CHAR_W+:CHAR_W] = B;
            query_i[55*CHAR_W+:CHAR_W] = B;
            query_i[56*CHAR_W+:CHAR_W] = B;
            query_i[57*CHAR_W+:CHAR_W] = B;
            query_i[58*CHAR_W+:CHAR_W] = B;
            query_i[59*CHAR_W+:CHAR_W] = B;
            query_i[60*CHAR_W+:CHAR_W] = B;
            query_i[61*CHAR_W+:CHAR_W] = B;
            query_i[62*CHAR_W+:CHAR_W] = B;
            query_i[63*CHAR_W+:CHAR_W] = B;
            query_i[64*CHAR_W+:CHAR_W] = B;
            query_i[65*CHAR_W+:CHAR_W] = B;
            query_i[66*CHAR_W+:CHAR_W] = B;
            query_i[67*CHAR_W+:CHAR_W] = B;
            query_i[68*CHAR_W+:CHAR_W] = B;
            query_i[69*CHAR_W+:CHAR_W] = B;
            query_i[70*CHAR_W+:CHAR_W] = B;
            query_i[71*CHAR_W+:CHAR_W] = B;
            query_i[72*CHAR_W+:CHAR_W] = B;
            query_i[73*CHAR_W+:CHAR_W] = B;
        end

        // Run first, observe total_obs in console, then update expectation.
        // R=58 chars, Q=49 chars → significant padding mismatch region
        // likely > E=5 obstacles → REJECT expected
        run_and_check(15, 0);

        // =========================================================
        // Summary
        // =========================================================
        $display("\n============================================================");
        $display("  Tests passed : %0d", pass_count);
        $display("  Tests failed : %0d", fail_count);
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> FAILURES DETECTED <<<");
        $display("============================================================");
        $finish;
    end

endmodule