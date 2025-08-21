`timescale 1ns/1ps
// ?��?�� Verilog TB (-10~+10 ?��?�� ?��?��), DUT: pool_relu_wrapper
module tb_pool_relu_wrapper;

    // ==== ?��?��미터 (wrapper?? ?��?��) ====
    localparam integer In_d_W = 32;
    localparam integer W      = 26;

    // ==== DUT ?��?�� ====
    reg                        clk;
    reg                        clr;
    reg        [3:0]           in_valid;   // 채널�? ?��?��?��?��
    reg  signed [4*In_d_W-1:0] in_data;    // 채널 4�? ?��?�� ?��?��
    wire       [3:0]           out_valid;  // 채널�? ?��?��?��?��
    wire signed [4*In_d_W-1:0] out_data;   // 채널 4�? ?��?�� 출력

    // ==== DUT ?��?��?��?�� (모듈�?/?��?���? ?��?��?�� ?���?) ====
    pool_relu_wrapper #(
        .In_d_W (In_d_W),
        .W      (W)
    ) dut (
        .clk      (clk),
        .clr      (clr),
        .in_valid (in_valid),
        .in_data  (in_data),
        .out_valid(out_valid),
        .out_data (out_data)
    );

    // ==== ?���?: 10ns ====
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ==== 채널�? 출력 ?��?��?��?��(�?찰용) ====
    wire signed [In_d_W-1:0] in_ch0, in_ch1, in_ch2, in_ch3;
    assign in_ch0 = in_data[In_d_W-1:0]; // [31:0]
    assign in_ch1 = in_data[2*In_d_W-1:In_d_W]; // [63:32]
    assign in_ch2 = in_data[3*In_d_W-1:2*In_d_W]; // [95:64]
    assign in_ch3 = in_data[4*In_d_W-1:3*In_d_W]; // [127:96]
    
    wire signed [In_d_W-1:0] out_ch0, out_ch1, out_ch2, out_ch3;
    assign out_ch0 = out_data[In_d_W-1:0]; // [31:0]
    assign out_ch1 = out_data[2*In_d_W-1:In_d_W]; // [63:32]
    assign out_ch2 = out_data[3*In_d_W-1:2*In_d_W]; // [95:64]
    assign out_ch3 = out_data[4*In_d_W-1:3*In_d_W]; // [127:96]

    // ==== ?��?�� ?��?�� ?��?��: {ch3, ch2, ch1, ch0} ====
    function [4*In_d_W-1:0] pack4;
        input signed [In_d_W-1:0] d0; // lane0 (LSB)
        input signed [In_d_W-1:0] d1; // lane1
        input signed [In_d_W-1:0] d2; // lane2
        input signed [In_d_W-1:0] d3; // lane3 (MSB)
        begin
            pack4 = {d3, d2, d1, d0};
        end
    endfunction

    // ==== -10 ~ +10 ?��?�� (Verilog $random ?��?��) ====
    function signed [In_d_W-1:0] rand_m10_p10;
        input dummy;
        integer r;
        begin
            r = $random;            // 32-bit signed
            r = r % 21;             // -20..+20 (?��?�� �??��)
            if (r < 0) r = r + 21;  // 0..20
            rand_m10_p10 = r - 10;  // -10..+10
        end
    endfunction

    // ==== ?�� ?��?��?�� ?��?�� 주입 ?��?��?�� ====
    task drive_all_rand;
        input [3:0] vld;
        reg signed [In_d_W-1:0] d0, d1, d2, d3;
        begin
            d0 = rand_m10_p10(1'b0);
            d1 = rand_m10_p10(1'b0);
            d2 = rand_m10_p10(1'b0);
            d3 = rand_m10_p10(1'b0);
            in_data  <= pack4(d0, d1, d2, d3);
            in_valid <= vld;
            @(posedge clk);
        end
    endtask

    // ==== out_valid=1?�� ?���? 결과 로그 ====
    always @(posedge clk) begin
        if (out_valid != 4'b0000) begin
            $display("[%0t] OUT  vld=%b  ch0=%0d  ch1=%0d  ch2=%0d  ch3=%0d",
                     $time, out_valid, out_ch0, out_ch1, out_ch2, out_ch3);
        end
    end

    integer k;
    initial begin
        // (?��?��) VCD ?��?�� ?��?��
        $dumpfile("tb_pool_relu_wrapper.vcd");
        $dumpvars(0, tb_pool_relu_wrapper);

        // 초기�? �? 리셋
        clr      = 1'b1;
        in_valid = 4'b0000;
        in_data  = {4*In_d_W{1'b0}};
        repeat (2) @(posedge clk);
        clr = 1'b0;
        @(posedge clk);

        // ?�� ODD ?��: W?��?��?�� ?��?�� 주입
        for (k = 0; k < W; k = k + 1) begin
            drive_all_rand(4'b1111);
        end

        // ?�� EVEN ?��: W?��?��?�� ?��?�� 주입
        //    (EVEN ?��?��?��?�� col_cnt>0�??�� out_valid�? 1�? ?��?��?��?�� �? ?��?��)
        for (k = 0; k < W; k = k + 1) begin
            drive_all_rand(4'b1111);
        end

        // 마무�?
        in_valid <= 4'b0000;
        repeat (5) @(posedge clk);
        $display("Simulation done.");
        $finish;
    end

endmodule
