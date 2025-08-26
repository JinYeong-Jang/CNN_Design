module cnn_top #(
    parameter integer WI    = 8,
    parameter integer BW    = 32,
    parameter integer ACCW  = 32
)(
    input            iClk,
    input            iRsn,      // active-low reset
    input            iPixelIn,  // image pixel input
    input            iPixelValid,

    output [3:0]     oValid,
    output signed [ACCW-1:0] oData0,
    output signed [ACCW-1:0] oData1,
    output signed [ACCW-1:0] oData2,
    output signed [ACCW-1:0] oData3
);

    // 내부 연결 와이어 선언
    wire [3*WI-1:0]  wWindowInRow1;
    wire [3*WI-1:0]  wWindowInRow2;
    wire [3*WI-1:0]  wWindowInRow3;
    wire             wMapDone;
    wire             wInValid;

    // conv_3x3_window 모듈 인스턴스화
    // 이 모듈은 iPixelIn을 받아 wWindowInRow* 출력을 생성한다고 가정합니다.
    sliding_3x3window #(
        .WI(WI)
    ) u_sliding_window (
        .iClk(iClk),
        .iRsn(iRsn),
        .iPixelIn(iPixelIn),
        .iPixelValid(iPixelValid),
        .oWindowOutRow1(wWindowInRow1),
        .oWindowOutRow2(wWindowInRow2),
        .oWindowOutRow3(wWindowInRow3),
        .oWindowValid(wInValid),
        .oMapDone(wMapDone)
    );

    // four_conv3x3_kernel 모듈 인스턴스화
    // 슬라이딩 윈도우의 출력을 커널 모듈의 입력으로 연결합니다.
    conv3x3_wrapper #(
        .WI(WI),
        .BW(BW),
        .ACCW(ACCW)
    ) u_conv_kernel (
        .iClk(iClk),
        .iRsn(iRsn),
        .iInValid(wInValid),
        .iMapDone(wMapDone),
        .iWindowInRow1(wWindowInRow1),
        .iWindowInRow2(wWindowInRow2),
        .iWindowInRow3(wWindowInRow3),
        .oValid4(oValid),
        .oData0(oData0),
        .oData1(oData1),
        .oData2(oData2),
        .oData3(oData3)
    );


endmodule

