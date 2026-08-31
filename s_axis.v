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
    output wire [VIDEOC_W -1 : 0] red, green, blue,
    output reg [9 : 0] sx_o, sy_o,

    // sync signals
    output wire hsync_o, vsync_o, 
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

wire eol = (sx == LINE) ? 1'b1 : 1'b0;
wire eof = (sy == FRAME) ? 1'b1 : 1'b0;
wire de  = ((sx < HACTIVE) && (sy < VACTIVE)) ? 1'b1 : 1'b0;

assign hsync_o = (sx >= HSYNC_S && sx < HSYNC_E) ? 1'b0 : 1'b1;
assign vsync_o = (sy >= VSYNC_S && sy < VSYNC_E) ? 1'b0 : 1'b1;

wire we = (s_axis_tvalid & s_axis_tlast);

// ============ Test colors ===============================================================================================
//assign red   = ((sy < 160) || (sy >= 320 && sy < VACTIVE)) ? 8'd50 : {VIDEOC_W{1'b1}};
//assign green = ((sy < 160) || (sy >= 320 && sy < VACTIVE)) ? 8'd50 : {VIDEOC_W{1'b1}};
//assign blue  = 8'd230; //((sy < 160) || (sy >= 320 && sy < VACTIVE)) ? {VIDEOC_W{1'b1}} : {VIDEOC_W{1'b1}}

reg xdir, ydir;
reg [HCNT_W-1 : 0] xpos, ypos; // square (10x10) pos
reg [7:0] cnt;
wire [1:0] color_cnt = cnt[7:6];

localparam integer SQUARE_SIZE = 50;

wire square = (de && (sx >= xpos) && (sx < xpos + SQUARE_SIZE) && (sy >= ypos) && (sy < ypos + SQUARE_SIZE));

assign red   = square ? (color_cnt == 2'b00) ? {VIDEOC_W{1'b1}} : (color_cnt == 2'b01) ? {VIDEOC_W{1'b1}} : (color_cnt == 2'b10) ? {VIDEOC_W{1'b0}} : {VIDEOC_W{1'b0}} : 8'd50;
assign green = square ? (color_cnt == 2'b00) ? {VIDEOC_W{1'b1}} : (color_cnt == 2'b01) ? {VIDEOC_W{1'b0}} : (color_cnt == 2'b10) ? {VIDEOC_W{1'b1}} : {VIDEOC_W{1'b0}} : 8'd50;
assign blue  = square ? (color_cnt == 2'b00) ? {VIDEOC_W{1'b1}} : (color_cnt == 2'b01) ? {VIDEOC_W{1'b0}} : (color_cnt == 2'b10) ? {VIDEOC_W{1'b0}} : {VIDEOC_W{1'b1}} : 8'd230;

always @(posedge aclk) begin
    if(!arst_n) begin
        xpos <= {HCNT_W{1'b0}};
        ypos <= {HCNT_W{1'b0}};
        xdir <= 1'b0;
        ydir <= 1'b0;
        cnt <= 8'b00000000;
    end else begin
        if (sx == HACTIVE-1 && sy == VACTIVE-1) begin
            cnt <= cnt + 1'b1;
            if(!xdir) begin
                xpos <= xpos + 1'b1;
                if(xpos >= HACTIVE - SQUARE_SIZE) begin
                    xdir <= 1'b1;
                    xpos <= xpos - 1'b1;
                end
            end else begin
                xpos <= xpos - 1'b1;
                if (xpos == 0) begin
                    xdir <= 1'b0;
                    xpos <= xpos + 1'b1;
                end
            end

            if(!ydir) begin
                ypos <= ypos + 1'b1;
                if(ypos >= VACTIVE - SQUARE_SIZE) begin
                    ydir <= 1'b1;
                    ypos <= ypos - 1'b1;
                end
            end else begin
                ypos <= ypos - 1'b1;
                if(ypos == 0) begin
                    ydir <= 1'b0;
                    ypos <= ypos + 1'b1;
                end 
            end
        end
    end    
end
// =============================================================================================================================

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

        sx <= (eol) ? {HCNT_W{1'b0}} : sx + 1'b1;
        if (eol)
            sy <= (eof) ? {VCNT_W{1'b0}} : sy + 1'b1;     
    end
end

endmodule
