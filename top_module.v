module top_module #(
    parameter integer IMG_W  = 28,
    parameter integer PIX_W  = 8,   // pixel bit width
    parameter integer WI     = 8,   // four_conv3x3_kernel.WI (== PIX_W 권장)
    parameter integer BW     = 32,
    parameter integer ACCW   = 32,
    parameter integer In_d_W = 32,  // pool_relu input data width
    parameter integer W      = 26,  // input feature map column count
    parameter integer FEAT_W_FC = In_d_W,     // FC input width
    parameter integer WGT_W_FC  = 8,
    parameter integer ACC_W_FC  = (FEAT_W_FC + WGT_W_FC) + 12
)(
    input        iClk,
    input        iRsn,      // active-low reset

    // === 7-seg 출력 ===
    output [6:0] oSeg,      // {a,b,c,d,e,f,g}
    output       oC         // 자리 선택 1비트
);

    // ================= ROM → 픽셀 피더 =================
    wire [PIX_W-1:0] pixel_data;
    wire             pixel_valid;

    // NOTE: IMG_FILE은 합성에서 문자열 파라미터 이슈가 있으니 하드코딩 권장
    pixel_feeder #(
        .NPIX    (784)               // 28x28
        // .IMG_FILE("mnist_0_0.mem") // 하드코딩 시 pixel_feeder 내부에서 $readmemh("...") 사용
    ) u_feeder (
        .clk   (iClk),               // 필요 시 clk50로 교체
        .rstn  (iRsn),
        .pixel (pixel_data),
        .valid (pixel_valid)
    );

    // ================= CNN 파이프라인 =================
    // Sliding window
    wire [3*PIX_W-1:0] wWindowOutRow1, wWindowOutRow2, wWindowOutRow3;
    wire               wWindowValid, wMapDone;

    sliding_3x3window #(
        .IMG_W (IMG_W),
        .PIX_W (PIX_W)
    ) u_window (
        .iClk          (iClk),
        .iRsn          (iRsn),
        .iPixelIn      (pixel_data),     // <<< 내부 ROM 픽셀
        .iPixelValid   (pixel_valid),    // <<< 내부 ROM valid

        .oWindowOutRow1(wWindowOutRow1),
        .oWindowOutRow2(wWindowOutRow2),
        .oWindowOutRow3(wWindowOutRow3),
        .oWindowValid  (wWindowValid),
        .oMapDone      (wMapDone)
    );

    // Conv3x3 x4
    wire [ACCW-1:0] wData0, wData1, wData2, wData3;
    wire [3:0]      wValid4;

    conv3x3_wrapper #(
        .WI   (WI),
        .BW   (BW),
        .ACCW (ACCW)
    ) u_four (
        .iClk          (iClk),
        .iRsn          (iRsn),
        .iInValid      (wWindowValid),
        .iMapDone      (wMapDone),
        .iWindowInRow1 (wWindowOutRow1),
        .iWindowInRow2 (wWindowOutRow2),
        .iWindowInRow3 (wWindowOutRow3),
        .oValid4       (wValid4),
        .oData0        (wData0),
        .oData1        (wData1),
        .oData2        (wData2),
        .oData3        (wData3)
    );

    // Pool + ReLU
    wire signed [In_d_W-1:0] relu_wData0, relu_wData1, relu_wData2, relu_wData3;
    wire [3:0]               relu_wValid4;

    pool_relu_wrapper #(
        .In_d_W (In_d_W),
        .W      (W)
    ) u_four_pool_relu (
        .iClk     (iClk),
        .iRsn     (iRsn),
        .iValid4  (wValid4),
        .iData0   (wData0),
        .iData1   (wData1),
        .iData2   (wData2),
        .iData3   (wData3),
        .oValid4  (relu_wValid4),
        .oData0   (relu_wData0),
        .oData1   (relu_wData1),
        .oData2   (relu_wData2),
        .oData3   (relu_wData3)
    );

    // Phase gen (그대로)
    wire any_valid = |relu_wValid4;
    reg  [7:0] cnt169;     // 0..168
    reg  [1:0] rPhase_g;   // 0..3
    always @(posedge iClk) begin
        if (!iRsn) begin
            cnt169   <= 8'd0;
            rPhase_g <= 2'd0;
        end else if (any_valid) begin
            if (cnt169 == 8'd168) begin
                cnt169   <= 8'd0;
                rPhase_g <= rPhase_g + 2'd1;
            end else begin
                cnt169 <= cnt169 + 8'd1;
            end
        end
    end

    // FC
    wire                    wLogitValid;
    wire signed [ACC_W_FC-1:0] wLogit;
    wire                    wClass;

    fc_1 #(
        .FEAT_W (FEAT_W_FC),
        .WGT_W  (WGT_W_FC),
        .PROD_W (FEAT_W_FC + WGT_W_FC),
        .N_POS  (169),
        .N_CH   (16),
        .ACC_W  (ACC_W_FC)
    ) u_fc (
        .iClk        (iClk),
        .iRstn       (iRsn),
        .iValid4     (relu_wValid4),
        .iData0      (relu_wData0),
        .iData1      (relu_wData1),
        .iData2      (relu_wData2),
        .iData3      (relu_wData3),
        .iPhase_g    (rPhase_g),
        .oLogitValid (wLogitValid),
        .oLogit      (wLogit),
        .oClass      (wClass)
    );

    // ================= 7-세그 표시 =================
    // seg7_0or1: oClass==0 → "00", oClass==1 → "01"
    seg7_0or1 u_seg (
        .clk   (iClk),     // 필요 시 clk50로 교체
        .rstn  (iRsn),
        .iClass(wClass),
        .oSeg  (oSeg),
        .oC    (oC)
    );

endmodule
