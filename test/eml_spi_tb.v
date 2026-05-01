`timescale 1ns/1ps
module eml_spi_tb;
  reg clk,rst,sclk,cs_n,mosi; wire miso;
  eml_spi_wrapper #(.W(12),.F(6)) dut(.clk,.rst,.sclk,.cs_n,.mosi,.miso);
  initial clk=0; always #5 clk=~clk;

  reg [15:0] cap;
  task spi_xfer; input [15:0] fo; integer i; begin
    cap=0; cs_n=0; #200;
    for(i=15;i>=0;i=i-1) begin mosi=fo[i]; #50; sclk=1; #10; cap[i]=miso; #40; sclk=0; #50; end
    #500; cs_n=1; #2000; end endtask

  function [11:0] q66; input real v; integer r; begin
    r=$rtoi(v*64.0); if(r>2047)r=2047; if(r<-2048)r=-2048; q66=r[11:0]; end endfunction

  function real fq66; input [11:0] v; real sv; begin
    if(v[11]) sv=$itor($signed(v)); else sv=$itor(v); fq66=sv/64.0; end endfunction

  task read_res; output [11:0] r; output o; begin
    spi_xfer(16'hB000); r=cap[11:0]; o=cap[13]; end endtask

  task wtrig; input real rx,ry; input [1:0] sel; begin
    spi_xfer({4'h1,q66(rx)}); spi_xfer({4'h2,q66(ry)});
    spi_xfer({4'h0,9'b0,1'b1,sel[1],sel[0]});
    repeat(10) @(posedge clk); end endtask

  reg [11:0] rb; reg ro;
  task chk; input [127:0] lbl; input real ex,tol; real g,e; begin
    read_res(rb,ro); g=fq66(rb); e=(g>ex)?(g-ex):(ex-g);
    $display("  %s  %-30s  exp=%+7.4f  got=%+7.4f  err=%.4f  ovf=%b",
             (e<=tol)?"PASS":"FAIL",lbl,ex,g,e,ro); end endtask

  initial begin
    $display("\n==============================================");
    $display("  EML SPI wrapper — full integration test");
    $display("==============================================");
    clk=0;rst=1;sclk=0;cs_n=1;mosi=0; #200; rst=0; #200;

    $display("\n  Mode 00  feed-forward");
    wtrig( 0.0, 1.0, 2'b00); chk("eml(0,1)=1.0",      1.0,   0.05);
    wtrig( 1.0, 1.0, 2'b00); chk("eml(1,1)=e",        2.718, 0.25);
    wtrig( 0.0, 2.0, 2'b00); chk("eml(0,2)=1-ln2",    0.307, 0.05);
    wtrig(-1.0, 1.0, 2'b00); chk("eml(-1,1)=1/e",     0.368, 0.05);
    wtrig( 0.5, 1.0, 2'b00); chk("eml(0.5,1)=sqrt(e)",1.649, 0.15);

    $display("\n  Mode 01  iterate X  (sel_x=1)");
    wtrig(0.0,1.0,2'b00); chk("seed eml(0,1)=1",    1.0,   0.10);
    spi_xfer({4'h0,9'b0,3'b101}); repeat(10) @(posedge clk);
    chk("step1 eml(1,1)=e",   2.718, 0.25);

    $display("\n  Mode 10  iterate Y  (sel_y=1)");
    wtrig(1.0,1.0,2'b00); chk("seed eml(1,1)=e",    2.718, 0.25);
    spi_xfer({4'h0,9'b0,3'b110}); repeat(10) @(posedge clk);
    chk("step1 eml(1,e)=e-1", 1.718, 0.25);

    $display("\n  Mode 11  cross-feedback");
    wtrig(0.0,1.0,2'b00); chk("seed eml(0,1)=1",    1.0,   0.10);
    spi_xfer({4'h0,9'b0,3'b111}); repeat(10) @(posedge clk);
    chk("step1 eml(1,1)=e",   2.718, 0.30);

    $display("\n  Overflow y=0");
    spi_xfer({4'h1,q66(1.0)}); spi_xfer({4'h2,12'h000});
    spi_xfer({4'h0,9'b0,3'b001}); repeat(10) @(posedge clk);
    read_res(rb,ro);
    $display("  %s  ovf when y=0  ovf=%b","PASS"==ro?"FAIL":"PASS",ro);

    $display("\n==============================================\n"); $finish;
  end
  initial begin #5_000_000; $display("WATCHDOG"); $finish; end
endmodule
