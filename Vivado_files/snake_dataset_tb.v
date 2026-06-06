// ============================================================
// snake_dataset_tb.v  -  Dataset testbench for snake_on_chip_top
// ============================================================
// Reads sequence pairs from input.txt (one pair per line,
// REF<TAB>QUERY format, each sequence exactly 100 bases).
//
// Parameters:
//   M      = 104  (next multiple of T=8 above 100)
//   E      = 5
//   T      = 8
//   Y      = 4
//   CHAR_W = 3
//
// Sequences are 100 bases, padded to M=104 with B (3'b100).
//
// DNA encoding: A=000 C=001 G=010 T=011 B=100(pad)
//
// HOW TO USE IN VIVADO:
// =====================
// 1. Add this file as a simulation source
// 2. Set snake_dataset_tb as simulation top
// 3. Copy input.txt to:
//    <project>.sim/sim_1/behav/xsim/input.txt
// 4. Set simulation run time to 500 us (or click Run All)
// 5. Results appear in Tcl console
//
// OUTPUT:
// =======
// Per-pair: pair number, obs count, ACCEPT/REJECT
// Final: total accepted, total rejected, filtering rate
// ============================================================

`timescale 1ns/1ps

module snake_dataset_tb;

    // ----------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------
    localparam E        = 5;
    localparam T        = 8;
    localparam Y        = 4;
    localparam M        = 104;   // 100 bases padded to next multiple of T=8
    localparam CHAR_W   = 3;
    localparam SEQ_LEN  = 100;   // actual sequence length in the file
    localparam Q_TOT    = M + 2*E;
    localparam CLK_HALF = 5;     // 100 MHz clock
    localparam NUM_PAIRS = 100;  // number of pairs in input.txt

    // DNA encoding
    localparam [CHAR_W-1:0] BASE_A = 3'b000;
    localparam [CHAR_W-1:0] BASE_C = 3'b001;
    localparam [CHAR_W-1:0] BASE_G = 3'b010;
    localparam [CHAR_W-1:0] BASE_T = 3'b011;
    localparam [CHAR_W-1:0] BASE_B = 3'b100;  // padding

    // ----------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------
    reg                        clk, rst, start_i;
    wire                       done_o, accept_o;
    reg  [M*CHAR_W-1:0]        ref_i;
    reg  [Q_TOT*CHAR_W-1:0]    query_i;

    snake_on_chip_top #(
        .E(E),.T(T),.Y(Y),.M(M),.CHAR_W(CHAR_W)
    ) DUT (
        .clk(clk),.rst(rst),.start_i(start_i),
        .done_o(done_o),.accept_o(accept_o),
        .ref_i(ref_i),.query_i(query_i)
    );

    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    // ----------------------------------------------------------
    // File I/O variables
    // ----------------------------------------------------------
    integer fd;                       // file descriptor
    integer scan_ret;                 // $fscanf return value
    reg [8*101-1:0] ref_str;          // string buffer for ref  (100 chars + null)
    reg [8*101-1:0] query_str;        // string buffer for query
    reg [7:0]       ch;               // single character

    // ----------------------------------------------------------
    // Counters
    // ----------------------------------------------------------
    integer pair_num;
    integer total_accepted;
    integer total_rejected;
    integer timeout_c;
    integer i, j;

    // ----------------------------------------------------------
    // Helper function: encode one ASCII character to 3-bit DNA
    // ----------------------------------------------------------
    function [CHAR_W-1:0] encode_base;
        input [7:0] ascii;
        begin
            case (ascii)
                8'h41, 8'h61: encode_base = BASE_A;  // A or a
                8'h43, 8'h63: encode_base = BASE_C;  // C or c
                8'h47, 8'h67: encode_base = BASE_G;  // G or g
                8'h54, 8'h74: encode_base = BASE_T;  // T or t
                default:       encode_base = BASE_B;  // anything else = B pad
            endcase
        end
    endfunction

    // ----------------------------------------------------------
    // Task: reset DUT cleanly
    // ----------------------------------------------------------
    task reset_dut;
        begin
            rst=1; start_i=0;
            repeat(4) @(posedge clk);
            rst=0; @(posedge clk); #1;
        end
    endtask

    // ----------------------------------------------------------
    // Task: load ref_i from ref_str (SEQ_LEN chars, pad rest to M)
    // ----------------------------------------------------------
    task load_ref_from_string;
        integer k;
        reg [7:0] c;
        begin
            // Load real bases
            for (k = 0; k < SEQ_LEN; k = k + 1) begin
                c = ref_str[(8*(100-k))-1 -: 8];
                ref_i[k*CHAR_W +: CHAR_W] = encode_base(c);
            end
            // Pad remaining positions with B
            for (k = SEQ_LEN; k < M; k = k + 1) begin
                ref_i[k*CHAR_W +: CHAR_W] = BASE_B;
            end
        end
    endtask

    // ----------------------------------------------------------
    // Task: load query_i from query_str
    // query_i layout:
    //   [0..E-1]       = B (left E-padding)
    //   [E..E+SEQ_LEN-1] = actual bases
    //   [E+SEQ_LEN..E+M-1] = B (pad short seq to M)
    //   [E+M..Q_TOT-1]   = B (right E-padding)
    // ----------------------------------------------------------
    task load_query_from_string;
        integer k;
        reg [7:0] c;
        begin
            // Left E padding
            for (k = 0; k < E; k = k + 1)
                query_i[k*CHAR_W +: CHAR_W] = BASE_B;
            // Real bases
            for (k = 0; k < SEQ_LEN; k = k + 1) begin
                c = query_str[(8*(100-k))-1 -: 8];
                query_i[(E+k)*CHAR_W +: CHAR_W] = encode_base(c);
            end
            // Pad short sequence portion
            for (k = SEQ_LEN; k < M; k = k + 1)
                query_i[(E+k)*CHAR_W +: CHAR_W] = BASE_B;
            // Right E padding
            for (k = E+M; k < Q_TOT; k = k + 1)
                query_i[k*CHAR_W +: CHAR_W] = BASE_B;
        end
    endtask

    // ----------------------------------------------------------
    // Task: run DUT and wait for done_o
    // ----------------------------------------------------------
    task run_filter;
        begin
            @(posedge clk); #1;
            start_i = 1;
            @(posedge clk); #1;
            start_i = 0;
            timeout_c = 0;
            while (!done_o && timeout_c < 1000) begin
                @(posedge clk); #1;
                timeout_c = timeout_c + 1;
            end
            if (!done_o)
                $display("  WARNING: pair %0d timed out!", pair_num);
        end
    endtask

    // ----------------------------------------------------------
    // Task: read one string from file up to tab or newline
    // Reads char by char. Stores into str_reg.
    // Returns 0 if EOF reached before any chars read.
    // ----------------------------------------------------------
    task read_string;
        output reg [8*101-1:0] str_reg;
        output integer         str_len;
        output integer         hit_eof;
        integer                pos;
        reg [7:0]              c;
        begin
            str_reg  = 0;
            str_len  = 0;
            hit_eof  = 0;
            pos      = 0;
            forever begin
                c = $fgetc(fd);
                if ($feof(fd)) begin
                    hit_eof = 1;
                    disable read_string;
                end
                // stop at tab, newline, carriage return
                if (c == 8'h09 || c == 8'h0A || c == 8'h0D) begin
                    disable read_string;
                end
                // store character - pack MSB first
                str_reg = (str_reg << 8) | c;
                str_len = str_len + 1;
            end
        end
    endtask

    // ----------------------------------------------------------
    // Main stimulus
    // ----------------------------------------------------------
    initial begin
        // Initialise
        clk=0; rst=1; start_i=0;
        ref_i=0; query_i=0;
        pair_num=0; total_accepted=0; total_rejected=0;

        $display("============================================================");
        $display("  Snake-on-Chip Dataset TB");
        $display("  E=%0d T=%0d Y=%0d M=%0d SEQ_LEN=%0d", E, T, Y, M, SEQ_LEN);
        $display("  A=000 C=001 G=010 T=011 B=100(pad)");
        $display("  ACCEPT if total_obstacles <= E=%0d", E);
        $display("  Reading from: input.txt (%0d pairs)", NUM_PAIRS);
        $display("============================================================");

        repeat(4) @(posedge clk);
        rst=0; @(posedge clk); #1;

        // Open input file
        fd = $fopen("input.txt", "r");
        if (fd == 0) begin
            $display("ERROR: could not open input.txt");
            $display("Place input.txt in the xsim working directory:");
            $display("  <project>.sim/sim_1/behav/xsim/");
            $finish;
        end

        // Process pairs
        while (!$feof(fd) && pair_num < NUM_PAIRS) begin : pair_loop

            integer ref_len, query_len, eof_r, eof_q;
            integer skip_char;

            // Read ref string (up to tab)
            read_string(ref_str, ref_len, eof_r);
            if (eof_r || ref_len == 0) disable pair_loop;

            // Read query string (up to newline)
            read_string(query_str, query_len, eof_q);
            if (eof_q && query_len == 0) disable pair_loop;

            pair_num = pair_num + 1;

            // Load into DUT buses
            reset_dut();
            load_ref_from_string();
            load_query_from_string();

            // Run the filter
            run_filter();

            // Record result
            if (accept_o) begin
                total_accepted = total_accepted + 1;
                $display("  Pair %3d: ACCEPT  (cycles=%0d)", pair_num, timeout_c);
            end else begin
                total_rejected = total_rejected + 1;
                $display("  Pair %3d: REJECT  (cycles=%0d)", pair_num, timeout_c);
            end

            // Small gap between pairs
            repeat(5) @(posedge clk); #1;
        end

        $fclose(fd);

        // Final summary
        $display("");
        $display("============================================================");
        $display("  FINAL RESULTS");
        $display("============================================================");
        $display("  Total pairs     : %0d", pair_num);
        $display("  Accepted (ALIGN): %0d", total_accepted);
        $display("  Rejected (SKIP) : %0d", total_rejected);
        if (pair_num > 0) begin
            // filtering rate as integer percentage (no real division)
            $display("  Filtering rate  : %0d / %0d pairs rejected",
                     total_rejected, pair_num);
            $display("  (= approx %0d%%)",
                     (total_rejected * 100) / pair_num);
        end
        $display("============================================================");
        $finish;
    end

endmodule