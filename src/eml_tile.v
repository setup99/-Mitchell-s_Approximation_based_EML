// ============================================================
//  eml_tile.v
//  Single EML gate tile — the atomic unit of the EML matrix
//
//  Computes:  out = exp(x) - ln(y)
//
//  Implementation via Mitchell's approximation:
//    ln(x)   = log2(x) / log2(e)  ≈ log2(x) * 0.693
//    exp(x)  = 2^(x / ln2)        = 2^(x * 1.4427)
//
//  Fixed-point format: Q6.6  (12-bit, 6 integer + 6 fractional)
//  Range:  integer ~  -32 .. +31
//          fractional resolution:  1/64 ≈ 0.0156
//
//  All arithmetic is combinational (no clock).
//  For pipelining, wrap in registers at the parent level.
//
//  Port summary
//  ------------
//  x    [11:0]  signed Q6.6   argument to exp()
//  y    [11:0]  unsigned Q6.6 argument to ln()  (must be > 0)
//  out  [11:0]  signed Q6.6   result = exp(x) - ln(y)
//  ovf           overflow flag (exp overflowed or y==0)
// ============================================================

`timescale 1ns/1ps

module eml_tile #(
    parameter W = 12,   // word width
    parameter F = 6     // fractional bits  → Q6.6
)(
    input  wire signed [W-1:0]  x,      // exponent argument
    input  wire        [W-1:0]  y,      // log argument (unsigned)
    output wire signed [W-1:0]  out,    // exp(x) - ln(y)
    output wire                 ovf     // overflow / domain error
);

    // ---- Constants in Q6.6 ----------------------------------------
    // 1/ln(2)  = 1.4427  → Q6.6: round(1.4427 * 64) = 92 = 12'sh05C
    // ln(2)    = 0.6931  → Q6.6: round(0.6931 * 64) = 44 = 12'sh02C
    localparam signed [W-1:0] INV_LN2 = 12'sh05C;  // 92 → 92/64 = 1.4375
    localparam signed [W-1:0] LN2     = 12'sh02C;  // 44 → 44/64 = 0.6875

    // ---------------------------------------------------------------
    // Step 1: compute  exp(x)
    //   a) x2 = x * (1/ln2) in Q6.6, product is Q12.12, take middle W bits
    //   b) feed x2 into mitchell_exp2
    // ---------------------------------------------------------------
    // x is Q6.6 signed, INV_LN2 is Q6.6 signed
    // product is Q12.12 in 24-bit register; take bits [2F+W-1:2F] = [23:12]
    // but we only have W=12 bits of integer result, so take [F+W-1:F] = [17:6]
    wire signed [2*W-1:0] x_scaled_wide;
    assign x_scaled_wide = x * INV_LN2;

    // x_scaled_wide is Q12.12 (24-bit signed).
    // To get a Q6.6 result we take bits [2F+W-1 : 2F] but cap at W bits.
    // For small x this is bits [17:6] of the 24-bit product.
    wire signed [W-1:0] x2;
    assign x2 = x_scaled_wide[F + W - 1 : F];

    wire [W-1:0] exp_x;
    mitchell_exp2 #(.W(W), .F(F)) u_exp (
        .x  (x2),
        .y  (exp_x)
    );

    // ---------------------------------------------------------------
    // Step 2: compute  ln(y)
    //   a) mitchell_log2 gives log2(y) in Q6.6
    //   b) ln(y) = log2(y) * ln(2)
    // ---------------------------------------------------------------
    wire signed [W-1:0] log2_y;
    mitchell_log2 #(.W(W), .F(F)) u_log (
        .x  (y),
        .y  (log2_y)
    );

    // log2_y * LN2: both Q6.6, product is Q12.12 in 24-bit
    wire signed [2*W-1:0] ln_y_wide;
    assign ln_y_wide = log2_y * LN2;

    wire signed [W-1:0] ln_y;
    assign ln_y = ln_y_wide[F + W - 1 : F];

    // ---------------------------------------------------------------
    // Step 3: subtract
    // ---------------------------------------------------------------
    wire signed [W:0] diff_wide;
    assign diff_wide = $signed({1'b0, exp_x}) - $signed({ln_y[W-1], ln_y});

    // Saturate to W bits
    assign out = (diff_wide[W] != diff_wide[W-1])
                 ? (diff_wide[W] ? {1'b1,{(W-1){1'b0}}} : {1'b0,{(W-1){1'b1}}})
                 : diff_wide[W-1:0];

    // ---------------------------------------------------------------
    // Overflow / domain error flag
    // ---------------------------------------------------------------
    assign ovf = (y == 0)                       // ln(0) undefined
               | (diff_wide[W] != diff_wide[W-1]); // subtraction overflow

endmodule