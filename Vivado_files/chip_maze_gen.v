// ============================================================
// chip_maze_gen.v  -  Chip Maze Generator for Snake-on-Chip
// ============================================================
// Paper ref: Supplementary Section 8, Step (1) and Equation (1)
//
// Builds ONE (2E+1) × T chip maze subproblem.
//
// ALIGNMENT MODEL
// ===============
// For subproblem block s, reference window = ref[s*T .. s*T+T-1].
// Query window = T+2E chars starting E positions before the block:
//   query_block[k] = query[s*T - E + k],  k = 0 .. T+2E-1
//
// For row i (shift = i-E), column j:
//   ref  char: ref_block[j]
//   query char: query_block[j + i]     (j+i = j + shift + E)
//
// maze[i][j] = 0  (match  → free path)
//            = 1  (mismatch or padding sentinel → obstacle)
//
// CHARACTER ENCODING (3-bit, CHAR_W=3)
// =====================================
//   A = 3'b000
//   C = 3'b001
//   G = 3'b010
//   T = 3'b011
//   B = 3'b100  ← padding sentinel ONLY, never in real sequence data
//
// Why 3-bit: with 2-bit encoding T(thymine)=2'b11 collided with
// the padding sentinel. 3-bit gives a clean unused code (B=100)
// that never matches any real base, so padded positions always
// produce obstacle bits (1) in the maze - correct behaviour.
//
// PARAMETERS
// ==========
//   E      - edit distance threshold
//   T      - subproblem column count
//   CHAR_W - character width in bits  ← SET TO 3 for 3-bit encoding
//
// DERIVED (do not override):
//   NUM_ROWS = 2*E + 1
//   Q_WINDOW = T + 2*E    (query window width per block)
//
// PARAMETER DEPENDENCY NOTE:
//   If you change E, NUM_ROWS and Q_WINDOW both change.
//   If you change T, Q_WINDOW changes and all bus widths change.
//   If you change CHAR_W, all bus widths change - update the
//   encoding constants in all testbenches accordingly.
//
// PORTS
// =====
//   ref_block   [T*CHAR_W-1:0]            T reference characters
//   query_block [Q_WINDOW*CHAR_W-1:0]     T+2E query characters
//   maze_rows   [NUM_ROWS*T-1:0]          output bit-matrix
//
// Packing convention:
//   ref_block  [j*CHAR_W   +: CHAR_W]  = ref char at column j
//   query_block[k*CHAR_W   +: CHAR_W]  = query char at window index k
//   maze_rows  [i*T + j]               = bit for row i, column j
//   maze_rows  [i*T +: T]              = full bit-vector for row i
//
// Fully combinational - no registers, no clock.
// ============================================================

module chip_maze_gen #(
    parameter E      = 5,
    parameter T      = 8,
    parameter CHAR_W = 3        // ← 3-bit encoding: A=000 C=001 G=010 T=011 B=100
)(
    input  wire [T*CHAR_W-1:0]            ref_block,
    input  wire [((T+2*E)*CHAR_W)-1:0]    query_block,
    output wire [((2*E+1)*T)-1:0]          maze_rows
);

    // ----------------------------------------------------------
    // Derived parameters
    // ----------------------------------------------------------
    localparam NUM_ROWS = 2*E + 1;   // number of HRT rows
    localparam Q_WINDOW = T + 2*E;   // query window width in characters

    // ----------------------------------------------------------
    // Build maze: one bit per (row, column) cell
    // For each cell compare ref_block[j] with query_block[j+i].
    // Any mismatch OR padding sentinel (B) → obstacle (1).
    // B = CHAR_W'b100 never equals A/C/G/T, so it auto-generates
    // obstacle bits without any special-case logic needed here.
    // ----------------------------------------------------------
    genvar i, j;
    generate
        for (i = 0; i < NUM_ROWS; i = i + 1) begin : row_gen
            for (j = 0; j < T; j = j + 1) begin : col_gen

                // Query window index: always in [0, Q_WINDOW-1]
                localparam integer Q_IDX = j + i;

                wire [CHAR_W-1:0] ref_char   = ref_block  [j     * CHAR_W +: CHAR_W];
                wire [CHAR_W-1:0] query_char = query_block[Q_IDX * CHAR_W +: CHAR_W];

                // 0 = match (free), 1 = mismatch or padding (obstacle)
                assign maze_rows[i*T + j] = (ref_char == query_char) ? 1'b0 : 1'b1;
            end
        end
    endgenerate

endmodule