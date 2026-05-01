// ============================================================
//  eml_feedback_cell.v
//  EML tile with dual-mux feedback architecture
//
//  Adds two 2-to-1 multiplexers and one output register to
//  the base eml_tile, enabling iterative and cross-feedback
//  computation modes.
//
//  Port summary
//  ------------
//  clk          clock  (rising-edge triggers register)
//  rst          synchronous active-high reset
//  valid_in     pulse high for one cycle to load new data
//
//  x_ext [W-1:0]   external X input   (signed   Q6.6)
//  y_ext [W-1:0]   external Y input   (unsigned Q6.6)
//
//  sel_x        0 = X comes from x_ext
//               1 = X comes from feedback register (prev output)
//  sel_y        0 = Y comes from y_ext
//               1 = Y comes from feedback register (prev output)
//
//  out   [W-1:0]   registered output  (signed   Q6.6)
//  ovf              overflow flag (registered)
//  valid_out        output valid (registered, one-cycle delayed)
//
//  Mode table
//  ----------
//  sel_x  sel_y   mode
//    0      0     feed-forward   out = eml(x_ext, y_ext)
//    1      0     iterate X      out_n = eml(out_{n-1}, y_ext)
//    0      1     iterate Y      out_n = eml(x_ext,     out_{n-1})
//    1      1     cross-feedback out_n = eml(out_{n-1}, out_{n-1})
//
//  Fixed-point format: Q6.6  (W=12, F=6)
//    real = integer / 64
// ============================================================

`timescale 1ns/1ps

module eml_feedback_cell #(
    parameter W = 12,
    parameter F = 6
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             valid_in,

    input  wire signed [W-1:0]  x_ext,   // external X  (signed Q6.6)
    input  wire        [W-1:0]  y_ext,   // external Y  (unsigned Q6.6)

    input  wire                 sel_x,   // 0=external  1=feedback
    input  wire                 sel_y,   // 0=external  1=feedback

    output reg  signed [W-1:0]  out,     // registered result
    output reg                  ovf,     // overflow flag
    output reg                  valid_out
);

    // ----------------------------------------------------------
    // Feedback register  (holds previous out)
    // ----------------------------------------------------------
    reg [W-1:0] fb_reg;   // unsigned storage (same bits, sign-depends on use)

    // ----------------------------------------------------------
    // MUX X:  select external input or feedback
    // ----------------------------------------------------------
    wire signed [W-1:0] x_in;
    assign x_in = sel_x ? $signed(fb_reg) : x_ext;

    // ----------------------------------------------------------
    // MUX Y:  select external input or feedback
    // ----------------------------------------------------------
    wire [W-1:0] y_in;
    assign y_in = sel_y ? fb_reg : y_ext;

    // ----------------------------------------------------------
    // EML tile  (combinational)
    // ----------------------------------------------------------
    wire signed [W-1:0] tile_out;
    wire                tile_ovf;

    eml_tile #(.W(W), .F(F)) u_tile (
        .x   (x_in),
        .y   (y_in),
        .out (tile_out),
        .ovf (tile_ovf)
    );

    // ----------------------------------------------------------
    // Output register  +  feedback register update
    // Both capture on rising clock when valid_in is asserted.
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            out       <= {W{1'b0}};
            ovf       <= 1'b0;
            valid_out <= 1'b0;
            fb_reg    <= {W{1'b0}};
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                out    <= tile_out;
                ovf    <= tile_ovf;
                fb_reg <= tile_out;   // store for next iteration
            end
        end
    end

endmodule
