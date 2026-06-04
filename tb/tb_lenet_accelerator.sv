`timescale 1ns / 1ps

// ============================================================================
// TOP-LEVEL TESTBENCH: tb_lenet_accelerator
// ============================================================================
// Chức năng:
// 1. Khởi tạo lenet_accelerator
// 2. AXI-Lite BFM: Gửi cấu hình và tập lệnh (Instructions) cho Controller
// 3. AXI-Full BFM (DDR Mock): Giả lập bộ nhớ DDR chứa ảnh đầu vào và nhận ảnh đầu ra
// 4. Random Data Generator & Reference Model: Tự động kiểm tra tính đúng đắn
// ============================================================================

module tb_lenet_accelerator();

    // =========================================================
    // PARAMETERS & SIGNALS
    // =========================================================
    localparam AXI_AWIDTH = 40;
    localparam AXI_DWIDTH = 64;

    logic clk;
    logic rst_n;

    // --- AXI-Lite Slave (CPU -> FPGA) ---
    logic                    s_axi_awvalid;
    logic                    s_axi_awready;
    logic [31:0]             s_axi_awaddr;
    logic                    s_axi_wvalid;
    logic                    s_axi_wready;
    logic [31:0]             s_axi_wdata;
    
    logic                    s_axi_arvalid;
    logic                    s_axi_arready;
    logic [31:0]             s_axi_araddr;
    logic                    s_axi_rvalid;
    logic                    s_axi_rready;
    logic [31:0]             s_axi_rdata;
    logic [1:0]              s_axi_rresp;
    
    logic                    s_axi_bready;
    logic                    s_axi_bvalid;
    logic [1:0]              s_axi_bresp;

    // --- AXI-Full Master (FPGA -> DDR) ---
    logic [AXI_AWIDTH-1:0]   m_axi_araddr;
    logic [7:0]              m_axi_arlen;
    logic [2:0]              m_axi_arsize;
    logic [1:0]              m_axi_arburst;
    logic                    m_axi_arvalid;
    logic                    m_axi_arready;
    
    logic [AXI_DWIDTH-1:0]   m_axi_rdata;
    logic                    m_axi_rlast;
    logic                    m_axi_rvalid;
    logic                    m_axi_rready;

    logic [AXI_AWIDTH-1:0]   m_axi_awaddr;
    logic [7:0]              m_axi_awlen;
    logic [2:0]              m_axi_awsize;
    logic [1:0]              m_axi_awburst;
    logic                    m_axi_awvalid;
    logic                    m_axi_awready;

    logic [AXI_DWIDTH-1:0]   m_axi_wdata;
    logic                    m_axi_wlast;
    logic                    m_axi_wvalid;
    logic                    m_axi_wready;

    logic [1:0]              m_axi_bresp;
    logic                    m_axi_bvalid;
    logic                    m_axi_bready;

    logic                    finish_irq_o;

    // =========================================================
    // INSTANTIATION
    // =========================================================
    lenet_accelerator #(
        .AXI_AWIDTH(AXI_AWIDTH),
        .AXI_DWIDTH(AXI_DWIDTH)
    ) uut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready), .s_axi_awaddr(s_axi_awaddr),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready), .s_axi_wdata(s_axi_wdata),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready), .s_axi_araddr(s_axi_araddr),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready), .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_bready(s_axi_bready), .s_axi_bvalid(s_axi_bvalid), .s_axi_bresp(s_axi_bresp),

        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        
        .finish_irq_o(finish_irq_o)
    );

    // =========================================================
    // CLOCK & RESET
    // =========================================================
    always #5 clk = ~clk; // 100MHz

    // =========================================================
    // AXI-LITE BFM (Master)
    // =========================================================
    task axi_lite_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;

            // Chờ Ready từ Slave
            wait(s_axi_awready && s_axi_wready);
            @(posedge clk);
            s_axi_awaddr  = '0;
            s_axi_awvalid = 1'b0;
            s_axi_wdata   = '0;
            s_axi_wvalid  = 1'b0;

            // Chờ BVALID trả về
            wait(s_axi_bvalid);
            @(posedge clk);
            s_axi_bready  = 1'b0;
        end
    endtask

    // Tương tự, AXI-Lite Read (không dùng nhiều trong test flow này)
    task axi_lite_read(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(posedge clk);
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            s_axi_rready  = 1'b1;

            wait(s_axi_arready);
            @(posedge clk);
            s_axi_arvalid = 1'b0;

            wait(s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready  = 1'b0;
        end
    endtask

    // =========================================================
    // AXI-FULL BFM (DDR Memory Mock - Slave)
    // =========================================================
    logic [7:0] ddr_mem [longint]; // Associative Array cho bộ nhớ 64-bit address space

    // 1. Read Channel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rlast   <= 1'b0;
            m_axi_rdata   <= '0;
        end else begin
            // Chấp nhận yêu cầu đọc
            if (m_axi_arvalid && !m_axi_arready) begin
                m_axi_arready <= 1'b1;
            end else if (m_axi_arready) begin
                m_axi_arready <= 1'b0;
            end

            // Phản hồi dữ liệu liên tục theo Burst
            // Lưu ý: BFM này giản lược, giả định Burst INCR và luôn gửi liền mạch
            // (Thực tế cần dùng máy trạng thái xử lý m_axi_arlen)
            // Để đơn giản cho mô phỏng, ta dùng vòng lặp (với delay giả lập) ở khối process riêng
        end
    end

    // Read Data Thread
    initial begin
        m_axi_rvalid = 1'b0;
        m_axi_rlast  = 1'b0;
        m_axi_rdata  = '0;
        forever begin
            @(posedge clk);
            if (m_axi_arvalid && m_axi_arready) begin
                logic [AXI_AWIDTH-1:0] r_addr = m_axi_araddr;
                int r_len = m_axi_arlen;
                
                // Mất 5 nhịp clock để truy cập DDR
                repeat(5) @(posedge clk);

                for (int i = 0; i <= r_len; i++) begin
                    m_axi_rvalid = 1'b1;
                    m_axi_rlast  = (i == r_len);
                    
                    // Ghép 8 bytes thành 1 từ 64-bit
                    for (int b = 0; b < 8; b++) begin
                        m_axi_rdata[b*8 +: 8] = ddr_mem.exists(r_addr + b) ? ddr_mem[r_addr + b] : 8'h00;
                    end
                    
                    wait(m_axi_rready); // Đợi Master sẵn sàng nhận
                    @(posedge clk);
                    r_addr = r_addr + 8; // Mặc định bus 64-bit = 8 bytes
                end
                
                m_axi_rvalid = 1'b0;
                m_axi_rlast  = 1'b0;
            end
        end
    end

    // 2. Write Channel
    initial begin
        m_axi_awready = 1'b0;
        m_axi_wready  = 1'b0;
        m_axi_bvalid  = 1'b0;
        m_axi_bresp   = 2'b00;

        forever begin
            @(posedge clk);
            // Chấp nhận Address
            if (m_axi_awvalid && !m_axi_awready) begin
                m_axi_awready = 1'b1;
                
                // Thu thập Data
                fork
                    begin
                        logic [AXI_AWIDTH-1:0] w_addr = m_axi_awaddr;
                        int w_len = m_axi_awlen;
                        int beats = 0;

                        m_axi_wready = 1'b1; // Sẵn sàng nhận data
                        
                        while (beats <= w_len) begin
                            @(posedge clk);
                            if (m_axi_wvalid && m_axi_wready) begin
                                // Ghi 8 bytes vào DDR Mock
                                for (int b = 0; b < 8; b++) begin
                                    ddr_mem[w_addr + b] = m_axi_wdata[b*8 +: 8];
                                end
                                w_addr = w_addr + 8;
                                beats++;
                                if (m_axi_wlast) break;
                            end
                        end
                        m_axi_wready = 1'b0;
                        
                        // Phản hồi BVALID
                        @(posedge clk);
                        m_axi_bvalid = 1'b1;
                        wait(m_axi_bready);
                        @(posedge clk);
                        m_axi_bvalid = 1'b0;
                    end
                join_none
            end else begin
                m_axi_awready = 1'b0;
            end
        end
    end

    // =========================================================
    // KỊCH BẢN KIỂM THỬ (TEST SEQUENCE)
    // =========================================================
    
    // Memory map
    localparam IFM_ADDR  = 40'h1000_0000;
    localparam WGT_ADDR  = 40'h2000_0000; // Trọng số và Bias
    localparam OFM_ADDR  = 40'h3000_0000; // Kết quả trả về
    
    // Kích thước (Fix theo phần cứng K=5 của PEA)
    localparam IFM_W = 10;
    localparam IFM_H = 10;
    localparam C_IN  = 1;
    localparam C_OUT = 16;
    localparam K_SIZE = 5;
    localparam OUT_W = IFM_W - K_SIZE + 1; // 6
    localparam OUT_H = IFM_H - K_SIZE + 1; // 6
    localparam RIGHT_SHIFT = 2;
    localparam RELU_EN = 1;

    // Bộ nhớ Reference
    logic signed [7:0] ref_ifm [IFM_H][IFM_W][C_IN];
    logic signed [7:0] ref_wgt [C_OUT][C_IN][K_SIZE][K_SIZE];
    logic signed [15:0] ref_bias [C_OUT];
    logic signed [7:0] ref_ofm [OUT_H][OUT_W][C_OUT];

    initial begin
        // Khởi tạo tín hiệu
        clk = 0;
        rst_n = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_arvalid = 0; s_axi_rready = 0; s_axi_bready = 0;
        
        $display("==================================================");
        $display("Bắt đầu khởi tạo dữ liệu ngẫu nhiên (Random Data)");
        $display("==================================================");
        
        // 1. Khởi tạo mảng DDR bằng 0
        ddr_mem.delete();

        // 2. Sinh dữ liệu IFM ngẫu nhiên [-128..127]
        for (int h = 0; h < IFM_H; h++) begin
            for (int w = 0; w < IFM_W; w++) begin
                for (int c = 0; c < C_IN; c++) begin
                    ref_ifm[h][w][c] = $random;
                    ddr_mem[IFM_ADDR + (h * IFM_W + w) * C_IN + c] = ref_ifm[h][w][c];
                end
            end
        end

        // 3. Sinh WGT ngẫu nhiên (Lưu theo trật tự: C_out_tile -> C_in -> K_h -> K_w -> C_out_ch)
        // Kiến trúc yêu cầu nạp 16 channels WGT cùng lúc (128-bit = 16 bytes)
        for (int c_out_tile = 0; c_out_tile < C_OUT/16; c_out_tile++) begin
            for (int c_in = 0; c_in < C_IN; c_in++) begin
                for (int kh = 0; kh < K_SIZE; kh++) begin
                    for (int kw = 0; kw < K_SIZE; kw++) begin
                        for (int ch = 0; ch < 16; ch++) begin
                            int real_cout = c_out_tile * 16 + ch;
                            ref_wgt[real_cout][c_in][kh][kw] = $random;
                            
                            // Ghi vào DDR: Mỗi (c_in, kh, kw) chiếm 16 bytes (1 word nội bộ)
                            longint offset = (c_out_tile * C_IN * K_SIZE * K_SIZE * 16) +
                                             (c_in * K_SIZE * K_SIZE * 16) +
                                             (kh * K_SIZE * 16) +
                                             (kw * 16) + ch;
                            ddr_mem[WGT_ADDR + offset] = ref_wgt[real_cout][c_in][kh][kw];
                        end
                    end
                end
            end
        end

        // 4. Sinh BIAS ngẫu nhiên 16-bit
        // Bias được đặt ngai sau đoạn Weight của Tile
        for (int c_out_tile = 0; c_out_tile < C_OUT/16; c_out_tile++) begin
            longint bias_base_offset = (c_out_tile + 1) * C_IN * K_SIZE * K_SIZE * 16; // Tạm quy ước bias nằm cuối
            
            for (int ch = 0; ch < 16; ch++) begin
                int real_cout = c_out_tile * 16 + ch;
                ref_bias[real_cout] = $random;
                
                // Bias 16-bit: Ghi 2 byte (Little Endian)
                // Cấu trúc trong SRAM: 2 words = 32 bytes (16 kênh * 2 byte)
                ddr_mem[WGT_ADDR + bias_base_offset + ch*2]     = ref_bias[real_cout][7:0];
                ddr_mem[WGT_ADDR + bias_base_offset + ch*2 + 1] = ref_bias[real_cout][15:8];
            end
        end

        // Bỏ Reset
        #100 rst_n = 1;
        #100;

        $display("Gửi cấu hình PEA Array qua AXI-Lite...");
        // Các thanh ghi PEA Cfg map ở 0x100 trở đi trong lenet_accelerator.sv
        axi_lite_write(32'h0100, IFM_W); // ifm_width
        axi_lite_write(32'h0104, IFM_H); // ifm_height
        axi_lite_write(32'h0108, C_IN);  // channels_in
        axi_lite_write(32'h010C, C_OUT); // channels_out
        axi_lite_write(32'h0110, K_SIZE);// kernel_size
        axi_lite_write(32'h0114, RIGHT_SHIFT); // right_shift
        axi_lite_write(32'h0120, 0); // weight base nội bộ SRAM = 0
        // Bias base = base của tile 0 weight + offset
        axi_lite_write(32'h0124, C_IN * K_SIZE * K_SIZE); // bias base (word addr)
        axi_lite_write(32'h0128, RELU_EN); // relu enable

        $display("Đẩy tập lệnh (Instructions) vào Controller (Instruction FIFO map ở 0x00)...");
        // Format Lệnh 64-bit (chúng ta phân tích theo RTL của Controller):
        // [63:60] Opcode
        // OP_SET_ADDR (1): [59:58] 00=IFM, 01=WGT, 10=OFM. [39:0] addr
        
        // 1. SET ADDR
        axi_lite_write(32'h0000, 32'h10000000); // Nửa thấp (IFM_ADDR)
        axi_lite_write(32'h0004, 32'h10000000); // Nửa cao (Opcode=1, Type=00)
        
        axi_lite_write(32'h0000, 32'h20000000); // Nửa thấp (WGT_ADDR)
        axi_lite_write(32'h0004, 32'h14000000); // Nửa cao (Opcode=1, Type=01)

        axi_lite_write(32'h0000, 32'h30000000); // Nửa thấp (OFM_ADDR)
        axi_lite_write(32'h0004, 32'h18000000); // Nửa cao (Opcode=1, Type=10)

        // 2. LOAD_WGT (Opcode=4) - Cần DMA Bytes. 
        // 16 kernels (5x5) + 16 biases(2 bytes) = 400 + 32 = 432 bytes
        axi_lite_write(32'h0000, 432); 
        axi_lite_write(32'h0004, 32'h40000000);

        // 3. LOAD_IFM (Opcode=A) - Cần DMA Bytes. 10x10 = 100 bytes
        axi_lite_write(32'h0000, 100);
        axi_lite_write(32'h0004, 32'hA0000000);

        // 4. RUN_MAC (Opcode=5) - Chỉ cần xung bật
        axi_lite_write(32'h0000, 0);
        axi_lite_write(32'h0004, 32'h50000000);

        // 5. STORE_OFM (Opcode=7) - Cần DMA Bytes. 6x6 x 16 = 576 bytes
        axi_lite_write(32'h0000, 576);
        axi_lite_write(32'h0004, 32'h70000000);

        // 6. FINISH (Opcode=F)
        axi_lite_write(32'h0000, 0);
        axi_lite_write(32'h0004, 32'hF0000000);

        $display("Chờ tín hiệu ngắt hoàn thành (finish_irq_o)...");
        wait(finish_irq_o);
        $display("Đã nhận ngắt hoàn thành! Bắt đầu kiểm tra kết quả.");

        // =========================================================================
        // KIỂM TRA MÔ HÌNH THAM CHIẾU (REFERENCE CHECK)
        // =========================================================================
        compute_reference();
        
        check_results();

        $finish;
    end

    // Hàm tính toán Reference Model (Sát với phần cứng đã thiết kế)
    task compute_reference();
        for (int h = 0; h < OUT_H; h++) begin
            for (int w = 0; w < OUT_W; w++) begin
                for (int cout = 0; cout < C_OUT; cout++) begin
                    int psum = 0;
                    
                    // Convolution
                    for (int cin = 0; cin < C_IN; cin++) begin
                        for (int kh = 0; kh < K_SIZE; kh++) begin
                            for (int kw = 0; kw < K_SIZE; kw++) begin
                                psum += ref_ifm[h+kh][w+kw][cin] * ref_wgt[cout][cin][kh][kw];
                            end
                        end
                    end
                    
                    // Post Processing
                    // Cộng Bias (Bias đã là int16, psum là int32)
                    psum = psum + int'(ref_bias[cout]);
                    
                    // Right Shift Arithmetic
                    psum = psum >>> RIGHT_SHIFT;
                    
                    // Saturating Clamp
                    if (psum > 127) psum = 127;
                    else if (psum < -128) psum = -128;
                    
                    // ReLU
                    if (RELU_EN && psum < 0) psum = 0;
                    
                    ref_ofm[h][w][cout] = psum[7:0];
                end
            end
        end
    endtask

    // Hàm đối chiếu DDR với kết quả tham chiếu
    task check_results();
        int errors = 0;
        int checked = 0;
        
        for (int h = 0; h < OUT_H; h++) begin
            for (int w = 0; w < OUT_W; w++) begin
                for (int cout = 0; cout < C_OUT; cout++) begin
                    // Tính offset ghi ra DMA: PEA ghi theo thứ tự Pixel -> Channel
                    longint offset = (h * OUT_W + w) * 16 + cout;
                    logic [7:0] hw_val = ddr_mem.exists(OFM_ADDR + offset) ? ddr_mem[OFM_ADDR + offset] : 8'hXX;
                    logic [7:0] ref_val = ref_ofm[h][w][cout];
                    
                    checked++;
                    
                    if (hw_val !== ref_val) begin
                        $display("[LỖI] Tại (h=%0d, w=%0d, c=%0d): HW = %0d, REF = %0d", h, w, cout, $signed(hw_val), $signed(ref_val));
                        errors++;
                    end
                end
            end
        end
        
        $display("==================================================");
        if (errors == 0)
            $display("[THÀNH CÔNG] Toàn bộ %0d pixels khớp hoàn toàn!", checked);
        else
            $display("[THẤT BẠI] Có %0d / %0d pixels bị sai.", errors, checked);
        $display("==================================================");
    endtask

endmodule
