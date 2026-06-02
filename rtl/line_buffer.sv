`timescale 1ns / 1ps

// ============================================================================
// Module: line_buffer
// Description: Local SRAM Circular Line Buffer for Processing Element Array.
//              Automatically handles modulo row mapping.
// ============================================================================
module line_buffer #(
    parameter MAX_WIDTH = 32,
    parameter KERNEL_SIZE = 5,
    parameter DATA_WIDTH = 128
)(
    input  logic clk,
    
    input  logic rst_n,
    // Control signals
    input  logic stream_en, // FSM báo hiệu đang stream ảnh
    input  logic [$clog2(MAX_WIDTH)-1:0] img_width, // Width thực tế
    // Write Interface (From IFM SRAM)
    input  logic pixel_valid_in,
    input  logic [DATA_WIDTH-1:0] pixel_in,
    
    // Read Interface (To Window Router)
    output logic [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0][DATA_WIDTH-1:0] window_data_out
);
    //================================================//
    //                  1.Declaration                 //
    //================================================//
    // Khai báo 4 LUTRAM cho Delay Lines
    localparam LB_DEPTH = MAX_WIDTH;

    (* ram_style = "distributed" *) logic [DATA_WIDTH-1:0] r_lb_1[LB_DEPTH-1:0];
    (* ram_style = "distributed" *) logic [DATA_WIDTH-1:0] r_lb_2[LB_DEPTH-1:0];
    (* ram_style = "distributed" *) logic [DATA_WIDTH-1:0] r_lb_3[LB_DEPTH-1:0];
    (* ram_style = "distributed" *) logic [DATA_WIDTH-1:0] r_lb_4[LB_DEPTH-1:0];
    
    // Khai báo 25 Flip-Flops cho Window Array
    logic [DATA_WIDTH-1:0] r_window_arr[KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
    // Logic con trỏ col_ptr (0 -> img_width-1)
    logic [$clog2(MAX_WIDTH)-1:0] r_col_ptr;
    // =========================================================
    // LOGIC CON TRỎ COL_PTR (DELAY LINE POINTER)
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_col_ptr <= '0;
        end else if (stream_en) begin
            // Đếm quay vòng dựa trên width thực tế của Layer hiện tại
            if (r_col_ptr == img_width - 1) begin
                r_col_ptr <= '0;
            end else begin
                r_col_ptr <= r_col_ptr + 1'b1;
            end
        end
    end
    
    // =========================================================
    // LOGIC THÁC NƯỚC (WATERFALL SHIFT & RAM DELAY)
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset toàn bộ Window Array về 0
            for(int r = 0; r < KERNEL_SIZE; r++) begin
                for(int c = 0; c < KERNEL_SIZE; c++) begin
                    r_window_arr[r][c] <= '0;
                end
            end
        end else if (stream_en) begin
            // Bước 1: Dịch chuyển các cột trong Window sang Trái
            // (Cột 0 nhận từ cột 1, cột 1 nhận từ cột 2)
            for(int r = 0; r < KERNEL_SIZE; r++) begin
                for(int c = 0; c < KERNEL_SIZE -1 ; c++) begin
                    r_window_arr[r][c] <= r_window_arr[r][c+1];
                end
            end

            // Bước 2: Cột ngoài cùng bên Phải hứng dữ liệu mới
            r_window_arr[0][4] <= pixel_in;        // Hàng 0 lấy từ SRAM ngoài
            r_window_arr[1][4] <= r_lb_1[r_col_ptr]; // Hàng 1 lấy từ RAM Delay 1
            r_window_arr[2][4] <= r_lb_2[r_col_ptr]; // Hàng 2 lấy từ RAM Delay 2
            r_window_arr[3][4] <= r_lb_3[r_col_ptr]; // Hàng 3 lấy từ RAM Delay 3
            r_window_arr[4][4] <= r_lb_4[r_col_ptr]; // Hàng 4 lấy từ RAM Delay 4

            // Bước 3: Dữ liệu tràn ra ở cột Trái rơ xuống Line buffers
            r_lb_1[r_col_ptr] <= r_window_arr[0][0];  // Hàng 1 lấy từ RAM Delay 1
            r_lb_2[r_col_ptr] <= r_window_arr[1][0];  // Hàng 2 lấy từ RAM Delay 2
            r_lb_3[r_col_ptr] <= r_window_arr[2][0];  // Hàng 3 lấy từ RAM Delay 3
            r_lb_4[r_col_ptr] <= r_window_arr[3][0];  // Hàng 4 lấy từ RAM Delay 4
        end
    end

    // Gắn mảng thanh ghi nội bộ ra cổng output
    always_comb begin
        for (int r = 0; r < KERNEL_SIZE; r++) begin
            for (int c = 0; c < KERNEL_SIZE; c++) begin
                window_data_out[r][c] = r_window_arr[r][c];
            end
        end
    end
endmodule
