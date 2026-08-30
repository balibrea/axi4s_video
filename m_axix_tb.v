//! @author Yosel Balibrea Lastre
//! @title: m_axis_tb.v
//! @date: 2026-08-28
//! @brief: AXI4-Stream Master Interface Module testbench

`timescale 1ns/1ps

module m_axis_tb; 

    localparam FIFO_DEPT = 2;
    localparam TDATA_WIDTH = 32;
    localparam V_RES = 640;
    localparam H_RES = 480;
    localparam VIDEOC_W = 8;

    wire [TDATA_WIDTH-1:0] s_axis_tdata;
    wire s_axis_tvalid;
    wire s_axis_tlast;
    wire s_axis_tuser;
    wire s_axis_tready;

    wire [VIDEOC_W - 1 : 0] red, green, blue;
    wire hsync, vsync, de;

    // generate the clock and reset signals
    reg aclk;
    reg arst_n;

    // 100MHZ clock and active low reset
    initial begin
        aclk = 0;
        arst_n = 0;
        #10 arst_n = 1;
        forever #5 aclk = ~aclk;
    end

    //m_axis #(
    //    .TDATA_WIDTH(TDATA_WIDTH)
    //) dut (
    //    .aclk(aclk),
    //    .arst_n(arst_n),
    //    .m_axis_tdata(m_axis_tdata),
    //    .m_axis_tvalid(m_axis_tvalid),
    //    .m_axis_tlast(m_axis_tlast),
    //    .m_axis_tuser(m_axis_tuser),
    //    .m_axis_tready(m_axis_tready)
    //);


    s_axis # (
        .TDATA_WIDTH(TDATA_WIDTH),
        .VIDEOC_W(VIDEOC_W),
        .FIFO_DEPT(FIFO_DEPT)
    )
    s_axis_inst (
        .red(red),
        .gree(gree),
        .blue(blue),
        .hsync_o(hsync),
        .vsync_o(vsync),
        .de_o(de),
        .aclk(aclk),
        .arst_n(arst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser)
    );

    // Main test
    initial begin
        $dumpfile("wave.fst");
        $dumpvars(0, m_axis_tb);

        #100;
        $finish;
    end

endmodule