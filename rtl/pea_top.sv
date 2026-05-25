`timescale 1ns / 1ps

// ============================================================================
// Module: pea_top
// Description: Top-level wrapper for the Processing Element Array.
//              Includes the 16x16 Systolic Core, AGU/FSM, Config Regs, and Post-Processing.
// ============================================================================
module pea_top #(
    parameter DATA_WIDTH = 8,
    parameter PSUM_WIDTH = 32,
    parameter ADDR_WIDTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    // Controller Interface
    input  logic start,
    output logic done,

    // Configuration Interface (Memory Mapped Register File)
    input  logic [7:0]  cfg_addr,
    input  logic [31:0] cfg_data,
    input  logic        cfg_we,

    // Memory Interface: Weight & Bias Bank (Read)
    output logic [ADDR_WIDTH-1:0] wb_read_addr,
    output logic                  wb_re,
    input  logic [15:0][7:0]      wb_read_data,
    
    // Memory Interface: IFM Buffer (Read)
    output logic [ADDR_WIDTH-1:0] ifm_read_addr,
    output logic                  ifm_re,
    input  logic [15:0][7:0]      ifm_read_data,

    // Memory Interface: OFM Buffer (Write)
    output logic [ADDR_WIDTH-1:0] ofm_write_addr,
    output logic                  ofm_we,
    output logic [15:0][7:0]      ofm_write_data
);

    // =========================================================================
    // 1. Configuration Register File (Layer-specific parameters)
    // =========================================================================
    logic [31:0] reg_ifm_width;     // Chiều rộng của ảnh đầu vào (Input Feature Map)
    logic [31:0] reg_ifm_height;    // Chiều cao của ảnh đầu vào
    logic [31:0] reg_channels_in;   // Số lượng kênh đầu vào (Input Channels / Depth)
    logic [31:0] reg_channels_out;  // Số lượng kênh đầu ra (Số lượng bộ lọc / Filters)
    logic [31:0] reg_kernel_size;   // Kích thước cạnh của bộ lọc (ví dụ: 5 cho kernel 5x5)
    logic [4:0]  reg_right_shift;   // Số bit dịch phải (Right Shift) dùng cho quá trình Lượng tử hóa
    
    // Pre-computed strides to reduce multiplier delay in critical path
    logic [31:0] reg_row_stride;    // Bước nhảy bộ nhớ cho mỗi hàng (Bytes per row = ifm_width * channels_in)
    logic [31:0] reg_col_stride;    // Bước nhảy bộ nhớ cho mỗi cột (Bytes per pixel = channels_in)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ifm_width    <= '0;
            reg_ifm_height   <= '0;
            reg_channels_in  <= '0;
            reg_channels_out <= '0;
            reg_kernel_size  <= '0;
            reg_right_shift  <= '0;
            reg_row_stride   <= '0;
            reg_col_stride   <= '0;
        end else if (cfg_we) begin
            case (cfg_addr)
                8'h00: reg_ifm_width    <= cfg_data;
                8'h04: reg_ifm_height   <= cfg_data;
                8'h08: reg_channels_in  <= cfg_data;
                8'h0C: reg_channels_out <= cfg_data;
                8'h10: reg_kernel_size  <= cfg_data;
                8'h14: reg_right_shift  <= cfg_data[4:0];
                8'h18: reg_row_stride   <= cfg_data;
                8'h1C: reg_col_stride   <= cfg_data;
            endcase
        end
    end

    // =========================================================================
    // 2. FSM & Nested Loop AGU (Address Generation Unit)
    // =========================================================================
    typedef enum logic [1:0] {
        IDLE      = 2'd0,
        PRE_LOAD  = 2'd1, // Load weights & biases
        COMPUTE   = 2'd2, // Nested loops for im2col MACs
        POST_PROC = 2'd3  // Wait for pipeline flush
    } state_t;

    state_t state, next_state;

    // Control signals for the Systolic Core
    logic [15:0]       load_weight_en;
    logic [15:0][7:0]  weight_in_top;
    logic [15:0]       data_en_left;
    logic [15:0]       psum_en_top;
    logic [15:0][31:0] psum_in_top;

    // Outputs from Systolic Core
    logic [15:0][31:0] psum_out_bottom;
    logic [15:0]       psum_en_bottom;
    
    // Bias Array
    logic [31:0] bias_array [0:15]; 

    // Nested Loops Counters for Im2Col AGU
    logic [31:0] loop_out_x, loop_out_y, loop_cin, loop_kx, loop_ky;
    logic        compute_done;
    logic [7:0]  load_counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            loop_out_x <= '0; loop_out_y <= '0;
            loop_cin <= '0; loop_kx <= '0; loop_ky <= '0;
            compute_done <= 1'b0;
            load_weight_en <= 16'd0;
            load_counter <= '0;
        end else begin
            state <= next_state;
            
            if (state == IDLE) begin
                loop_out_x <= '0; loop_out_y <= '0;
                loop_cin <= '0; loop_kx <= '0; loop_ky <= '0;
                compute_done <= 1'b0;
                load_counter <= '0;
                // Clear load_weight_en in IDLE
                load_weight_en <= 16'd0; 
                
            end else if (state == PRE_LOAD) begin
                load_counter <= load_counter + 1;
                // Enable weights only during first 16 cycles of PRE_LOAD
                if (load_counter < 16) load_weight_en <= 16'hFFFF;
                else load_weight_en <= 16'd0;
                
                // Load bias into bias_array after weights
                if (load_counter >= 16 && load_counter < 32) begin
                    // Read lowest 32 bits (4 bytes) of the 128-bit bus as the bias value
                    bias_array[load_counter - 16] <= {wb_read_data[3], wb_read_data[2], wb_read_data[1], wb_read_data[0]}; 
                end
                
            end else if (state == COMPUTE) begin
                // Ensure weight load is off
                load_weight_en <= 16'd0;
                
                // Im2Col Nested Loop Execution
                if (loop_cin < reg_channels_in - 1) begin
                    loop_cin <= loop_cin + 1;
                end else begin
                    loop_cin <= '0;
                    if (loop_kx < reg_kernel_size - 1) begin
                        loop_kx <= loop_kx + 1;
                    end else begin
                        loop_kx <= '0;
                        if (loop_ky < reg_kernel_size - 1) begin
                            loop_ky <= loop_ky + 1;
                        end else begin
                            loop_ky <= '0;
                            // Sliding window striding
                            if (loop_out_x < reg_ifm_width - reg_kernel_size) begin
                                loop_out_x <= loop_out_x + 1;
                            end else begin
                                loop_out_x <= '0;
                                if (loop_out_y < reg_ifm_height - reg_kernel_size) begin
                                    loop_out_y <= loop_out_y + 1;
                                end else begin
                                    compute_done <= 1'b1;
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    // Im2Col Address Calculation using pre-computed strides
    // -------------------------------------------------------------------------
    // Công thức tính địa chỉ 1D trên mảng SRAM từ tọa độ 3D (Y, X, C_in) theo chuẩn NHWC:
    // Tọa độ pixel đang xử lý: 
    //   - Tọa độ Y: (loop_out_y + loop_ky)
    //   - Tọa độ X: (loop_out_x + loop_kx)
    // Để tối ưu timing (tránh dùng 3 bộ nhân 32-bit), ta dùng row_stride và col_stride.
    // Địa chỉ = Y * row_stride + X * col_stride + C_in
    // -------------------------------------------------------------------------
    assign ifm_read_addr = (loop_out_y + loop_ky) * reg_row_stride + 
                           (loop_out_x + loop_kx) * reg_col_stride + loop_cin;

    always_comb begin
        next_state = state;
        done = 1'b0;

        case (state)
            IDLE: begin
                if (start) next_state = PRE_LOAD;
            end
            PRE_LOAD: begin
                // 16 cycles for weights + 16 cycles for biases = 32 cycles
                if (load_counter == 31) next_state = COMPUTE; 
            end
            COMPUTE: begin
                if (compute_done) next_state = POST_PROC; 
            end
            POST_PROC: begin
                if (psum_en_bottom[15] == 1'b0) begin // Wait for pipeline flush
                    done = 1'b1;
                    next_state = IDLE;
                end
            end
        endcase
    end

    // wb_read_addr mapped to load_counter
    assign wb_read_addr = load_counter;
    assign wb_re = (state == PRE_LOAD);

    // Connect 128-bit read data directly to the 16 columns
    assign weight_in_top = wb_read_data;

    assign ifm_re = (state == COMPUTE);
    assign data_en_left = {16{ifm_re}}; // Enable all rows during compute

    // psum_en_top and psum_in_top assignment
    assign psum_en_top = {16{ifm_re}}; // Active during compute
    assign psum_in_top = '0;           // Bias is added at post-processing, so top is 0

    // =========================================================================
    // 3. Systolic Array Core Instantiation
    // =========================================================================
    pea_systolic_16x16 u_systolic_core (
        .clk             (clk),
        .rst_n           (rst_n),
        .load_weight_en  (load_weight_en),
        .weight_in_top   (weight_in_top),
        .data_en_left    (data_en_left),
        .data_in_left    (ifm_read_data),
        .psum_en_top     (psum_en_top),
        .psum_in_top     (psum_in_top),
        .psum_out_bottom (psum_out_bottom),
        .psum_en_bottom  (psum_en_bottom)
    );

    // =========================================================================
    // 4. Post-Processing Unit (With Right Shift Quantization)
    // =========================================================================
    logic [15:0][31:0] post_psum;
    logic [15:0]       post_valid;
    
    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : bias_add
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    post_psum[i] <= 32'd0;
                    post_valid[i] <= 1'b0;
                end else begin
                    post_valid[i] <= psum_en_bottom[i];
                    if (psum_en_bottom[i]) begin
                        post_psum[i] <= $signed(psum_out_bottom[i]) + $signed(bias_array[i]);
                    end
                end
            end
        end
    endgenerate

    logic [15:0][7:0] final_ofm;
    logic [15:0]      final_valid;
    logic signed [31:0] shifted_val [0:15];

    generate
        for (i = 0; i < 16; i++) begin : relu_quantize
            // Arithmetic Right Shift with Rounding
            assign shifted_val[i] = ($signed(post_psum[i]) + (32'sd1 <<< (reg_right_shift - 1))) >>> reg_right_shift;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    final_ofm[i] <= 8'd0;
                    final_valid[i] <= 1'b0;
                end else begin
                    final_valid[i] <= post_valid[i];
                    if (post_valid[i]) begin
                        // ReLU Activation
                        if ($signed(shifted_val[i]) < 0) begin
                            final_ofm[i] <= 8'd0;
                        end else begin
                            // Saturation Clamp to 127 for signed INT8 max
                            if (shifted_val[i] > 127) begin
                                final_ofm[i] <= 8'd127; 
                            end else begin
                                final_ofm[i] <= shifted_val[i][7:0];
                            end
                        end
                    end
                end
            end
            assign ofm_write_data[i] = final_ofm[i];
        end
    endgenerate

    assign ofm_we = |final_valid; 
    
    // ofm_write_addr generation
    logic [ADDR_WIDTH-1:0] out_pixel_counter;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pixel_counter <= '0;
        end else if (state == IDLE) begin
            out_pixel_counter <= '0;
        end else if (ofm_we) begin
            out_pixel_counter <= out_pixel_counter + 1;
        end
    end
    assign ofm_write_addr = out_pixel_counter;

endmodule
