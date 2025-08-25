// 4-lane wrapper for pool_relu
module pool_relu_wrapper #(
    parameter In_d_W = 32,
    parameter W      = 26
)(
    input  wire                     clk,
    input  wire                     clr,
    input  wire [3:0]               in_valid,                       // [채널3:채널0]
    input  wire signed [4*In_d_W-1:0] in_data,                      // 채널별 In_d_W비트 패킹
    output wire [3:0]               out_valid,                      // [채널3:채널0]
    output wire signed [4*In_d_W-1:0] out_data                      // 채널별 In_d_W비트 패킹
);

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_lane
            pool_relu #(
                .In_d_W (In_d_W),
                .W      (W)
            ) u_lane (
                .clk      (clk),
                .clr      (clr),
                .in_valid (in_valid[i]),
                .in_data  (in_data [(i+1)*In_d_W-1 -: In_d_W]),
                .out_valid(out_valid[i]),
                .out_data (out_data[(i+1)*In_d_W-1 -: In_d_W])
            );
        end
    endgenerate

endmodule

