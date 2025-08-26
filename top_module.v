module top_module #(
    parameter integer IMG_W  = 28,
    parameter integer PIX_W  = 8,   // pixel bit width
    parameter integer WI     = 8,   // four_conv3x3_kernel.WI (== PIX_W 권장)
    parameter integer BW     = 32,
    parameter integer ACCW   = 32,
    parameter integer In_d_W = 32,  // pool_relu input data width
    parameter integer W      = 26   // input feature map column count
)(
    input            iClk,
    input            iRsn,      // active-low reset
    input            iPixelIn,  // image pixel input
    input            iPixelValid,

    //output은 최종 결과물(동균이형) 이 블록에 맞게 설정해주세요
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

endmodule


