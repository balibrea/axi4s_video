//! @author: Yosel Balibrea Lastre
//! @title: s_axis.v
//! @date: 2026-08-28
//! @brief: AXI4-Stream Slave Interface Module test

module s_axis #(
    parameter TDATA_WIDTH = 32,
    parameter VIDEOC_W = 8,
    parameter FIFO_DEPT = 2  // 2 frames
)(
    // VGA signals
    // outputs RGB
    output reg [VIDEOC_W -1 : 0] red, gree, blue,

    // sync signals
    output wire hsync_o, vsync_o, de_o,
    
    // AXIS signals
    input wire aclk,
    input wire arst_n,

    input wire [TDATA_WIDTH-1:0] s_axis_tdata,
    input wire  s_axis_tvalid,      //! Data valid
    output wire s_axis_tready,     //! Slave ready

    input wire s_axis_tlast,       //! End of line (only for video stream)
    input wire s_axis_tuser        //! Start of frame (only for video stream)  
);

localparam integer HACTIVE = 640, HFP = 16, HSW = 96, HBP = 48;
localparam integer VACTIVE = 480, VFP = 10, VSW =  2, VBP = 33;


endmodule