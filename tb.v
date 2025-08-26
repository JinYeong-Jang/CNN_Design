`timescale 1ns/1ps

module tb_pool_relu;

    localparam In_d_W = 32;
    localparam W      = 26;

    reg                           iClk;
    reg                           iRsn;          // sync, active-high
    reg                           iInValid;
    reg  signed [In_d_W-1:0]      iPoolData;
    wire                          oOutValid;
    wire signed [In_d_W-1:0]      oOutData;

    // DUT
    pool_relu #(
        .In_d_W (In_d_W),
        .W      (W)
    ) dut (
        .iClk      (iClk),
        .iRsn      (iRsn),
        .iInValid (iInValid),
        .iPoolData  (iPoolData),
        .oOutValid(oOutValid),
        .oOutData (oOutData)
    );

    // 100 MHz clock
    initial iClk = 1'b0;
    always #5 iClk = ~iClk;

    integer out_cnt;

    // ---- 랜덤 한 행을 구동: −10..10 정수 생성 ----
    task drive_row_random;
        input odd_row;      // 1=odd, 0=even (구조 유지용)
        integer c;
        integer r;          // raw random
        integer u;          // 0..20
        integer s;          // -10..10
        begin
            for (c = 0; c < W; c = c + 1) begin
                @(posedge iClk);
                iInValid <= 1'b1;

                // $random은 음수가 나올 수 있으므로 절댓값으로 0..20 범위 생성
                r = $random;
                if (r < 0) r = -r;
                u = r % 21;         // 0..20
                s = u - 10;         // -10..10

                iPoolData <= s;

                // 확인용 로그 
                // $display("[%0t] drive row=%0d col=%0d data=%0d", $time, odd_row, c, s);
            end

            // 행 간 간격 1사이클
            @(posedge iClk);
            iInValid <= 1'b0;
            iPoolData  <= 0;
        end
    endtask

    // DUT 출력 모니터
    always @(posedge iClk) begin
        if (!iRsn && oOutValid) begin
            out_cnt = out_cnt + 1;
            $display("[%0t] OUT[%0d]=%0d", $time, out_cnt-1, oOutData);
        end
    end

    initial begin
        // 초기화
        iInValid = 1'b0;
        iPoolData  = 0;
        iRsn      = 1'b1;
        out_cnt  = 0;

        // 리셋 3사이클
        repeat (3) @(posedge iClk);
        iRsn <= 1'b0;

        // 4개 행(odd, even, odd, even)
        drive_row_random(1'b1);   // row 1
        drive_row_random(1'b0);   // row 2 → 13개 출력
        drive_row_random(1'b1);   // row 3
        drive_row_random(1'b0);   // row 4 → 13개 출력

        // 파이프라인 드레인
        repeat (10) @(posedge iClk);

        $display("INFO: total outputs = %0d (expected ~%0d)", out_cnt, (W/2)*2);
        $finish;
    end

endmodule
