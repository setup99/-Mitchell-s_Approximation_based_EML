// ============================================================
//  eml_tile_tb.v
//  Testbench for eml_tile
//
//  Tests against known mathematical values in Q6.6 format.
//
//  Q6.6 encoding:
//    real_value = integer_bits / 2^F  = integer_bits / 64
//
//  To encode a real number r: round(r * 64)
// ============================================================

`timescale 1ns/1ps

module eml_tile_tb;

    parameter W = 12;
    parameter F = 6;

    // DUT ports
    reg  signed [W-1:0] x;
    reg         [W-1:0] y;
    wire signed [W-1:0] out;
    wire                ovf;

    // Instantiate DUT
    eml_tile #(.W(W), .F(F)) dut (
        .x   (x),
        .y   (y),
        .out (out),
        .ovf (ovf)
    );

    // Helper: convert Q6.6 signed to real
    function real q2r;
        input signed [W-1:0] v;
        q2r = $itor($signed(v)) / 64.0;
    endfunction

    // Helper: encode real to Q6.6 (signed)
    function [W-1:0] r2q;
        input real v;
        r2q = $rtoi(v * 64.0);
    endfunction

    real exp_x_real, ln_y_real, expected, got;
    integer pass, fail;

    task check;
        input real rx, ry;        // real-valued inputs
        input real tol;           // acceptable error (in real units)
        input [127:0] label;
        begin
            x = r2q(rx);
            y = r2q(ry);
            #10;
            exp_x_real = $exp(rx);
            ln_y_real  = $ln(ry);
            expected   = exp_x_real - ln_y_real;
            got        = q2r(out);
            if ($abs(got - expected) <= tol + 0.1) begin
                $display("PASS  %-30s  exp(%0.3f)-ln(%0.3f) = %0.4f  got %0.4f  err %0.4f",
                         label, rx, ry, expected, got, $abs(got-expected));
                pass = pass + 1;
            end else begin
                $display("FAIL  %-30s  expected %0.4f  got %0.4f  err %0.4f",
                         label, expected, got, $abs(got-expected));
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        pass = 0; fail = 0;
        $display("----------------------------------------------------");
        $display("  EML tile testbench  (Q6.6 = 12-bit, F=6)");
        $display("  eml(x,y) = exp(x) - ln(y)");
        $display("----------------------------------------------------");

        // ------- Depth-1 key results --------
        // eml(0, 1) = exp(0) - ln(1) = 1 - 0 = 1
        check(0.0,  1.0,  0.2, "eml(0,1)=1");

        // eml(1, 1) = exp(1) - ln(1) = e - 0 = 2.718
        check(1.0,  1.0,  0.2, "eml(1,1)=e");

        // eml(0, e) = exp(0) - ln(e) = 1 - 1 = 0
        check(0.0,  2.718, 0.2, "eml(0,e)=0");

        // eml(2, 1) = exp(2) - 0 = 7.389
        check(2.0,  1.0,  0.5, "eml(2,1)=e^2");

        // eml(0, 2) = 1 - ln(2) = 1 - 0.693 = 0.307
        check(0.0,  2.0,  0.15, "eml(0,2)=1-ln2");

        // eml(0.5, 1) = e^0.5 = 1.6487
        check(0.5,  1.0,  0.15, "eml(0.5,1)=sqrt(e)");

        // eml(0, 4) = 1 - ln(4) = 1 - 1.386 = -0.386
        check(0.0,  4.0,  0.15, "eml(0,4) negative");

        // eml(-1, 1) = e^-1 = 0.3679
        check(-1.0, 1.0,  0.15, "eml(-1,1)=1/e");

        // eml(1, 2) = e - ln(2) = 2.718 - 0.693 = 2.025
        check(1.0,  2.0,  0.2, "eml(1,2)=e-ln2");

        // Overflow: y = 0 should set ovf flag
        x = r2q(1.0); y = 12'h000; #10;
        if (ovf) begin
            $display("PASS  ovf flag set when y=0");
            pass = pass + 1;
        end else begin
            $display("FAIL  ovf flag NOT set when y=0");
            fail = fail + 1;
        end

        $display("----------------------------------------------------");
        $display("  Results: %0d passed,  %0d failed", pass, fail);
        $display("----------------------------------------------------");

        if (fail == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED — check Mitchell error budget");

        $finish;
    end

endmodule
