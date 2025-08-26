module conv3x3 #(
    parameter integer WI    = 8,
    parameter integer BW    = 32,
    parameter integer ACCW  = 32
)(
    input                         iClk,
    input                         iRsn,        // active-low
    input                         iInValid,

    input      [3*WI-1:0]         iWindowInRow1,
    input      [3*WI-1:0]         iWindowInRow2,
    input      [3*WI-1:0]         iWindowInRow3,

    input  signed [WI*9-1:0]      conv_weight,    // {w00,w01,...,w22}
    input  signed [BW-1:0]        conv_bias,         // bias for this output channel

    output reg                    oOutValid,
    output reg signed [ACCW-1:0]  oOutData
);

    // ---------------------------------
    // Corrected parameter declaration
    // ---------------------------------
    localparam DATAW = WI;
    localparam WW    = WI;
    localparam PRODW = DATAW + WW; // Product width


    // ---------------------------------
    // weight/bias ROM
    // ---------------------------------

    wire signed [DATAW-1:0] a00, a01, a02,
                            a10, a11, a12,
                            a20, a21, a22;

    wire signed [WW-1:0] w00, w01, w02,
                         w10, w11, w12,
                         w20, w21, w22;

    wire signed [BW-1:0] b;

    // product results
    wire signed [PRODW-1:0] p00, p01, p02,
                               p10, p11, p12,
                               p20, p21, p22;

    // sum results
    wire signed [ACCW-1:0] sum_products;
    wire signed [ACCW-1:0] sum_with_bias;

    // base index(OC)
    wire [7:0] base;

    //level 1 wire & reg
    wire signed [ACCW-1:0] s0_l1, s1_l1, s2_l1, s3_l1, s4_l1;
    reg signed [ACCW-1:0] s0_r1, s1_r1, s2_r1, s3_r1, s4_r1;
    reg                   v_r1;

    //level 2 wire
    wire signed [ACCW-1:0] s0_l2, s1_l2, s2_l2; 

    //level 3 wire & reg
    wire signed [ACCW-1:0] s0_l3, s1_l3;
    reg signed [ACCW-1:0] s0_r3, s1_r3;
    reg                   v_r3;


    
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
    assign w00 =  conv_weight[(1)*WW-1 -: WW];
    assign w01 =  conv_weight[(2)*WW-1 -: WW];
    assign w02 =  conv_weight[(3)*WW-1 -: WW];
    assign w10 =  conv_weight[(4)*WW-1 -: WW];
    assign w11 =  conv_weight[(5)*WW-1 -: WW];
    assign w12 =  conv_weight[(6)*WW-1 -: WW];
    assign w20 =  conv_weight[(7)*WW-1 -: WW];
    assign w21 =  conv_weight[(8)*WW-1 -: WW];
    assign w22 =  conv_weight[(9)*WW-1 -: WW];

    // ---------------------------------
    // mul instance
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

 // sign-extend helper
    function [ACCW-1:0] sx;
        input signed [PRODW-1:0] v;
        begin sx = {{(ACCW-PRODW){v[PRODW-1]}}, v}; end
    endfunction

    // 한 번에 조합 합산
    wire signed [ACCW-1:0] sum_products =
          sx(p00)+sx(p01)+sx(p02)
        + sx(p10)+sx(p11)+sx(p12)
        + sx(p20)+sx(p21)+sx(p22);

    wire signed [ACCW-1:0] sum_with_bias =
        sum_products + {{(ACCW-BW){conv_bias[BW-1]}}, conv_bias};

    // 출력 1단 레지스터 → LAT_kernel = 1
    always @(posedge iClk) begin
        if (!iRsn) begin
            oOutValid <= 1'b0;
            oOutData  <= {ACCW{1'b0}};
        end else begin
            oOutValid <= iInValid;      // 같은 단계로 valid 동행
            oOutData  <= sum_with_bias; // data
        end
    end
endmodule
