//! @author: Yosel Balibrea Lastre
//! @title: m_axis.v
//! @date: 2026-08-28
//! @brief: AXI4-Stream Master Interface Module test

module m_axis #(
    parameter TDATA_WIDTH = 32,
    parameter V_RES = 480,
    parameter H_RES = 640
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
localparam integer PADW = TDATA_WIDTH - HCNT_WIDTH - VCNT_WIDTH;

reg [HCNT_WIDTH-1:0] x_count;
reg [VCNT_WIDTH-1:0] y_count;

wire eol = (x_count == V_RES-1); // End of line
wire eof = (y_count == H_RES-1); // End of frame

reg tvalid = 1'b0;
assign m_axis_tvalid = tvalid; // Always valid for this example

// sample dummy data
assign m_axis_tdata = {{PADW{1'b0}}, y_count, x_count}; 

// Assert tlast at the end of each line
assign m_axis_tlast = (x_count == H_RES - 1) ? 1'b1 : 1'b0;

assign m_axis_tuser = (x_count == 0 && y_count == 0) ? 1'b1 : 1'b0;

// Pixel scan...
always @(posedge aclk) begin
    if (!arst_n) begin
        x_count <= {HCNT_WIDTH{1'b0}};
        y_count <= {VCNT_WIDTH{1'b0}};
        tvalid <= 1'b0;
    end else if (tvalid && m_axis_tready) begin
        x_count <= (x_count == H_RES - 1) ? 0 : x_count + 1'b1;
        //y_count <= (x_count == H_RES - 1) ? ((y_count == V_RES - 1) ? 0 : y_count + 1'b1) : y_count;
        if (eof) begin
            y_count <= (eol) ? {HCNT_WIDTH{1'b0}} : y_count + 1'b1;
        end
        
        tvalid <= 1'b1;
    end
end

endmodule
