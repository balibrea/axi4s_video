//! @author: Yosel Balibrea Lastre
//! @title: m_axis.v
//! @date: 2026-08-28
//! @brief: AXI4-Stream Master Interface Module test

`default_nettype none

module m_axis #(
    parameter TDATA_WIDTH = 32,
    parameter V_RES = 480,
    parameter H_RES = 640,
    parameter VIDEOC_W = 8
)(
    input wire aclk,
    input wire arst_n,

    output wire [TDATA_WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,      //! Data valid
    input  wire m_axis_tready,      //! Slave ready

    output wire m_axis_tlast,       //! End of line (only for video stream)
    output wire m_axis_tuser        //! Start of frame (only for video stream)  
);

localparam integer HCNT_WIDTH = $clog2(H_RES);
localparam integer VCNT_WIDTH = $clog2(V_RES);
localparam integer PADW = TDATA_WIDTH - VIDEOC_W*3; // Padding width for RGB data

reg [HCNT_WIDTH-1:0] x_count;
reg [VCNT_WIDTH-1:0] y_count;

wire eol = (x_count == H_RES-1); // End of line
wire eof = (y_count == V_RES-1); // End of frame

reg tvalid = 1'b0;
assign m_axis_tvalid = tvalid; // Always valid for this example

// Assert tlast at the end of each line 
assign m_axis_tlast = eol;

// Start of frame (SOF)
assign m_axis_tuser = (x_count == 0 && y_count == 0) ? 1'b1 : 1'b0;

wire valid = tvalid && m_axis_tready; // Valid transfer

// ============================= Video Pattern ======================================
reg xdir, ydir; // Direction of the pixel pattern
reg [HCNT_WIDTH-1:0] xpos;
reg [VCNT_WIDTH-1:0] ypos;

reg [7:0] cnt;
wire [1:0] color_cnt = cnt[7:6];

localparam integer SQUARE_SIZE = 50;

wire square = (x_count >= xpos && x_count < xpos + SQUARE_SIZE && y_count >= ypos && y_count < ypos + SQUARE_SIZE) ? 1'b1 : 1'b0;

wire [7:0] red =   square ? (color_cnt == 2'b00) ? {VIDEOC_W{1'b1}} : (color_cnt == 2'b01) ? {VIDEOC_W{1'b1}} : (color_cnt == 2'b10) ? {VIDEOC_W{1'b0}} : {VIDEOC_W{1'b0}} : 8'd50;
wire [7:0] green = square ? (color_cnt == 2'b00) ? {VIDEOC_W{1'b1}} : (color_cnt == 2'b01) ? {VIDEOC_W{1'b0}} : (color_cnt == 2'b10) ? {VIDEOC_W{1'b1}} : {VIDEOC_W{1'b0}} : 8'd50;
wire [7:0] blue =  square ? (color_cnt == 2'b00) ? {VIDEOC_W{1'b1}} : (color_cnt == 2'b01) ? {VIDEOC_W{1'b0}} : (color_cnt == 2'b10) ? {VIDEOC_W{1'b0}} : {VIDEOC_W{1'b1}} : 8'd230;

always @(posedge aclk) begin
    if (!arst_n) begin
        xpos <= {HCNT_WIDTH{1'b0}};
        ypos <= {VCNT_WIDTH{1'b0}};
        xdir <= 1'b0;
        ydir <= 1'b0;
        cnt <= 8'b00000000;
    end else if (valid && eol && eof) begin
        cnt <= cnt + 1'b1;
        if(!xdir) begin
            xpos <= xpos + 1'b1;
            if(xpos == H_RES - SQUARE_SIZE - 1) begin
                xdir <= 1'b1;
                xpos <= xpos - 1'b1;
            end
        end else begin
            xpos <= xpos - 1'b1;
            if(xpos == 0) begin
                xdir <= 1'b0;
                xpos <= xpos + 1'b1;
            end
        end

        if(!ydir) begin
            ypos <= ypos + 1'b1;
            if(ypos == V_RES - SQUARE_SIZE - 1) begin
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

assign m_axis_tdata = {{PADW{1'b0}}, red, green, blue}; // Concatenate RGB values with padding

// ==================================================================================

// Pixel scan...
always @(posedge aclk) begin
    if (!arst_n) begin
        x_count <= {HCNT_WIDTH{1'b0}};
        y_count <= {VCNT_WIDTH{1'b0}};
        tvalid <= 1'b0;
    end else if (valid) begin
        x_count <= (x_count == H_RES - 1) ? 0 : x_count + 1'b1;
        //y_count <= (x_count == H_RES - 1) ? ((y_count == V_RES - 1) ? 0 : y_count + 1'b1) : y_count;
        if (eof) begin
            y_count <= (eol) ? {HCNT_WIDTH{1'b0}} : y_count + 1'b1;
        end
        
        tvalid <= 1'b1;
    end
end

endmodule
