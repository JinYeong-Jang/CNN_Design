// fc_4mac_16ch.v (Quartus 20.1 friendly Verilog-2001)
// Assumptions:
// - For the same spatial position p, 4 consecutive cycles g=0,1,2,3 arrive.
// - Post-pooling 13x13 positions, p = 0..168.
// - Weight indexing: w_idx(p,g,l) = p*16 + g*4 + l (HWC flattened weights).

module fc_1 #(
  parameter integer FEAT_W  = 32,             // feature width (pool output)
  parameter integer WGT_W   = 8,              // weight width (INT8 signed)
  parameter integer PROD_W  = FEAT_W + WGT_W, // product width (e.g., 40)
  parameter integer N_POS   = 169,            // 13x13
  parameter integer N_CH    = 16,             // 16 channels
  parameter integer ACC_W   = PROD_W + 12     // >= PROD_W + ceil(log2(2704))
)(
  input  wire                     iClk,
  input  wire                     iRstn,        // active-low

  input  wire [3:0]               iValid4,      // all lanes must be valid
  input  wire signed [FEAT_W-1:0] iData0,
  input  wire signed [FEAT_W-1:0] iData1,
  input  wire signed [FEAT_W-1:0] iData2,
  input  wire signed [FEAT_W-1:0] iData3,

  input  wire [1:0]               iPhase_g,     // 0..3, per position p
  input  wire                     iFrameStart,  // 1-cycle pulse before (p=0,g=0)

  output reg                      oLogitValid,  // 1-cycle pulse at frame end
  output reg  signed [ACC_W-1:0]  oLogit,
  output wire                     oClass
);

  // ROMs (HWC order: 16 channels contiguous per position)
  reg  signed [7:0]  w_rom [0:N_POS*N_CH-1];   // 2704 entries
  reg  signed [31:0] b_rom_a [0:0];            // 1-deep array for bias
  wire signed [31:0] b_rom = b_rom_a[0];


  initial begin
    $readmemh("fc_w.mem", w_rom);
    $readmemh("fc_b.mem", b_rom_a);
  end

  // Position counter (0..168)
  reg [7:0] pos;
  wire      all_valid = &iValid4;

  // base = p*16 + g*4
  wire [15:0] base_idx = pos*16 + {iPhase_g, 2'b00};
  wire [15:0] idx0 = base_idx + 16'd0;
  wire [15:0] idx1 = base_idx + 16'd1;
  wire [15:0] idx2 = base_idx + 16'd2;
  wire [15:0] idx3 = base_idx + 16'd3;

  // Weight fetch (signed)
  wire signed [7:0] w0 = w_rom[idx0];
  wire signed [7:0] w1 = w_rom[idx1];
  wire signed [7:0] w2 = w_rom[idx2];
  wire signed [7:0] w3 = w_rom[idx3];

  // Products
  wire signed [PROD_W-1:0] p0 = iData0 * w0;
  wire signed [PROD_W-1:0] p1 = iData1 * w1;
  wire signed [PROD_W-1:0] p2 = iData2 * w2;
  wire signed [PROD_W-1:0] p3 = iData3 * w3;

  // Sign-extend helper (Verilog function)
  function [ACC_W-1:0] sx;
    input signed [PROD_W-1:0] v;
    begin
      sx = {{(ACC_W-PROD_W){v[PROD_W-1]}}, v};
    end
  endfunction

  wire signed [ACC_W-1:0] sum4 = sx(p0) + sx(p1) + sx(p2) + sx(p3);

  // Accumulator and bias
  reg  signed [ACC_W-1:0] acc;
  wire signed [ACC_W-1:0] bias_ext = {{(ACC_W-32){b_rom[31]}}, b_rom};

  wire last_phase = (iPhase_g == 2'd3);
  wire last_pos   = (pos == N_POS-1);

  always @(posedge iClk) begin
    if (!iRstn) begin
      pos         <= 8'd0;
      acc         <= {ACC_W{1'b0}};
      oLogit      <= {ACC_W{1'b0}};
      oLogitValid <= 1'b0;
    end else begin
      oLogitValid <= 1'b0;

      // Frame start: reset counters/accumulator
      if (iFrameStart) begin
        pos <= 8'd0;
        acc <= {ACC_W{1'b0}};
      end

      // Consume when all 4 lanes are valid
      if (all_valid) begin
        acc <= acc + sum4;

        // Advance position at the end of g=3
        if (last_phase) begin
          if (last_pos) begin
            // Frame complete: output logit with bias
            oLogit      <= acc + sum4 + bias_ext;
            oLogitValid <= 1'b1;
            // pos/acc will be cleared by the next iFrameStart
          end else begin
            pos <= pos + 8'd1;
          end
        end
      end
    end
  end

  // Class decision: logit >= 0
  assign oClass = ~oLogit[ACC_W-1];

endmodule