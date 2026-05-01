// ============================================================
//  eml_spi_wrapper.v  (v2 - fixed MISO timing)
//  SPI slave wrapper for the EML feedback cell
//
//  SPI: CPOL=0 CPHA=0, 16-bit MSB-first frames
//  Frame: [15]=R/W  [14:12]=addr  [11:0]=data
//
//  Register map
//  0x0  CTRL_REG   [0]=sel_x [1]=sel_y [2]=valid_in  (W)
//  0x1  X_EXT_REG  signed Q6.6 x_ext                  (W)
//  0x2  Y_EXT_REG  unsigned Q6.6 y_ext                (W)
//  0x3  RESULT_REG {ovf, out[11:0]}                   (R)
//
//  MISO is pre-loaded on CS falling edge (first bit on MISO
//  before first SCLK rise) and shifts on each SCLK falling edge.
// ============================================================
`timescale 1ns/1ps

module eml_spi_wrapper #(
    parameter W = 12,
    parameter F = 6
)(
    input  wire  clk,
    input  wire  rst,
    input  wire  sclk,
    input  wire  cs_n,
    input  wire  mosi,
    output reg   miso
);

    // ── register bank ─────────────────────────────────────────
    reg         reg_sel_x;
    reg         reg_sel_y;
    reg  [W-1:0] reg_x_ext;
    reg  [W-1:0] reg_y_ext;
    reg  [W-1:0] result_latch;
    reg          ovf_latch;

    // ── 3-stage synchronisers ─────────────────────────────────
    reg [2:0] sclk_r, cs_r, mosi_r;
    always @(posedge clk) begin
        sclk_r <= {sclk_r[1:0], sclk};
        cs_r   <= {cs_r[1:0],   cs_n};
        mosi_r <= {mosi_r[1:0], mosi};
    end

    wire sclk_rise = (sclk_r[2:1] == 2'b01);
    wire sclk_fall = (sclk_r[2:1] == 2'b10);
    wire cs_fall   = (cs_r[2:1]   == 2'b10);   // CS asserted (high→low)
    wire cs_active = ~cs_r[2];
    wire mosi_s    = mosi_r[2];

    // ── SPI shift register ────────────────────────────────────
    reg [15:0] rx_shift;    // incoming MOSI bits
    reg [15:0] tx_shift;    // outgoing MISO bits
    reg [4:0]  bit_cnt;     // 0..15, 16=done
    reg        frame_done;
    reg [15:0] rx_frame;    // latched complete frame

    always @(posedge clk) begin
        if (rst) begin
            rx_shift   <= 0;
            tx_shift   <= 0;
            bit_cnt    <= 0;
            frame_done <= 0;
            rx_frame   <= 0;
            miso       <= 0;
        end else begin
            frame_done <= 0;

            // Pre-load MISO shift register at CS falling edge
            // so bit 15 is already on MISO before first SCLK rise
            if (cs_fall) begin
                tx_shift <= {2'b0, ovf_latch, result_latch};
                miso     <= ovf_latch;   // drive bit 15 immediately
                bit_cnt  <= 0;
            end

            if (cs_active) begin
                if (sclk_rise) begin
                    // sample MOSI
                    rx_shift <= {rx_shift[14:0], mosi_s};
                    bit_cnt  <= bit_cnt + 1;
                    // latch full frame after 16th bit
                    if (bit_cnt == 5'd15) begin
                        rx_frame   <= {rx_shift[14:0], mosi_s};
                        frame_done <= 1;
                        bit_cnt    <= 0;
                    end
                end

                if (sclk_fall) begin
                    // shift MISO, drive next bit
                    tx_shift <= {tx_shift[14:0], 1'b0};
                    miso     <= tx_shift[14];  // next bit (current [15] just sent)
                end
            end else begin
                bit_cnt <= 0;
            end
        end
    end

    // ── decode frame ──────────────────────────────────────────
    wire        frame_rw   = rx_frame[15];
    wire [2:0]  frame_addr = rx_frame[14:12];
    wire [11:0] frame_data = rx_frame[11:0];

    // valid_in: self-clearing pulse (one cycle)
    reg valid_in_r;
    reg valid_pending;

    always @(posedge clk) begin
        if (rst) begin
            reg_sel_x    <= 0;
            reg_sel_y    <= 0;
            reg_x_ext    <= 0;
            reg_y_ext    <= 0;
            valid_in_r   <= 0;
            valid_pending<= 0;
        end else begin
            valid_in_r    <= valid_pending;
            valid_pending <= 0;

            if (frame_done && !frame_rw) begin
                case (frame_addr)
                    3'h0: begin
                        reg_sel_x <= frame_data[0];
                        reg_sel_y <= frame_data[1];
                        if (frame_data[2]) valid_pending <= 1;
                    end
                    3'h1: reg_x_ext <= frame_data;
                    3'h2: reg_y_ext <= frame_data;
                    default: ;
                endcase
            end
        end
    end

    // ── EML feedback cell ─────────────────────────────────────
    wire signed [W-1:0] eml_out;
    wire                eml_ovf;
    wire                eml_valid_out;

    eml_feedback_cell #(.W(W), .F(F)) u_eml (
        .clk      (clk),
        .rst      (rst),
        .valid_in (valid_in_r),
        .x_ext    ($signed(reg_x_ext)),
        .y_ext    (reg_y_ext),
        .sel_x    (reg_sel_x),
        .sel_y    (reg_sel_y),
        .out      (eml_out),
        .ovf      (eml_ovf),
        .valid_out(eml_valid_out)
    );

    // ── latch result ──────────────────────────────────────────
    always @(posedge clk) begin
        if (rst) begin
            result_latch <= 0;
            ovf_latch    <= 0;
        end else if (eml_valid_out) begin
            result_latch <= eml_out;
            ovf_latch    <= eml_ovf;
        end
    end

endmodule
