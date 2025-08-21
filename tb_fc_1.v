`timescale 1ns/1ps

module tb_fc_1;

  // DUT 파라미터와 동일하게
  localparam FEAT_W = 32;
  localparam WGT_W  = 8;
  localparam PROD_W = FEAT_W + WGT_W;
  localparam N_POS  = 169;    // 13x13
  localparam N_CH   = 16;
  localparam ACC_W  = PROD_W + 12;

  // 클럭/리셋
  reg iClk  = 1'b0;
  reg iRstn = 1'b0;
  always #10 iClk = ~iClk;   // 50 MHz

  // DUT I/O
  reg  [3:0]               iValid4;
  reg  signed [FEAT_W-1:0] iData0, iData1, iData2, iData3;
  reg  [1:0]               iPhase_g;
  reg                      iFrameStart;
  wire                     oLogitValid;
  wire signed [ACC_W-1:0]  oLogit;
  wire                     oClass;

  // DUT 인스턴스 (원본 모듈 그대로)
  fc_4mac_16ch #(
    .FEAT_W (FEAT_W),
    .WGT_W  (WGT_W),
    .PROD_W (PROD_W),
    .N_POS  (N_POS),
    .N_CH   (N_CH),
    .ACC_W  (ACC_W)
  ) dut (
    .iClk(iClk), .iRstn(iRstn),
    .iValid4(iValid4),
    .iData0(iData0), .iData1(iData1), .iData2(iData2), .iData3(iData3),
    .iPhase_g(iPhase_g),
    .iFrameStart(iFrameStart),
    .oLogitValid(oLogitValid), .oLogit(oLogit), .oClass(oClass)
  );

  // 입력은 전부 1로 고정
  localparam signed [FEAT_W-1:0] ONE = 32'sd1;

  initial begin
    // 초기화
    iValid4 = 4'b0000;
    iData0  = {FEAT_W{1'b0}};
    iData1  = {FEAT_W{1'b0}};
    iData2  = {FEAT_W{1'b0}};
    iData3  = {FEAT_W{1'b0}};
    iPhase_g    = 2'd0;
    iFrameStart = 1'b0;

    // 리셋 해제
    repeat (5) @(posedge iClk);
    iRstn = 1'b1;
    @(posedge iClk);

    // 프레임 시작 (p=0, g=0 직전 1클럭)
    iFrameStart = 1'b1;
    @(posedge iClk);
    iFrameStart = 1'b0;

    // 1 프레임 구동: p=0..168, 각 p에서 4사이클(g=0..3), lane4 전부 valid=1, data=1
    begin : DRIVE_FRAME
      integer p, g;
      for (p = 0; p < N_POS; p = p + 1) begin
        for (g = 0; g < 4; g = g + 1) begin
          iPhase_g <= g[1:0];
          iValid4  <= 4'b1111;
          iData0   <= ONE;
          iData1   <= ONE;
          iData2   <= ONE;
          iData3   <= ONE;
          @(posedge iClk);
        end
      end
      // 입력 내려줌
      iValid4  <= 4'b0000;
      iData0   <= {FEAT_W{1'b0}};
      iData1   <= {FEAT_W{1'b0}};
      iData2   <= {FEAT_W{1'b0}};
      iData3   <= {FEAT_W{1'b0}};
      iPhase_g <= 2'd0;
    end

    // 결과 대기해서 그대로 출력만
    wait (oLogitValid === 1'b1);
    $display("[%0t] oLogit = %0d, oClass = %0d", $time, oLogit, oClass);

    @(posedge iClk);
    $finish;
  end

endmodule