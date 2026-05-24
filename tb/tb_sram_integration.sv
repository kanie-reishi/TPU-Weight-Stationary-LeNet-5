`timescale 1ns / 1ps

// [GIẢNG BÀI] Testbench Mới: Kiểm thử tích hợp SRAM Ping/Pong với Global Arbiter
// Mục tiêu: Bơm dữ liệu thật vào AXI-Full Slave (DDR), dùng DMA kéo về SRAM,
// sau đó kiểm tra xem dữ liệu trong SRAM có khớp không (Scoreboard).

module tb_sram_integration();

    // ==========================================
    // Cấu hình thông số
    // ==========================================
    localparam AXI_AWIDTH  = 40;
    localparam AXI_DWIDTH  = 64;
    localparam SRAM_AWIDTH = 11;
    
    // ==========================================
    // Khai báo tín hiệu
    // ==========================================
    logic clk;
    logic rst_n;
    
    // AXI-Lite
    logic [31:0] s_axi_awaddr, s_axi_wdata;
    logic s_axi_awvalid, s_axi_wvalid, s_axi_bready;
    logic s_axi_awready, s_axi_wready, s_axi_bvalid;
    
    // AXI-Full
    logic [AXI_AWIDTH-1:0] m_axi_araddr, m_axi_awaddr;
    logic [7:0]  m_axi_arlen, m_axi_awlen;
    logic        m_axi_arvalid, m_axi_arready;
    logic        m_axi_awvalid, m_axi_awready;
    logic [AXI_DWIDTH-1:0] m_axi_wdata, m_axi_rdata;
    logic        m_axi_wvalid, m_axi_wready, m_axi_wlast;
    logic        m_axi_rvalid, m_axi_rready, m_axi_rlast;
    logic        m_axi_bvalid, m_axi_bready;
    
    // Tín hiệu nội bộ (Dành cho SRAM Port B - Mạch MAC mô phỏng)
    logic mac_ping_en, mac_ping_we;
    logic [SRAM_AWIDTH-1:0] mac_ping_addr;
    logic [AXI_DWIDTH-1:0]  mac_ping_wdata, mac_ping_rdata;

    logic mac_pong_en, mac_pong_we;
    logic [SRAM_AWIDTH-1:0] mac_pong_addr;
    logic [AXI_DWIDTH-1:0]  mac_pong_wdata, mac_pong_rdata;

    // Các tín hiệu kết nối Arbiter và SRAM
    logic ping_we_o, pong_we_o;
    logic [SRAM_AWIDTH-1:0] ping_addr_o, pong_addr_o;
    logic [AXI_DWIDTH-1:0] ping_wdata_o, pong_wdata_o;
    logic [AXI_DWIDTH-1:0] ping_rdata_i, pong_rdata_i;

    // Các tín hiệu WGT (Không test trong bài này, gán tĩnh)
    logic wgt_we_o;
    logic [SRAM_AWIDTH-1:0] wgt_addr_o;
    logic [AXI_DWIDTH-1:0] wgt_wdata_o, wgt_rdata_i;
    assign wgt_rdata_i = '0;

    // ==========================================
    // KHỞI TẠO DUT (Design Under Test)
    // ==========================================
    global_arbiter #(
        .AXI_AWIDTH(AXI_AWIDTH),
        .AXI_DWIDTH(AXI_DWIDTH),
        .SRAM_AWIDTH(SRAM_AWIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        // AXI-Lite
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),   .s_axi_wvalid(s_axi_wvalid),   .s_axi_wready(s_axi_wready),
        .s_axi_bready(s_axi_bready), .s_axi_bvalid(s_axi_bvalid),
        // AXI-Full
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),   .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready), .m_axi_rlast(m_axi_rlast),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),   .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wlast(m_axi_wlast),   .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        // SRAM Ports
        .wgt_we_o(wgt_we_o), .wgt_addr_o(wgt_addr_o), .wgt_wdata_o(wgt_wdata_o), .wgt_rdata_i(wgt_rdata_i),
        .ping_we_o(ping_we_o), .ping_addr_o(ping_addr_o), .ping_wdata_o(ping_wdata_o), .ping_rdata_i(ping_rdata_i),
        .pong_we_o(pong_we_o), .pong_addr_o(pong_addr_o), .pong_wdata_o(pong_wdata_o), .pong_rdata_i(pong_rdata_i)
    );

    // ==========================================
    // KHỞI TẠO BỘ NHỚ PING / PONG (SRAM TDP)
    // ==========================================
    // [GIẢNG BÀI] Port A nối với DMA (ping_we_o, ping_addr_o...)
    // Port B nối với mạch test ảo (mac_ping_en...) để ta đọc thử.
    sram_tdp #(.DWIDTH(64), .AWIDTH(11)) ping_bank (
        .clk(clk),
        .ena(1'b1), .wea(ping_we_o), .addra(ping_addr_o), .dina(ping_wdata_o), .douta(ping_rdata_i),
        .enb(mac_ping_en), .web(mac_ping_we), .addrb(mac_ping_addr), .dinb(mac_ping_wdata), .doutb(mac_ping_rdata)
    );

    sram_tdp #(.DWIDTH(64), .AWIDTH(11)) pong_bank (
        .clk(clk),
        .ena(1'b1), .wea(pong_we_o), .addra(pong_addr_o), .dina(pong_wdata_o), .douta(pong_rdata_i),
        .enb(mac_pong_en), .web(mac_pong_we), .addrb(mac_pong_addr), .dinb(mac_pong_wdata), .doutb(mac_pong_rdata)
    );

    // ==========================================
    // CLOCK & RESET
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // TASKS AXI-LITE (Đẩy lệnh vào FIFO)
    // ==========================================
    task axi_lite_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_wdata   <= data;
            s_axi_awvalid <= 1'b1;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;
            while(!(s_axi_awready && s_axi_wready)) @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            while(!s_axi_bvalid) @(posedge clk);
            s_axi_bready  <= 1'b0;
        end
    endtask

    task send_instruction(input [63:0] inst);
        begin
            axi_lite_write(32'h0000_0004, inst[63:32]);
            axi_lite_write(32'h0000_0000, inst[31:0]);
        end
    endtask

    // ==========================================
    // DATA SCOREBOARD (Mock DDR)
    // ==========================================
    // [GIẢNG BÀI] Mảng nhớ này đóng vai trò như DDR thật để AXI-Full đọc/ghi
    logic [63:0] mock_ddr [0:2047];

    initial begin
        // Phản hồi luồng ĐỌC (DDR -> FPGA)
        m_axi_arready <= 1'b0;
        m_axi_rvalid  <= 1'b0;
        m_axi_rlast   <= 1'b0;
        
        forever begin
            m_axi_arready <= 1'b1;
            @(posedge clk);
            if (m_axi_arvalid) begin
                logic [AXI_AWIDTH-1:0] start_addr = m_axi_araddr;
                integer len = m_axi_arlen + 1;
                m_axi_arready <= 1'b0;
                
                // Trả dữ liệu từ Mock DDR
                for (integer i = 0; i < len; i = i + 1) begin
                    m_axi_rvalid <= 1'b1;
                    // Lấy địa chỉ word (chia 8 vì 64-bit)
                    m_axi_rdata  <= mock_ddr[(start_addr / 8) + i]; 
                    m_axi_rlast  <= (i == len - 1) ? 1'b1 : 1'b0;
                    while(1) begin
                        @(posedge clk);
                        if (m_axi_rready) break;
                    end
                end
                m_axi_rvalid <= 1'b0;
                m_axi_rlast  <= 1'b0;
            end
        end
    end

    // ==========================================
    // MAIN TEST FLOW
    // ==========================================
    initial begin
        // Reset hệ thống
        rst_n = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_bready = 0;
        mac_ping_en = 0; mac_ping_we = 0;
        mac_pong_en = 0; mac_pong_we = 0;
        
        // Khởi tạo dữ liệu mẫu trên Mock DDR (Địa chỉ 0x100 -> word 32)
        mock_ddr[32] = 64'h1111_2222_3333_4444;
        mock_ddr[33] = 64'h5555_6666_7777_8888;

        #20 rst_n = 1;
        #50;

        $display("==================================================");
        $display("   BẮT ĐẦU TEST SỰ TÍCH HỢP SRAM PING/PONG");
        $display("==================================================");

        // -----------------------------------------------------------
        // TEST CASE 1: DMA nạp ảnh IFM (từ Mock DDR) vào Ping Bank
        // -----------------------------------------------------------
        $display("\n[TC1] Gọi lệnh OP_LOAD_IFM nạp 16 byte từ DDR (0x100) vào Ping...");
        // Cấu hình địa chỉ IFM trên DDR = 0x100 (Sẽ truyền word 32, 33)
        // OP_SET_ADDR (Opcode=1, Type=00 -> IFM)
        send_instruction({4'h1, 2'b00, 18'd0, 40'h0000_000100});
        
        // Phát lệnh OP_LOAD_IFM (Opcode=A, Bytes=16)
        send_instruction({4'hA, 28'd0, 32'd16});

        // Chờ DMA xử lý xong (dma_req_o phát ra, sau đó chờ dma_busy_o)
        // Vì tb chưa xuất trực tiếp dma_busy_o ra ngoai, ta sẽ chờ 1 khoảng thời gian đủ lâu
        #500; 

        // [SCOREBOARD CHECK] Kiểm tra xem Ping Bank có chứa đúng 16 byte không!
        $display("[SCOREBOARD] Đọc trực tiếp từ Port B của Ping SRAM để kiểm chứng...");
        
        mac_ping_en = 1;
        mac_ping_we = 0;
        mac_ping_addr = 0; // Đọc Word 0
        @(posedge clk);
        @(posedge clk); // Đợi 1 nhịp vì BRAM trễ 1 clock
        if (mac_ping_rdata == 64'h1111_2222_3333_4444) 
            $display("   [PASS] Word 0 khớp: %h", mac_ping_rdata);
        else 
            $display("   [FAIL] Word 0 sai: %h", mac_ping_rdata);

        mac_ping_addr = 1; // Đọc Word 1
        @(posedge clk);
        @(posedge clk);
        if (mac_ping_rdata == 64'h5555_6666_7777_8888) 
            $display("   [PASS] Word 1 khớp: %h", mac_ping_rdata);
        else 
            $display("   [FAIL] Word 1 sai: %h", mac_ping_rdata);
        
        mac_ping_en = 0;

        $display("\n==================================================");
        $display("   TEST HOÀN TẤT");
        $display("==================================================");
        $finish;
    end

endmodule
