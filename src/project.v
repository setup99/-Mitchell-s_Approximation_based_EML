/*
 * Copyright (c) 2024 Tiny Tapeout
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_Mitchell_s_Approximation_based_EML (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Map UIO pins to the SPI interface used by the EML SPI wrapper.
    // uio_in[0] = MOSI, uio_in[1] = SCLK, uio_in[2] = CS_N
    wire spi_mosi = uio_in[0];
    wire spi_sck  = uio_in[1];
    wire spi_cs_n = uio_in[2];
    wire spi_miso;

    eml_spi_wrapper #(.W(12), .F(6)) u_spi (
        .clk   (clk),
        .rst   (~rst_n),
        .sclk  (spi_sck),
        .cs_n  (spi_cs_n),
        .mosi  (spi_mosi),
        .miso  (spi_miso)
    );

    assign uio_out = {7'b0, spi_miso};
    assign uio_oe  = 8'b0000_0001;
    assign uo_out  = 8'h00;

    // Keep unused host pins connected to prevent warnings.
    wire _unused = &{ui_in, ena, clk, 1'b0};

endmodule
