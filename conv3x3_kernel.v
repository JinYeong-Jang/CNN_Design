// 3x3 Convolution (한 커널) - 9개 병렬 곱셈 + 가중합 + bias
module conv3x3_kernel #(
    parameter integer WI    = 8,   // 입력/가중치 비트폭 (signed)
    parameter integer BW    = 32,  // bias 비트폭 (signed)
    parameter integer ACCW  = 32   // 누산/출력 비트폭 (signed)
)(
    input                         iClk,
    input                         iRsn,        // active-low sync reset
    input                         iInValid,

    // 각 행당 3픽셀: {left, mid, right}, 총 3*WI 비트
    input      [3*WI-1:0]         iWindowInRow1,  // top row
    input      [3*WI-1:0]         iWindowInRow2,  // middle row
    input      [3*WI-1:0]         iWindowInRow3,  // bottom row

    output reg                    oOutValid,
    output reg signed [ACCW-1:0]  oOutData
);


    // ---------------------------------
    // 가중치/바이어스 ROM
    // ---------------------------------
    reg signed [WW-1:0] weight_mem [0:8];
    reg signed [BW-1:0] bias_mem   [0:0];

    wire signed [DATAW-1:0] a00, a01, a02,
                            a10, a11, a12,
                            a20, a21, a22;

    wire signed [WW-1:0] w00, w01, w02,
                         w10, w11, w12,
                         w20, w21, w22;

    wire signed [BW-1:0] b;

    // product results
    wire signed [DATAW+WW-1:0] p00, p01, p02,
                               p10, p11, p12,
                               p20, p21, p22;

    // sum results
    wire signed [ACCW-1:0] sum_products;
    wire signed [ACCW-1:0] sum_with_bias;

    initial begin
        $readmemh("weights.mem", weight_mem);
        $readmemh("bias.mem",    bias_mem);
    end

    // ---------------------------------
    // 입력/가중치 wire 선언부
    // ---------------------------------
    // ---------------------------------
    // input data assign
    // ---------------------------------
    assign a00 = iWindowInRow1[3*DATAW-1 -: DATAW];
    assign a01 = iWindowInRow1[2*DATAW-1 -: DATAW];
    assign a02 = iWindowInRow1[1*DATAW-1 -: DATAW];

    assign a10 = iWindowInRow2[3*DATAW-1 -: DATAW];
    assign a11 = iWindowInRow2[2*DATAW-1 -: DATAW];
    assign a12 = iWindowInRow2[1*DATAW-1 -: DATAW];

    assign a20 = iWindowInRow3[3*DATAW-1 -: DATAW];
    assign a21 = iWindowInRow3[2*DATAW-1 -: DATAW];
    assign a22 = iWindowInRow3[1*DATAW-1 -: DATAW];

    // ---------------------------------
    // weight/bias assign
    // ---------------------------------
    assign w00 = weight_mem[0];
    assign w01 = weight_mem[1];
    assign w02 = weight_mem[2];
    assign w10 = weight_mem[3];
    assign w11 = weight_mem[4];
    assign w12 = weight_mem[5];
    assign w20 = weight_mem[6];
    assign w21 = weight_mem[7];
    assign w22 = weight_mem[8];

    assign b   = bias_mem[0];

    // ---------------------------------
    // 곱셈기 인스턴스
    // ---------------------------------
    mul #(.WI(WI)) u_mul_00 (.w(w00), .x(a00), .y(p00));
    mul #(.WI(WI)) u_mul_01 (.w(w01), .x(a01), .y(p01));
    mul #(.WI(WI)) u_mul_02 (.w(w02), .x(a02), .y(p02));

    mul #(.WI(WI)) u_mul_10 (.w(w10), .x(a10), .y(p10));
    mul #(.WI(WI)) u_mul_11 (.w(w11), .x(a11), .y(p11));
    mul #(.WI(WI)) u_mul_12 (.w(w12), .x(a12), .y(p12));

    mul #(.WI(WI)) u_mul_20 (.w(w20), .x(a20), .y(p20));
    mul #(.WI(WI)) u_mul_21 (.w(w21), .x(a21), .y(p21));
    mul #(.WI(WI)) u_mul_22 (.w(w22), .x(a22), .y(p22));

    // ---------------------------------
    // adder tree 조합 assign
    // ---------------------------------
    assign sum_products =
          {{(ACCW-(DATAW+WW)){p00[DATAW+WW-1]}}, p00}
        + {{(ACCW-(DATAW+WW)){p01[DATAW+WW-1]}}, p01}
        + {{(ACCW-(DATAW+WW)){p02[DATAW+WW-1]}}, p02}
        + {{(ACCW-(DATAW+WW)){p10[DATAW+WW-1]}}, p10}
        + {{(ACCW-(DATAW+WW)){p11[DATAW+WW-1]}}, p11}
        + {{(ACCW-(DATAW+WW)){p12[DATAW+WW-1]}}, p12}
        + {{(ACCW-(DATAW+WW)){p20[DATAW+WW-1]}}, p20}
        + {{(ACCW-(DATAW+WW)){p21[DATAW+WW-1]}}, p21}
        + {{(ACCW-(DATAW+WW)){p22[DATAW+WW-1]}}, p22};

    assign sum_with_bias = sum_products + {{(ACCW-BW){b[BW-1]}}, b};

    // ---------------------------------
    // output 
    // ---------------------------------
    always @(posedge iClk) begin
        if (!iRsn) begin
            oOutValid <= 1'b0;
            oOutData  <= '0;
        end else begin
            oOutValid <= iInValid;
            oOutData  <= sum_with_bias;
        end
    end

endmodule
