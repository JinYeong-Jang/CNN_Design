// Pmod SSD (Common Cathode): AA..AG = a..g (ON=1), C = digit select (1bit)
// 목표: oClass=0 => "00", oClass=1 => "01"
module seg7_0or1 (
  input  wire       clk,     // 100 MHz
  input  wire       rstn,    // active-low
  input  wire       iClass,  // 0 or 1
  output reg  [6:0] oSeg,    // {a,b,c,d,e,f,g}  (CC: ON=1)
  output reg        oC       // 자리 선택 1비트 (한 자리씩 선택)
);
  // 약 1kHz로 자리 전환 (100_000 주기)
  localparam integer DIV = 100_000;
  reg [16:0] cnt;   // 충분한 비트수
  reg        sel;   // 0이면 왼쪽, 1이면 오른쪽 (배치에 따라 반대일 수 있음)

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      cnt <= 0; sel <= 0;
    end else begin
      cnt <= cnt + 1;
      if (cnt == DIV-1) begin
        cnt <= 0;
        sel <= ~sel;   // 자리 토글
      end
    end
  end

  // 액티브-하이(ON=1) 기준 패턴
  localparam [6:0] ZERO = 7'b1111110; // a,b,c,d,e,f=1, g=0
  localparam [6:0] ONE  = 7'b0110000; // b,c=1

  always @* begin
    if (iClass == 1'b0) begin
      // "00": 두 자리 모두 0 (멀티플렉싱 도는 동안 항상 ZERO)
      oSeg = ZERO;
      oC   = sel;      // sel=0일 때 한 자리, sel=1일 때 다른 자리
    end else begin
      // "01": 왼쪽=0, 오른쪽=1
      if (sel == 1'b0) begin
        oSeg = ZERO;   // 왼쪽
        oC   = 1'b0;
      end else begin
        oSeg = ONE;    // 오른쪽
        oC   = 1'b1;
      end
    end
  end
endmodule
