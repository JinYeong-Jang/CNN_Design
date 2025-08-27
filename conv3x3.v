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

    output                    oOutValid,
    output  signed [ACCW-1:0]  oOutData
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
    wire signed [DATAW-1:0] a00 = iWindowInRow1[3*DATAW-1 -: DATAW];
    wire signed [DATAW-1:0] a01 = iWindowInRow1[2*DATAW-1 -: DATAW];
    wire signed [DATAW-1:0] a02 = iWindowInRow1[1*DATAW-1 -: DATAW];

    wire signed [DATAW-1:0] a10 = iWindowInRow2[3*DATAW-1 -: DATAW];
    wire signed [DATAW-1:0] a11 = iWindowInRow2[2*DATAW-1 -: DATAW];
    wire signed [DATAW-1:0] a12 = iWindowInRow2[1*DATAW-1 -: DATAW];

    wire signed [DATAW-1:0] a20 = iWindowInRow3[3*DATAW-1 -: DATAW];
    wire signed [DATAW-1:0] a21 = iWindowInRow3[2*DATAW-1 -: DATAW];
    wire signed [DATAW-1:0] a22 = iWindowInRow3[1*DATAW-1 -: DATAW];

    wire signed [WW-1:0] w00 = conv_weight[(1)*WW-1 -: WW];
    wire signed [WW-1:0] w01 = conv_weight[(2)*WW-1 -: WW];
    wire signed [WW-1:0] w02 = conv_weight[(3)*WW-1 -: WW];
    wire signed [WW-1:0] w10 = conv_weight[(4)*WW-1 -: WW];
    wire signed [WW-1:0] w11 = conv_weight[(5)*WW-1 -: WW];
    wire signed [WW-1:0] w12 = conv_weight[(6)*WW-1 -: WW];
    wire signed [WW-1:0] w20 = conv_weight[(7)*WW-1 -: WW];
    wire signed [WW-1:0] w21 = conv_weight[(8)*WW-1 -: WW];
    wire signed [WW-1:0] w22 = conv_weight[(9)*WW-1 -: WW];
    wire signed [BW-1:0] b    = conv_bias;

    wire ce = iInValid;


    // product results
    reg signed [PRODW-1:0] p00, p01, p02,
                               p10, p11, p12,
                               p20, p21, p22;

    always @(posedge iClk) begin
        if (!iRsn) begin
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0; p20<=0; p21<=0; p22<=0;
        end else if (ce) begin
            p00 <= a00 * w00;  p01 <= a01 * w01;  p02 <= a02 * w02;
            p10 <= a10 * w10;  p11 <= a11 * w11;  p12 <= a12 * w12;
            p20 <= a20 * w20;  p21 <= a21 * w21;  p22 <= a22 * w22;
        end
    end

    // sign-extend helper
    function [ACCW-1:0] sx;
        input signed [PRODW-1:0] v;
        begin sx = {{(ACCW-PRODW){v[PRODW-1]}}, v}; end
    endfunction

    // 한 번에 조합 합산
    wire signed [ACCW-1:0] sum_products;
    assign sum_products =
          sx(p00)+sx(p01)+sx(p02)
        + sx(p10)+sx(p11)+sx(p12)
        + sx(p20)+sx(p21)+sx(p22);

    wire signed [ACCW-1:0] sum_with_bias;
    assign sum_with_bias =
        sum_products + {{(ACCW-BW){b[BW-1]}}, b};

    reg                      rOutValid;
    reg  signed [ACCW-1:0]   rOutData;
    always @(posedge iClk) begin
        if (!iRsn) begin
            rOutValid <= 1'b0;
            rOutData  <= {ACCW{1'b0}};
        end else if (ce) begin
            rOutValid <= 1'b1;
            rOutData  <= sum_with_bias;
        end else begin
            rOutValid <= 1'b0;  // 필요하면 hold로 바꿔도 됨
        end
    end

    assign oOutValid = rOutValid;
    assign oOutData = rOutData;

endmodule
