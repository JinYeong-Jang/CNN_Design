`timescale 1ns/1ps

module tb_ReLU;

  reg  clk, rst, en;
  reg  signed [7:0]  A;
  wire signed [7:0]  Y;
  wire valid;

  // DUT
  ReLU #(.In_d_W(8)) dut (
    .clk(clk),
    .rst(rst),
    .en(en),
    .A(A),
    .Y(Y),
    .valid(valid)
  );

  // clock
  initial clk = 0;
  always #5 clk = ~clk; // 100 MHz

  integer errors;

  task apply(input signed [7:0] a_in, input [255:0] name);
  begin
    @(negedge clk);
    A  <= a_in;
    en <= 1'b1;
    @(posedge clk); #1;
    // 체크
    if (!valid) begin
      $display("[ReLU][%s] VALID=0 (A=%0d)", name, a_in);
      errors = errors + 1;
    end else begin
      if (Y !== ((a_in < 0) ? 8'sd0 : a_in)) begin
        $display("[ReLU][%s] MISMATCH: A=%0d, Y=%0d (exp=%0d)",
                 name, a_in, Y, ((a_in < 0) ? 8'sd0 : a_in));
        errors = errors + 1;
      end
    end
    en <= 1'b0;
  end
  endtask

  initial begin
    errors = 0;
    rst = 1; en = 0; A = 0;
    repeat(3) @(posedge clk);
    rst = 0;

    apply(-128, "neg_min");
    apply(-1,   "neg_one");
    apply(0,    "zero");
    apply(1,    "pos_one");
    apply(64,   "pos_64");
    apply(127,  "pos_max");

    @(posedge clk);
    if (errors==0) $display("ReLU TB PASSED ✅");
    else           $display("ReLU TB FAILED ❌ errors=%0d", errors);
    $finish;
  end

endmodule

