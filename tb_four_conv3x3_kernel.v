`timescale 1ns/1ps
module tb_conv3x3_wrapper;

    // ===== 환경 파라미터 =====
    localparam integer WI    = 8;    // input/weight bit width (signed)
    localparam integer BW    = 32;   // bias bit width (signed)
    localparam integer ACCW  = 32;   // accumulator width (signed)
    localparam integer IMG_W = 28;
    localparam integer IMG_H = 28;
    localparam integer OW    = IMG_W - 2;  // 26
    localparam integer OH    = IMG_H - 2;  // 26
    localparam integer NWIN  = OW * OH;    // 676

    // ===== 총 지연(LAT) 설정 =====
    // conv3x3_kernel(균형트리+2단 파이프라인) = 2
    // four_conv3x3_kernel 내부 출력 레지스터 = +1
    // ==> 총 LAT = 3  (필요에 따라 1/2/3으로 바꿔 써)
    localparam integer LAT   = 3;

    // ===== DUT I/O =====
    reg                      iClk;
    reg                      iRsn;       // active-low
    reg                      iInValid;
    reg                      iMapDone;

    reg  [3*WI-1:0]          iWindowInRow1;
    reg  [3*WI-1:0]          iWindowInRow2;
    reg  [3*WI-1:0]          iWindowInRow3;

    wire [3:0]               oValid4;
    wire signed [ACCW-1:0]   oData0, oData1, oData2, oData3;

    // ===== DUT 인스턴스 =====
    conv3x3_wrapper #(
        .WI(WI), .BW(BW), .ACCW(ACCW)
    ) dut (
        .iClk(iClk),
        .iRsn(iRsn),
        .iInValid(iInValid),
        .iMapDone(iMapDone),
        .iWindowInRow1(iWindowInRow1),
        .iWindowInRow2(iWindowInRow2),
        .iWindowInRow3(iWindowInRow3),
        .oValid4(oValid4),
        .oData0(oData0),
        .oData1(oData1),
        .oData2(oData2),
        .oData3(oData3)
    );

    // ===== Clock / Reset =====
    initial iClk = 1'b0;
    always #5 iClk = ~iClk; // 100 MHz

    initial begin
        iRsn = 1'b0; iInValid = 1'b0; iMapDone = 1'b0;
        iWindowInRow1 = '0; iWindowInRow2 = '0; iWindowInRow3 = '0;
        repeat(6) @(posedge iClk);
        iRsn = 1'b1;
    end

    // ===== VCD 덤프(파형) =====
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb_four_conv3x3_kernel);
    end

    // ===== 디버그 조건 =====
    integer dbg_en        = 1;         // 0=off, 1=on
    integer dbg_r_match   = 10;        // 보고 싶은 r
    integer dbg_c_match   = 5;         // 보고 싶은 c
    reg [1:0] dbg_phase   = 2;         // 보고 싶은 phase
    reg [3:0] dbg_lane_m  = 4'b1111;   // lane mask

    // ===== TB 메모리 =====
    reg  signed [WI-1:0]  img   [0:IMG_W*IMG_H-1];  // 28x28
    reg  signed [WI-1:0]  w_all [0:16*9-1];         // 16ch * 9
    reg  signed [BW-1:0]  b_all [0:16-1];           // 16 bias

    // ===== 현재 주입 중인 좌표 추적 =====
    integer cur_r, cur_c;

    // ===== 윈도우 드라이브 =====
    task drive_window(input integer r, input integer c);
        reg signed [WI-1:0] a00,a01,a02,a10,a11,a12,a20,a21,a22;
        begin
            cur_r = r; cur_c = c;
            a00 = img[(r+0)*IMG_W + (c+0)];
            a01 = img[(r+0)*IMG_W + (c+1)];
            a02 = img[(r+0)*IMG_W + (c+2)];
            a10 = img[(r+1)*IMG_W + (c+0)];
            a11 = img[(r+1)*IMG_W + (c+1)];
            a12 = img[(r+1)*IMG_W + (c+2)];
            a20 = img[(r+2)*IMG_W + (c+0)];
            a21 = img[(r+2)*IMG_W + (c+1)];
            a22 = img[(r+2)*IMG_W + (c+2)];
            // DUT 패킹과 동일
            iWindowInRow1 = {a00, a01, a02};
            iWindowInRow2 = {a10, a11, a12};
            iWindowInRow3 = {a20, a21, a22};
        end
    endtask

    // ===== golden dot product + bias =====
    function signed [ACCW-1:0] dot9_bias;
        input integer oc;
        input integer r;
        input integer c;
        integer base, ky, kx;
        reg signed [ACCW-1:0] acc;
        reg signed [WI-1:0]  px, w;
        begin
            base = oc*9; acc = 0;
            for (ky=0; ky<3; ky=ky+1) begin
                for (kx=0; kx<3; kx=kx+1) begin
                    px = img[(r+ky)*IMG_W + (c+kx)];
                    w  = w_all[base + ky*3 + kx];
                    acc = acc + $signed(px) * $signed(w);
                end
            end
            dot9_bias = acc + b_all[oc];
        end
    endfunction

    // ===== 지연 정렬용 FIFO =====
    // (r,c) 지연
    reg [7:0] r_d [0:LAT];
    reg [7:0] c_d [0:LAT];

    // lane별 기대값 FIFO
    reg signed [ACCW-1:0] exp0_fifo [0:LAT];
    reg signed [ACCW-1:0] exp1_fifo [0:LAT];
    reg signed [ACCW-1:0] exp2_fifo [0:LAT];
    reg signed [ACCW-1:0] exp3_fifo [0:LAT];

    // 같은 사이클에 계산해 둘 기대값(푸시 전 버퍼)
    reg signed [ACCW-1:0] exp0_now, exp1_now, exp2_now, exp3_now;

    // FIFO 푸시/쉬프트 (posedge에서 호출)
    task push_expected_and_coords(input integer r_in, input integer c_in);
        integer k;
        begin
            r_d[0] <= r_in[7:0];
            c_d[0] <= c_in[7:0];
            for (k=1; k<=LAT; k=k+1) begin
                r_d[k] <= r_d[k-1];
                c_d[k] <= c_d[k-1];
            end
            for (k=LAT; k>0; k=k-1) begin
                exp0_fifo[k] <= exp0_fifo[k-1];
                exp1_fifo[k] <= exp1_fifo[k-1];
                exp2_fifo[k] <= exp2_fifo[k-1];
                exp3_fifo[k] <= exp3_fifo[k-1];
            end
            exp0_fifo[0] <= exp0_now;
            exp1_fifo[0] <= exp1_now;
            exp2_fifo[0] <= exp2_now;
            exp3_fifo[0] <= exp3_now;
        end
    endtask

    // ===== 디버그: 특정 지점에서 내부 신호 콘솔 덤프 =====
    task dump_one_pe;
        input [8*8-1:0] tag;   // "PE0" 등
        input integer lane;    // 0..3
        begin
            $display("---- %s (lane=%0d) phase=%0d  oc_now=%0d  r=%0d c=%0d ----",
                     tag, lane, dut.phase,
                     (lane==0)?dut.oc0_now : (lane==1)?dut.oc1_now : (lane==2)?dut.oc2_now : dut.oc3_now,
                     cur_r, cur_c);

            // 입력/가중치/곱/합: conv3x3_kernel 내부 신호 접근
            $display("a = [%0d %0d %0d | %0d %0d %0d | %0d %0d %0d]",
              (lane==0)?dut.PE0.a00 : (lane==1)?dut.PE1.a00 : (lane==2)?dut.PE2.a00 : dut.PE3.a00,
              (lane==0)?dut.PE0.a01 : (lane==1)?dut.PE1.a01 : (lane==2)?dut.PE2.a01 : dut.PE3.a01,
              (lane==0)?dut.PE0.a02 : (lane==1)?dut.PE1.a02 : (lane==2)?dut.PE2.a02 : dut.PE3.a02,
              (lane==0)?dut.PE0.a10 : (lane==1)?dut.PE1.a10 : (lane==2)?dut.PE2.a10 : dut.PE3.a10,
              (lane==0)?dut.PE0.a11 : (lane==1)?dut.PE1.a11 : (lane==2)?dut.PE2.a11 : dut.PE3.a11,
              (lane==0)?dut.PE0.a12 : (lane==1)?dut.PE1.a12 : (lane==2)?dut.PE2.a12 : dut.PE3.a12,
              (lane==0)?dut.PE0.a20 : (lane==1)?dut.PE1.a20 : (lane==2)?dut.PE2.a20 : dut.PE3.a20,
              (lane==0)?dut.PE0.a21 : (lane==1)?dut.PE1.a21 : (lane==2)?dut.PE2.a21 : dut.PE3.a21,
              (lane==0)?dut.PE0.a22 : (lane==1)?dut.PE1.a22 : (lane==2)?dut.PE2.a22 : dut.PE3.a22);

            $display("w = [%0d %0d %0d | %0d %0d %0d | %0d %0d %0d]  bias=%0d",
              (lane==0)?dut.PE0.w00 : (lane==1)?dut.PE1.w00 : (lane==2)?dut.PE2.w00 : dut.PE3.w00,
              (lane==0)?dut.PE0.w01 : (lane==1)?dut.PE1.w01 : (lane==2)?dut.PE2.w01 : dut.PE3.w01,
              (lane==0)?dut.PE0.w02 : (lane==1)?dut.PE1.w02 : (lane==2)?dut.PE2.w02 : dut.PE3.w02,
              (lane==0)?dut.PE0.w10 : (lane==1)?dut.PE1.w10 : (lane==2)?dut.PE2.w10 : dut.PE3.w10,
              (lane==0)?dut.PE0.w11 : (lane==1)?dut.PE1.w11 : (lane==2)?dut.PE2.w11 : dut.PE3.w11,
              (lane==0)?dut.PE0.w12 : (lane==1)?dut.PE1.w12 : (lane==2)?dut.PE2.w12 : dut.PE3.w12,
              (lane==0)?dut.PE0.w20 : (lane==1)?dut.PE1.w20 : (lane==2)?dut.PE2.w20 : dut.PE3.w20,
              (lane==0)?dut.PE0.w21 : (lane==1)?dut.PE1.w21 : (lane==2)?dut.PE2.w21 : dut.PE3.w21,
              (lane==0)?dut.PE0.w22 : (lane==1)?dut.PE1.w22 : (lane==2)?dut.PE2.w22 : dut.PE3.w22,
              (lane==0)?dut.PE0.conv_bias : (lane==1)?dut.PE1.conv_bias : (lane==2)?dut.PE2.conv_bias : dut.PE3.conv_bias);

            $display("p = [%0d %0d %0d | %0d %0d %0d | %0d %0d %0d]",
              (lane==0)?dut.PE0.p00 : (lane==1)?dut.PE1.p00 : (lane==2)?dut.PE2.p00 : dut.PE3.p00,
              (lane==0)?dut.PE0.p01 : (lane==1)?dut.PE1.p01 : (lane==2)?dut.PE2.p01 : dut.PE3.p01,
              (lane==0)?dut.PE0.p02 : (lane==1)?dut.PE1.p02 : (lane==2)?dut.PE2.p02 : dut.PE3.p02,
              (lane==0)?dut.PE0.p10 : (lane==1)?dut.PE1.p10 : (lane==2)?dut.PE2.p10 : dut.PE3.p10,
              (lane==0)?dut.PE0.p11 : (lane==1)?dut.PE1.p11 : (lane==2)?dut.PE2.p11 : dut.PE3.p11,
              (lane==0)?dut.PE0.p12 : (lane==1)?dut.PE1.p12 : (lane==2)?dut.PE2.p12 : dut.PE3.p12,
              (lane==0)?dut.PE0.p20 : (lane==1)?dut.PE1.p20 : (lane==2)?dut.PE2.p20 : dut.PE3.p20,
              (lane==0)?dut.PE0.p21 : (lane==1)?dut.PE1.p21 : (lane==2)?dut.PE2.p21 : dut.PE3.p21,
              (lane==0)?dut.PE0.p22 : (lane==1)?dut.PE1.p22 : (lane==2)?dut.PE2.p22 : dut.PE3.p22);

            $display("sum_products=%0d  sum_with_bias=%0d  oData=%0d  oValid=%b",
              (lane==0)?dut.PE0.sum_products : (lane==1)?dut.PE1.sum_products : (lane==2)?dut.PE2.sum_products : dut.PE3.sum_products,
              (lane==0)?dut.PE0.sum_with_bias: (lane==1)?dut.PE1.sum_with_bias: (lane==2)?dut.PE2.sum_with_bias: dut.PE3.sum_with_bias,
              (lane==0)?oData0 : (lane==1)?oData1 : (lane==2)?oData2 : oData3,
              (lane==0)?oValid4[0] : (lane==1)?oValid4[1] : (lane==2)?oValid4[2] : oValid4[3]);
        end
    endtask

    always @(posedge iClk) if (dbg_en && iInValid) begin
        if ((cur_r==dbg_r_match) && (cur_c==dbg_c_match) && (dut.phase==dbg_phase)) begin
            if (dbg_lane_m[0]) dump_one_pe("PE0", 0);
            if (dbg_lane_m[1]) dump_one_pe("PE1", 1);
            if (dbg_lane_m[2]) dump_one_pe("PE2", 2);
            if (dbg_lane_m[3]) dump_one_pe("PE3", 3);
        end
    end

    // ===== 이미지/가중치 로드 =====
    initial begin
        $readmemh("mnist_0.mem", img);  // 784 lines, 8-bit two's complement hex
        $readmemh("conv_w.mem",  w_all); // 144 lines
        $readmemh("conv_b.mem",  b_all); // 16 lines
    end

    // ===== 비교 출력(지연된 기대값 사용) =====
    task print_compare_with_expected;
        input integer lane;            // 0..3
        input integer oc;              // phase*4 + lane
        input integer r, c;            // (LAT 지연된) 윈도우 좌상단
        input signed [ACCW-1:0] expected_delayed;
        input signed [ACCW-1:0] actual;
        reg signed [WI-1:0] a[0:8];
        begin
            a[0]=img[(r+0)*IMG_W + (c+0)];
            a[1]=img[(r+0)*IMG_W + (c+1)];
            a[2]=img[(r+0)*IMG_W + (c+2)];
            a[3]=img[(r+1)*IMG_W + (c+0)];
            a[4]=img[(r+1)*IMG_W + (c+1)];
            a[5]=img[(r+1)*IMG_W + (c+2)];
            a[6]=img[(r+2)*IMG_W + (c+0)];
            a[7]=img[(r+2)*IMG_W + (c+1)];
            a[8]=img[(r+2)*IMG_W + (c+2)];

            $display("OC=%0d lane=%0d  r=%0d c=%0d  bias=%0d",
                     oc, lane, r, c, b_all[oc]);
            $display("  in(3x3) = [[%0d %0d %0d] [%0d %0d %0d] [%0d %0d %0d]]",
                     a[0],a[1],a[2], a[3],a[4],a[5], a[6],a[7],a[8]);
            $display("  expected=%0d  actual=%0d %s",
                     expected_delayed, actual,
                     (expected_delayed===actual) ? "(OK)" : "<-- MISMATCH");
        end
    endtask

    // ===== 메인 시나리오 =====
    integer ph, r, c;
    initial begin
        @(posedge iRsn);
        @(posedge iClk);

        $display("\n[TB] 28x28 → 26x26 슬라이딩, per-map phase 0..3 (LAT=%0d) 시작\n", LAT);

        for (ph=0; ph<4; ph=ph+1) begin
            // 26x26 모든 윈도우 스트리밍
            for (r=0; r<OH; r=r+1) begin
                for (c=0; c<OW; c=c+1) begin
                    // 입력과 동일 사이클에 golden 계산
                    drive_window(r,c);
                    iInValid   = 1'b1;
                    exp0_now   = dot9_bias(ph*4+0, r, c);
                    exp1_now   = dot9_bias(ph*4+1, r, c);
                    exp2_now   = dot9_bias(ph*4+2, r, c);
                    exp3_now   = dot9_bias(ph*4+3, r, c);

                    // 다음 클럭에서 FIFO로 밀기
                    @(posedge iClk);
                    push_expected_and_coords(r, c);

                    // 출력 유효 시, LAT 지연된 (r,c)/expected로 비교
                    if (oValid4[0]) print_compare_with_expected(0, ph*4+0, r_d[LAT], c_d[LAT], exp0_fifo[LAT], oData0);
                    if (oValid4[1]) print_compare_with_expected(1, ph*4+1, r_d[LAT], c_d[LAT], exp1_fifo[LAT], oData1);
                    if (oValid4[2]) print_compare_with_expected(2, ph*4+2, r_d[LAT], c_d[LAT], exp2_fifo[LAT], oData2);
                    if (oValid4[3]) print_compare_with_expected(3, ph*4+3, r_d[LAT], c_d[LAT], exp3_fifo[LAT], oData3);
                end
            end

            // 맵 종료: phase 전환 트리거 (iInValid 낮춘 뒤 iMapDone 펄스)
            iInValid = 1'b0; @(posedge iClk);
            iMapDone = 1'b1; @(posedge iClk);
            iMapDone = 1'b0;

            // tail flush (LAT+여유)
            repeat(LAT+4) begin
                @(posedge iClk);
                if (oValid4[0]) print_compare_with_expected(0, ph*4+0, r_d[LAT], c_d[LAT], exp0_fifo[LAT], oData0);
                if (oValid4[1]) print_compare_with_expected(1, ph*4+1, r_d[LAT], c_d[LAT], exp1_fifo[LAT], oData1);
                if (oValid4[2]) print_compare_with_expected(2, ph*4+2, r_d[LAT], c_d[LAT], exp2_fifo[LAT], oData2);
                if (oValid4[3]) print_compare_with_expected(3, ph*4+3, r_d[LAT], c_d[LAT], exp3_fifo[LAT], oData3);
            end

            repeat(3) @(posedge iClk);
        end

        $display("\n[TB] DONE.");
        $finish;
    end

endmodule

