`define IMG_FILE "mnist_0_0.mem"

module pixel_feeder #(
  parameter integer NPIX = 784
)(
  input  wire clk,
  input  wire rstn,
  output reg  [7:0] pixel,
  output reg        valid
);
  reg [7:0] mem [0:NPIX-1];
  initial $readmemh(`IMG_FILE, mem);

  reg [9:0] addr;
  always @(posedge clk) begin
    if (!rstn) begin
      addr<=0; valid<=0; pixel<=0;
    end else begin
      valid <= 1'b1;
      pixel <= mem[addr];
      addr  <= (addr==NPIX-1) ? 10'd0 : addr+10'd1;
    end
  end
endmodule