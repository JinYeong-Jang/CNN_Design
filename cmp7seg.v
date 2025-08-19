// cmp7seg.v : threshold + seven-seg driver (1 digit)
module cmp7seg #(
  parameter integer ACC_BITS = 26,
  parameter signed  [ACC_BITS-1:0] T = 0,
  parameter integer ACTIVE_LOW = 1,
  parameter integer BLANK_ON_IDLE = 1
)(
  input  wire                         clk,
  input  wire                         rst_n,
  input  wire signed [ACC_BITS-1:0]   sum_in,
  input  wire                         valid_in,
  output reg                          is_one,
  output reg        [6:0]             seg,
  output reg                          valid_out
);

  // active-high patterns (a..g)
  localparam [6:0] DIGIT0_AH = 7'b1111110;
  localparam [6:0] DIGIT1_AH = 7'b0110000;
  localparam [6:0] BLANK_AH  = 7'b0000000;

  // polarity conversion
  function [6:0] to_polarity;
    input [6:0] ah_pat;
    begin
      to_polarity = (ACTIVE_LOW != 0) ? ~ah_pat : ah_pat;
    end
  endfunction

  always @(posedge clk) begin
    if (!rst_n) begin
      is_one    <= 1'b0;
      seg       <= to_polarity(BLANK_AH);
      valid_out <= 1'b0;
    end else begin
      valid_out <= 1'b0;

      if (valid_in) begin
        is_one    <= (sum_in > T);
        seg       <= (sum_in > T) ? to_polarity(DIGIT1_AH) : to_polarity(DIGIT0_AH);
        valid_out <= 1'b1;
      end else if (BLANK_ON_IDLE != 0) begin
        seg       <= to_polarity(BLANK_AH);
      end
    end
  end

endmodule