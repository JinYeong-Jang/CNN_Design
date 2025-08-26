module pool_relu_wrapper #(
    parameter In_d_W = 32,
    parameter W      = 26
)(
    input                         iClk,
    input                         iRsn,       // active-low

    input   [3:0]                iValid4,
    input signed [In_d_W-1:0]    iData0,     // [31:0] signed pixel
    input signed [In_d_W-1:0]    iData1,     
    input signed [In_d_W-1:0]    iData2,     
    input signed [In_d_W-1:0]    iData3,     

    output [3:0]                        oValid4,
    output reg signed [In_d_W-1:0]      oData0,     // [31:0] signed pixel
    output reg signed [In_d_W-1:0]      oData1,
    output reg signed [In_d_W-1:0]      oData2,
    output reg signed [In_d_W-1:0]      oData3
);

    wire rst_ah = ~iRsn;    // change to active-high reset
    wire oValid0, oValid1, oValid2, oValid3;    // oValid per channel
    wire signed [In_d_W-1:0] y0, y1, y2, y3;    // output per channel
  

    pool_relu #(.In_d_W(In_d_W),.W(W)) PE0 (
        .iClk(iClk), 
        .iRsn(rst_ah),     // active-high
        .iInValid(iValid4[0]),
        .iPoolData(iData0),
        .oOutValid(oValid0), 
        .oOutData(y0)
    );

        pool_relu #(.In_d_W(In_d_W),.W(W)) PE1 (
        .iClk(iClk), 
        .iRsn(rst_ah), 
        .iInValid(iValid4[1]),
        .iPoolData(iData1),
        .oOutValid(oValid1), 
        .oOutData(y1)
    );

    pool_relu #(.In_d_W(In_d_W),.W(W)) PE2 (
        .iClk(iClk), 
        .iRsn(rst_ah), 
        .iInValid(iValid4[2]),
        .iPoolData(iData2),
        .oOutValid(oValid2), 
        .oOutData(y2)
    );

    pool_relu #(.In_d_W(In_d_W),.W(W)) PE3 (
        .iClk(iClk), 
        .iRsn(rst_ah), 
        .iInValid(iValid4[3]),
        .iPoolData(iData3),
        .oOutValid(oValid3), 
        .oOutData(y3)
    );

    // ---------- Output alignment: register data and valid in the same stage ----------
    reg [3:0] reg_oValid4;
    always @(posedge iClk) begin
        if (!iRsn) begin
            reg_oValid4 <= 4'b0000;
            oData0    <= {In_d_W{1'b0}};
            oData1    <= {In_d_W{1'b0}};
            oData2    <= {In_d_W{1'b0}};
            oData3    <= {In_d_W{1'b0}};
        end else begin
            reg_oValid4 <= {oValid3, oValid2, oValid1, oValid0};
            oData0    <= y0;
            oData1    <= y1;
            oData2    <= y2;
            oData3    <= y3;
        end
    end
    assign oValid4 = reg_oValid4; 

endmodule

