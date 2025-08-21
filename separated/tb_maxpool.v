`timescale 1ns/1ps

module tb_MaxPool2x2;

  reg clk, rst, en;
  reg  [7:0] A0, A1, A2, A3;   // unsigned inputs only (0..255)
  wire [7:0] Y;
  wire valid;

  // DUT
  MaxPool2x2 #(.In_W(8)) dut (
    .clk(clk),
    .rst(rst),
    .en(en),
    .A0(A0), .A1(A1), .A2(A2), .A3(A3),
    .Y(Y),
    .valid(valid)
  );

  // clock: 100MHz
  initial clk = 0;
  always #5 clk = ~clk;

  reg [31:0] errors;

  // unsigned max helpers
  function [7:0] umax2(input [7:0] x, input [7:0] y);
    begin umax2 = (x > y) ? x : y; end
  endfunction

  function [7:0] umax4(input [7:0] a0, input [7:0] a1, input [7:0] a2, input [7:0] a3);
    reg [7:0] m01, m23;
    begin
      m01   = umax2(a0,a1);
      m23   = umax2(a2,a3);
      umax4 = umax2(m01,m23);
    end
  endfunction

  task apply_u(input [7:0] a0, input [7:0] a1, input [7:0] a2, input [7:0] a3, input [255:0] name);
    reg [7:0] exp;
  begin
    exp = umax4(a0,a1,a2,a3);

    // drive on negedge, sample on next posedge
    @(negedge clk);
    A0 <= a0; A1 <= a1; A2 <= a2; A3 <= a3; en <= 1'b1;

    @(posedge clk); #1;
    if (!valid) begin
      $display("[MaxPool][%s] VALID=0", name);
      errors = errors + 1;
    end else if (Y !== exp) begin
      $display("[MaxPool][%s] MISMATCH: Y=%0d exp=%0d  (A0..A3=%0d,%0d,%0d,%0d)",
               name, Y, exp, a0,a1,a2,a3);
      errors = errors + 1;
    end

    // idle cycle
    @(negedge clk);
    en <= 1'b0;
    @(posedge clk);
  end
  endtask

  initial begin
    errors = 0;
    rst = 1; en = 0; A0=0; A1=0; A2=0; A3=0;
    repeat(3) @(posedge clk);
    rst = 0;

    // ---- unsigned-only test cases ----
    apply_u(  5,  9,  2,  7, "case1");      // exp = 9
    apply_u(  0,  0,  0,  0, "zeros");      // exp = 0
    apply_u(255,  1,  2,  3, "max255");     // exp = 255
    apply_u(  4,200,199,200, "tie200");     // exp = 200
    apply_u( 10, 20,250,100, "case5");      // exp = 250
    apply_u(  0,128,127, 64, "mid");        // exp = 128
    apply_u(  1,  1,  1,  1, "all1");       // exp = 1
    apply_u(  0,  1,  0,  1, "two_ones");   // exp = 1

    @(posedge clk);
    if (errors==0) $display("MaxPool2x2 TB PASSED ✅");
    else           $display("MaxPool2x2 TB FAILED ❌ errors=%0d", errors);
    $finish;
  end

endmodule

