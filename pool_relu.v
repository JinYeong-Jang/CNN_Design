module pool_relu #(
    parameter In_d_W = 32,
    parameter W      = 26
)(
    input                        iClk,
    input                        iRsn,         // sync, active-high
    input                        iInValid,    // 1 pixel / iClk
    input   signed [In_d_W-1:0]  iPoolData,     // [31:0] signed pixel

    output reg                       oOutValid,
    output reg signed [In_d_W-1:0]   oOutData // [31:0]
);

    localparam S_LOAD_ODD  = 1'b0;
    localparam S_LOAD_EVEN = 1'b1;

    reg state; // 0 = odd row, 1 = even row

    // Flattened odd-row buffer (W * In_d_W bits)
    reg signed [In_d_W*W-1:0] odd_row; // [831:0]

    // Column counter 0..W-1
    reg [$clog2(W):0] col_cnt; // [5:0]
   
    // Row counter 0..W-1
    reg [$clog2(W):0] row_cnt; // [5:0]

    // Even-row shift regs (hold previous two samples)
    reg signed [In_d_W-1:0] even_s0;  // previous sample
    reg signed [In_d_W-1:0] even_s1;  // older sample


    // Signed max and ReLU
    function [In_d_W-1:0] maxpool;
        input signed [In_d_W-1:0] a, b;
        begin
            if (a >= b) maxpool = a; else maxpool = b;
        end
    endfunction

    function [In_d_W-1:0] relu;
        input signed [In_d_W-1:0] x;
        begin
            if (x[In_d_W-1]) relu = {In_d_W{1'b0}}; else relu = x;
        end
    endfunction

    // Slices from odd_row for current window columns (left = col_cnt, right = col_cnt+1)
    wire signed [In_d_W-1:0] odd_pix_left;
    wire signed [In_d_W-1:0] odd_pix_right;
    assign odd_pix_left  = odd_row[(In_d_W*col_cnt)-1 -: In_d_W];
    assign odd_pix_right = odd_row[(In_d_W*(col_cnt+1))-1 -: In_d_W];

    // >>> Combinational 2x2 pooling for "this" cycle window
    // bottom-left  should be previous sample (even_s0)
    // bottom-right should be current sample  (iPoolData)
    wire signed [In_d_W-1:0] max_ab_now = maxpool(odd_pix_left,  odd_pix_right); // top row
    wire signed [In_d_W-1:0] max_cd_now = maxpool(even_s0,       iPoolData);       // bottom row
    wire signed [In_d_W-1:0] pool_now   = maxpool(max_ab_now,    max_cd_now);    // 2x2 max

    always @(posedge iClk) begin
        if (iRsn) begin
            state     <= S_LOAD_ODD;
            col_cnt   <= 0;
            row_cnt   <= 0;
            odd_row   <= {In_d_W*W{1'b0}};
            even_s0   <= {In_d_W{1'b0}};
            even_s1   <= {In_d_W{1'b0}};
            oOutValid <= 1'b0;
            oOutData  <= {In_d_W{1'b0}};
        end else begin
            oOutValid <= 1'b0; // default

            case (state)
                S_LOAD_ODD: begin
                    if (iInValid) begin
                        // Write current odd-row pixel into flattened buffer
                        odd_row[(In_d_W*(col_cnt+1))-1 -: In_d_W] <= iPoolData;
                        col_cnt <= col_cnt + 1;

                        if (col_cnt + 1 == W) begin
                            state   <= S_LOAD_EVEN;
                            col_cnt <= 0;
                            row_cnt <= row_cnt + 1;
                            // Clear even-row shifters
                            even_s0 <= {In_d_W{1'b0}};
                            even_s1 <= {In_d_W{1'b0}};
                        end
                    end
                end

                S_LOAD_EVEN: begin
                    if (iInValid) begin
                        // Shift previous samples (note: RHS are "old" values this cycle)
                        even_s1 <= even_s0;   // older <= previous
                        even_s0 <= iPoolData;   // previous <= current

                        // When col_cnt is odd, we have [col_cnt-1, col_cnt] window ready
                        if (col_cnt[0] == 1'b1) begin
                            // Use combinational pool_now to avoid 1-cycle latency
                            oOutData  <= relu(pool_now);
                            oOutValid <= 1'b1;
                        end

                        col_cnt <= col_cnt + 1;

                        if (col_cnt + 1 == W) begin
                            state   <= S_LOAD_ODD;
                            col_cnt <= 0;
                            row_cnt <= row_cnt + 1;
                        end

                        if ((row_cnt + 1 == W) && (col_cnt + 1 == W)) begin
                            state   <= S_LOAD_ODD;
                            col_cnt <= 0;
                            row_cnt <= 0;
                        end
                    end
                end

                default: state <= S_LOAD_ODD;
            endcase
        end
    end
endmodule



