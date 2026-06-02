`timescale 1ns / 1ps

// ============================================================================
// Module: line_buffer
// Description: Local SRAM Circular Line Buffer for Processing Element Array.
//              Automatically handles modulo row mapping.
// ============================================================================
module line_buffer #(
    parameter IMG_WIDTH = 32,
    parameter KERNEL_SIZE = 5,
    parameter DATA_WIDTH = 8
)(
    input  logic clk,
    
    input  logic rst_n,
    // Write Interface (From IFM Serializer)
    input  logic pixel_valid_in,
    input  logic [DATA_WIDTH-1:0] pixel_in,
    input  logic new_image,
    
    // Read Interface (To PE Array)
    output logic window_valid_out,
    output logic [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0][DATA_WIDTH-1:0] window_data_out
);

    localparam LB_DEPTH = IMG_WIDTH;

    logic [DATA_WIDTH-1:0] r_lb_1[LB_DEPTH-1:0];
    logic [DATA_WIDTH-1:0] r_lb_2[LB_DEPTH-1:0];
    logic [DATA_WIDTH-1:0] r_lb_3[LB_DEPTH-1:0];
    logic [DATA_WIDTH-1:0] r_lb_4[LB_DEPTH-1:0];
    
    

endmodule
