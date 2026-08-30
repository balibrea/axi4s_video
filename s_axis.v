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

// timing parameters
// Horizontal timing parameters
localparam integer HACTIVE = 640;       // Horizontal active area
localparam integer HFRONT_PORCH = 16;
localparam integer HBACK_PORCH = 48;
localparam integer HSYNC_W = 96;
localparam integer LINE = HACTIVE + HFRONT_PORCH + HBACK_PORCH + HSYNC_W;
localparam integer HSYNC_S = HACTIVE + HFRONT_PORCH; // Start of hsync
localparam integer HSYNC_E = HSYNC_S + HSYNC_W;         // End of hsync

// Vertical timing parameters
localparam integer VACTIVE = 480;      // Vertical active area
localparam integer VFRONT_PORCH = 10;
localparam integer VBACK_PORCH = 33;
localparam integer VSYNC_W = 2;
localparam integer FRAME = VACTIVE + VFRONT_PORCH + VBACK_PORCH + VSYNC_W;
localparam integer VSYNC_S = VACTIVE + VFRONT_PORCH;
localparam integer VSYNC_E = VSYNC_S + VSYNC_W;

// Counters width
localparam integer HCNT_WIDTH = $clog2(LINE);
localparam integer VCNT_WIDTH = $clog2(FRAME);

// Video fifo from master
reg [TDATA_WIDTH - 1 : 0] fifo [0 : (VACTIVE * HACTIVE * FIFO_DEPT)];

// VGA free running counters
reg [HCNT_WIDTH-1:0] x_count;
reg [VCNT_WIDTH-1:0] y_count;

wire eol = (x_count == LINE-1); // End of line
wire eof = (y_count == FRAME-1); // End of frame

// sync signals
wire hsync = (x_count >= HSYNC_S && x_count < HSYNC_E) ? 1'b0 : 1'b1;
wire vsync = (y_count >= VSYNC_S && y_count < VSYNC_E) ? 1'b0 : 1'b1;

// Active video data area
wire active_x = (x_count >= HBACK_PORCH && x_count < (HBACK_PORCH + HACTIVE));
wire active_y = (y_count >= VBACK_PORCH && y_count > (VBACK_PORCH + VACTIVE));
wire de    = (active_x && active_y);

assign s_axis_tready = de;

wire valid = s_axis_tvalid && s_axis_tready; // valid data transfer

// VGA Scan (has to be free running)
always @(posedge aclk) begin
    if (!arst_n) begin
        x_count <= {HCNT_WIDTH{1'b0}};
        y_count <= {VCNT_WIDTH{1'b0}};
    end else begin
        x_count <= (x_count == LINE - 1) ? 0 : x_count + 1'b1;
        if (eol) begin
            y_count <= (eof) ? {VCNT_WIDTH{1'b0}} : y_count + 1'b1;
        end
    end    
end

// AXIS stream registers


endmodule