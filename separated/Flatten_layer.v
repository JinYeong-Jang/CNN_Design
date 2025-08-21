/*******************************************************************
  - Project          : CNN design
  - File name        : Flatten_Layer.v
  - Description      : ReLU (Rectified Linear Unit) implementation
  - Owner            : Minji.Jeong
  - Revision history : 1) 2025.08.14 : Initial release
*******************************************************************/
`timescale 1ns / 1ps

module Flatten_Layer (
    input  wire        clk,
    input  wire        rst,          // sync reset, high
    input  wire        en,           // stage enable
    input  wire        in_valid,     // 입력 유효
    input  wire        frame_start,  // 프레임 시작(1클럭)
    input  wire [7:0]  din,          // unsigned int8 (픽셀단위 interleave: ch0..15)
    output reg         out_valid,    // 출력 유효
    output reg [7:0]   dout,         // 플래튼 스트림
    output reg [11:0]  idx,          // 0..3135
    output reg         frame_done    // 마지막 샘플에서 1클럭
);
    // 고정 파라미터(14x14x16)
    // W=14, H=14, C=16, 총 샘플 = 3136
    // ch,x,y 카운터 폭은 각각 4비트면 충분
    reg [3:0]  ch;
    reg [3:0]  x;
    reg [3:0]  y;
    reg [11:0] count;                // 0..3135
    wire       last_sample = (count == 12'd3135);

    always @(posedge clk) begin
        if (rst) begin
            out_valid  <= 1'b0;
            dout       <= 8'd0;
            idx        <= 12'd0;
            ch         <= 4'd0;
            x          <= 4'd0;
            y          <= 4'd0;
            count      <= 12'd0;
            frame_done <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            // 프레임 경계 정렬
            if (frame_start) begin
                ch    <= 4'd0;
                x     <= 4'd0;
                y     <= 4'd0;
                count <= 12'd0;
            end

            if (en && in_valid) begin
                // 그대로 통과 (flatten = 순서 보장)
                dout      <= din;
                out_valid <= 1'b1;
                idx       <= count;

                // 위치 전진: ch -> x -> y
                if (ch == 4'd15) begin
                    ch <= 4'd0;
                    if (x == 4'd13) begin
                        x <= 4'd0;
                        if (y == 4'd13) begin
                            y <= 4'd0;      // 프레임 끝
                        end else begin
                            y <= y + 4'd1;
                        end
                    end else begin
                        x <= x + 4'd1;
                    end
                end else begin
                    ch <= ch + 4'd1;
                end

                // 전체 샘플 카운트
                if (last_sample) begin
                    frame_done <= 1'b1;
                    count      <= 12'd0;
                end else begin
                    count <= count + 12'd1;
                end
            end else begin
                out_valid <= 1'b0;
            end
        end
    end
endmodule
