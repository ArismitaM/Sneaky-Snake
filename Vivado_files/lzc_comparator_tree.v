// ============================================================
// lzc_comparator_tree.v  -  Hierarchical max-finder
// ============================================================
// Paper ref: Supplementary Section 8, Step (3) and Fig. 7
//
// Parameters (paper-exact):
//   E        = 5
//   NUM_ROWS = 2*E+1 = 11
//   T        = 8  → CNT_W = $clog2(8)+1 = 4  (holds 0..8)
//
// From the paper (Supp. Section 8):
//   "We need 2E+2 = 12 comparators arranged into 4 levels:
//    Level 1: 6 comparators (directly connected to LZCs)
//    Level 2: 3 comparators
//    Level 3: 2 comparators
//    Level 4: 1 comparator"
//
// Tree layout for 11 inputs (indices 0..10):
//
//  Level 0 (inputs):  lzc[0..10]
//
//  Level 1 - 6 comparators, 1 pass-through (lzc[10]):
//    node[1][0] = max(lzc[0],  lzc[1])
//    node[1][1] = max(lzc[2],  lzc[3])
//    node[1][2] = max(lzc[4],  lzc[5])
//    node[1][3] = max(lzc[6],  lzc[7])
//    node[1][4] = max(lzc[8],  lzc[9])
//    node[1][5] = lzc[10]              ← odd → pass-through
//
//  Level 2 - 3 comparators:
//    node[2][0] = max(node[1][0], node[1][1])
//    node[2][1] = max(node[1][2], node[1][3])
//    node[2][2] = max(node[1][4], node[1][5])
//
//  Level 3 - 2 comparators, but 3 is odd so 1 pass-through:
//    node[3][0] = max(node[2][0], node[2][1])
//    node[3][1] = node[2][2]           ← odd → pass-through
//
//  Level 4 - 1 comparator (root):
//    max_out = max(node[3][0], node[3][1])
//
//  Real comparators: 6 + 3 + 2 + 1 = 12  ✓ matches paper exactly
//
// VALID_OUT
// =========
//   valid_out = 1  when at least one of the 11 rows has an obstacle
//               (i.e. max_out < T  →  best row did not fully escape)
//   valid_out = 0  when ALL rows are fully zero (max_out == T)
//               meaning the snake escaped with zero obstacles this stage
//
//   This mirrors the Valid signal in the official Comparator_3Bit
//   which sets AB3=1 only when a real obstacle is present.
//   Used by snake_pipeline to count per-stage obstacle hits directly
//   instead of inferring them from the min(Y, T-sum_x) formula.
// ============================================================

module lzc_comparator_tree #(
    parameter NUM_ROWS = 11,   // 2*E+1  for E=5
    parameter CNT_W    = 4,    // $clog2(T)+1  for T=8
    parameter T        = 8     // needed to compute valid_out threshold
)(
    input  wire [NUM_ROWS*CNT_W-1:0]  lzc_in,    // packed {lzc[10],...,lzc[0]}
    output wire [CNT_W-1:0]           max_out,    // longest escape segment  x
    output wire                        valid_out   // 1 = obstacle exists in this stage
);

    // ----------------------------------------------------------
    // 1. Unpack flat bus → per-row wires
    // ----------------------------------------------------------
    wire [CNT_W-1:0] lzc [0:NUM_ROWS-1];

    genvar u;
    generate
        for (u = 0; u < NUM_ROWS; u = u + 1) begin : unpack
            assign lzc[u] = lzc_in[u*CNT_W +: CNT_W];
        end
    endgenerate

    // ----------------------------------------------------------
    // 2. Binary comparator tree
    //
    // LEVELS = ceil(log2(11)) = 4
    //
    // We allocate a 2-D wire array  tree[level][node].
    // Level 0 holds the raw LZC inputs.
    // Each subsequent level pairs adjacent nodes and keeps the
    // larger value.  Odd-count levels pass the unpaired node
    // straight through (no comparator consumed).
    //
    // Unused slots at the right end of each level are tied to 0
    // and pruned by synthesis.
    // ----------------------------------------------------------

    localparam LEVELS = $clog2(NUM_ROWS);   // 4 for NUM_ROWS=11

    wire [CNT_W-1:0] tree [0:LEVELS] [0:NUM_ROWS-1];

    // Level 0 = raw LZC outputs
    genvar i;
    generate
        for (i = 0; i < NUM_ROWS; i = i + 1) begin : feed_inputs
            assign tree[0][i] = lzc[i];
        end
    endgenerate

    // Levels 1 .. LEVELS
    genvar lvl, nd;
    generate
        for (lvl = 1; lvl <= LEVELS; lvl = lvl + 1) begin : level_gen
            for (nd = 0; nd < NUM_ROWS; nd = nd + 1) begin : node_gen

                localparam L = 2 * nd;      // left  child in previous level
                localparam R = 2 * nd + 1;  // right child in previous level

                if (L >= NUM_ROWS) begin
                    // Dead node - lies beyond the active range; tie to 0
                    assign tree[lvl][nd] = {CNT_W{1'b0}};

                end else if (R >= NUM_ROWS) begin
                    // Odd (unpaired) node - pass left child straight through
                    assign tree[lvl][nd] = tree[lvl-1][L];

                end else begin
                    // Normal 2-input comparator: keep the larger value
                    assign tree[lvl][nd] =
                        (tree[lvl-1][L] >= tree[lvl-1][R])
                            ? tree[lvl-1][L]
                            : tree[lvl-1][R];
                end
            end
        end
    endgenerate

    // Root of the tree = maximum LZC across all rows = escape length x
    assign max_out = tree[LEVELS][0];

    // ----------------------------------------------------------
    // valid_out
    // If max_out == T: ALL rows were fully zero → no obstacle
    //                  snake escaped completely this stage
    // If max_out  < T: even the best row hit something → obstacle
    //                  snake consumed at least one obstacle bit
    // ----------------------------------------------------------
    assign valid_out = (max_out != T[CNT_W:0]);

endmodule