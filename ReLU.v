/*******************************************************************
  - Project          : CNN design
  - File name        : ReLU.v
  - Description      : ReLU (Rectified Linear Unit) implementation
  - Owner            : Minji.Jeong
  - Revision history : 1) 2025.08.14 : Initial release
*******************************************************************/
`timescale 1ns / 1ps

module ReLU #(
    parameter In_d_W=32  //input data width
)(
    input clk, 
    input rst, 
    input en, 
    input signed [In_d_W-1:0] A,
    output reg  signed [In_d_W-1:0] Y,
    output reg  valid
 );

    always@(posedge clk or posedge rst)
    begin
        if (rst)
          begin 
            Y<=0; 
            valid<=0;  
        end
        else if (en) begin
            Y<=(A<0) ? 0 : A; 
            valid<=1;
        end
        else begin
            valid<=0;
        end
    end

endmodule

