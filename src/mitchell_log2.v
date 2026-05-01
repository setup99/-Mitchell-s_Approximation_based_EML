// ============================================================
//  mitchell_log2.v
//  Mitchell's approximation:  log2(x) ≈ e + f
//
//  Input:  x  [W-1:0]  unsigned fixed-point  Q(W-F).F
//          (x must be > 0; caller must guarantee)
//  Output: y  [W-1:0]  signed   fixed-point  Q(W-F).F
//          representing log2(x) in the same format
//
//  Algorithm
//  ---------
//  Any positive x can be written as  x = 2^e * (1 + f)
//  where  e = floor(log2(x))  (integer exponent)
//         f = fractional mantissa  0 <= f < 1
//  Mitchell's key insight:
//         log2(x) = e + f          (approximation, max error ~0.086)
//
//  Hardware:
//    1. Leading-Zero Detector (LZD) → finds position of MSB → e
//    2. Barrel shifter          → aligns mantissa   → f
//    3. Concatenate e and f     → result
//
//  Parameters
//  ----------
//  W   total word width  (8 or 12)
//  F   fractional bits   (e.g. 4 for Q4.4 at W=8, 6 for Q6.6 at W=12)
// ============================================================

module mitchell_log2 #(
    parameter W = 12,   // total bits  (8 or 12)
    parameter F = 6     // fractional bits
)(
    input  wire [W-1:0]   x,      // unsigned fixed-point input
    output reg  [W-1:0]   y       // signed fixed-point log2(x)
);

    localparam INT = W - F;       // integer bits

    // ----------------------------------------------------------
    // 1. Leading-Zero Detector
    //    Find position of the most-significant '1' bit → exponent e
    // ----------------------------------------------------------
    reg [$clog2(W)-1:0] lzd_pos;   // position of MSB (0 = LSB)
    integer k;

    always @(*) begin
        lzd_pos = 0;
        for (k = 0; k < W; k = k + 1)
            if (x[k]) lzd_pos = k;
    end

    // e in fixed-point: shift left by F to place in integer field
    // e_fp = (lzd_pos - F) << F   (subtract F to account for Q format)
    // We treat lzd_pos as the unbiased exponent of the integer value
    wire signed [W-1:0] e_fp;
    assign e_fp = ($signed({{(W-$clog2(W)){1'b0}}, lzd_pos}) - $signed(F[W-1:0]))
                  <<< F;

    // ----------------------------------------------------------
    // 2. Barrel Shifter — extract fractional mantissa f
    //    After removing the implicit leading 1, the next F bits
    //    are the Mitchell fractional approximation.
    //    We shift x left so the MSB is at bit W-1, then take
    //    the F bits just below it.
    // ----------------------------------------------------------
    reg [W-1:0] x_shifted;
    always @(*) begin
        // shift left so MSB of x lands at bit position W-1
        x_shifted = x << (W - 1 - lzd_pos);
    end

    // f_fp: take the F bits below the implicit 1, placed in LSB field
    wire [W-1:0] f_fp;
    assign f_fp = {{INT{1'b0}}, x_shifted[W-2 -: F]};

    // ----------------------------------------------------------
    // 3. Result: log2(x) ≈ e + f
    // ----------------------------------------------------------
    always @(*) begin
        if (x == 0)
            y = {1'b1, {(W-1){1'b0}}};   // saturate to large negative
        else
            y = e_fp + $signed(f_fp);
    end

endmodule
