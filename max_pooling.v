/*******************************************************************
  - Project          : CNN design
  - File name        : MaxPooling.v
  - Description      : MaxPooling implementation
  - Owner            : Minji.Jeong
  - Revision history : 1) 2025.08.14 : Initial release
*******************************************************************/
`timescale 1ns / 1ps

module max_pooling #(
    parameter In_d_W=8  //input data width
) (
    input clk,
    input rst,
    input en,
    input [In_d_W-1:0] A0,  //4 window pixels
    input [In_d_W-1:0] A1, 
    input [In_d_W-1:0] A2, 
    input [In_d_W-1:0] A3, 
    output reg [In_d_W-1:0] Y,  //output max
    output reg valid
);
    
    always@(posedge clk or posedge rst)
    begin
        if (rst)
          begin 
            Y<=0; 
            valid<=0;  
        end
        else if (en) begin
            Y<=(A0 > A1 ? A0 : A1) > (A2 > A3 ? A2 : A3) ?
               (A0 > A1 ? A0 : A1) : (A2 > A3 ? A2 : A3); 
            valid<=1;
        end
        else begin
            valid<=0;
        end
    end

endmodule