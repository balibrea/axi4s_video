
module top_tb;

  // Parameters
  localparam  VIDEOC_W = 8;
  localparam  TDATA_WIDTH = 32;

  //Ports
  reg  aclk;
  reg  arst_n;
  wire [VIDEOC_W-1 : 0] red;
  wire [VIDEOC_W-1 : 0] green;
  wire [VIDEOC_W-1 : 0] blue;
  wire [9 : 0] sx_o;
  wire [9 : 0] sy_o;
  wire de_o;
  wire hsync_o;
  wire vsync_o;

  top # (
    .VIDEOC_W(VIDEOC_W),
    .TDATA_WIDTH(TDATA_WIDTH)
  )
  top_inst (
    .aclk(aclk),
    .arst_n(arst_n),
    .red(red),
    .green(green),
    .blue(blue),
    .sx_o(sx_o),
    .sy_o(sy_o),
    .de_o(de_o),
    .hsync_o(hsync_o),
    .vsync_o(vsync_o)
  );

always #5  aclk = ! aclk ;

initial begin
    $dumpfile("top_tb.vcd");
    $dumpvars(0, top_tb);

    aclk = 1'b0;
    arst_n = 1'b0;
    #100;
    arst_n = 1'b1;
    #1000000;
    $finish;
end

endmodule
