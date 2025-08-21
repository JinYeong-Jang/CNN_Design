`timescale 1ns/1ps

module tb_Flatten_Layer;

  reg        clk, rst, en;
  reg        in_valid, frame_start;
  reg  [7:0] din;
  wire       out_valid, frame_done;
  wire [7:0] dout;
  wire [11:0] idx;

  // DUT
  Flatten_Layer dut (
    .clk(clk),
    .rst(rst),
    .en(en),
    .in_valid(in_valid),
    .frame_start(frame_start),
    .din(din),
    .out_valid(out_valid),
    .dout(dout),
    .idx(idx),
    .frame_done(frame_done)
  );

  // clock
  initial clk = 0;
  always #5 clk = ~clk;

  integer errors;
  integer i;

  localparam integer N_TOTAL = 3136; // 14*14*16

  task drive_frame;
  begin
    // 프레임 시작
    @(negedge clk);
    frame_start <= 1'b1;
    in_valid    <= 1'b1;
    en          <= 1'b1;
    @(posedge clk);
    frame_start <= 1'b0;

    // 3136 샘플 송신
    for (i=0; i<N_TOTAL; i=i+1) begin
      @(negedge clk);
      din <= i[7:0];      // 패턴: idx의 하위 8비트
      @(posedge clk); #1;
      // 체크: out_valid, dout==din, idx==i
      if (!out_valid) begin
        $display("[Flatten] VALID=0 at i=%0d", i);
        errors = errors + 1;
      end else begin
        if (idx !== i[11:0]) begin
          $display("[Flatten] IDX mismatch: got=%0d exp=%0d", idx, i);
          errors = errors + 1;
        end
        if (dout !== din) begin
          $display("[Flatten] DOUT mismatch at i=%0d: dout=%0d din=%0d", i, dout, din);
          errors = errors + 1;
        end
      end
      // 마지막 샘플에서 frame_done=1 기대
      if (i==N_TOTAL-1) begin
        if (frame_done !== 1'b1) begin
          $display("[Flatten] frame_done not asserted at last sample");
          errors = errors + 1;
        end
      end
    end

    // 프레임 종료 후 아이들
    @(negedge clk);
    in_valid <= 1'b0;
    en       <= 1'b0;
  end
  endtask

  initial begin
    errors = 0;
    rst = 1; en = 0; in_valid = 0; frame_start = 0; din = 0;
    repeat(5) @(posedge clk);
    rst = 0;

    drive_frame();

    repeat(5) @(posedge clk);
    if (errors==0) $display("Flatten_Layer TB PASSED ✅");
    else           $display("Flatten_Layer TB FAILED ❌ errors=%0d", errors);
    $finish;
  end

endmodule
