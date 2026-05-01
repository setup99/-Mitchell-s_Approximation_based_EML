`default_nettype none
`timescale 1ns/1ps

module tb;

    // DUT inputs
    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    reg        ena;
    reg        clk;
    reg        rst_n;

    // DUT outputs
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    `ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
   `endif
    // Instantiate DUT
    tt_um_Mitchell_s_Approximation_based_EML dut (
        `ifdef GL_TEST
        .VPWR(VPWR),
        .VGND(VGND),
        `endif
        .ui_in (ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena   (ena),
        .clk   (clk),
        .rst_n (rst_n)
    );

   
    // Dump waves
    initial begin
        $dumpfile("tb.fst");
        $dumpvars(0, tb);
    end

endmodule
