// tb_fc_top.v : testbench for fc_top (Verilog-2001)
`timescale 1ns/1ps

module tb_fc_top;

  // ---- DUT parameters (match your design or override here) ----
  localparam integer INPUT_NUM   = 14*14*16;  // 3136
  localparam integer DATA_BITS   = 8;
  localparam integer ACC_BITS    = 26;
  localparam integer SUM_BITS    = 32;
  localparam integer SHIFT_BITS  = 7;
  localparam signed  [ACC_BITS-1:0] T = 0;
  localparam integer ACTIVE_LOW  = 1;
  localparam integer BLANK_ON_IDLE = 1;

  // ---- clock & reset ----
  reg clk;
  reg rst_n;

  // ---- stimulus -> DUT ----
  reg                         feat_valid;
  reg signed [DATA_BITS-1:0]  feat_data;

  // ---- DUT outputs ----
  wire [6:0] seg;
  wire       is_one;
  wire       sum_valid;

  // ---- bookkeeping ----
  integer cycle_cnt;
  integer frame_cnt;
  integer sum_valid_count_in_frame;
  integer i;
  integer seed;

  // ---- clock generation: 100 MHz (10 ns) ----
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---- instantiate DUT ----
  fc_top #(
    .INPUT_NUM   (INPUT_NUM),
    .DATA_BITS   (DATA_BITS),
    .ACC_BITS    (ACC_BITS),
    .SUM_BITS    (SUM_BITS),
    .SHIFT_BITS  (SHIFT_BITS),
    .T           (T),
    .ACTIVE_LOW  (ACTIVE_LOW),
    .BLANK_ON_IDLE(BLANK_ON_IDLE)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .feat_valid (feat_valid),
    .feat_data  (feat_data),
    .seg        (seg),
    .is_one     (is_one),
    .sum_valid  (sum_valid)
  );

  // ---- helpers ----
  // clamp 32-bit $random to signed int8
  function signed [DATA_BITS-1:0] rand_i8;
    input integer s;
    integer r;
    begin
      r = $random(s); // 32-bit signed
      // map to -128..127
      rand_i8 = r[7:0]; // truncation yields -128..127 naturally
    end
  endfunction

  task automatic apply_reset;
    begin
      rst_n   = 1'b0;
      feat_valid = 1'b0;
      feat_data  = {DATA_BITS{1'b0}};
      cycle_cnt  = 0;
      frame_cnt  = 0;
      sum_valid_count_in_frame = 0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  // send one frame of INPUT_NUM samples
  task automatic send_frame;
    integer k;
    begin
      sum_valid_count_in_frame = 0;

      // stream INPUT_NUM samples back-to-back
      for (k = 0; k < INPUT_NUM; k = k + 1) begin
        @(posedge clk);
        feat_valid <= 1'b1;
        feat_data  <= rand_i8(seed);

        // assert that sum_valid only fires on the last element
        if (sum_valid) begin
          $display("[%0t] ERROR: sum_valid high before last sample! k=%0d", $time, k);
          $fatal;
        end

        cycle_cnt = cycle_cnt + 1;
      end

      // last element is just sent; on same cycle sum_valid should pulse
      // Wait one cycle to observe the pulse from cmp7seg
      @(posedge clk);
      feat_valid <= 1'b0; // idle after frame
      feat_data  <= 'bx;

      // Check pulse count during the last cycle and now
      if (sum_valid) sum_valid_count_in_frame = sum_valid_count_in_frame + 1;

      // Allow a few idle cycles; ensure no extra pulses
      repeat (3) begin
        @(posedge clk);
        if (sum_valid) begin
          sum_valid_count_in_frame = sum_valid_count_in_frame + 1;
        end
      end

      if (sum_valid_count_in_frame != 1) begin
        $display("[%0t] ERROR: sum_valid_count_in_frame=%0d (expected 1)", $time, sum_valid_count_in_frame);
        $fatal;
      end

      frame_cnt = frame_cnt + 1;
      $display("[%0t] Frame %0d done. is_one=%0d seg=%b", $time, frame_cnt, is_one, seg);
    end
  endtask

  // ---- monitor (optional prints) ----
  always @(posedge clk) begin
    if (rst_n && sum_valid) begin
      $display("[%0t] sum_valid pulse. is_one=%0d seg=%b", $time, is_one, seg);
    end
  end

  // ---- main stimulus ----
  initial begin
    // VCD
    $dumpfile("fc_top_tb.vcd");
    $dumpvars(0, tb_fc_top);

    // IMPORTANT:
    // Ensure these files exist in your sim dir before time 0:
    //   fc_weight_i8_pos1.txt  (int8 weights, length INPUT_NUM)
    //   fc_bias_i32_zero.txt   (one 32-bit signed bias)
    // The DUT reads them at t=0 via $readmemh in fc_accum.
    seed = 32'h1234_5678;

    apply_reset;

    // 1) Frame of random int8 data
    send_frame;

    // 2) Another frame (new random sequence)
    send_frame;

    // 3) All-zero frame to sanity-check bias/threshold path
    //    (hold feat_valid=1 with 0 for INPUT_NUM cycles)
    sum_valid_count_in_frame = 0;
    repeat (INPUT_NUM) begin
      @(posedge clk);
      feat_valid <= 1'b1;
      feat_data  <= {DATA_BITS{1'b0}};
      if (sum_valid) begin
        $display("[%0t] ERROR: sum_valid high before last sample on zero-frame!", $time);
        $fatal;
      end
    end
    @(posedge clk);
    feat_valid <= 1'b0;
    feat_data  <= 'bx;
    if (sum_valid) sum_valid_count_in_frame = sum_valid_count_in_frame + 1;
    repeat (3) begin
      @(posedge clk);
      if (sum_valid) sum_valid_count_in_frame = sum_valid_count_in_frame + 1;
    end
    if (sum_valid_count_in_frame != 1) begin
      $display("[%0t] ERROR: sum_valid_count_in_frame (zero-frame)=%0d (expected 1)",
               $time, sum_valid_count_in_frame);
      $fatal;
    end
    frame_cnt = frame_cnt + 1;
    $display("[%0t] Zero-frame done. is_one=%0d seg=%b", $time, is_one, seg);

    $display("All tests completed. Frames sent=%0d", frame_cnt);
    $finish;
  end

endmodule