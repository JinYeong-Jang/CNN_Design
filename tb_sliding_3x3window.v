`timescale 1ns/1ps

module tb_sliding_3x3window;

  // --- 파라미터 ---
  localparam IMG_W     = 28;
  localparam PIX_W     = 8;
  localparam FRAME_SZ  = IMG_W*IMG_W; // 784

  // --- DUT I/O ---
  reg                  iClk;
  reg                  iRsn;          // active-low reset
  reg  [PIX_W-1:0]     iPixelIn;
  reg                  iPixelValid;
  wire [3*PIX_W-1:0]   oWindowOutRow1;
  wire [3*PIX_W-1:0]   oWindowOutRow2;
  wire [3*PIX_W-1:0]   oWindowOutRow3;

  sliding_3x3window #(
    .IMG_W(IMG_W),
    .PIX_W(PIX_W)
  ) dut (
    .iClk(iClk),
    .iRsn(iRsn),
    .iPixelIn(iPixelIn),
    .iPixelValid(iPixelValid),
    .oWindowOutRow1(oWindowOutRow1),
    .oWindowOutRow2(oWindowOutRow2),
    .oWindowOutRow3(oWindowOutRow3)
  );

  // --- 클럭 ---
  initial iClk = 1'b0;
  always  #5 iClk = ~iClk;   // 100 MHz

  // --- TB 내부 메모리 & 표기용 신호들 ---
  reg [7:0] img [0:FRAME_SZ-1];   // mem에서 읽은 이미지

  integer i, k;
  integer row_idx, col_idx;        // 현재 스트리밍 위치(행/열)
  integer frame_no;                // 0,1 ...

  // 파형에서 보기 쉽게 내보내는 기대 윈도우(24비트씩)
  reg [23:0] exp_row1, exp_row2, exp_row3;
  reg        exp_window_valid;

  // 24비트 묶음을 바이트로도 바로 보려면 아래 wire 들을 파형에 추가해서 보면 편함
  wire [7:0] exp_r1_p0 = exp_row1[7:0];
  wire [7:0] exp_r1_p1 = exp_row1[15:8];
  wire [7:0] exp_r1_p2 = exp_row1[23:16];

  wire [7:0] exp_r2_p0 = exp_row2[7:0];
  wire [7:0] exp_r2_p1 = exp_row2[15:8];
  wire [7:0] exp_r2_p2 = exp_row2[23:16];

  wire [7:0] exp_r3_p0 = exp_row3[7:0];
  wire [7:0] exp_r3_p1 = exp_row3[15:8];
  wire [7:0] exp_r3_p2 = exp_row3[23:16];

  // 디버그용: 현재 위치와 밸리드도 파형에서 보자
  // (ModelSim에서 add wave 할 때 같이 추가)
  // row_idx, col_idx, frame_no, exp_window_valid, oWindowOutRow1/2/3, iPixelIn, iPixelValid

  // --- 태스크: 리셋 ---
  task do_reset;
    begin
      iRsn        = 1'b0;  // assert reset (active-low)
      iPixelIn    = {PIX_W{1'b0}};
      iPixelValid = 1'b0;
      row_idx     = 0;
      col_idx     = 0;
      exp_row1    = 24'h0;
      exp_row2    = 24'h0;
      exp_row3    = 24'h0;
      exp_window_valid = 1'b0;

      repeat (5) @(posedge iClk);
      iRsn = 1'b1;         // deassert
      repeat (2) @(posedge iClk);
    end
  endtask

  // --- 태스크: 파일 로드 + 한 프레임 스트리밍 + 기대 윈도우 산출 신호 내보내기 ---
  task stream_image_from_mem(input [1023:0] memfile);
    begin
      $display("[TB] Loading mem file: %0s", memfile);
      $readmemh(memfile, img);

      // 위치 초기화
      row_idx = 0;
      col_idx = 0;

      // 한 프레임 전송
      iPixelValid = 1'b1;
      for (i = 0; i < FRAME_SZ; i = i + 1) begin
        // 입력 데이터 준비 (엣지 전에)
        iPixelIn = img[i];

        // 엣지: DUT 샘플링
        @(posedge iClk);

        // 콤비 경로가 안정되도록 아주 짧은 시간 대기 후 (파형 관찰용)
        #1;

        // 기대 윈도우 유효 여부
        exp_window_valid = (row_idx >= 2) && (col_idx >= 2);

        if (exp_window_valid) begin
          // 윈도우의 3줄을 24비트로 묶어서 내보냄: {x-2, x-1, x}
          exp_row1 = { img[((row_idx-2)*IMG_W) + (col_idx-2)],
                       img[((row_idx-2)*IMG_W) + (col_idx-1)],
                       img[((row_idx-2)*IMG_W) + (col_idx  )] };

          exp_row2 = { img[((row_idx-1)*IMG_W) + (col_idx-2)],
                       img[((row_idx-1)*IMG_W) + (col_idx-1)],
                       img[((row_idx-1)*IMG_W) + (col_idx  )] };

          exp_row3 = { img[((row_idx  )*IMG_W) + (col_idx-2)],
                       img[((row_idx  )*IMG_W) + (col_idx-1)],
                       img[((row_idx  )*IMG_W) + (col_idx  )] };
        end else begin
          exp_row1 = 24'h0;
          exp_row2 = 24'h0;
          exp_row3 = 24'h0;
        end

        // 다음 위치로 진행
        if (col_idx == IMG_W-1) begin
          col_idx = 0;
          row_idx = row_idx + 1;
        end else begin
          col_idx = col_idx + 1;
        end
      end
      iPixelValid = 1'b0;

      // 프레임 후 여유 클럭
      repeat (20) @(posedge iClk);
    end
  endtask

  // --- 메인 시나리오 ---
  initial begin
    frame_no = 0;

    do_reset();

    // 0 이미지
    stream_image_from_mem("mnist_0.mem");
    frame_no = frame_no + 1;

    // 필요시 리셋 (선택)
    // do_reset();

    // 1 이미지
    stream_image_from_mem("mnist_1.mem");
    frame_no = frame_no + 1;

    $display("[TB] Done. %0d frames streamed.", frame_no);
    $stop;
  end

endmodule
