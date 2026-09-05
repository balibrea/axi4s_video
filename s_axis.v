//! @author: Yosel Balibrea Lastre
//! @title: s_axis.v
//! @date: 2026-08-28
//! @brief: AXI4-Stream Slave Interface Module test

`default_nettype none

module s_axis #(
    parameter TDATA_WIDTH = 32,
    parameter VIDEOC_W = 8
)(
    // VGA signals
    // outputs RGB
    output reg [VIDEOC_W -1 : 0] red, green, blue,
    output reg [9 : 0] sx_o, sy_o,

    // sync signals
    output reg hsync_o, vsync_o, 
    output reg de_o,
    
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

localparam integer HSYNC_S = HACTIVE + HFP;
localparam integer HSYNC_E = HSYNC_S + HSW;
localparam integer VSYNC_S = VACTIVE + VFP;
localparam integer VSYNC_E = VSYNC_S + VSW;
localparam integer LINE    = HACTIVE + HFP + HBP + HSW; // line width
localparam integer FRAME   = VACTIVE + VFP + VBP + VSW; // frame width

localparam integer HCNT_W = $clog2(LINE);
localparam integer VCNT_W = $clog2(FRAME);

reg [HCNT_W - 1 : 0] sx = {HCNT_W{1'b0}};
reg [VCNT_W - 1 : 0] sy = {VCNT_W{1'b0}};

wire eol = (sx == LINE-1) ? 1'b1 : 1'b0;
wire eof = (sy == FRAME-1) ? 1'b1 : 1'b0;
wire de  = ((sx < HACTIVE) && (sy < VACTIVE)) ? 1'b1 : 1'b0;

wire hsync = (sx >= HSYNC_S && sx < HSYNC_E) ? 1'b0 : 1'b1;
wire vsync = (sy >= VSYNC_S && sy < VSYNC_E) ? 1'b0 : 1'b1;

wire we = (s_axis_tvalid & s_axis_tlast);
wire valid = (s_axis_tvalid & s_axis_tready);


// AXIS Registers
assign s_axis_tready = de;

always @(posedge aclk) begin
    if (!arst_n) begin
        red <= {VIDEOC_W{1'b0}};
        green <= {VIDEOC_W{1'b0}};
        blue <= {VIDEOC_W{1'b0}};
        
    end else begin
        if (valid) begin
            red <= s_axis_tdata[VIDEOC_W*3-1:VIDEOC_W*2];
            green <= s_axis_tdata[VIDEOC_W*2-1:VIDEOC_W];
            blue <= s_axis_tdata[VIDEOC_W-1:0];
        end
    end
    
end


// VGA free running counters
always @(posedge aclk) begin
    if(!arst_n) begin
        sx <= {HCNT_W{1'b0}};
        sy <= {VCNT_W{1'b0}};
        sx_o <= {HCNT_W{1'b0}};
        sy_o <= {VCNT_W{1'b0}};
        de_o <= 1'b0;
    end else begin
        sx_o <= sx;
        sy_o <= sy;
        de_o <= de;
        hsync_o <= hsync;
        vsync_o <= vsync;

        sx <= (eol) ? {HCNT_W{1'b0}} : sx + 1'b1;
        if (eol)
            sy <= (eof) ? {VCNT_W{1'b0}} : sy + 1'b1;     
    end
end

endmodule
