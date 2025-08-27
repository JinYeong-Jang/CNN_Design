`timescale 1ns/1ps

module tb_pool_relu_wrapper;

    // ===== Parameters =====
    localparam In_d_W = 32;
    localparam W      = 26;   // 입력 가로 폭
    localparam H      = 28;    // 테스트용 입력 세로 높이(짝수 권장)
    localparam W_OUT  = W/2;  // stride=2, no padding -> 출력 가로
    localparam H_OUT  = H/2;  // stride=2, no padding -> 출력 세로
    localparam N_OUT  = W_OUT*H_OUT;

    // ===== DUT Ports =====
    reg                         iClk;
    reg                         iRsn;          // active-low reset (wrapper)
    reg   [3:0]                 iValid4;
    reg   signed [In_d_W-1:0]   iData0, iData1, iData2, iData3;

    wire  [3:0]                 oValid4;
    wire  signed [In_d_W-1:0]   oData0, oData1, oData2, oData3;

    // ===== DUT Instance =====
    pool_relu_wrapper #(
        .In_d_W (In_d_W),
        .W      (W)
    ) dut (
        .iClk    (iClk),
        .iRsn    (iRsn),          // active-low
        .iValid4 (iValid4),
        .iData0  (iData0),
        .iData1  (iData1),
        .iData2  (iData2),
        .iData3  (iData3),
        .oValid4 (oValid4),
        .oData0  (oData0),
        .oData1  (oData1),
        .oData2  (oData2),
        .oData3  (oData3)
    );

    // ===== Clock =====
    initial iClk = 1'b0;
    always #5 iClk = ~iClk;   // 100MHz

    // ===== Test Images (4 channels) =====
    // Verilog-2001 2D 메모리 사용
    reg signed [In_d_W-1:0] img0 [0:H-1][0:W-1];
    reg signed [In_d_W-1:0] img1 [0:H-1][0:W-1];
    reg signed [In_d_W-1:0] img2 [0:H-1][0:W-1];
    reg signed [In_d_W-1:0] img3 [0:H-1][0:W-1];

    // ===== Expected outputs after 2x2 maxpool + ReLU =====
    reg signed [In_d_W-1:0] exp0 [0:N_OUT-1];
    reg signed [In_d_W-1:0] exp1 [0:N_OUT-1];
    reg signed [In_d_W-1:0] exp2 [0:N_OUT-1];
    reg signed [In_d_W-1:0] exp3 [0:N_OUT-1];

    integer idx0, idx1, idx2, idx3;  // scoreboard pointers

    // Vivado의 "function must have at least one input" 경고 회피용 더미 인자
    function integer rand_m10_p10;
        input dummy;
        integer r;
        begin
            r = $random;
            // -10 ~ +10 범위로 매핑
            r = (r % 21);
            if (r < 0) r = r + 21;
            rand_m10_p10 = r - 10;
        end
    endfunction

    // 2x2 max + ReLU(0보다 작으면 0)
    function signed [In_d_W-1:0] max4_relu;
        input signed [In_d_W-1:0] a, b, c, d;
        reg   signed [In_d_W-1:0] m1, m2, m;
        begin
            m1 = (a > b) ? a : b;
            m2 = (c > d) ? c : d;
            m  = (m1 > m2) ? m1 : m2;
            max4_relu = (m < 0) ? 0 : m;
        end
    endfunction

    // ===== Stimulus / Scoreboard =====
    integer r, c, k;

    initial begin
        // ---------- Reset ----------
        iRsn    = 1'b0;       // active-low reset assert
        iValid4 = 4'b0000;
        iData0  = 0; iData1 = 0; iData2 = 0; iData3 = 0;

        // ---------- Prepare Random Images ----------
        for (r = 0; r < H; r = r + 1) begin
            for (c = 0; c < W; c = c + 1) begin
                img0[r][c] = rand_m10_p10(0);
                img1[r][c] = rand_m10_p10(0);
                img2[r][c] = rand_m10_p10(0);
                img3[r][c] = rand_m10_p10(0);
            end
        end

        // ---------- Pre-compute GOLDEN for stride=2, no padding ----------
        k = 0;
        for (r = 0; r < H; r = r + 2) begin
            for (c = 0; c < W; c = c + 2) begin
                // window: (r,c), (r,c+1), (r+1,c), (r+1,c+1)
                exp0[k] = max4_relu(img0[r][c], img0[r][c+1], img0[r+1][c], img0[r+1][c+1]);
                exp1[k] = max4_relu(img1[r][c], img1[r][c+1], img1[r+1][c], img1[r+1][c+1]);
                exp2[k] = max4_relu(img2[r][c], img2[r][c+1], img2[r+1][c], img2[r+1][c+1]);
                exp3[k] = max4_relu(img3[r][c], img3[r][c+1], img3[r+1][c], img3[r+1][c+1]);
                k = k + 1;
            end
        end

        idx0 = 0; idx1 = 0; idx2 = 0; idx3 = 0;

        // ---------- Release reset ----------
        repeat (5) @(posedge iClk);
        iRsn = 1'b1;   // deassert reset

        // ---------- Drive Stream (row-major) ----------
        // 각 사이클에 모든 채널을 동시에 1 pixel씩 투입
        for (r = 0; r < H; r = r + 1) begin
            for (c = 0; c < W; c = c + 1) begin
                @(posedge iClk);
                iValid4 <= 4'b1111;     // 4채널 모두 유효
                iData0  <= img0[r][c];
                iData1  <= img1[r][c];
                iData2  <= img2[r][c];
                iData3  <= img3[r][c];
            end
        end

        // ---------- Stop inputs ----------
        @(posedge iClk);
        iValid4 <= 4'b0000;
        iData0  <= 0; iData1 <= 0; iData2 <= 0; iData3 <= 0;

        // ---------- Wait some cycles for pipeline flush ----------
        repeat (200) @(posedge iClk);

        // ---------- Final report ----------
        if ((idx0==N_OUT) && (idx1==N_OUT) && (idx2==N_OUT) && (idx3==N_OUT))
            $display("PASS: All channels produced %0d outputs each and matched GOLDEN.", N_OUT);
        else
            $display("WARN: Outputs seen (ch0..3) = %0d %0d %0d %0d, expected each = %0d",
                     idx0, idx1, idx2, idx3, N_OUT);

        $finish;
    end

    // ===== Scoreboard: compare on-the-fly when oValid4[x] rises =====
    // 채널 0
    always @(posedge iClk) begin
        if (!iRsn) begin
            idx0 <= 0;
        end else if (oValid4[0]) begin
            if (idx0 < N_OUT) begin
                if (oData0 !== exp0[idx0]) begin
                    $display("%t ERROR CH0 idx=%0d: got %0d, exp %0d",
                              $time, idx0, oData0, exp0[idx0]);
                end
            end else begin
                $display("%t ERROR CH0: extra output beyond expected length!", $time);
            end
            idx0 <= idx0 + 1;
            // 추가 안정성: ReLU 속성 확인
            if (oData0 < 0) $display("%t ERROR CH0: ReLU violated (negative output)", $time);
        end
    end

    // 채널 1
    always @(posedge iClk) begin
        if (!iRsn) begin
            idx1 <= 0;
        end else if (oValid4[1]) begin
            if (idx1 < N_OUT) begin
                if (oData1 !== exp1[idx1]) begin
                    $display("%t ERROR CH1 idx=%0d: got %0d, exp %0d",
                              $time, idx1, oData1, exp1[idx1]);
                end
            end else begin
                $display("%t ERROR CH1: extra output beyond expected length!", $time);
            end
            idx1 <= idx1 + 1;
            if (oData1 < 0) $display("%t ERROR CH1: ReLU violated (negative output)", $time);
        end
    end

    // 채널 2
    always @(posedge iClk) begin
        if (!iRsn) begin
            idx2 <= 0;
        end else if (oValid4[2]) begin
            if (idx2 < N_OUT) begin
                if (oData2 !== exp2[idx2]) begin
                    $display("%t ERROR CH2 idx=%0d: got %0d, exp %0d",
                              $time, idx2, oData2, exp2[idx2]);
                end
            end else begin
                $display("%t ERROR CH2: extra output beyond expected length!", $time);
            end
            idx2 <= idx2 + 1;
            if (oData2 < 0) $display("%t ERROR CH2: ReLU violated (negative output)", $time);
        end
    end

    // 채널 3
    always @(posedge iClk) begin
        if (!iRsn) begin
            idx3 <= 0;
        end else if (oValid4[3]) begin
            if (idx3 < N_OUT) begin
                if (oData3 !== exp3[idx3]) begin
                    $display("%t ERROR CH3 idx=%0d: got %0d, exp %0d",
                              $time, idx3, oData3, exp3[idx3]);
                end
            end else begin
                $display("%t ERROR CH3: extra output beyond expected length!", $time);
            end
            idx3 <= idx3 + 1;
            if (oData3 < 0) $display("%t ERROR CH3: ReLU violated (negative output)", $time);
        end
    end

endmodule
