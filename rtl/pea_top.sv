`timescale 1ns / 1ps

module pea_top #(
    parameter DATA_WIDTH = 8,
    parameter PSUM_WIDTH = 32,
    parameter ADDR_WIDTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    // Controller Interface
    input  logic ctrl_start,
    output logic ctrl_done,

    // Configuration Interface
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
    // 1. Configuration Register File
    // =========================================================================
    logic [31:0] r_reg_ifm_width;     
    logic [31:0] r_reg_ifm_height;    
    logic [31:0] r_reg_channels_in;   
    logic [31:0] r_reg_channels_out;  
    logic [31:0] r_reg_kernel_size;   
    logic [4:0]  r_reg_right_shift;   
    logic [31:0] r_reg_row_stride;    
    logic [31:0] r_reg_col_stride;    
    logic [31:0] r_reg_weight_base;   
    logic [31:0] r_reg_bias_base;     
    logic        r_reg_relu_en;
    logic        r_reg_pool_en;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_reg_ifm_width    <= '0;
            r_reg_ifm_height   <= '0;
            r_reg_channels_in  <= '0;
            r_reg_channels_out <= '0;
            r_reg_kernel_size  <= '0;
            r_reg_right_shift  <= '0;
            r_reg_row_stride   <= '0;
            r_reg_col_stride   <= '0;
            r_reg_weight_base  <= '0;
            r_reg_bias_base    <= '0;
            r_reg_relu_en      <= 1'b0;
            r_reg_pool_en      <= 1'b0;
        end else if (cfg_we) begin
            case (cfg_addr)
                8'h00: r_reg_ifm_width    <= cfg_data;
                8'h04: r_reg_ifm_height   <= cfg_data;
                8'h08: r_reg_channels_in  <= cfg_data;
                8'h0C: r_reg_channels_out <= cfg_data;
                8'h10: r_reg_kernel_size  <= cfg_data;
                8'h14: r_reg_right_shift  <= cfg_data[4:0];
                8'h18: r_reg_row_stride   <= cfg_data;
                8'h1C: r_reg_col_stride   <= cfg_data;
                8'h20: r_reg_weight_base  <= cfg_data;
                8'h24: r_reg_bias_base    <= cfg_data;
                8'h28: r_reg_relu_en      <= cfg_data[0];
                8'h2C: r_reg_pool_en      <= cfg_data[0];
            endcase
        end
    end

    logic [31:0] w_out_width;
    assign w_out_width = r_reg_ifm_width - r_reg_kernel_size + 1;

    logic [31:0] w_tiles_per_cout;
    assign w_tiles_per_cout = r_reg_channels_in * r_reg_kernel_size * r_reg_kernel_size;

    // =========================================================================
    // 2. FSM & Control
    // =========================================================================
    typedef enum logic [2:0] {
        IDLE            = 3'd0,
        LOAD_BIAS       = 3'd1,
        LOAD_LINE_BUFFER= 3'd2,
        LOAD_WEIGHT     = 3'd3,
        STREAM_ROW      = 3'd4,
        WAIT_FLUSH      = 3'd5,
        WAIT_BRAM       = 3'd6,
        POST_PROC       = 3'd7
    } state_t;

    state_t r_state, r_next_state;

    logic [31:0] r_loop_cout; 
    logic [31:0] r_loop_y;    
    logic [31:0] r_loop_cin;  
    logic [31:0] r_loop_ky;   
    logic [31:0] r_loop_kx;   

    logic [7:0]  r_load_counter;
    logic [31:0] r_stream_cnt;
    logic [31:0] r_psum_flush_cnt;
    
    logic [31:0] r_lb_load_row_cnt;
    logic [31:0] r_lb_load_col_cnt;
    logic        r_load_full_lb;
    logic [31:0] w_rows_to_load;
    
    assign w_rows_to_load = r_load_full_lb ? r_reg_kernel_size : 32'd1;

    logic [31:0] w_tile_index;
    assign w_tile_index = r_loop_cout * w_tiles_per_cout + 
                        r_loop_cin * (r_reg_kernel_size * r_reg_kernel_size) + 
                        r_loop_ky * r_reg_kernel_size + 
                        r_loop_kx;

    logic w_is_first_acc;
    assign w_is_first_acc = (r_loop_cin == 0 && r_loop_ky == 0 && r_loop_kx == 0);

    logic [15:0]       r_load_weight_en;
    logic              w_swap_weight_in_global;
    logic [15:0]       w_data_en_left;
    logic [15:0]       w_psum_en_top;
    logic [15:0][31:0] w_psum_in_top;

    logic [15:0][31:0] w_psum_out_bottom;
    logic [15:0]       w_psum_en_bottom;

    logic [31:0] r_bias_array [0:15]; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state <= IDLE;
            r_loop_cout <= '0; r_loop_y <= '0; r_loop_cin <= '0; 
            r_loop_ky <= '0; r_loop_kx <= '0;
            r_load_counter <= '0; r_stream_cnt <= '0; r_psum_flush_cnt <= '0;
            r_lb_load_row_cnt <= '0; r_lb_load_col_cnt <= '0;
            r_load_full_lb <= 1'b1;
        end else begin
            r_state <= r_next_state;
            
            if (r_state == IDLE && ctrl_start) begin
                r_loop_cout <= '0; r_loop_y <= '0; r_loop_cin <= '0; 
                r_loop_ky <= '0; r_loop_kx <= '0;
                r_load_full_lb <= 1'b1;
            end
            
            if (r_state != LOAD_LINE_BUFFER && r_next_state == LOAD_LINE_BUFFER) begin
                r_lb_load_row_cnt <= '0;
                r_lb_load_col_cnt <= '0;
            end
            
            case (r_state)
                LOAD_BIAS: begin
                    // 1-cycle latency SRAM handling moved to a separate always_ff block
                    r_load_counter <= r_load_counter + 1;
                    if (r_load_counter == 15) r_load_counter <= '0;
                end
                
                LOAD_LINE_BUFFER: begin
                    r_lb_load_col_cnt <= r_lb_load_col_cnt + 1;
                    if (r_lb_load_col_cnt == r_reg_ifm_width - 1) begin
                        r_lb_load_col_cnt <= '0;
                        r_lb_load_row_cnt <= r_lb_load_row_cnt + 1;
                    end
                end
                
                LOAD_WEIGHT: begin
                    r_load_counter <= r_load_counter + 1;
                    if (r_load_counter == 15) r_load_counter <= '0;
                end
                
                STREAM_ROW: begin
                    r_stream_cnt <= r_stream_cnt + 1;
                    if (r_stream_cnt == w_out_width - 1) r_stream_cnt <= '0;
                end
                
                WAIT_FLUSH: begin
                    if (w_psum_en_bottom[0]) begin
                        r_psum_flush_cnt <= r_psum_flush_cnt + 1;
                        if (r_psum_flush_cnt == w_out_width - 1) begin
                            r_psum_flush_cnt <= '0;
                            if (r_loop_kx < r_reg_kernel_size - 1) begin
                                r_loop_kx <= r_loop_kx + 1;
                            end else begin
                                r_loop_kx <= '0;
                                if (r_loop_ky < r_reg_kernel_size - 1) begin
                                    r_loop_ky <= r_loop_ky + 1;
                                end else begin
                                    r_loop_ky <= '0;
                                    if (r_loop_cin + 1 < r_reg_channels_in) begin
                                        r_loop_cin <= r_loop_cin + 1;
                                        r_load_full_lb <= 1'b1;
                                    end else begin
                                        r_loop_cin <= '0;
                                    end
                                end
                            end
                        end
                    end
                end
                
                POST_PROC: begin
                    r_stream_cnt <= r_stream_cnt + 1;
                    if (r_stream_cnt == w_out_width - 1) begin
                        r_stream_cnt <= '0;
                        if (r_loop_y < r_reg_ifm_height - r_reg_kernel_size) begin
                            r_loop_y <= r_loop_y + 1;
                            r_load_full_lb <= 1'b0;
                        end else begin
                            r_loop_y <= '0;
                            if (r_loop_cout + 1 < (r_reg_channels_out >> 4)) begin
                                r_loop_cout <= r_loop_cout + 1;
                                r_load_full_lb <= 1'b1;
                            end
                        end
                    end
                end
            endcase
        end
    end

    logic r_done_comb;
    logic r_done_d1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_done_d1 <= 1'b0;
            ctrl_done <= 1'b0;
        end else begin
            r_done_d1 <= r_done_comb;
            ctrl_done <= r_done_d1;
        end
    end

    always_comb begin
        r_next_state = r_state;
        r_done_comb = 1'b0;
        
        case (r_state)
            IDLE: if (ctrl_start) r_next_state = LOAD_BIAS;
            LOAD_BIAS: if (r_load_counter == 15) r_next_state = LOAD_LINE_BUFFER;
            LOAD_LINE_BUFFER: begin
                if (r_lb_load_col_cnt == r_reg_ifm_width - 1 && r_lb_load_row_cnt == w_rows_to_load - 1)
                    r_next_state = LOAD_WEIGHT;
            end
            LOAD_WEIGHT: if (r_load_counter == 15) r_next_state = STREAM_ROW;
            STREAM_ROW: if (r_stream_cnt == w_out_width - 1) r_next_state = WAIT_FLUSH;
            WAIT_FLUSH: begin
                if (w_psum_en_bottom[0] && r_psum_flush_cnt == w_out_width - 1) begin
                    if (r_loop_kx == r_reg_kernel_size - 1 && r_loop_ky == r_reg_kernel_size - 1) begin
                        if (r_loop_cin + 1 == r_reg_channels_in)
                            r_next_state = WAIT_BRAM;
                        else
                            r_next_state = LOAD_LINE_BUFFER;
                    end else begin
                        r_next_state = LOAD_WEIGHT;
                    end
                end
            end
            WAIT_BRAM: begin
                r_next_state = POST_PROC;
            end
            POST_PROC: begin
                if (r_stream_cnt == w_out_width - 1) begin
                    if (r_loop_y == r_reg_ifm_height - r_reg_kernel_size && r_loop_cout + 1 == (r_reg_channels_out >> 4)) begin
                        r_next_state = IDLE;
                        r_done_comb = 1'b1;
                    end else if (r_loop_y == r_reg_ifm_height - r_reg_kernel_size)
                        r_next_state = LOAD_BIAS;
                    else
                        r_next_state = LOAD_LINE_BUFFER;
                end
            end
        endcase
    end

    // =========================================================================
    // 3. Line Buffer & IFM SRAM Interface
    // =========================================================================
    logic [31:0] w_current_load_abs_row;
    assign w_current_load_abs_row = r_load_full_lb ? (r_loop_y + r_lb_load_row_cnt) : (r_loop_y + r_reg_kernel_size - 1);
    
    assign ifm_re = (r_state == LOAD_LINE_BUFFER);
    assign ifm_read_addr = w_current_load_abs_row * r_reg_row_stride + r_lb_load_col_cnt * r_reg_col_stride + r_loop_cin;
    
    // 1-cycle latency for IFM SRAM
    logic r_lb_we;
    logic [31:0] r_lb_write_row, r_lb_write_col;
    logic [31:0] w_lb_read_row, w_lb_read_col;
    logic [127:0] w_lb_read_data;
    
    always_ff @(posedge clk) begin
        r_lb_we <= ifm_re;
        r_lb_write_row <= w_current_load_abs_row;
        r_lb_write_col <= r_lb_load_col_cnt;
    end

    assign w_lb_read_row = r_loop_y + r_loop_ky;
    assign w_lb_read_col = r_stream_cnt + r_loop_kx;
    
    line_buffer #(
        .MAX_WIDTH(32),
        .MAX_ROWS(5),
        .DATA_WIDTH(128)
    ) u_line_buffer (
        .clk(clk),
        .we(r_lb_we),
        .write_row(r_lb_write_row),
        .write_col(r_lb_write_col),
        .write_data(ifm_read_data),
        .read_row(w_lb_read_row),
        .read_col(w_lb_read_col),
        .read_data(w_lb_read_data)
    );

    // =========================================================================
    // 4. Memory Interfaces & Systolic Signals
    // =========================================================================
    assign wb_re = (r_state == LOAD_BIAS) || (r_state == LOAD_WEIGHT);
    assign wb_read_addr = (r_state == LOAD_BIAS) ? (r_reg_bias_base + r_loop_cout * 16 + r_load_counter) :
                                                 (r_reg_weight_base + (w_tile_index * 16) + (15 - r_load_counter));

    // 1-cycle latency for WB SRAM
    always_ff @(posedge clk) begin
        r_load_weight_en <= (r_state == LOAD_WEIGHT) ? 16'hFFFF : 16'd0;
    end
    
    // Delayed states for bias load
    logic [3:0] r_state_delayed;
    logic [31:0] r_load_counter_delayed;
    always_ff @(posedge clk) begin
        r_state_delayed <= r_state;
        r_load_counter_delayed <= r_load_counter;
    end
    
    always_ff @(posedge clk) begin
        if (r_state_delayed == LOAD_BIAS) begin
            r_bias_array[r_load_counter_delayed] <= {wb_read_data[3], wb_read_data[2], wb_read_data[1], wb_read_data[0]};
        end
    end
    
    // Line buffer has 1-cycle latency internally, so delay w_data_en_left
    logic r_data_en_delayed;
    logic r_psum_en_top_delayed;
    logic r_swap_weight_delayed;
    
    always_ff @(posedge clk) begin
        r_data_en_delayed <= (r_state == STREAM_ROW);
        r_psum_en_top_delayed <= (r_state == STREAM_ROW);
        r_swap_weight_delayed <= (r_state == STREAM_ROW && r_stream_cnt == 0);
    end

    assign w_data_en_left = r_data_en_delayed ? 16'hFFFF : 16'd0;
    assign w_psum_en_top = r_psum_en_top_delayed ? 16'hFFFF : 16'd0;
    assign w_swap_weight_in_global = r_swap_weight_delayed;
    assign w_psum_in_top = '0; 

    // =========================================================================
    // 5. Systolic Array Core Instantiation
    // =========================================================================
    pea_systolic_16x16 u_systolic_core (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .r_load_weight_en        (r_load_weight_en),
        .weight_in_top         (wb_read_data),
        .w_swap_weight_in_global (w_swap_weight_in_global),
        .w_data_en_left          (w_data_en_left),
        .data_in_left          (w_lb_read_data),
        .w_psum_en_top           (w_psum_en_top),
        .w_psum_in_top           (w_psum_in_top),
        .w_psum_out_bottom       (w_psum_out_bottom),
        .w_psum_en_bottom        (w_psum_en_bottom)
    );

    // =========================================================================
    // 6. Psum Buffer (Block RAM)
    // =========================================================================
    logic [511:0] r_psum_bram [0:63]; 
    logic [511:0] r_psum_bram_dout;
    logic [5:0]   r_psum_read_addr;
    logic [5:0]   r_psum_write_addr;
    logic         r_psum_we;
    logic [511:0] r_psum_din;
    
    always_comb begin
        if (r_state == WAIT_FLUSH && w_psum_en_bottom[0])
            r_psum_read_addr = r_psum_flush_cnt;
        else if (r_state == POST_PROC)
            r_psum_read_addr = r_stream_cnt;
        else
            r_psum_read_addr = '0;
    end

    always_ff @(posedge clk) begin
        if (r_psum_we) r_psum_bram[r_psum_write_addr] <= r_psum_din;
        
        if (r_psum_we && r_psum_write_addr == r_psum_read_addr)
            r_psum_bram_dout <= r_psum_din;
        else
            r_psum_bram_dout <= r_psum_bram[r_psum_read_addr];
    end

    logic [15:0][31:0] r_psum_out_delayed;
    logic              r_psum_en_delayed;
    logic [5:0]        r_psum_write_addr_reg;
    logic              r_is_first_acc_delayed;

    always_ff @(posedge clk) begin
        r_psum_out_delayed <= w_psum_out_bottom;
        r_psum_en_delayed  <= w_psum_en_bottom[0] && (r_state == WAIT_FLUSH);
        r_psum_write_addr_reg <= r_psum_flush_cnt; 
        r_is_first_acc_delayed <= w_is_first_acc; // FIX: Delay w_is_first_acc to match BRAM write cycle
    end

    always_comb begin
        r_psum_we = r_psum_en_delayed;
        r_psum_write_addr = r_psum_write_addr_reg;
        for (int i=0; i<16; i++) begin
            if (r_is_first_acc_delayed) 
                r_psum_din[i*32 +: 32] = r_psum_out_delayed[i];
            else 
                r_psum_din[i*32 +: 32] = r_psum_out_delayed[i] + r_psum_bram_dout[i*32 +: 32];
        end
    end

    // BRAM write logic moved to the combined block above

    // =========================================================================
    // 7. Post-Processing Unit (Apply Bias, Right Shift, ReLU)
    // =========================================================================
    logic               r_post_proc_en;
    logic [31:0]        r_post_proc_x;
    logic [15:0][7:0]   r_final_ofm;
    logic               r_ofm_we_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_post_proc_en <= 1'b0;
            r_post_proc_x <= '0;
        end else begin
            r_post_proc_en <= (r_state == POST_PROC);
            r_post_proc_x <= r_stream_cnt; 
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_ofm_we_reg <= 1'b0;
        end else begin
            r_ofm_we_reg <= r_post_proc_en;
            if (r_post_proc_en) begin
                for (int i=0; i<16; i++) begin
                    logic signed [31:0] val;
                    logic signed [31:0] s_val;
                    val = $signed(r_psum_bram_dout[i*32 +: 32]) + $signed(r_bias_array[i]);
                    s_val = (val + (32'sd1 <<< (r_reg_right_shift - 1))) >>> r_reg_right_shift;
                    
                    if (s_val > 127) r_final_ofm[i] <= 8'd127;
                    else if (s_val < -128) r_final_ofm[i] <= -8'sd128;
                    else r_final_ofm[i] <= s_val[7:0];
                end
            end
        end
    end
    
    logic [31:0] r_post_proc_x_delayed;
    logic [31:0] r_loop_y_delayed;
    logic [31:0] r_loop_cout_delayed;
    
    always_ff @(posedge clk) begin
        r_post_proc_x_delayed <= r_post_proc_x;
        r_loop_y_delayed <= r_loop_y;
        r_loop_cout_delayed <= r_loop_cout;
    end
    
    ofm_post_processor #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(16)
    ) u_post_processor (
        .clk(clk),
        .rst_n(rst_n),
        .r_reg_relu_en(r_reg_relu_en),
        .r_reg_pool_en(r_reg_pool_en),
        .reg_out_width(w_out_width),
        .r_reg_channels_out(r_reg_channels_out),
        .pea_we(r_ofm_we_reg),
        .pea_x(r_post_proc_x_delayed),
        .pea_y(r_loop_y_delayed),
        .pea_cout(r_loop_cout_delayed),
        .pea_data(r_final_ofm),
        .sram_we(ofm_we),
        .sram_addr(ofm_write_addr),
        .sram_data(ofm_write_data)
    );

endmodule
