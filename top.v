
`default_nettype none

module top #(
    parameter integer VIDEOC_W = 8
)(
    input wire aclk,
    input wire arst_n,

    output wire [VIDEOC_W-1 : 0] red, green, blue,
    output reg [9 : 0] sx_o, sy_o,
    output reg de_o,

);

// AXIS master



// AXIS slave

endmodule