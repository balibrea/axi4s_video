
`default_nettype none

module top #(
    parameter VIDEOC_W = 8,
    parameter TDATA_WIDTH = 32
)(
    input wire aclk,
    input wire arst_n,

    output wire [VIDEOC_W-1 : 0] red, green, blue,
    output wire [9 : 0] sx_o, sy_o,
    output wire de_o,
    output wire hsync_o, vsync_o

);

localparam integer V_RES = 480;
localparam integer H_RES = 640;

wire [TDATA_WIDTH-1 : 0] m_axis_tdata;
wire m_axis_tvalid, m_axis_tready, m_axis_tlast, m_axis_tuser;

// AXIS master
m_axis # (
    .TDATA_WIDTH(TDATA_WIDTH),
    .V_RES(V_RES),
    .H_RES(H_RES)
  )
  m_axis_inst (
    .aclk(aclk),
    .arst_n(arst_n),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tuser(m_axis_tuser)
  );


// AXIS slave
s_axis # (
    .TDATA_WIDTH(TDATA_WIDTH),
    .VIDEOC_W(VIDEOC_W)
  )
  s_axis_inst (
    .red(red),
    .green(green),
    .blue(blue),
    .sx_o(sx_o),
    .sy_o(sy_o),
    .hsync_o(hsync_o),
    .vsync_o(vsync_o),
    .de_o(de_o),
    .aclk(aclk),
    .arst_n(arst_n),
    .s_axis_tdata(m_axis_tdata),
    .s_axis_tvalid(m_axis_tvalid),
    .s_axis_tready(m_axis_tready),
    .s_axis_tlast(m_axis_tlast),
    .s_axis_tuser(m_axis_tuser)
  );

endmodule
