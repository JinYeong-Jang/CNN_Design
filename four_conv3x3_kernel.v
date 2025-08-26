module conv3x3_wrapper #(
    parameter integer WI    = 8,
    parameter integer BW    = 32,
    parameter integer ACCW  = 32
)(
    input                         iClk,
    input                         iRsn,       // active-low
    input                         iInValid,   // per pixel
    input                         iMapDone,    // 모든 sliding window 작업이 끝나면 1

    input      [3*WI-1:0]         iWindowInRow1,
    input      [3*WI-1:0]         iWindowInRow2,
    input      [3*WI-1:0]         iWindowInRow3,


    output      [3:0]             oValid4,
    output reg signed [ACCW-1:0]      oData0,
    output reg signed [ACCW-1:0]      oData1,
    output reg signed [ACCW-1:0]      oData2,
    output reg signed [ACCW-1:0]      oData3
);

    reg  signed [WI-1:0] weight [0:143];   
    reg  signed [BW-1:0] bias   [0:15];    

    initial begin
        $readmemh("conv_w.mem", weight);  // 144 lines
        $readmemh("conv_b.mem", bias);    // 16  lines
    end
    
    // -----------------------------
    // phase 제어
    //   - 0: OC 0..3
    //   - 1: OC 4..7
    //   - 2: OC 8..11
    //   - 3: OC 12..15
    // -----------------------------
    reg [1:0] phase;
    always @(posedge iClk) begin
        if (!iRsn) begin
            phase <= 2'd0;
        end else if (iMapDone) begin
            phase <= phase + 2'd1;  // 0->1->2->3->0
        end
    end

    // 이 사이클에 계산할 4개 출력채널
    // oc_now = phase*4 + lane
    wire [5:0] oc0_now = phase*4 + 0;
    wire [5:0] oc1_now = phase*4 + 1;
    wire [5:0] oc2_now = phase*4 + 2;
    wire [5:0] oc3_now = phase*4 + 3;

    // 가중치 pack: {w00,w01,...,w22} (MSB=w00)
    function [WI*9-1:0] pack9;
        input [5:0] oc;
        integer b;
        begin
            b = oc * 9;
            pack9 = {
                weight[b+0], weight[b+1], weight[b+2],
                weight[b+3], weight[b+4], weight[b+5],
                weight[b+6], weight[b+7], weight[b+8]
            };
        end
    endfunction

    wire signed [WI*9-1:0] w_flat0 = pack9(oc0_now);
    wire signed [WI*9-1:0] w_flat1 = pack9(oc1_now);
    wire signed [WI*9-1:0] w_flat2 = pack9(oc2_now);
    wire signed [WI*9-1:0] w_flat3 = pack9(oc3_now);

    wire signed [BW-1:0] b0 = bias[oc0_now];
    wire signed [BW-1:0] b1 = bias[oc1_now];
    wire signed [BW-1:0] b2 = bias[oc2_now];
    wire signed [BW-1:0] b3 = bias[oc3_now];

    wire v0,v1,v2,v3;
    wire signed [ACCW-1:0] y0,y1,y2,y3;

    conv3x3_kernel #(.WI(WI),.BW(BW),.ACCW(ACCW)) PE0 (
        .iClk(iClk), .iRsn(iRsn), .iInValid(iInValid),
        .iWindowInRow1(iWindowInRow1), .iWindowInRow2(iWindowInRow2), .iWindowInRow3(iWindowInRow3),
        .conv_weight(w_flat0), .conv_bias(b0),
        .oOutValid(v0), .oOutData(y0)
    );
    conv3x3_kernel #(.WI(WI),.BW(BW),.ACCW(ACCW)) PE1 (
        .iClk(iClk), .iRsn(iRsn), .iInValid(iInValid),
        .iWindowInRow1(iWindowInRow1), .iWindowInRow2(iWindowInRow2), .iWindowInRow3(iWindowInRow3),
        .conv_weight(w_flat1), .conv_bias(b1),
        .oOutValid(v1), .oOutData(y1)
    );
    conv3x3_kernel #(.WI(WI),.BW(BW), .ACCW(ACCW)) PE2 (
        .iClk(iClk), .iRsn(iRsn), .iInValid(iInValid),
        .iWindowInRow1(iWindowInRow1), .iWindowInRow2(iWindowInRow2), .iWindowInRow3(iWindowInRow3),
        .conv_weight(w_flat2), .conv_bias(b2),
        .oOutValid(v2), .oOutData(y2)
    );
    conv3x3_kernel #(.WI(WI),.BW(BW), .ACCW(ACCW)) PE3 (
        .iClk(iClk), .iRsn(iRsn), .iInValid(iInValid),
        .iWindowInRow1(iWindowInRow1), .iWindowInRow2(iWindowInRow2), .iWindowInRow3(iWindowInRow3),
        .conv_weight(w_flat3), .conv_bias(b3),
        .oOutValid(v3), .oOutData(y3)
    );
    
    // ---------- 출력 정렬: data와 valid를 "같은 단계" 레지스터 ----------
    reg [3:0] oValid4_r;
    always @(posedge iClk) begin
        if (!iRsn) begin
            oValid4_r <= 4'b0;
            oData0    <= '0;
            oData1    <= '0;
            oData2    <= '0;
            oData3    <= '0;
        end else begin
            // 커널 출력(v*, y*)는 LAT=1 → 여기서 1단 더 넣어 data/valid 같이 정렬
            oValid4_r <= {v3, v2, v1, v0};
            oData0    <= y0;
            oData1    <= y1;
            oData2    <= y2;
            oData3    <= y3;
        end
    end
    assign oValid4 = oValid4_r;  // valid도 data와 같은 클럭에 유효

endmodule

