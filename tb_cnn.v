`timescale 1ns / 1ps

module cnn_top_tb;

    // Parameters (must match the module under test)
    parameter integer WI    = 8;
    parameter integer BW    = 32;
    parameter integer ACCW  = 32;

    // Testbench signals
    reg iClk;
    reg iRsn;
    reg iPixelValid;
    reg [WI-1:0] iPixelIn;

    wire [3:0] oValid;
    wire signed [ACCW-1:0] oData0, oData1, oData2, oData3;

    // Image data and counters
    localparam integer IMG_W = 28;
    localparam integer IMG_SIZE = IMG_W * IMG_W;
    reg [WI-1:0] image_mem [0:IMG_SIZE-1];
    integer pixel_idx;

    // Instantiate the Unit Under Test (UUT)
    cnn_top #(
        .WI(WI),
        .BW(BW),
        .ACCW(ACCW)
    ) uut (
        .iClk(iClk),
        .iRsn(iRsn),
        .iPixelIn(iPixelIn),
        .iPixelValid(iPixelValid),
        .oValid(oValid),
        .oData0(oData0),
        .oData1(oData1),
        .oData2(oData2),
        .oData3(oData3)
    );

    // Clock generator
    initial begin
        iClk = 1'b0;
        forever #5 iClk = ~iClk; // 100 MHz clock (10 ns period)
    end

    // Test stimulus
    initial begin
        // Load image data and kernel weights/biases
        $readmemh("mnist_0.mem", image_mem);
        // Note: The `cnn_top` module and its sub-modules,
        // `four_conv3x3_kernel` and `conv_3x3_window`,
        // would require these files to be available during simulation.
        // `conv_w.mem` and `conv_b.mem` are handled by `four_conv3x3_kernel`.
        // `image.mem` is handled by this testbench.

        // Apply reset
        iRsn = 1'b0;
        iPixelValid = 1'b0;
        iPixelIn = '0;
        pixel_idx = 0;
        #20; // Wait for 2 clock cycles
        iRsn = 1'b1;

        // Feed pixels to the design
        @(posedge iClk);
        while (pixel_idx < IMG_SIZE) begin
            iPixelValid = 1'b1;
            iPixelIn = image_mem[pixel_idx];
            @(posedge iClk);
            pixel_idx = pixel_idx + 1;
        end
        iPixelValid = 1'b0; // Stop feeding pixels after the last one

        // Wait for pipeline to drain
        #500; // Allow enough time for all computations to complete

        // End of test
        $display("Test finished.");
        $finish;
    end

    // Monitor for debugging
    initial begin
        $monitor("Time=%0t, Pixel Valid=%b, Pixel In=%d, oValid=%b, oData0=%d, oData1=%d, oData2=%d, oData3=%d",
                 $time, iPixelValid, iPixelIn, oValid, oData0, oData1, oData2, oData3);
    end

endmodule