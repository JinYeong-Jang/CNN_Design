module top_module #(
    parameter integer IMG_W  = 28,
    parameter integer PIX_W  = 8,   // pixel bit width
    parameter integer WI     = 8,   // four_conv3x3_kernel.WI (== PIX_W 권장)
    parameter integer BW     = 32,
    parameter integer ACCW   = 32,
    parameter integer In_d_W = 32,  // pool_relu input data width
    parameter integer W      = 26   // input feature map column count
    parameter integer FEAT_W_FC = In_d_W;     // FC input width
    parameter integer WGT_W_FC  = 8;
    parameter integer ACC_W_FC  = (FEAT_W_FC + WGT_W_FC) + 12;
)(
    input            iClk,
    input            iRsn,      // active-low reset
    input            iPixelIn,  // image pixel input
    input            iPixelValid,

    //output은 최종 결과물(동균이형) 이 블록에 맞게 설정해주세요
    output  oLogitValid, // frame done pulse (one cycle)
    output  signed [((In_d_W+8)+12)-1:0] oLogit, // ACC_W_FC = (FEAT_W + WGT_W) + 12
    output  oClass
);  

    // -------- Sliding window 출력선 --------
    // output은 wire로 선언후 신호에 넣음
    wire [3*PIX_W-1:0] wWindowOutRow1;
    wire [3*PIX_W-1:0] wWindowOutRow2;
    wire [3*PIX_W-1:0] wWindowOutRow3;
    wire                wWindowValid;
    wire                wMapDone;

    // -------- 3x3 컨볼루션 4개 출력선 --------
    wire [ACCW-1:0]     wData0;
    wire [ACCW-1:0]     wData1;
    wire [ACCW-1:0]     wData2;
    wire [ACCW-1:0]     wData3;
    wire [3:0]          wValid4;

    // -------- pool_relu 4개 출력선 --------
    wire signed [In_d_W-1:0]     relu_wData0;
    wire signed [In_d_W-1:0]     relu_wData1;
    wire signed [In_d_W-1:0]     relu_wData2;
    wire signed [In_d_W-1:0]     relu_wData3;
    wire [3:0]                   relu_wValid4;
    
  sliding_3x3window #(
        .IMG_W (IMG_W),
        .PIX_W (PIX_W)
    ) u_window (
        .iClk          (iClk),
        .iRsn          (iRsn),
        .iPixelIn      (iPixelIn),
        .iPixelValid   (iPixelValid),

        .oWindowOutRow1(wWindowOutRow1),
        .oWindowOutRow2(wWindowOutRow2),
        .oWindowOutRow3(wWindowOutRow3),
        .oWindowValid  (wWindowValid), // per-pixel window valid
        .oMapDone      (wMapDone)      // 한 맵(프레임) 끝났을 때 1
    );

    // -------- 3x3 컨볼루션 4개--------
    conv3x3_wrapper #(
        .WI   (WI),
        .BW   (BW),
        .ACCW (ACCW)
    ) u_four (
        .iClk          (iClk),
        .iRsn          (iRsn),
        .iInValid      (wWindowValid),  
        .iMapDone      (wMapDone),      

        .iWindowInRow1 (wWindowOutRow1),         // {p(x-2), p(x-1), p(x)}
        .iWindowInRow2 (wWindowOutRow2),
        .iWindowInRow3 (wWindowOutRow3),

        .oValid4       (wValid4),       // [v3 v2 v1 v0]
        .oData0        (wData0),
        .oData1        (wData1),
        .oData2        (wData2),
        .oData3        (wData3)
    );

        // -------- pool_relu 4개--------
    pool_relu_wrapper #(
        .In_d_W   (In_d_W),
        .W (W)
    ) u_four_pool_relu (
        .iClk          (iClk),
        .iRsn          (iRsn),
        
        .iValid4       (wValid4),
        .iData0        (wData0),
        .iData1        (wData1),
        .iData2        (wData2),
        .iData3        (wData3),

        .oValid4       (relu_wValid4),       
        .oData0        (relu_wData0),
        .oData1        (relu_wData1),
        .oData2        (relu_wData2),
        .oData3        (relu_wData3)
    );


    wire any_valid = |relu_wValid4;   // reduction OR: 4비트 중 하나라도 1이면 1

    reg  in_run;  // 프레임 진행 중 플래그
    always @(posedge iClk) begin
        if (!iRsn)          in_run <= 1'b0;  // 리셋 시 IDLE
        else if (wMapDone)  in_run <= 1'b0;  // 프레임 종료 시 IDLE
        else if (any_valid) in_run <= 1'b1;  // 첫 any_valid에서 RUN 진입
    end

    // 첫 any_valid 사이클에만 1사이클 펄스
    wire wFrameStart = any_valid & ~in_run;

    // iPhase_g: 유효가 들어올 때마다 0→1→2→3 순환
    reg [1:0] rPhase_g;
    always @(posedge iClk) begin
        if (!iRsn)       rPhase_g <= 2'd0;
        else if (wFrameStart) rPhase_g <= 2'd0;           // 프레임 시작 시 0부터
        else if (any_valid)   rPhase_g <= rPhase_g + 2'd1; // 유효 샘플마다 증가
    end

    // -------- FC 본체 --------
    wire                      wLogitValid;
    wire signed [ACC_W_FC-1:0] wLogit;
    wire                      wClass;

    fc_1 #(
        .FEAT_W (FEAT_W_FC),     // == In_d_W
        .WGT_W  (WGT_W_FC),
        .PROD_W (FEAT_W_FC + WGT_W_FC),
        .N_POS  (169),           // 13x13
        .N_CH   (16),
        .ACC_W  (ACC_W_FC)
    ) u_fc (
        .iClk        (iClk),
        .iRstn       (iRsn),           // active-low 그대로 연결
        .iValid4     (relu_wValid4),
        .iData0      (relu_wData0),
        .iData1      (relu_wData1),
        .iData2      (relu_wData2),
        .iData3      (relu_wData3),
        .iPhase_g    (rPhase_g),
        .iFrameStart (wFrameStart),
        .oLogitValid (wLogitValid),
        .oLogit      (wLogit),
        .oClass      (wClass)
    );

    // -------- Outputs --------
    assign oLogitValid = wLogitValid;
    assign oLogit      = wLogit;
    assign oClass      = wClass;

endmodule
