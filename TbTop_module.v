`timescale 1ns/10ps

module Tbtop_module;

// ----------------------------
// Parameters (DUT와 동일하게)
// ----------------------------
localparam integer IMG_W      = 28;
localparam integer PIX_W      = 8;
localparam integer WI         = 8;
localparam integer BW         = 32;
localparam integer ACCW       = 32;
localparam integer In_d_W     = 32;
localparam integer W          = 26;         // 3x3 stride=1 컨볼브 후 맵 가로 (예: 28->26)
localparam integer FEAT_W_FC  = In_d_W;
localparam integer WGT_W_FC   = 8;
localparam integer ACC_W_FC   = (FEAT_W_FC + WGT_W_FC) + 12;
localparam integer NPIX       = IMG_W*IMG_W;
localparam integer FRAME_GAP = 2; // 원하는 만큼 변경 가능(>=1)


reg                                 iClk;
reg                                 iRsn;

reg  [PIX_W-1:0]        iPixelIn;     // !!! top_module에서 [PIX_W-1:0]로 수정 필요
reg                                 iPixelValid;

wire                                oLogitValid;
wire  signed [((In_d_W+8)+12)-1:0]  oLogit;
wire                                oClass;


  top_module #(
    .IMG_W(IMG_W), .PIX_W(PIX_W), .WI(WI), .BW(BW), .ACCW(ACCW),
    .In_d_W(In_d_W), .W(W), .FEAT_W_FC(FEAT_W_FC), .WGT_W_FC(WGT_W_FC), .ACC_W_FC(ACC_W_FC)
  ) A_CnnTOP(
    .iClk           (iClk),
    .iRsn           (iRsn),
    .iPixelIn       (iPixelIn),
    .iPixelValid    (iPixelValid),
    .oLogitValid    (oLogitValid),
    .oLogit         (oLogit),
    .oClass         (oClass)
);


// ----------------------------
// Clock Gen (100 MHz -> 10 ns period)
// ----------------------------
initial iClk = 1'b0;
always  #5 iClk = ~iClk;


reg [PIX_W-1:0] img_mem [0:NPIX-1];
integer r, c;


initial begin
// 고정 파일명으로 읽기 (string/plusargs 없이)
$display("[TB] Using image file: mnist_0.mem");
$readmemh("mnist_0.mem", img_mem);

// 간단한 헤더 출력 (상위 8×8 프리뷰)
$display("[TB] Preview (8x8) first values:");
for (r = 0; r < 8; r = r + 1) begin
    $write("row %0d :", r);
    for (c = 0; c < 8; c = c + 1) begin
    $write(" %02x", img_mem[r*IMG_W + c]);
    end
    $write("\n");
end
end

  // ----------------------------
  // Drive tasks
  // ----------------------------
  // 28x28 프레임 전송 + 프레임 사이 공백(FRAME_GAP클럭) 삽입
  task send_frame_from_mem_gap(input integer gap_cycles);
    integer idx;
    begin
      // 프레임 스트림: 매 클럭 한 픽셀, valid=1 유지
      for (idx = 0; idx < NPIX; idx = idx + 1) begin
        @(posedge iClk);
        iPixelIn    <= img_mem[idx];
        iPixelValid <= 1'b1;
      end

      // 프레임 종료 직후: valid 낮추고 gap_cycles 만큼 공백 유지
      @(posedge iClk);
      iPixelValid <= 1'b0;

      // gap_cycles가 2라면, 지금 1클럭 쉬었으니 1클럭 더 쉼
      if (gap_cycles > 1) begin
        repeat (gap_cycles-1) @(posedge iClk);
      end
    end
  endtask

  // ----------------------------
  // Monitor & Finish
  // ----------------------------
  integer logit_cnt;
  initial logit_cnt = 0;

  always @(posedge iClk) begin
    if (oLogitValid) begin
      logit_cnt <= logit_cnt + 1;
      $display("[%0t] oLogitValid=1  oClass=%0d  oLogit=%0d", $time, oClass, oLogit);
    end
  end

  initial begin


    // 초기값
    iRsn        = 1'b0; // active-low reset assert
    iPixelIn    = 1'b0;
    iPixelValid = 1'b0;

    // 리셋 유지
    repeat (5) @(posedge iClk);
    iRsn = 1'b1; // deassert

    // 안정화
    repeat (5) @(posedge iClk);

    // 프레임 여러 장 전송(phase 회전/FC 파이프라인 관찰)
    send_frame_from_mem_gap(FRAME_GAP);
    send_frame_from_mem_gap(FRAME_GAP);
    send_frame_from_mem_gap(FRAME_GAP);
    send_frame_from_mem_gap(FRAME_GAP);
    // send_frame_from_mem();

    // 후행 여유
    repeat (2000) @(posedge iClk);

    $display("[TB] Simulation done. oLogitValid observed %0d times.", logit_cnt);
    $finish;
  end

endmodule
