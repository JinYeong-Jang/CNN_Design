// fc_top.v : flatten -> fc_accum -> cmp7seg
module fc_top #(
  parameter integer INPUT_NUM   = 14*14*16,
  parameter integer DATA_BITS   = 8,
  parameter integer ACC_BITS    = 26,
  parameter integer SUM_BITS    = 32,
  parameter integer SHIFT_BITS  = 7,
  parameter signed  [ACC_BITS-1:0] T = 0,
  parameter integer ACTIVE_LOW  = 1,
  parameter integer BLANK_ON_IDLE = 1
)(
  input  wire                        clk,
  input  wire                        rst_n,
  input  wire                        feat_valid,          // upstream flattener
  input  wire signed [DATA_BITS-1:0] feat_data,           // int8 feature stream
  output wire [6:0]                  seg,
  output wire                        is_one,
  output wire                        sum_valid
);

  wire signed [ACC_BITS-1:0] sum_out;
  wire                       valid_out_fc;

  fc_accum #(
    .INPUT_NUM (INPUT_NUM),
    .DATA_BITS (DATA_BITS),
    .ACC_BITS  (ACC_BITS),
    .SUM_BITS  (SUM_BITS),
    .SHIFT_BITS(SHIFT_BITS)
  ) u_fc_accum (
    .clk      (clk),
    .rst_n    (rst_n),
    .valid_in (feat_valid),
    .data_in  (feat_data),
    .sum_out  (sum_out),
    .valid_out(valid_out_fc)
  );

  cmp7seg #(
    .ACC_BITS     (ACC_BITS),
    .T            (T),
    .ACTIVE_LOW   (ACTIVE_LOW),
    .BLANK_ON_IDLE(BLANK_ON_IDLE)
  ) u_cmp7seg (
    .clk      (clk),
    .rst_n    (rst_n),
    .sum_in   (sum_out),
    .valid_in (valid_out_fc),
    .is_one   (is_one),
    .seg      (seg),
    .valid_out(sum_valid)
  );

endmodule