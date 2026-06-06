// ============================================================
// snake_pipeline.v  -  y-stage Snake-on-Chip Pipeline
// ============================================================
// Paper ref: Supplementary Section 8, Steps (5) and (6)
//
// Chains Y snake_stage instances with pipeline registers.
// Carries a running sum_r alongside the data so that at the
// final stage, sum_r[Y-1] = x_0 + x_1 + ... + x_{Y-1}
// all from the SAME subproblem.
//
// OBSTACLE COUNTING - FIXED: lives_r (direct hit counter)
// =========================================================
// Original paper formula: obs = min(Y, T - sum_x)
//   Problem: when a scattered obstacle is encountered and the
//   snake routes around it diagonally, stages after the shift
//   see all-zeros (x = T) inflating sum_x beyond T. This makes
//   T - sum_x go negative → clamped to 0 → obstacle missed.
//   Result: false accepts for scattered obstacle patterns.
//
// Fix (matches official SneakySnake_8bit Lives counter):
//   For each stage k, if valid_out = 1 from the comparator tree,
//   the snake encountered an obstacle → increment lives_r.
//   valid_out = 1 when max_out < T (best row did not fully escape).
//   valid_out = 0 when max_out == T (all rows fully clear, no hit).
//
//   obs_count = lives_r[Y-1]
//
//   This directly counts how many stages hit an obstacle,
//   regardless of how large sum_x grows afterward.
//   lives_r is naturally capped at Y (increments once per stage).
//
//   sum_r is kept in parallel for debug printing only.
//
// PARAMETERS
// ==========
//   E, T, Y - primary design knobs
//
// DERIVED (do not override manually):
//   CNT_W   = $clog2(T)+1     holds 0..T (LZC output)
//   SHIFT_W = $clog2(T+1)     holds shift amount 0..T
//   OBS_W   = $clog2(Y)+1     holds 0..Y (per-subproblem obs)
//   SUMX_W  = $clog2(Y*T)+1   holds 0..Y*T (running sum, debug)
//
// LATENCY: Y+1 cycles from valid_in to valid_out.
//   (Y pipeline register stages + 1 output register stage)
// ============================================================

