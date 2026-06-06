// ============================================================
// snake_on_chip_top.v  -  Top-level Snake-on-Chip Filter
// ============================================================
// Paper ref: Supplementary Section 8 (complete architecture)
//
// Streams a sequence pair through the pipeline and outputs
// a single ACCEPT/REJECT pre-alignment filter decision.
//
// OPERATION
// =========
// Splits reference into NUM_BLOCKS = M/T subproblems.
// For each subproblem s:
//   ref_block[j]    = ref[s*T + j]        j = 0..T-1
//   query_block[k]  = query[s*T + k]      k = 0..Q_WINDOW-1
//     (query_i already has E chars of left-padding at index 0)
//
// chip_maze_gen  → (2E+1)×T bit-matrix
// snake_pipeline → per-subproblem obstacle count
// Accumulate total_obs across all subproblems.
// If total_obs > E → REJECT, else → ACCEPT.
//
// TIMING
// ======
// Assert start_i for one cycle → runs autonomously.
// done_o pulses for one cycle when result is ready.
// accept_o is valid when done_o is high.
//
// PARAMETERS
// ==========
//   E      - edit distance threshold
//   T      - subproblem column width   (M must be multiple of T)
//   Y      - pipeline stages
//   M      - sequence length           (must be multiple of T)
//   CHAR_W - character bit-width       (3 for 3-bit DNA encoding)
//
// CHARACTER ENCODING (CHAR_W=3):
//   A=000  C=001  G=010  T=011  B=100 (padding sentinel)
//
// DERIVED LOCALPARAMS (all computed - do not override):
//   NUM_BLOCKS - depends on M, T    (M must be multiple of T)
//   Q_WINDOW   - depends on T, E
//   Q_TOT      - depends on M, E
//   CNT_W      - depends on T
//   SHIFT_W    - depends on T
//   OBS_W      - depends on Y
//   SUMX_W     - depends on Y, T
//   NUM_ROWS   - depends on E
//   RBITS      - depends on E, T
//   TOT_OBS_W  - depends on NUM_BLOCKS, Y
//
// HARD CONSTRAINT: M must be an exact multiple of T.
//   If sequences are shorter than M, pad with B (3'b100).
// ============================================================

