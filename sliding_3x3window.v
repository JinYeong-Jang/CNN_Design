module sliding_3x3window #(
    parameter IMG_W  = 28,       // image width
    parameter PIX_W  = 8         // pixel bit width
)(
    
    //clock & reset
    input                       iClk,                     // Rising edge
    input                       iRsn,                     // Sync. & low reset


    input       [PIX_W-1:0]     iPixelIn,                 // 8-bit input pixel
    input                       iPixelValid,              // Input data valid signal
    
    
    output reg [3*PIX_W-1:0]    oWindowOutRow1,           // 3x3 window output, row 1
    output reg [3*PIX_W-1:0]    oWindowOutRow2,           // 3x3 window output, row 2
    output reg [3*PIX_W-1:0]    oWindowOutRow3,            // 3x3 window output, row 3
    output                  oWindowValid,
    output                  oMapDone
);
    // =========================
    // FSM
    // =========================
    localparam P_IDLE = 2'd0;
    localparam P_RUN  = 2'd1;
    localparam P_DONE = 2'd2;

    reg [1:0] state, state_n;

    // wire & reg
    reg [PIX_W-1:0] line0 [0:IMG_W-1];  // top
    reg [PIX_W-1:0] line1 [0:IMG_W-1];  // mid
    reg [PIX_W-1:0] line2 [0:IMG_W-1];  // bottom 

    reg [4:0] rColCount;
    reg [4:0] rRowCount;

    reg [4:0] col_q, row_q;
    reg       window_q;


    reg rWindowValid;
    reg rMapDone;

    integer i;

    // -------------------------
    // FSM: next-state
    // -------------------------
    always @* begin
        state_n = state;
        case (state)
            P_IDLE: begin
                if (iPixelValid) state_n = P_RUN;
            end
            P_RUN: begin
                if ((col_q == IMG_W-1) && (row_q == IMG_W-1))
                    state_n = P_DONE;
            end
            P_DONE: begin
                state_n = P_IDLE;
            end
            default: state_n = P_IDLE;
        endcase
    end

    // -------------------------
    // FSM: state register
    // -------------------------
    always @(posedge iClk) begin
        if (!iRsn)
            state <= P_IDLE;
        else
            state <= state_n;
    end


    // Main sequential logic block
    always @(posedge iClk) begin
        if (!iRsn) begin
            rColCount    <= 5'd0;
            rRowCount    <= 5'd0;
            rWindowValid <= 1'b0;
            rMapDone     <= 1'b0;

        end else begin
        
        rWindowValid <= 1'b0;
        rMapDone <= 1'b0;

        if (state_n == P_RUN) begin
            if (iPixelValid) begin
                // ----- 픽셀 쓰기 -----
                if (rRowCount == 5'd0) begin
                    line0[rColCount] <= iPixelIn;
                end else if (rRowCount == 5'd1) begin
                    line1[rColCount] <= iPixelIn;
                end else if (rRowCount == 5'd2) begin
                    line2[rColCount] <= iPixelIn;
                end else begin
                    if (rColCount == 5'd0) begin
                        // 행 넘어갈 때 라인 쉬프트
                        for (i = 0; i < IMG_W; i = i + 1) begin
                            line0[i] <= line1[i];
                            line1[i] <= line2[i];
                        end
                        line2[0] <= iPixelIn;
                    end else begin
                        line2[rColCount] <= iPixelIn;
                    end
                end

                // ----- 윈도우 유효 여부 -----
                if ((rRowCount >= 5'd2) && (rColCount >= 5'd2))
                    rWindowValid <= 1'b1;

                if ((rRowCount == (IMG_W-1)) && (rColCount == (IMG_W-1))) 
                    rMapDone <= 1'b1;


                // ----- 카운터 업데이트 -----
                if (rColCount == IMG_W - 1) begin
                    rColCount <= 5'd0;
                    if(rRowCount == IMG_W -1)
                        rRowCount <= 5'd0;
                    else
                        rRowCount <= rRowCount + 5'd1;
                end else begin
                    rColCount <= rColCount + 5'd1;
                end
            end
        end else if(state == P_IDLE) begin
                rColCount <= 5'd0;
                rRowCount <= 5'd0;
            end
        end
    end

    always @(posedge iClk) begin
        if (!iRsn) begin
            col_q          <= 5'd0;
            row_q          <= 5'd0;
            window_q       <= 1'b0;
        end else begin
            if (iPixelValid) begin
                col_q          <= rColCount;
                row_q          <= rRowCount;
                window_q       <= (rRowCount >= 5'd2) && (rColCount >= 5'd2);
            end else begin
                window_q <= 1'b0;
            end
        end
    end

    // Combinational logic to form the 3x3 window from the line buffers.
    always @* begin
        if (window_q) begin
            oWindowOutRow1 = { line0[col_q-2], line0[col_q-1], line0[col_q] };
            oWindowOutRow2 = { line1[col_q-2], line1[col_q-1], line1[col_q] };
            oWindowOutRow3 = { line2[col_q-2], line2[col_q-1], line2[col_q] };
        end else begin
            oWindowOutRow1 = {(3*PIX_W){1'b0}};
            oWindowOutRow2 = {(3*PIX_W){1'b0}};
            oWindowOutRow3 = {(3*PIX_W){1'b0}};
        end
    end
    
    // Assign outputs
    assign oWindowValid = rWindowValid;
    assign oMapDone     = (state == P_DONE) ? 1'b1 : 1'b0; // 1사이클 펄스

endmodule
