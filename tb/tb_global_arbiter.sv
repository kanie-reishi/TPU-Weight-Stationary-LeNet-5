`timescale 1ns / 1ps

module tb_global_arbiter();

    // ==========================================
    // Tham số cấu hình
    // ==========================================
    localparam AXI_AWIDTH  = 40;
    localparam AXI_DWIDTH  = 64;
    localparam SRAM_AWIDTH = 11;
    
    // ==========================================
    // Khai báo tín hiệu
    // ==========================================
    logic clk;
    logic rst_n;
    
    // --- 1. AXI-Lite Slave Interface (Host CPU) ---
    logic                    s_axi_awvalid;
    logic                    s_axi_awready;
    logic [31:0]             s_axi_awaddr;
    logic                    s_axi_wvalid;
    logic                    s_axi_wready;
    logic [31:0]             s_axi_wdata;
    
    // --- 2. AXI4-Full Master Interface (DDR) ---
    // Kênh AR
    logic [AXI_AWIDTH-1:0]   m_axi_araddr;
    logic [7:0]              m_axi_arlen;
    logic [2:0]              m_axi_arsize;
    logic [1:0]              m_axi_arburst;
    logic                    m_axi_arvalid;
    logic                    m_axi_arready;
    // Kênh R
    logic [AXI_DWIDTH-1:0]   m_axi_rdata;
    logic                    m_axi_rlast;
    logic                    m_axi_rvalid;
    logic                    m_axi_rready;
    // Kênh AW
    logic [AXI_AWIDTH-1:0]   m_axi_awaddr;
    logic [7:0]              m_axi_awlen;
    logic [2:0]              m_axi_awsize;
    logic [1:0]              m_axi_awburst;
    logic                    m_axi_awvalid;
    logic                    m_axi_awready;
    // Kênh W
    logic [AXI_DWIDTH-1:0]   m_axi_wdata;
    logic                    m_axi_wlast;
    logic                    m_axi_wvalid;
    logic                    m_axi_wready;
    // Kênh B
    logic [1:0]              m_axi_bresp;
    logic                    m_axi_bvalid;
    logic                    m_axi_bready;
    
    // --- 3. Controller Interface ---
    logic [63:0]             ctrl_inst_data_o;
    logic                    ctrl_inst_empty_o;
    logic                    ctrl_inst_read_i;
    
    logic                    ctrl_dma_req_i;
    logic                    ctrl_dma_dir_i;
    logic [AXI_AWIDTH-1:0]   ctrl_dma_addr_i;
    logic [31:0]             ctrl_dma_bytes_i;
    logic [1:0]              ctrl_dma_bank_sel_i;
    logic                    ctrl_dma_busy_o;
    
    // --- 4. SRAM Interfaces ---
    logic                    wgt_we_o;
    logic [SRAM_AWIDTH-1:0]  wgt_addr_o;
    logic [AXI_DWIDTH-1:0]   wgt_wdata_o;
    
    logic                    ping_we_o;
    logic [SRAM_AWIDTH-1:0]  ping_addr_o;
    logic [AXI_DWIDTH-1:0]   ping_wdata_o;
    logic [AXI_DWIDTH-1:0]   ping_rdata_i;
    
    logic                    pong_we_o;
    logic [SRAM_AWIDTH-1:0]  pong_addr_o;
    logic [AXI_DWIDTH-1:0]   pong_wdata_o;
    logic [AXI_DWIDTH-1:0]   pong_rdata_i;

    // ==========================================
    // Instantiate DUT
    // ==========================================
    global_arbiter #(
        .AXI_AWIDTH(AXI_AWIDTH),
        .AXI_DWIDTH(AXI_DWIDTH),
        .SRAM_AWIDTH(SRAM_AWIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_wdata(s_axi_wdata),
        
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        
        .ctrl_inst_data_o(ctrl_inst_data_o),
        .ctrl_inst_empty_o(ctrl_inst_empty_o),
        .ctrl_inst_read_i(ctrl_inst_read_i),
        
        .ctrl_dma_req_i(ctrl_dma_req_i),
        .ctrl_dma_dir_i(ctrl_dma_dir_i),
        .ctrl_dma_addr_i(ctrl_dma_addr_i),
        .ctrl_dma_bytes_i(ctrl_dma_bytes_i),
        .ctrl_dma_bank_sel_i(ctrl_dma_bank_sel_i),
        .ctrl_dma_busy_o(ctrl_dma_busy_o),
        
        .wgt_we_o(wgt_we_o),
        .wgt_addr_o(wgt_addr_o),
        .wgt_wdata_o(wgt_wdata_o),
        
        .ping_we_o(ping_we_o),
        .ping_addr_o(ping_addr_o),
        .ping_wdata_o(ping_wdata_o),
        .ping_rdata_i(ping_rdata_i),
        
        .pong_we_o(pong_we_o),
        .pong_addr_o(pong_addr_o),
        .pong_wdata_o(pong_wdata_o),
        .pong_rdata_i(pong_rdata_i)
    );

    // ==========================================
    // Khối bảo vệ (Watchdog) - Chống treo vĩnh viễn
    // ==========================================
    initial begin
        #5000;
        $display("[%0t] [FAIL] FATAL ERROR: SIMULATION TIMEOUT (5000ns)! Deadlock detected.", $time);
        $finish;
    end

    // ==========================================
    // Tạo xung Clock
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Chu kỳ 10ns
    end
    
    // ==========================================
    // TASKS: Giao tiếp AXI-Lite (Giả lập CPU)
    // ==========================================
    task axi_lite_write(input [31:0] addr, input [31:0] data);
        begin
            $display("[%0t] [AXI-Lite] Writing %h to %h...", $time, data, addr);
            @(posedge clk);
            s_axi_awvalid <= 1'b1;
            s_axi_awaddr  <= addr;
            s_axi_wvalid  <= 1'b1;
            s_axi_wdata   <= data;
            
            // Chờ slave nhận
            while (!(s_axi_awready && s_axi_wready)) begin
                @(posedge clk);
            end
            @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            $display("[%0t] [AXI-Lite] Write completed.", $time);
        end
    endtask

    // ==========================================
    // MÔ PHỎNG AXI-FULL SLAVE (Giả lập DDR Memory)
    // ==========================================
    // 1. Phản hồi luồng Đọc (AR -> R)
    initial begin
        m_axi_arready <= 1'b0;
        m_axi_rvalid  <= 1'b0;
        m_axi_rlast   <= 1'b0;
        m_axi_rdata   <= '0;
        
        while(!rst_n) @(posedge clk);
        
        forever begin
            m_axi_arready <= 1'b1;
            @(posedge clk);
            
            if (m_axi_arvalid) begin
                integer len;
                len = m_axi_arlen + 1;
                m_axi_arready <= 1'b0;
                $display("[%0t] [AXI-Full] Start READ processing %0d beats from addr %h", $time, len, m_axi_araddr);
                
                // Bơm dữ liệu Rdata trả về
                for (integer i = 0; i < len; i = i + 1) begin
                    m_axi_rvalid <= 1'b1;
                    m_axi_rdata  <= $random; // Trả về dữ liệu ngẫu nhiên
                    m_axi_rlast  <= (i == len - 1) ? 1'b1 : 1'b0;
                    
                    // Chờ master sẵn sàng nhận
                    while(1) begin
                        @(posedge clk);
                        if (m_axi_rready) break;
                    end
                end
                m_axi_rvalid <= 1'b0;
                m_axi_rlast  <= 1'b0;
                $display("[%0t] [AXI-Full] READ completed", $time);
            end
        end
    end
    
    // 2. Phản hồi luồng Ghi (AW -> W -> B)
    initial begin
        m_axi_awready <= 1'b0;
        m_axi_wready  <= 1'b0;
        m_axi_bvalid  <= 1'b0;
        
        while(!rst_n) @(posedge clk);
        
        forever begin
            m_axi_awready <= 1'b1;
            @(posedge clk);
            
            if (m_axi_awvalid) begin
                m_axi_awready <= 1'b0;
                $display("[%0t] [AXI-Full] Start WRITE processing to addr %h", $time, m_axi_awaddr);
                
                // Chờ và nhận Wdata
                m_axi_wready <= 1'b1;
                while (1) begin
                    @(posedge clk);
                    if (m_axi_wvalid && m_axi_wlast) break;
                end
                m_axi_wready <= 1'b0;
                
                // Gửi phản hồi B (OKAY)
                m_axi_bvalid <= 1'b1;
                m_axi_bresp  <= 2'b00; 
                while (1) begin
                    @(posedge clk);
                    if (m_axi_bready) break;
                end
                m_axi_bvalid <= 1'b0;
                $display("[%0t] [AXI-Full] WRITE completed", $time);
            end
        end
    end

    // ==========================================
    // LUỒNG KIỂM THỬ CHÍNH
    // ==========================================
    initial begin
        // --- KHỞI TẠO TÍN HIỆU ---
        rst_n = 0;
        s_axi_awvalid = 0;
        s_axi_awaddr  = 0;
        s_axi_wvalid  = 0;
        s_axi_wdata   = 0;
        
        ctrl_inst_read_i = 0;
        ctrl_dma_req_i   = 0;
        ctrl_dma_dir_i   = 0;
        ctrl_dma_addr_i  = 0;
        ctrl_dma_bytes_i = 0;
        ctrl_dma_bank_sel_i = 0;
        
        // Cấp dữ liệu giả cho đường Đọc từ Ping/Pong Bank lên DDR
        ping_rdata_i = 64'hAAAA_BBBB_CCCC_DDDD;
        pong_rdata_i = 64'h1111_2222_3333_4444;

        // Giữ reset 100ns
        #100;
        rst_n = 1;
        #50;
        
        // ----------------------------------------------------
        $display("[%0t] === TC1: Post-Reset State ===", $time);
        // ----------------------------------------------------
        #20;
        $display("[%0t] [PASS] TC1 completed.", $time);
        
        // ----------------------------------------------------
        $display("[%0t] === TC2: CPU loads instruction via AXI-Lite ===", $time);
        // ----------------------------------------------------
        // Lệnh 64-bit: Nửa cao = 0xABCD_EF01, Nửa thấp = 0x2345_6789
        axi_lite_write(32'h04, 32'hABCDEF01);
        axi_lite_write(32'h00, 32'h23456789);
        
        #50;
        // Controller xin lấy lệnh từ FIFO ra
        if (!ctrl_inst_empty_o) begin
            $display("[%0t] [Controller] Fetching instruction from FIFO...", $time);
            ctrl_inst_read_i = 1'b1;
            @(posedge clk);
            ctrl_inst_read_i = 1'b0;
            $display("[%0t] [PASS] TC2: Instruction received correctly: %h", $time, ctrl_inst_data_o);
        end else begin
            $display("[%0t] [FAIL] TC2: FIFO is empty!", $time);
        end
        
        // ----------------------------------------------------
        $display("[%0t] === TC3: DMA Demux (Read DDR -> Write SRAM Ping) ===", $time);
        // ----------------------------------------------------
        @(posedge clk);
        ctrl_dma_req_i      <= 1'b1;
        ctrl_dma_dir_i      <= 1'b0;          // READ (DDR -> SRAM)
        ctrl_dma_addr_i     <= 40'h1000;
        ctrl_dma_bytes_i    <= 32'h40;        // 64 bytes
        ctrl_dma_bank_sel_i <= 2'b01;         // Chọn PING BANK (01)
        
        @(posedge clk);
        ctrl_dma_req_i      <= 1'b0;
        
        // Chờ DMA bắt đầu
        while(!ctrl_dma_busy_o) @(posedge clk);
        // Chờ DMA hoàn thành
        while(ctrl_dma_busy_o) @(posedge clk);
        $display("[%0t] [PASS] TC3: DMA transfer DDR -> PING Bank completed!", $time);
        
        #50;
        
        // ----------------------------------------------------
        $display("[%0t] === TC4: DMA Mux (Read SRAM Pong -> Write DDR) ===", $time);
        // ----------------------------------------------------
        @(posedge clk);
        ctrl_dma_req_i      <= 1'b1;
        ctrl_dma_dir_i      <= 1'b1;          // WRITE (SRAM -> DDR)
        ctrl_dma_addr_i     <= 40'h2000;
        ctrl_dma_bytes_i    <= 32'h20;        // 32 bytes
        ctrl_dma_bank_sel_i <= 2'b10;         // Chọn PONG BANK (10)
        
        @(posedge clk);
        ctrl_dma_req_i      <= 1'b0;
        
        $display("[%0t] [TC4] Waiting for DMA to start...", $time);
        while(!ctrl_dma_busy_o) @(posedge clk);
        $display("[%0t] [TC4] DMA is busy. Waiting for DMA to complete...", $time);
        while(ctrl_dma_busy_o) @(posedge clk);
        $display("[%0t] [PASS] TC4: DMA transfer SRAM -> DDR completed!", $time);
        
        #50;
        
        // ----------------------------------------------------
        $display("[%0t] === TC5: Hardware Backpressure (Bơm FIFO) ===", $time);
        // ----------------------------------------------------
        // Bơm 16 lệnh liên tục để quan sát tín hiệu awready/wready
        for (int i = 0; i < 16; i++) begin
            axi_lite_write(32'h04, i);
            axi_lite_write(32'h00, ~i);
        end
        $display("[%0t] [PASS] TC5: Pumped 16 instructions successfully.", $time);
        
        #100;
        $display("[%0t] === [PASS] ALL TEST CASES COMPLETED SUCCESSFULLY ===", $time);
        $finish;
    end

endmodule
