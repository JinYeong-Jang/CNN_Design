// fc_accum.v : streaming dot-product accumulator for MNIST 0/1 (Verilog-2001)
module fc_accum #(
  parameter integer INPUT_NUM  = 14*14*16,   // 3136
  parameter integer DATA_BITS  = 8,          // int8 inputs & weights
  parameter integer ACC_BITS   = 26,         // after scale output width
  parameter integer SUM_BITS   = 32,         // internal accumulator safety
  parameter integer SHIFT_BITS = 7           // scale (right arithmetic shift)
)(
  input  wire                         clk,
  input  wire                         rst_n,
  input  wire                         valid_in,         // one data / cycle
  input  wire signed [DATA_BITS-1:0]  data_in,          // flattened feature stream
  output reg  signed [ACC_BITS-1:0]   sum_out,          // scaled sum
  output reg                          valid_out         // one cycle pulse / frame
);

  localparam integer ADDR_BITS  = $clog2(INPUT_NUM);
  localparam integer PROD_BITS  = DATA_BITS*2;

  // weight ROM (distributed/comb output)
  reg  signed [DATA_BITS-1:0] w_mem [0:INPUT_NUM-1];
  initial $readmemh("fc_weight_i8_pos1.txt", w_mem);

  // bias ROM (single)
  reg  signed [SUM_BITS-1:0]  bias_mem [0:0];
  initial $readmemh("fc_bias_i32_zero.txt", bias_mem);
  wire signed [SUM_BITS-1:0] bias = bias_mem[0];

  // state
  reg [ADDR_BITS-1:0]        idx;    // 0 .. INPUT_NUM-1
  reg                        busy;
  reg signed [SUM_BITS-1:0]  acc;    // wide accumulator

  // current weight
  wire signed [DATA_BITS-1:0] w = w_mem[idx];

  // one multiply / cycle
  wire signed [PROD_BITS-1:0] prod = $signed(data_in) * $signed(w);

  // sign-extend generically
  wire signed [SUM_BITS-1:0] prod_ext =
    {{(SUM_BITS-PROD_BITS){prod[PROD_BITS-1]}}, prod};

  wire last_elem = (idx == INPUT_NUM-1);

  // running sums
  wire signed [SUM_BITS-1:0] acc_plus_prod = acc + prod_ext;
  wire signed [SUM_BITS-1:0] sum_wide      = acc_plus_prod + bias;

  // scaled (shift) – precompute as wire to avoid slicing an expression
  wire signed [SUM_BITS-1:0] scaled_wide =
    (SHIFT_BITS==0) ? sum_wide : (sum_wide >>> SHIFT_BITS);

  // degenerate case (INPUT_NUM == 1) precompute
  wire signed [SUM_BITS-1:0] deg_sum_unscaled = prod_ext + bias;
  wire signed [SUM_BITS-1:0] deg_sum_scaled =
    (SHIFT_BITS==0) ? deg_sum_unscaled : (deg_sum_unscaled >>> SHIFT_BITS);

  always @(posedge clk) begin
    if (!rst_n) begin
      idx       <= {ADDR_BITS{1'b0}};
      busy      <= 1'b0;
      acc       <= {SUM_BITS{1'b0}};
      sum_out   <= {ACC_BITS{1'b0}};
      valid_out <= 1'b0;
    end else begin
      valid_out <= 1'b0;

      if (valid_in) begin
        if (!busy) begin
          // start of frame
          busy <= 1'b1;
          idx  <= (INPUT_NUM > 1) ? {{(ADDR_BITS-1){1'b0}},1'b1} : {ADDR_BITS{1'b0}};
          acc  <= prod_ext; // first term

          // special: only 1 input -> direct output
          if (INPUT_NUM == 1) begin
            sum_out   <= deg_sum_scaled[ACC_BITS-1:0];
            valid_out <= 1'b1;
            busy      <= 1'b0;
            idx       <= {ADDR_BITS{1'b0}};
            acc       <= {SUM_BITS{1'b0}};
          end
        end else begin
          // process of frame
          if (!last_elem) begin
            acc <= acc_plus_prod;     // save for next
            idx <= idx + 1'b1;
          end else begin
            // last of frame: output including this multiply
            sum_out   <= scaled_wide[ACC_BITS-1:0];
            valid_out <= 1'b1;

            // ready for next frame
            busy      <= 1'b0;
            idx       <= {ADDR_BITS{1'b0}};
            acc       <= {SUM_BITS{1'b0}};
          end
        end
      end
    end
  end

endmodule