module snake_on_chip_top #(
    parameter E      = 5,
    parameter T      = 8,
    parameter Y      = 4,
    parameter M      = 64,   // must be multiple of T
    parameter CHAR_W = 3     // 3-bit encoding: A=000 C=001 G=010 T=011 B=100
)(
    input  wire                       clk,
    input  wire                       rst,

    input  wire                       start_i,   // one-cycle pulse to start
    output reg                        done_o,    // one-cycle pulse when done
    output reg                        accept_o,  // 1=accept, 0=reject

    // ref_i[j*CHAR_W +: CHAR_W] = ref character j  (j = 0..M-1)
    input  wire [M*CHAR_W-1:0]        ref_i,

    // query_i[k*CHAR_W +: CHAR_W] = query char at window index k
    // index 0 = position (-E) relative to ref start
    // total width = (M + 2*E) characters
    input  wire [((M+2*E)*CHAR_W)-1:0] query_i
);

    // ----------------------------------------------------------
    // Derived parameters - all computed, never hardcode
    // ----------------------------------------------------------
    localparam NUM_BLOCKS = M / T;                     // subproblems per pair
    localparam Q_WINDOW   = T + 2*E;                   // query chars per block
    localparam Q_TOT      = M + 2*E;                   // total query chars
    localparam CNT_W      = $clog2(T)   + 1;           // LZC output width
    localparam SHIFT_W    = $clog2(T+1);               // shift amount width
    localparam OBS_W      = $clog2(Y)   + 1;           // per-block obs width
    localparam SUMX_W     = $clog2(Y*T) + 1;           // running sum width
    localparam NUM_ROWS   = 2*E + 1;                   // HRT rows
    localparam RBITS      = NUM_ROWS * T;              // maze bus width
    localparam TOT_OBS_W  = $clog2(NUM_BLOCKS*Y+1)+1; // total obs counter

    // ----------------------------------------------------------
    // Current block extraction (combinational)
    // ----------------------------------------------------------
    reg  [T*CHAR_W-1:0]          ref_block;
    reg  [Q_WINDOW*CHAR_W-1:0]   query_block;

    wire [RBITS-1:0] maze_rows;

    chip_maze_gen #(.E(E), .T(T), .CHAR_W(CHAR_W)) maze_gen (
        .ref_block  (ref_block),
        .query_block(query_block),
        .maze_rows  (maze_rows)
    );

    // ----------------------------------------------------------
    // snake_pipeline
    // ----------------------------------------------------------
    wire [OBS_W-1:0]   pipe_obs;
    wire               pipe_valid;
    wire [Y*CNT_W-1:0] pipe_xbus;

    reg                pipe_valid_in;
    reg  [RBITS-1:0]   pipe_rows_in;

    snake_pipeline #(
        .E(E),.T(T),.Y(Y),
        .CNT_W(CNT_W),.SHIFT_W(SHIFT_W),
        .OBS_W(OBS_W),.SUMX_W(SUMX_W)
    ) pipeline (
        .clk      (clk),
        .rst      (rst),
        .rows_in  (pipe_rows_in),
        .valid_in (pipe_valid_in),
        .obs_count(pipe_obs),
        .valid_out(pipe_valid),
        .x_reg_bus(pipe_xbus)
    );

    // ----------------------------------------------------------
    // FSM states
    // ----------------------------------------------------------
    localparam S_IDLE  = 2'd0;
    localparam S_LOAD  = 2'd1;
    localparam S_DRAIN = 2'd2;
    localparam S_DONE  = 2'd3;

    reg [1:0]                        state;
    reg [$clog2(NUM_BLOCKS):0]       block_idx;
    reg [TOT_OBS_W-1:0]              total_obs;
    reg [$clog2(Y+2):0]              drain_cnt;
    reg [TOT_OBS_W-1:0]              blocks_received;

    // ----------------------------------------------------------
    // Combinational block extraction
    // ref_block  = ref_i  [block_idx*T   .. block_idx*T+T-1]
    // query_block= query_i[block_idx*T   .. block_idx*T+Q_WINDOW-1]
    // (query_i[0] already corresponds to position -E)
    // ----------------------------------------------------------
    integer j;
    always @(*) begin
        for (j = 0; j < T; j = j + 1)
            ref_block[j*CHAR_W +: CHAR_W] =
                ref_i[(block_idx*T + j)*CHAR_W +: CHAR_W];

        for (j = 0; j < Q_WINDOW; j = j + 1)
            query_block[j*CHAR_W +: CHAR_W] =
                query_i[(block_idx*T + j)*CHAR_W +: CHAR_W];
    end

    // ----------------------------------------------------------
    // FSM + obstacle accumulator - async reset
    // ----------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= S_IDLE;
            block_idx       <= 0;
            total_obs       <= 0;
            drain_cnt       <= 0;
            blocks_received <= 0;
            pipe_valid_in   <= 0;
            pipe_rows_in    <= 0;
            done_o          <= 0;
            accept_o        <= 0;
        end else begin
            done_o        <= 0;
            pipe_valid_in <= 0;

            // Accumulate pipeline outputs whenever valid
            if (pipe_valid) begin
                total_obs       <= total_obs +
                                   {{(TOT_OBS_W-OBS_W){1'b0}}, pipe_obs};
                blocks_received <= blocks_received + 1;

                // Debug: print each subproblem result as it exits pipeline
                //$display("  [top] subproblem done: block_received=%0d  pipe_obs=%0d  total_obs_so_far=%0d",
//                         blocks_received,
//                         pipe_obs,
//                         total_obs + {{(TOT_OBS_W-OBS_W){1'b0}}, pipe_obs});
            end

            case (state)

                S_IDLE: begin
                    if (start_i) begin
                        block_idx       <= 0;
                        total_obs       <= 0;
                        blocks_received <= 0;
                        drain_cnt       <= 0;
                        state           <= S_LOAD;
                        //$display("=== Snake-on-Chip START (M=%0d T=%0d E=%0d Y=%0d NUM_BLOCKS=%0d) ===",M, T, E, Y, NUM_BLOCKS);
                    end
                end

                S_LOAD: begin
                    pipe_rows_in  <= maze_rows;
                    pipe_valid_in <= 1;

//                    $display("  [top] loading block %0d / %0d",
//                             block_idx, NUM_BLOCKS-1);

                    if (block_idx == NUM_BLOCKS - 1) begin
                        state     <= S_DRAIN;
                        drain_cnt <= 0;
                    end else begin
                        block_idx <= block_idx + 1;
                    end
                end

                S_DRAIN: begin
                    if (blocks_received == NUM_BLOCKS[TOT_OBS_W-1:0]) begin
                        state <= S_DONE;
                    end else begin
                        drain_cnt <= drain_cnt + 1;
                        if (drain_cnt > Y + 5)
                            state <= S_DONE;  // safety timeout
                    end
                end

                S_DONE: begin
                    done_o   <= 1;
                    accept_o <= (total_obs <= E[TOT_OBS_W-1:0]) ? 1'b1 : 1'b0;
                    state    <= S_IDLE;

                    $display("=== Snake-on-Chip RESULT ===");
                    $display("  Total obstacles = %0d  (threshold E=%0d)", total_obs, E);
                    $display("  Decision        = %s",
                             (total_obs <= E) ?
                             "ACCEPT (alignment needed)" :
                             "REJECT (skip alignment)");
                end

            endcase
        end
    end
endmodule