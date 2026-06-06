// ============================================================
// lzc.v  -  Leading Zero Counter for Snake-on-Chip
// ============================================================
// Paper ref: Supplementary Section 8, Step (2)
//
// The bit-vector represents one HRT (Horizontal Routing Track).
//   bit = 0  →  match  (free path)
//   bit = 1  →  obstacle
//
// Bit ordering convention (matches the paper):
//   in[0]  = LSB = leftmost cell (current checkpoint side)
//   in[T-1]= MSB = rightmost cell
//
// We scan from in[0] upward and count consecutive zeros
// before hitting the first '1'.
//
// Examples  (T=8):
//   in = 8'b0001_0110  →  count = 1  (in[0]=0, in[1]=1 → stop)
//   in = 8'b0000_1000  →  count = 3  (in[0..2]=0, in[3]=1)
//   in = 8'b0000_0000  →  count = 8  (all zeros → full escape)
//   in = 8'b0000_0001  →  count = 0  (in[0]=1 → obstacle right away)
//
// Output width = $clog2(T)+1  to hold values 0 … T inclusive.
// For T=8  → 4 bits  (values 0..8)
// ============================================================

module lzc #(
    parameter T = 8  // bit-vector width (= subproblem column count)
)(
    input  wire [T-1:0]           in,      // t-bit HRT bit-vector
    output wire [$clog2(T):0]     count    // leading-zero count  (0 … T)
);

    // ----------------------------------------------------------
    // Pure combinational priority encoder
    //
    // We use a generate loop to build a chain of conditional
    // expressions - this is fully synthesisable and maps to a
    // priority encoder / LUT tree on the FPGA (exactly what the
    // Dimitrakopoulos 2008 design produces).
    // ----------------------------------------------------------

    // Internal array: found[i] = 1 if in[i] is the FIRST '1' bit
    // We compute count as the index of the lowest set bit.
    // If no bit is set, count = T.

    // We implement this as a cascaded mux chain using a
    // parameterised generate block so it works for any T.

    // intermediate wire array: partial_count[i] holds the answer
    // assuming we have already checked bits [i-1:0] and none were 1.
    // partial_count[0] = T  (base case: all zeros)
    // partial_count[i] = (in[i-1] == 1) ? (i-1) : partial_count[i+1]
    // final answer      = (in[0]  == 1) ? 0     : partial_count[1]

    // Use a wire array of T+1 entries.
    wire [$clog2(T):0] pc [0:T];   // pc[T] = base case

    assign pc[T] = T[$clog2(T):0]; // all zeros → count = T

    genvar i;
    generate
        for (i = T-1; i >= 0; i = i - 1) begin : lzc_chain
            // If in[i] is set, the first '1' is at position i → count = i
            // Otherwise inherit from the next higher partial result
            assign pc[i] = in[i] ? i[$clog2(T):0] : pc[i+1];
        end
    endgenerate

    assign count = pc[0];

endmodule