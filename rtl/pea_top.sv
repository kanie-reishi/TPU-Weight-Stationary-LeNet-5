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

    // =========================================================================
    // 2. KHAI BÁO TÍN HIỆU (WIRING & SIGNALS)
    // =========================================================================
    // Hằng số cho kiến trúc
    localparam MAX_IFM_WIDTH = 32;
    localparam KERNEL_SIZE = 5;
    localparam PSUM_ADDR_W = 10; // 10-bit cho phép lưu tối đa 1024 PSUM (C1 cần 28x28 = 784)

    // Datapath Wires (Luồng dữ liệu)
    logic [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0][127:0] w_window_data;
    logic w_is_valid_window;
    logic [15:0][7:0]  w_routed_data;
    logic [15:0][7:0]  w_routed_data_delayed; // Pipeline register (Delay 1 clock)

    logic [15:0][31:0] w_psum_to_top;
    logic [15:0][31:0] w_psum_from_bottom;
    logic [15:0]       w_psum_en_bottom;

    // FSM Control Wires (Các dây này sẽ được FSM điều khiển ở phần dưới)
    logic        w_stream_en;
    logic [4:0]  w_current_pass_id;
    logic        w_is_first_pass;
    logic        w_psum_re;
    logic        w_psum_we;
    logic [PSUM_ADDR_W-1:0] w_psum_read_addr;
    logic [PSUM_ADDR_W-1:0] w_psum_write_addr;
    
    logic [15:0] w_load_weight_en;
    logic        w_swap_weight;
    logic [15:0] w_data_en_left;
    logic [15:0] w_psum_en_top;

    // Giải mã địa chỉ Microcode (Giả sử Microcode RAM nằm ở địa chỉ >= 0x80)
    logic        w_microcode_we;
    assign w_microcode_we = cfg_we && (cfg_addr >= 8'h80);

    // Post-Processor Signals
    logic [15:0][15:0] r_bias_data;      // 16 bias values, 16-bit each (nạp từ Weight Bank)
    logic [1:0]        r_pp_bias_cnt;    // Bộ đếm sub-state đọc bias
    logic              r_pp_start;       // Xung kích hoạt post-processor
    logic              w_pp_done;        // Post-processor báo hoàn thành
    logic              w_pp_psum_re;     // PP → PSUM buffer read enable
    logic [PSUM_ADDR_W-1:0] w_pp_psum_rd_addr; // PP → PSUM buffer read address
    logic              w_pp_ofm_we;      // PP → OFM write enable
    logic [ADDR_WIDTH-1:0] w_pp_ofm_addr;// PP → OFM write address
    logic [15:0][7:0]  w_pp_ofm_data;    // PP → OFM write data
    logic              r_computation_done;// Cờ báo đã xong toàn bộ tiles
    logic              w_delay_chain_empty; // Delay chain PSUM write đã rỗng
    assign w_delay_chain_empty = (psum_we_delay_chain == 16'd0);

    // =========================================================================
    // 3. PIPELINE ALIGNMENT (ĐỒNG BỘ TRỄ 1 CLOCK)
    // =========================================================================
    // IFM Data phải bị làm trễ 1 clock để đợi BRAM nhả PSUM ra
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_routed_data_delayed <= '0;
        end else begin
            w_routed_data_delayed <= w_routed_data;
        end
    end

    // =========================================================================
    // 4. INSTANTIATE DATAPATH BLOCKS
    // =========================================================================
    line_buffer #(
        .MAX_WIDTH (MAX_IFM_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE),
        .DATA_WIDTH (128)
    ) u_line_buffer (
        .clk               (clk),
        .rst_n             (rst_n),
        .stream_en         (w_stream_en),
        .img_width         (r_reg_ifm_width[$clog2(MAX_IFM_WIDTH)-1:0]), // Input động từ Register file
        .pixel_in          (ifm_read_data),
        .window_data_out   (w_window_data)
    );

    window_router #(
        .DATA_WIDTH (128),
        .KERNEL_SIZE (r_reg_kernel_size)
    ) u_window_router (
        .clk             (clk),
        .i_cfg_we        (w_microcode_we),
        .i_cfg_addr      (cfg_addr[4:0]),
        .i_cfg_data      (cfg_data),
        .i_current_pass_id (w_current_pass_id),
        .window_in       (w_window_data),
        .routed_data_out (w_routed_data),
    );

    pea_systolic_16x16 u_systolic_core (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .load_weight_en        (w_load_weight_en),
        .weight_in_top         (wb_read_data),
        .swap_weight_in_global (w_swap_weight),
        .data_en_left          (w_data_en_left),
        .data_in_left          (w_routed_data_delayed),
        .psum_en_top           (w_psum_en_top),
        .psum_in_top           (w_psum_to_top),     // From BRAM
        .psum_out_bottom       (w_psum_from_bottom),// To BRAM
        .psum_en_bottom        (w_psum_en_bottom)
    );

    psum_buffer u_psum_bram (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .is_first_pass          (w_is_first_pass),
        .psum_re                (w_psum_re),
        .psum_we                (w_psum_we),
        .read_addr              (w_psum_read_addr),
        .write_addr             (w_psum_write_addr),
        .psum_from_bottom       (w_psum_from_bottom),
        .psum_to_top            (w_psum_to_top)
    );

    // =========================================================================
    // 4b. OFM POST-PROCESSOR (Bias + Right Shift + ReLU)
    // =========================================================================
    ofm_post_processor #(
        .PSUM_ADDR_W (PSUM_ADDR_W),
        .OFM_ADDR_W  (ADDR_WIDTH)
    ) u_ofm_pp (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (r_pp_start),
        .done           (w_pp_done),
        .reg_relu_en    (r_reg_relu_en),
        .reg_right_shift(r_reg_right_shift),
        .reg_out_pixels (w_max_output_pixels),
        .bias_data      (r_bias_data),
        .ofm_base_addr  (ADDR_WIDTH'(r_cout_tile_cnt)),
        .ofm_addr_stride(ADDR_WIDTH'(w_max_cout_tiles)),
        .psum_re        (w_pp_psum_re),
        .psum_rd_addr   (w_pp_psum_rd_addr),
        .psum_rdata     (w_psum_to_top),
        .ofm_we         (w_pp_ofm_we),
        .ofm_addr       (w_pp_ofm_addr),
        .ofm_data       (w_pp_ofm_data)
    );

    // Nối output post-processor ra port OFM của pea_top
    assign ofm_we         = w_pp_ofm_we;
    assign ofm_write_addr = w_pp_ofm_addr;
    assign ofm_write_data = w_pp_ofm_data;

    // =========================================================================
    // 5. FSM & Control
    // =========================================================================

    typedef enum logic [2:0] {
        ST_IDLE         = 3'd0,
        ST_LOAD_WEIGHT  = 3'd1,
        ST_WARM_UP      = 3'd2,
        ST_STREAM       = 3'd3,
        ST_CHECK_PASS   = 3'd4,
        ST_POST_PROC    = 3'd5,
        ST_PP_DRAIN     = 3'd6
    } state_t;

    state_t r_state, w_next_state;

    // Hardware Counters
    logic [6:0]  r_cout_tile_cnt; // Đếm Cout Tiles (C1:1, C5:8)
    logic [4:0]  r_pass_id_cnt;   // Đếm số Pass trong 1 Tile (C1:2, C5:25)
    logic [4:0]  r_weight_cnt;    // Đếm 16 nhịp nạp weight
    logic [31:0] r_warmup_cnt;    // Đếm nhịp fill Line Buffer
    logic [31:0] r_stream_cnt;    // Đếm tổng số pixel IFM đã đọc trong 1 pass
    logic [15:0] r_col_cnt;       // Đếm toạ độ X của pixel đang chui vào Line Buffer

    // Các bộ đếm quản lý Địa chỉ bộ nhớ PSUM BRAM
    logic [PSUM_ADDR_W-1:0] r_psum_rd_ptr; // Con trỏ đọc psum chuẩn (0 -> out_w*out_h-1)
    logic [PSUM_ADDR_W-1:0] r_psum_wr_ptr; // Con trỏ ghi psum (Phải trễ hơn rd_ptr 16 nhịp)

    // AUTOMATIC THRESHOLD CALCULATIONS
    logic [4:0]  w_num_passes;
    logic [6:0]  w_max_cout_tiles;
    logic [31:0] w_warmup_threshold;
    logic [31:0] w_total_ifm_pixels;
    logic [PSUM_ADDR_W-1:0] w_max_output_pixels;

    always_comb begin
        // Tính số passes = ceil(Cin * 25 / 16) -> Dùng dịch bit, không dùng chia
        w_num_passes     = ((r_reg_channels_in * 25) + 15) >> 4;
        
        // Tính số Cout Tiles = ceil(Cout / 16)
        w_max_cout_tiles = (r_reg_channels_out + 15) >> 4;
        
        // Ngưỡng Warm-up = (5-1)*Width + (5-1) = 4*Width + 4
        w_warmup_threshold = (r_reg_ifm_width << 2) + 4;
        
        // Tổng số pixel IFM của 1 ảnh = Width * Height
        w_total_ifm_pixels = r_reg_ifm_width * r_reg_ifm_height; // Phép nhân kích thước phẳng (chấp nhận được)
        
        // Tổng số lượng điểm ảnh kết quả (OFM) = out_width * out_height
        // Tạm thời lấy bằng tổng số pixel (Bạn có thể trừ đi border nếu ko dùng padding ở sw)
        w_max_output_pixels = (r_reg_ifm_width - 4) * (r_reg_ifm_height - 4); 

        // Cửa sổ hợp lệ
        w_is_valid_window = (r_col_cnt >= r_reg_kernel_size - 1);
    end

    // =========================================================================
    // 7. STATE TRANSITION LOGIC (Sequential Block)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state <= ST_IDLE;
        end else begin
            r_state <= w_next_state;
        end
    end
    // =========================================================================
    // 8. NEXT STATE LOGIC (Combinational Block)
    // =========================================================================
    always_comb begin
        w_next_state = r_state;
        
        case (r_state)
            ST_IDLE: begin
                if (ctrl_start) w_next_state = ST_LOAD_WEIGHT;
            end
            
            ST_LOAD_WEIGHT: begin
                // Nạp đủ 16 weights cho 16 hàng PE thì chuyển trạng thái
                if (r_weight_cnt == 5'd15) w_next_state = ST_WARM_UP;
            end

            ST_WARM_UP: begin
                // Đợi dòng nước (data) nạp đầy Line Buffer và Window Array
                if (r_warmup_cnt == w_warmup_threshold - 1) w_next_state = ST_STREAM;
            end
            
            ST_STREAM: begin
                // Stream cho đến khi cạn bộ nhớ ảnh IFM SRAM của pass đó
                if (r_stream_cnt == w_total_ifm_pixels - 1) w_next_state = ST_CHECK_PASS;
            end

            ST_CHECK_PASS: begin
                // Trạng thái ảo quyết định rẽ nhánh Pass
                if (r_pass_id_cnt < w_num_passes - 1)
                    w_next_state = ST_LOAD_WEIGHT; // Tua lại (Rewind) chạy Pass tiếp theo
                else
                    w_next_state = ST_POST_PROC;   // Đã xong 1 cụm 16 Cout -> Đi xử lý hậu kỳ
            end
            
            ST_POST_PROC: begin
                // Đợi delay chain rỗng, đọc bias, rồi kích Post-Processor
                if (w_delay_chain_empty && r_pp_bias_cnt == 2'd2)
                    w_next_state = ST_PP_DRAIN;
            end

            ST_PP_DRAIN: begin
                // Chờ Post-Processor xử lý xong toàn bộ OFM pixels
                if (w_pp_done) begin
                    if (r_cout_tile_cnt < w_max_cout_tiles - 1)
                        w_next_state = ST_LOAD_WEIGHT;
                    else
                        w_next_state = ST_IDLE;
                end
            end
            
            default: w_next_state = ST_IDLE;
        endcase
    end

    // =========================================================================
    // 9. HARDWARE COUNTERS CONTROL (Sequential Block)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_cout_tile_cnt <= '0;
            r_pass_id_cnt   <= '0;
            r_weight_cnt    <= '0;
            r_warmup_cnt    <= '0;
            r_stream_cnt    <= '0;
            r_psum_rd_ptr   <= '0;
            r_pp_bias_cnt   <= '0;
        end else begin
            case (r_state)
                ST_IDLE: begin
                    r_cout_tile_cnt <= '0;
                    r_pass_id_cnt   <= '0;
                    r_weight_cnt    <= '0;
                    r_warmup_cnt    <= '0;
                    r_stream_cnt    <= '0;
                    r_psum_rd_ptr   <= '0;
                    r_pp_bias_cnt   <= '0;
                end
                ST_LOAD_WEIGHT: begin
                    r_weight_cnt <= r_weight_cnt + 1;
                    // Reset các bộ đếm chuẩn bị cho khâu stream ảnh tiếp theo
                    r_warmup_cnt  <= '0;
                    r_stream_cnt  <= '0;
                    r_psum_rd_ptr <= '0;
                    r_col_cnt <= '0;
                end

                ST_WARM_UP: begin
                    r_weight_cnt <= '0;
                    r_warmup_cnt <= r_warmup_cnt + 1;

                    if(r_col_cnt == r_reg_ifm_width - 1)
                        r_col_cnt <= '0;
                    else 
                        r_col_cnt <= r_col_cnt + 1;
                end
                
                ST_STREAM: begin
                    r_stream_cnt <= r_stream_cnt + 1;
                    
                    if(r_col_cnt == r_reg_ifm_width - 1)
                        r_col_cnt <= '0;
                    else 
                        r_col_cnt <= r_col_cnt + 1;
                        
                    if (w_is_valid_window && (r_psum_rd_ptr < w_max_output_pixels - 1)) begin
                        r_psum_rd_ptr <= r_psum_rd_ptr + 1;
                    end
                end

                ST_CHECK_PASS: begin
                    if (r_pass_id_cnt < w_num_passes - 1) begin
                        r_pass_id_cnt <= r_pass_id_cnt + 1;
                    end
                    r_pp_bias_cnt <= '0;
                end
                
                ST_POST_PROC: begin
                    r_pass_id_cnt <= '0;
                    if (w_delay_chain_empty) begin
                        r_pp_bias_cnt <= r_pp_bias_cnt + 1;
                    end
                end

                ST_PP_DRAIN: begin
                    if (w_pp_done) begin
                        if (r_cout_tile_cnt < w_max_cout_tiles - 1) begin
                            r_cout_tile_cnt <= r_cout_tile_cnt + 1;
                        end
                    end
                end
            endcase
        end
    end
    // =========================================================================
    // 10. PSUM WRITE POINTER DELAY CHAIN (16-CYCLE LATENCY ALIGNMENT)
    // =========================================================================
    logic [15:0][PSUM_ADDR_W-1:0] psum_addr_delay_chain;
    logic [15:0]                 psum_we_delay_chain;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_addr_delay_chain <= '0;
            psum_we_delay_chain   <= '0;
        end else begin
            // Đẩy con trỏ đọc hiện tại và lệnh cho phép ghi (we) vào đầu ống
            // Lệnh ghi thực sự (w_psum_we) chỉ xảy ra trong trạng thái STREAM và cửa sổ đó hợp lệ
            psum_addr_delay_chain[0] <= r_psum_rd_ptr;
            psum_we_delay_chain[0]   <= (r_state == ST_STREAM) && w_is_valid_window;
            
            // Dịch chuyển đường ống trễ
            for (int i = 1; i < 16; i++) begin
                psum_addr_delay_chain[i] <= psum_addr_delay_chain[i-1];
                psum_we_delay_chain[i]   <= psum_we_delay_chain[i-1];
            end
        end
    end

    // Hứng dữ liệu rớt ra ở cuối ống trễ 16 nhịp gán vào cổng ghi của BRAM
    assign w_psum_write_addr = psum_addr_delay_chain[15];
    assign w_psum_we         = psum_we_delay_chain[15];

    // =========================================================================
    // 11. DRIVING CONTROL WIRES TO DATAPATH (Driving the Wires from Section 2)
    // =========================================================================
    assign w_stream_en       = (r_state == ST_WARM_UP) || (r_state == ST_STREAM);
    assign w_current_pass_id = r_pass_id_cnt;
    // Chỉ chặn BRAM nạp 0 ở Pass 0 trong giai đoạn streaming (tránh ảnh hưởng post-processing)
    assign w_is_first_pass   = (r_pass_id_cnt == 5'd0) && (r_state == ST_WARM_UP || r_state == ST_STREAM);

    // Mux port đọc PSUM buffer: streaming hoặc post-processor
    assign w_psum_re         = (r_state == ST_STREAM) || w_pp_psum_re;
    assign w_psum_read_addr  = w_pp_psum_re ? w_pp_psum_rd_addr : r_psum_rd_ptr;

    // Các tín hiệu kích hoạt lõi Systolic Array
    assign w_load_weight_en  = (r_state == ST_LOAD_WEIGHT) ? 16'hFFFF : 16'h0000;
    assign w_swap_weight     = (r_state == ST_LOAD_WEIGHT) && (r_weight_cnt == 5'd15);
    
    assign w_data_en_left    = (r_state == ST_STREAM) ? 16'hFFFF : 16'h0000;
    assign w_psum_en_top     = (r_state == ST_STREAM) ? 16'hFFFF : 16'h0000;

    // Giao diện SRAM Bộ nhớ ngoài (Rewind tự động bằng bộ đếm r_stream_cnt và r_warmup_cnt)
    assign ifm_re            = w_stream_en;
    // Đọc tuần tự từ địa chỉ gốc của ảnh, khi chuyển Pass bộ đếm tự reset về 0 làm con trỏ tự Rewind!
    assign ifm_read_addr     = (r_state == ST_WARM_UP) ? r_warmup_cnt[ADDR_WIDTH-1:0] : 
                               (r_state == ST_STREAM)  ? (w_warmup_threshold + r_stream_cnt)[ADDR_WIDTH-1:0] : '0;

    // Weight SRAM: Mux giữa nạp weight (LOAD_WEIGHT) và đọc bias (POST_PROC)
    assign wb_re             = (r_state == ST_LOAD_WEIGHT) ||
                               (r_state == ST_POST_PROC && w_delay_chain_empty && r_pp_bias_cnt <= 2'd1);
    assign wb_read_addr      = (r_state == ST_POST_PROC) ?
                               (r_reg_bias_base + {r_cout_tile_cnt, r_pp_bias_cnt[0]}) :
                               (r_reg_weight_base + (r_cout_tile_cnt * w_num_passes * 16) + (r_pass_id_cnt * 16) + r_weight_cnt);

    // Khối điều khiển tổng ngoài Core
    assign ctrl_done         = r_computation_done;

    // =========================================================================
    // 12. BIAS READING LOGIC (Đọc 2 word bias 16-bit từ Weight Bank)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_bias_data <= '0;
            r_pp_start  <= 1'b0;
        end else begin
            r_pp_start <= 1'b0; // Mặc định tắt xung

            if (r_state == ST_POST_PROC && w_delay_chain_empty) begin
                case (r_pp_bias_cnt)
                    2'd1: begin
                        // BRAM trả dữ liệu từ lệnh đọc ở cnt=0 → lưu bias[0..7]
                        for (int i = 0; i < 8; i++) begin
                            r_bias_data[i] <= {wb_read_data[2*i+1], wb_read_data[2*i]};
                        end
                    end
                    2'd2: begin
                        // BRAM trả dữ liệu từ lệnh đọc ở cnt=1 → lưu bias[8..15]
                        for (int i = 0; i < 8; i++) begin
                            r_bias_data[i+8] <= {wb_read_data[2*i+1], wb_read_data[2*i]};
                        end
                        // Kích hoạt post-processor pipeline
                        r_pp_start <= 1'b1;
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // 13. COMPUTATION DONE FLAG
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_computation_done <= 1'b0;
        end else begin
            if (ctrl_start)
                r_computation_done <= 1'b0;
            else if (r_state == ST_PP_DRAIN && w_pp_done && !(r_cout_tile_cnt < w_max_cout_tiles - 1))
                r_computation_done <= 1'b1;
        end
    end

endmodule
