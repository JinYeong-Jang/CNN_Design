module sliding_3x3window #(
    parameter IMG_W  = 28,       // image width
    parameter PIX_W  = 8         // pixel bit width
)(
    
    //clock & reset
    input                       iClk,                     // Rising edge
    input                       iRsn,                     // Sync. & low reset


    input       [PIX_W-1:0]     iPixelIn,                 // 8-bit input pixel
    input                       iPixelValid,              // Data valid signal
    
    
    output reg [3*PIX_W-1:0]    oWindowOutRow1,           // 3x3 window output, row 1
    output reg [3*PIX_W-1:0]    oWindowOutRow2,           // 3x3 window output, row 2
    output reg [3*PIX_W-1:0]    oWindowOutRow3            // 3x3 window output, row 3
);

    // wire & reg
    reg [PIX_W-1:0] line0 [0:IMG_W-1];
    reg [PIX_W-1:0] line1 [0:IMG_W-1];
    reg [PIX_W-1:0] line2 [0:IMG_W-1];

    reg [4:0] rColCount;
    reg [4:0] rRowCount;

    reg rWindowValid;

    // Main sequential logic block
    always @(posedge iClk) begin
        if (!iRsn) begin
            rColCount <= 5'd0;
            rRowCount <= 5'd0;
            rWindowValid <= 1'b0;
            // Initialize buffer to a known state on reset
        end else if (iPixelValid) begin
            if(rRowCount <= 2) 
                rLineBuffer[rRowCount][rColCount] <= iPixelIn;
            else begin 
                if (rColCount == 0) begin
                    rLineBuffer[0] <= rLineBuffer[1];
                    rLineBuffer[1] <= rLineBuffer[2];
                    rLineBuffer[2][rColCount] <= iPixelIn;
                end
                rLineBuffer[2][rColCount] <= iPixelIn;
            end

            // Update counters
            if (rColCount == 27) begin
                rColCount <= 5'd0;
                rRowCount <= rRowCount + 1;
            end else begin
                rColCount <= rColCount + 1;
            end

            // The window is valid when we have processed enough data to fill the 3x3 window
            if (rRowCount >= 2 && rColCount >= 2) begin
                rWindowValid <= 1'b1;
            end
        end
    end

    // Combinational logic to form the 3x3 window from the line buffers.
    always @(*) begin
        if (rWindowValid) begin
            oWindowOutRow1 = {rLineBuffer[0][rColCount - 2], rLineBuffer[0][rColCount - 1], rLineBuffer[0][rColCount]};
            oWindowOutRow2 = {rLineBuffer[1][rColCount - 2], rLineBuffer[1][rColCount - 1], rLineBuffer[1][rColCount]};
            oWindowOutRow3 = {rLineBuffer[2][rColCount - 2], rLineBuffer[2][rColCount - 1], rLineBuffer[2][rColCount]};
        end else begin
            oWindowOutRow1 = 24'd0;
            oWindowOutRow2 = 24'd0;
            oWindowOutRow3 = 24'd0;
        end
    end

endmodule