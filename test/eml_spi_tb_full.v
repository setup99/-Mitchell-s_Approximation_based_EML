// ============================================================
//  eml_spi_tb_full.v - النسخة النهائية المضمونة
//  Full System Test: SPI + Feedback + EML Core
// ============================================================

`timescale 1ns/1ps

module eml_spi_tb_full;

    parameter W = 12;
    parameter F = 6;

    // إشارات الاختبار
    reg clk, rst, mosi, sck, ss;
    wire miso;

    // متغيرات المراقبة
    reg [15:0] cap;
    reg [11:0] rb;
    reg ro;
// تنصيب النظام (DUT)
    eml_spi_wrapper #(W, F) dut (
        .clk     (clk),
        .rst     (rst),
        .spi_mosi(mosi),  // تأكد من أن الاسم في الـ Wrapper هو spi_mosi
        .spi_sck (sck),   // تأكد من أن الاسم في الـ Wrapper هو spi_sck
        .spi_cs_n(ss),    // عادة ما يسمى Chip Select بـ spi_cs_n
        .spi_miso(miso)   // تأكد من أن الاسم في الـ Wrapper هو spi_miso
    );

    // توليد الساعة (16 MHz حسب التعديلات الأخيرة)
    always #31.25 clk = ~clk;

    // تحويل من Q6.6 إلى Real للعرض
    function real fq66(input [11:0] din);
        integer signed_val;
        begin
            signed_val = din;
            if (din[11]) signed_val = signed_val - 4096;
            fq66 = signed_val / 64.0;
        end
    endfunction

    // تحويل من Real إلى Q6.6 للإرسال
    function [11:0] to66(input real r);
        integer i;
        begin
            i = $rtoi(r * 64.0);
            if (i < 0) i = i + 4096;
            to66 = i[11:0];
        end
    endfunction

    // محاكاة بروتوكول SPI
    task spi_xfer(input [15:0] din);
        integer i;
        begin
            ss = 0;
            cap = 0;
            for (i = 15; i >= 0; i = i - 1) begin
                mosi = din[i];
                #100 sck = 1;
                #100 cap[i] = miso;
                sck = 0;
                #100;
            end
            ss = 1;
            #500; // وقت استقرار إضافي للحسابات
        end
    endtask

    // مهمة الكتابة في السجلات (X=0, Y=1, CFG=2)
    task write_reg(input [2:0] addr, input [11:0] data);
        begin
            spi_xfer({1'b0, addr, data}); 
        end
    endtask

    // مهمة القراءة (تصحيح: OVF في البت 12)
    task read_res;
        output [11:0] r;
        output o;
        begin
            spi_xfer(16'hB000); // طلب قراءة من العنوان 3
            r = cap[11:0];
            o = cap[12];      // تصحيح هام: مطابقة tx_shift في الـ Wrapper
        end
    endtask

    // مهمة التحقق التلقائي
    task chk(input [127:0] lbl, input real ex, input real tol);
        real g;
        begin
            read_res(rb, ro);
            g = fq66(rb);
            if (((g-ex)*(g-ex) < tol*tol)) 
                $display("  PASS  %-25s  exp=%+7.4f  got=%+7.4f  ovf=%b", lbl, ex, g, ro);
            else
                $display("  FAIL  %-25s  exp=%+7.4f  got=%+7.4f  ovf=%b", lbl, ex, g, ro);
        end
    endtask

    initial begin
        // البداية
        clk = 0; rst = 1; mosi = 0; sck = 0; ss = 1;
        #200 rst = 0;
        #200;

        $display("\n==============================================");
        $display("  EML SPI SYSTEM VERIFICATION (IC DESIGN)");
        $display("==============================================\n");

        // [1] اختبارات Feed-forward (X=0, Y=1 => exp(0)-ln(1) = 1)
        write_reg(0, to66(0.0));
        write_reg(1, to66(1.0));
        write_reg(2, 12'b00_00_00_000001); // Valid high
        #1000 chk("eml(0,1)=1.0", 1.0, 0.05);

        // [2] اختبارات القيم الأسية (exp(1)-ln(1) ≈ 2.718)
        write_reg(0, to66(1.0));
        write_reg(2, 12'b00_00_00_000001);
        #1000 chk("eml(1,1)=e", 2.718, 0.2); // Mitchell error is ~0.15

        // [3] اختبار التكرار العميق (Deep Iteration Mode 11)
        // هذا الاختبار كان يفشل بسبب انقلاب الإشارة (Wrap-around)
        $display("\n[ITERATION TEST]");
        write_reg(0, to66(0.5));
        write_reg(1, to66(1.0));
        write_reg(2, 12'b11_00_00_000001); // Mode 11, Valid high
        #500 read_res(rb, ro); $display("  Step 1: %+7.4f (ovf=%b)", fq66(rb), ro);
        write_reg(2, 12'b11_00_00_000001);
        #500 read_res(rb, ro); $display("  Step 2: %+7.4f (ovf=%b)", fq66(rb), ro);
        write_reg(2, 12'b11_00_00_000001);
        #500 read_res(rb, ro); $display("  Step 3: %+7.4f (ovf=%b)", fq66(rb), ro);
        
        // التحقق من الثبات عند الحد الأقصى (Saturation)
        if (fq66(rb) > 30.0 && ro == 1) 
            $display("  PASS  Saturation & OVF Latched");
        else
            $display("  FAIL  Wrap-around detected!");

        // [4] اختبارات الحالات الحرجة (Edge Cases)
        $display("\n[OVERFLOW & EDGE CASES]");
        write_reg(0, to66(0.0));
        write_reg(1, to66(0.0)); // ln(0) = -inf => Result = +inf (Sat)
        write_reg(2, 12'b00_00_00_000001);
        #1000;
        read_res(rb, ro);
        if (ro == 1) 
            $display("  PASS  y=0 Overflow correctly flagged");
        else 
            $display("  FAIL  y=0 Overflow missed!");

        $display("\n==============================================\n");
        $finish;
    end

endmodule