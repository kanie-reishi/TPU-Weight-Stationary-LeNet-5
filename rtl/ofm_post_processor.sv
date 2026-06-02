`timescale 1ns / 1ps

module ofm_post_processor #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    // Configuration
    input  logic        reg_relu_en,
    input  logic        reg_pool_en,
    input  logic [31:0] reg_out_width,
    input  logic [31:0] reg_channels_out,

    // Interface from PEA MAC
    input  logic        pea_we,
    input  logic [31:0] pea_x,
    input  logic [31:0] pea_y,
    input  logic [31:0] pea_cout,
    input  logic [15:0][7:0] pea_data,

    // Interface to SRAM (OFM Arbiter)
    output logic                  sram_we,
    output logic [ADDR_WIDTH-1:0] sram_addr,
    output logic [15:0][7:0]      sram_data
);

    // =========================================================================
    // 1. ReLU Stage
    // =========================================================================
    logic [15:0][7:0] w_relu_out;
    
    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : gen_relu
            logic [7:0] w_relu_val;
            ReLU u_relu (
                .data_in(pea_data[i]),
                .data_out(w_relu_val)
            );
            assign w_relu_out[i] = reg_relu_en ? w_relu_val : pea_data[i];
        end
    endgenerate

    // =========================================================================
    // 2. Pooling Line Buffer Stage
    // =========================================================================
    // We need to buffer 1 row of `w_relu_out`. Max out_width is 32.
    logic [15:0][7:0] r_line_buffer [0:31];
    logic [15:0][7:0] w_lb_read_data;
    
    // Write to line buffer on every pea_we
    always_ff @(posedge clk) begin
        if (pea_we) begin
            r_line_buffer[pea_x] <= w_relu_out;
        end
        // Read combinational (or we can just read from the array directly since pea_x is known)
    end
    
    assign w_lb_read_data = r_line_buffer[pea_x];

    // =========================================================================
    // 3. Max Pooling Stage
    // =========================================================================
    // We only perform pooling when y is odd, meaning we have the previous even row in the line buffer.
    // Wait! Since data streams pixel by pixel:
    // To pool (x-1, y-1), (x, y-1), (x-1, y), (x, y), we need to buffer the PREVIOUS pixel in the SAME row too!
    // So we need a register to hold the previous pixel of the current row (x-1, y), 
    // and a register to hold the previous pixel of the line buffer (x-1, y-1).
    
    logic [15:0][7:0] r_prev_curr_row;
    logic [15:0][7:0] r_prev_prev_row;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_prev_curr_row <= '0;
            r_prev_prev_row <= '0;
        end else begin
            if (pea_we) begin
                r_prev_curr_row <= w_relu_out;
                r_prev_prev_row <= w_lb_read_data;
            end
        end
    end

    logic [15:0][7:0] w_pool_out;
    
    generate
        for (i = 0; i < 16; i++) begin : gen_pool
            Max_pooling u_pool (
                .p00(r_prev_prev_row[i]), // (x-1, y-1)
                .p01(w_lb_read_data[i]),  // (x, y-1)
                .p10(r_prev_curr_row[i]), // (x-1, y)
                .p11(w_relu_out[i]),      // (x, y)
                .data_out(w_pool_out[i])
            );
        end
    endgenerate

    // =========================================================================
    // 4. Output Logic & Address Calculation
    // =========================================================================
    // If Pooling is enabled, we only write when (x is odd) and (y is odd).
    // The target address width and height are halved.
    
    logic [31:0] r_final_x, r_final_y;
    logic [15:0][7:0] r_final_data;
    logic r_final_we;
    
    always_comb begin
        if (reg_pool_en) begin
            r_final_we    = pea_we && (pea_x[0] == 1'b1) && (pea_y[0] == 1'b1);
            r_final_x     = pea_x >> 1;
            r_final_y     = pea_y >> 1;
            r_final_data  = w_pool_out;
        end else begin
            r_final_we    = pea_we;
            r_final_x     = pea_x;
            r_final_y     = pea_y;
            r_final_data  = w_relu_out;
        end
    end

    assign sram_we   = r_final_we;
    
    logic [31:0] r_sram_addr_r;
    logic [31:0] r_next_sram_addr;
    
    always_comb begin
        if (r_final_x == 0 && r_final_y == 0) begin
            r_next_sram_addr = pea_cout;
        end else begin
            r_next_sram_addr = r_sram_addr_r + (reg_channels_out >> 4);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_sram_addr_r <= '0;
        end else if (r_final_we) begin
            r_sram_addr_r <= r_next_sram_addr;
        end
    end
    
    assign sram_addr = r_next_sram_addr;
    assign sram_data = r_final_data;

endmodule
