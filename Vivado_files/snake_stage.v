// ============================================================
// snake_stage.v  -  One Snake-on-Chip Pipeline Stage (y-instance)
// ============================================================
// Paper ref: Supplementary Section 8, Steps (2)+(3)+(4)
//
// ONE hardware routing iteration:
//
//   rows_in  (NUM_ROWS × T bits)
//      │
//      ├──► [LZC array]        NUM_ROWS parallel LZC units
//      │         │
//      │    [Comparator tree]  find x = max LZC across all rows
//      │         │              also produces valid_out
//      └──► [Barrel shifter]   shift all rows right by (x+1)
//                │
//      rows_out  (NUM_ROWS × T bits)  +  x_out  +  valid_out
//
// Fully combinational - no registers here.
// Registers live in snake_pipeline between stage instances.
//
// PARAMETERS
// ==========
//   E       - edit distance threshold  (sets NUM_ROWS = 2E+1)
//   T       - subproblem width in columns (bit-vector width)
//
// DERIVED (computed from T - do not override manually):
//   NUM_ROWS = 2*E + 1
//   CNT_W    = $clog2(T) + 1   holds 0..T
//   SHIFT_W  = $clog2(T+1)     holds shift amount 0..T
//
// PARAMETER DEPENDENCY NOTE:
//   CNT_W and SHIFT_W are both derived from T.
//   Changing only T is the single knob needed.
//   lzc.v, lzc_comparator_tree.v, and barrel_shifter.v all
//   derive their own widths from T and NUM_ROWS consistently.
//
// VALID_OUT
// =========
//   Propagated directly from lzc_comparator_tree.
//   valid_out = 1  →  at least one row had an obstacle this stage
//                      (max LZC < T, snake hit something)
//   valid_out = 0  →  all rows fully clear (max LZC == T)
//                      snake escaped without hitting anything
//   Used by snake_pipeline to count per-stage obstacle hits.
// ============================================================

module snake_stage #(
    parameter E       = 5,
    parameter T       = 8,
    // Derived from T - computed automatically, do not override
    parameter CNT_W   = $clog2(T) + 1,
    parameter SHIFT_W = $clog2(T+1)
)(
    input  wire [((2*E+1)*T)-1:0]   rows_in,
    output wire [((2*E+1)*T)-1:0]   rows_out,
    output wire [CNT_W-1:0]         x_out,
    output wire                      valid_out   // NEW: 1 = obstacle hit this stage
);

    localparam NUM_ROWS = 2*E + 1;

    // ----------------------------------------------------------
    // LZC array - one unit per row, all in parallel
    // ----------------------------------------------------------
    wire [NUM_ROWS*CNT_W-1:0] lzc_bus;

    genvar g;
    generate
        for (g = 0; g < NUM_ROWS; g = g + 1) begin : lzc_array
            lzc #(.T(T)) lzc_inst (
                .in   (rows_in[g*T +: T]),
                .count(lzc_bus[g*CNT_W +: CNT_W])
            );
        end
    endgenerate

    // ----------------------------------------------------------
    // Comparator tree - finds x = max LZC across all rows
    // Also produces valid_out: 1 if any row had an obstacle
    // ----------------------------------------------------------
    lzc_comparator_tree #(
        .NUM_ROWS(NUM_ROWS),
        .CNT_W   (CNT_W),
        .T       (T)          // NEW: needed for valid_out threshold
    ) comp_tree (
        .lzc_in   (lzc_bus),
        .max_out  (x_out),
        .valid_out(valid_out) // NEW: wired out to snake_pipeline
    );

    // ----------------------------------------------------------
    // Barrel shifter - shifts all rows right by (x+1)
    // ----------------------------------------------------------
    barrel_shifter #(
        .NUM_ROWS(NUM_ROWS),
        .T       (T),
        .SHIFT_W (SHIFT_W)
    ) shifter (
        .rows_in (rows_in),
        .x       (x_out),
        .rows_out(rows_out)
    );

endmodule