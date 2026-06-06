// ============================================================
// barrel_shifter.v  -  Row-parallel right-shift for Snake-on-Chip
// ============================================================
// Paper ref: Supplementary Section 8, Step (4)
//
// After the comparator tree finds x (longest escape segment),
// Snake-on-Chip must create a new checkpoint by shifting ALL
// (2E+1) bit-vector rows to the right by (x + 1) bits:
//   - x bits  : skip past the escape segment (the zeros)
//   - +1 bit  : skip the obstacle at the end of the escape segment
//
// This module takes all NUM_ROWS T-bit vectors as a flat packed
// bus, applies the same shift amount to every row, and outputs
// the shifted vectors on another flat packed bus.
//
// Bit ordering (matches lzc.v convention):
//   in[0]  = LSB = current checkpoint (leftmost cell)
//   in[T-1]= MSB = rightmost cell
// Shifting right by N means:
//   out = in >> N   (zeros fill in from the MSB side)
// The new checkpoint is now at out[0].
//
// Parameters (paper-exact):
//   NUM_ROWS = 11   (2*E+1, E=5)
//   T        = 8   (subproblem column count)
//   SHIFT_W  = $clog2(T+1) = 4  (shift amount needs to hold 0..T)
//              For T=8: shift can be 0..8, so 4 bits needed.
//
// Fully combinational - no registers.
// ============================================================

module barrel_shifter #(
    parameter NUM_ROWS = 11,              // 2*E+1
    parameter T        = 8,              // bit-vector width
    parameter SHIFT_W  = $clog2(T+1)    // bits to represent 0..T  (=4 for T=8)
)(
    // Input: all rows packed, row i occupies bits [i*T +: T]
    input  wire [NUM_ROWS*T-1:0]   rows_in,

    // Shift amount = x (escape length from comparator tree).
    // Hardware applies shift of (x + 1) internally.
    // We accept x here so the caller doesn't need to add 1.
    input  wire [SHIFT_W-1:0]      x,

    // Output: all rows shifted right by (x+1), same packing
    output wire [NUM_ROWS*T-1:0]   rows_out
);

    // ----------------------------------------------------------
    // Compute actual shift amount: shift = x + 1
    // We need SHIFT_W+1 bits to safely hold x+1 when x = T = 8
    // (8+1 = 9, which still fits in 4 bits since max useful shift
    //  is T=8 → 9 would shift everything out → all zeros, correct)
    // We clamp: if (x+1) >= T, output is all zeros anyway.
    // ----------------------------------------------------------
    wire [SHIFT_W:0] shift_amount = {1'b0, x} + 1'b1;  // x+1, one extra bit

    // ----------------------------------------------------------
    // Apply the shift to each row independently.
    // Because all rows use the same shift amount, we use a
    // generate loop for compactness.
    // Each row is a simple logical right shift (>> fills with 0s).
    // ----------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_ROWS; i = i + 1) begin : shift_rows
            // Extract row i from the packed input
            wire [T-1:0] row_in  = rows_in[i*T +: T];

            // Shift right by (x+1).
            // Verilog >> on an unsigned wire fills with zeros - correct.
            // If shift_amount >= T, result is 0 (all bits shifted out).
            wire [T-1:0] row_out = (shift_amount >= T) ? {T{1'b0}}
                                                       : (row_in >> shift_amount);

            assign rows_out[i*T +: T] = row_out;
        end
    endgenerate

endmodule