module snake_pipeline #(
    parameter E       = 5,
    parameter T       = 8,
    parameter Y       = 4,
    // Derived - computed from primary params, do not override
    parameter CNT_W   = $clog2(T)   + 1,
    parameter SHIFT_W = $clog2(T+1),
    parameter OBS_W   = $clog2(Y)   + 1,
    parameter SUMX_W  = $clog2(Y*T) + 1
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire [((2*E+1)*T)-1:0]     rows_in,
    input  wire                        valid_in,
    output reg  [OBS_W-1:0]           obs_count,
    output reg                         valid_out,
    // Debug: x_reg_bus[k*CNT_W +: CNT_W] = registered x from stage k
    output wire [Y*CNT_W-1:0]         x_reg_bus
);

    localparam NUM_ROWS = 2*E + 1;
    localparam RBITS    = NUM_ROWS * T;

    // ----------------------------------------------------------
    // Combinational stage outputs
    // ----------------------------------------------------------
    wire [RBITS-1:0]  stage_rows_w  [0:Y-1];
    wire [CNT_W-1:0]  stage_x_w     [0:Y-1];
    wire              stage_valid_w  [0:Y-1];  // NEW: valid_out from each stage

    // ----------------------------------------------------------
    // Pipeline registers (carry data + sums + lives + valid)
    // ----------------------------------------------------------
    reg [RBITS-1:0]   stage_rows_r  [0:Y-1];
    reg [CNT_W-1:0]   stage_x_r     [0:Y-1];
    reg [SUMX_W-1:0]  sum_r         [0:Y-1];  // kept for debug print
    reg [OBS_W-1:0]   lives_r       [0:Y-1];  // NEW: direct obstacle hit counter
    reg               stage_valid_r [0:Y-1];

    // ----------------------------------------------------------
    // Stage 0: driven by rows_in
    // ----------------------------------------------------------
    snake_stage #(.E(E),.T(T),.CNT_W(CNT_W),.SHIFT_W(SHIFT_W)) stage_0 (
        .rows_in  (rows_in),
        .rows_out (stage_rows_w[0]),
        .x_out    (stage_x_w[0]),
        .valid_out(stage_valid_w[0])   // NEW
    );

    // ----------------------------------------------------------
    // Stages 1..Y-1: driven by previous stage register
    // ----------------------------------------------------------
    genvar s;
    generate
        for (s = 1; s < Y; s = s + 1) begin : gen_stages
            snake_stage #(.E(E),.T(T),.CNT_W(CNT_W),.SHIFT_W(SHIFT_W)) stage_n (
                .rows_in  (stage_rows_r[s-1]),
                .rows_out (stage_rows_w[s]),
                .x_out    (stage_x_w[s]),
                .valid_out(stage_valid_w[s])   // NEW
            );
        end
    endgenerate

    // ----------------------------------------------------------
    // Pipeline registers with running sum + lives accumulation
    // Async reset so synthesis infers proper reset flops
    // ----------------------------------------------------------
    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (k = 0; k < Y; k = k + 1) begin
                stage_rows_r[k]  <= {RBITS{1'b0}};
                stage_x_r[k]     <= {CNT_W{1'b0}};
                sum_r[k]         <= {SUMX_W{1'b0}};
                lives_r[k]       <= {OBS_W{1'b0}};  // NEW
                stage_valid_r[k] <= 1'b0;
            end
        end else begin
            // Stage 0: start both sum and lives
            stage_rows_r[0]  <= stage_rows_w[0];
            stage_x_r[0]     <= stage_x_w[0];
            sum_r[0]         <= {{(SUMX_W-CNT_W){1'b0}}, stage_x_w[0]};
            // lives_r[0]: 1 if stage 0 hit an obstacle, 0 if fully clear
            lives_r[0]       <= {{(OBS_W-1){1'b0}}, stage_valid_w[0]};  // NEW
            stage_valid_r[0] <= valid_in;

            // Stages 1..Y-1: accumulate both sum and lives alongside data
            for (k = 1; k < Y; k = k + 1) begin
                stage_rows_r[k]  <= stage_rows_w[k];
                stage_x_r[k]     <= stage_x_w[k];
                sum_r[k]         <= sum_r[k-1] +
                                    {{(SUMX_W-CNT_W){1'b0}}, stage_x_w[k]};
                // lives_r[k]: add 1 if this stage hit an obstacle
                lives_r[k]       <= lives_r[k-1] +           // NEW
                                    {{(OBS_W-1){1'b0}}, stage_valid_w[k]};
                stage_valid_r[k] <= stage_valid_r[k-1];
            end
        end
    end

    // ----------------------------------------------------------
    // Obstacle count = lives_r[Y-1]
    // Direct count of stages that hit an obstacle.
    // Naturally capped at Y (increments by at most 1 per stage).
    // Replaces min(Y, T-sum_x) which lost scattered obstacles.
    // ----------------------------------------------------------
    reg [OBS_W-1:0] obs_comb;

    always @(*) begin
        obs_comb = lives_r[Y-1];   // CHANGED: was min(Y, T-sum_x)
    end

    // ----------------------------------------------------------
    // Output register - async reset
    // ----------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            obs_count <= {OBS_W{1'b0}};
            valid_out <= 1'b0;
        end else begin
            obs_count <= obs_comb;
            valid_out <= stage_valid_r[Y-1];

            // Debug: print once per subproblem result
            // Gated on valid so it only fires when real data exits
//            if (stage_valid_r[Y-1]) begin
//                $display("--- snake_pipeline: subproblem result ---");
//                begin : print_x
//                    integer dbg_k;
//                    for (dbg_k = 0; dbg_k < Y; dbg_k = dbg_k + 1)
//                        $display("  stage[%0d] x=%0d  valid=%0d",
//                                 dbg_k, stage_x_r[dbg_k],
//                                 (stage_x_r[dbg_k] != T[CNT_W:0]));
//                end
//                $display("  sum_x=%0d  lives=%0d  obs=%0d",
//                         sum_r[Y-1], lives_r[Y-1], obs_comb);
//            end
        end
    end

    // ----------------------------------------------------------
    // Debug bus: x_reg_bus[k*CNT_W +: CNT_W] = stage_x_r[k]
    // ----------------------------------------------------------
    genvar d;
    generate
        for (d = 0; d < Y; d = d + 1) begin : dbg_pack
            assign x_reg_bus[d*CNT_W +: CNT_W] = stage_x_r[d];
        end
    endgenerate

endmodule