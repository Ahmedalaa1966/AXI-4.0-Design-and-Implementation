module axi_top_1m3s #(
    parameter ADDR_WIDTH = 32 ,
    parameter DATA_WIDTH = 32 ,
    parameter ID_WIDTH   = 4  ,
    parameter FIFO_DEPTH = 16 ,
    parameter MEM_DEPTH  = 256 ,
    parameter OUT_DEPTH  = 2  ,   // number of outstanding transactions (must match master/slave OUT_DEPTH)
    parameter NUM_SLAVES = 3
) (
    input  logic aclk    ,
    input  logic aresetn ,

    // ... same user-facing write/read ports as axi_top ...
    input  logic                           start_wr           ,
    input  logic [ADDR_WIDTH-1:0]          wr_addr            ,
    input  logic [7:0]                     wr_len             ,
    input  logic [1:0]                     wr_burst           ,
    input  logic [2:0]                     wr_size            ,
    input  logic [ID_WIDTH-1:0]            wr_id              ,
    output logic                           wr_aw_fifo_full    ,
    input  logic                           wr_push            ,
    input  logic [DATA_WIDTH-1:0]          wr_push_data       ,
    output logic                           wr_fifo_full       ,
    output logic                           tx_done            ,
    output logic [ID_WIDTH-1:0]            tx_done_id         ,
    output logic [1:0]                     tx_resp            ,
    output logic [$clog2(OUT_DEPTH+1)-1:0] wr_outstanding_cnt ,

    input  logic                           start_rd           ,
    input  logic [ADDR_WIDTH-1:0]          rd_addr            ,
    input  logic [7:0]                     rd_len             ,
    input  logic [1:0]                     rd_burst           ,
    input  logic [2:0]                     rd_size            ,
    input  logic [ID_WIDTH-1:0]            rd_id              ,
    output logic                           rd_ar_fifo_full    ,
    input  logic                           rd_pop             ,
    output logic [DATA_WIDTH-1:0]          rd_pop_data        ,
    output logic                           rd_fifo_empty      ,
    output logic                           rx_done            ,
    output logic [ID_WIDTH-1:0]            rx_done_id
);

    // ---------------- slave address map - defined HERE, at the top level ----------------
    logic [ADDR_WIDTH-1:0] base_addr   [0:NUM_SLAVES-1] ;
    logic [ADDR_WIDTH-1:0] region_size [0:NUM_SLAVES-1] ;

    assign base_addr[0]   = 32'h0000_0000 ;   // slave 0: 0x0000_0000 - 0x0000_0FFF
    assign region_size[0] = 32'h0000_1000 ;   // 4KB

    assign base_addr[1]   = 32'h0000_1000 ;   // slave 1: 0x0000_1000 - 0x0000_1FFF
    assign region_size[1] = 32'h0000_1000 ;   // 4KB

    assign base_addr[2]   = 32'h0000_2000 ;   // slave 2: 0x0000_2000 - 0x0000_2FFF
    assign region_size[2] = 32'h0000_1000 ;   // 4KB


    // AXI wires: master <-> interconnect
    logic [ADDR_WIDTH-1:0]    m_awaddr   ; 
    logic [7:0]               m_awlen    ; 
    logic [1:0]               m_awburst  ; 
    logic [2:0]               m_awsize   ;
    logic [ID_WIDTH-1:0]      m_awid     ;
    logic                     m_awvalid  ; 
    logic                     m_awready  ;
    logic [DATA_WIDTH-1:0]    m_wdata    ;
    logic [DATA_WIDTH/8-1:0]  m_wstrb    ;
    logic                     m_wlast    ;
    logic                     m_wvalid   ; 
    logic                     m_wready   ;
    logic [1:0]               m_bresp    ; 
    logic [ID_WIDTH-1:0]      m_bid      ;
    logic                     m_bvalid   ;
    logic                     m_bready   ;
    logic [ADDR_WIDTH-1:0]    m_araddr   ;
    logic [7:0]               m_arlen    ;  
    logic [1:0]               m_arburst  ; 
    logic [2:0]               m_arsize   ;
    logic [ID_WIDTH-1:0]      m_arid     ;
    logic                     m_arvalid  ;
    logic                     m_arready  ;
    logic [DATA_WIDTH-1:0]    m_rdata    ; 
    logic [1:0]               m_rresp    ; 
    logic                     m_rlast    ;
    logic [ID_WIDTH-1:0]      m_rid      ;
    logic                     m_rvalid   ;  
    logic                     m_rready   ;

    // AXI wires: interconnect <-> slaves (arrayed)
    logic [ADDR_WIDTH-1:0]   s_awaddr  [0:NUM_SLAVES-1] ; 
    logic [7:0]              s_awlen   [0:NUM_SLAVES-1] ;
    logic [1:0]              s_awburst [0:NUM_SLAVES-1] ; 
    logic [2:0]              s_awsize  [0:NUM_SLAVES-1] ;
    logic [ID_WIDTH-1:0]     s_awid    [0:NUM_SLAVES-1] ;
    logic                    s_awvalid [0:NUM_SLAVES-1] ; 
    logic                    s_awready [0:NUM_SLAVES-1] ;
    logic [DATA_WIDTH-1:0]   s_wdata   [0:NUM_SLAVES-1] ; 
    logic [DATA_WIDTH/8-1:0] s_wstrb   [0:NUM_SLAVES-1] ;
    logic                    s_wlast   [0:NUM_SLAVES-1] ; 
    logic                    s_wvalid  [0:NUM_SLAVES-1] ; 
    logic                    s_wready  [0:NUM_SLAVES-1] ;
    logic [1:0]              s_bresp   [0:NUM_SLAVES-1] ; 
    logic [ID_WIDTH-1:0]     s_bid     [0:NUM_SLAVES-1] ;
    logic                    s_bvalid  [0:NUM_SLAVES-1] ; 
    logic                    s_bready  [0:NUM_SLAVES-1] ;
    logic [ADDR_WIDTH-1:0]   s_araddr  [0:NUM_SLAVES-1] ; 
    logic [7:0]              s_arlen   [0:NUM_SLAVES-1] ;
    logic [1:0]              s_arburst [0:NUM_SLAVES-1] ; 
    logic [2:0]              s_arsize  [0:NUM_SLAVES-1] ;
    logic [ID_WIDTH-1:0]     s_arid    [0:NUM_SLAVES-1] ;
    logic                    s_arvalid [0:NUM_SLAVES-1] ; 
    logic                    s_arready [0:NUM_SLAVES-1] ;
    logic [DATA_WIDTH-1:0]   s_rdata   [0:NUM_SLAVES-1] ; 
    logic [1:0]              s_rresp   [0:NUM_SLAVES-1] ;
    logic                    s_rlast   [0:NUM_SLAVES-1] ; 
    logic [ID_WIDTH-1:0]     s_rid     [0:NUM_SLAVES-1] ;
    logic                    s_rvalid  [0:NUM_SLAVES-1] ; 
    logic                    s_rready  [0:NUM_SLAVES-1] ;


    // ---------------- Manager ----------------
    axi_master_top #(
        .ADDR_WIDTH (ADDR_WIDTH) ,
        .DATA_WIDTH (DATA_WIDTH) ,
        .ID_WIDTH   (ID_WIDTH)   ,
        .FIFO_DEPTH (FIFO_DEPTH) ,
        .OUT_DEPTH  (OUT_DEPTH)
    ) u_master (
        .aclk(aclk), 
        .aresetn(aresetn),
        .awaddr(m_awaddr), 
        .awlen(m_awlen), 
        .awburst(m_awburst), 
        .awsize(m_awsize), 
        .awid(m_awid),
        .awvalid(m_awvalid), 
        .awready(m_awready),
        .wdata(m_wdata), 
        .wstrb(m_wstrb), 
        .wlast(m_wlast), 
        .wvalid(m_wvalid), 
        .wready(m_wready),
        .bresp(m_bresp), 
        .bid(m_bid),
        .bvalid(m_bvalid), 
        .bready(m_bready),
        .araddr(m_araddr), 
        .arlen(m_arlen), 
        .arburst(m_arburst), 
        .arsize(m_arsize), 
        .arid(m_arid),
        .arvalid(m_arvalid), 
        .arready(m_arready),
        .rdata(m_rdata), 
        .rresp(m_rresp), 
        .rlast(m_rlast), 
        .rid(m_rid),
        .rvalid(m_rvalid), 
        .rready(m_rready),

        .start_wr(start_wr), 
        .wr_addr(wr_addr), 
        .wr_len(wr_len), 
        .wr_burst(wr_burst), 
        .wr_size(wr_size),
        .wr_id(wr_id),
        .wr_aw_fifo_full(wr_aw_fifo_full),
        .wr_push(wr_push), 
        .wr_push_data(wr_push_data), 
        .wr_fifo_full(wr_fifo_full),
        .tx_done(tx_done), 
        .tx_done_id(tx_done_id),
        .tx_resp(tx_resp),
        .wr_outstanding_cnt(wr_outstanding_cnt),

        .start_rd(start_rd), 
        .rd_addr(rd_addr), 
        .rd_len(rd_len), 
        .rd_burst(rd_burst), 
        .rd_size(rd_size),
        .rd_id(rd_id),
        .rd_ar_fifo_full(rd_ar_fifo_full),
        .rd_pop(rd_pop), 
        .rd_pop_data(rd_pop_data), 
        .rd_fifo_empty(rd_fifo_empty),
        .rx_done(rx_done),
        .rx_done_id(rx_done_id)
    );

    // ---------------- Interconnect ----------------
    // NOTE: axi_interconnect must expose matching ID pass-through ports
    // (m_awid/m_arid/m_bid/m_rid on the manager side and s_awid/s_arid/s_bid/s_rid
    // arrays on the subordinate side) for this to elaborate. That module's
    // definition wasn't provided, so its port list is assumed here to mirror
    // the pattern of every other channel signal.
    axi_interconnect #(
        .ADDR_WIDTH (ADDR_WIDTH) ,
        .DATA_WIDTH (DATA_WIDTH) ,
        .ID_WIDTH   (ID_WIDTH)   ,
        .NUM_SLAVES (NUM_SLAVES)
    ) u_interconnect (
        .aclk          (aclk), 
        .aresetn       (aresetn),
        .base_addr     (base_addr), 
        .region_size   (region_size),
        .m_awaddr      (m_awaddr), 
        .m_awlen       (m_awlen), 
        .m_awburst     (m_awburst), 
        .m_awsize      (m_awsize), 
        .m_awid        (m_awid),
        .m_awvalid     (m_awvalid), 
        .m_awready     (m_awready),
        .m_wdata       (m_wdata), 
        .m_wstrb       (m_wstrb), 
        .m_wlast       (m_wlast), 
        .m_wvalid      (m_wvalid), 
        .m_wready      (m_wready),
        .m_bresp       (m_bresp), 
        .m_bid         (m_bid),
        .m_bvalid      (m_bvalid), 
        .m_bready      (m_bready),
        .m_araddr      (m_araddr), 
        .m_arlen       (m_arlen), 
        .m_arburst     (m_arburst), 
        .m_arsize      (m_arsize), 
        .m_arid        (m_arid),
        .m_arvalid     (m_arvalid), 
        .m_arready     (m_arready),
        .m_rdata       (m_rdata), 
        .m_rresp       (m_rresp), 
        .m_rlast       (m_rlast), 
        .m_rid         (m_rid),
        .m_rvalid      (m_rvalid),
        .m_rready      (m_rready),

        .s_awaddr      (s_awaddr), 
        .s_awlen       (s_awlen), 
        .s_awburst     (s_awburst), 
        .s_awsize      (s_awsize), 
        .s_awid        (s_awid),
        .s_awvalid     (s_awvalid), 
        .s_awready     (s_awready),
        .s_wdata       (s_wdata), 
        .s_wstrb       (s_wstrb), 
        .s_wlast       (s_wlast), 
        .s_wvalid      (s_wvalid), 
        .s_wready      (s_wready),
        .s_bresp       (s_bresp), 
        .s_bid         (s_bid),
        .s_bvalid      (s_bvalid), 
        .s_bready      (s_bready),
        .s_araddr      (s_araddr), 
        .s_arlen       (s_arlen), 
        .s_arburst     (s_arburst), 
        .s_arsize      (s_arsize), 
        .s_arid        (s_arid),
        .s_arvalid     (s_arvalid), 
        .s_arready     (s_arready),
        .s_rdata       (s_rdata), 
        .s_rresp       (s_rresp), 
        .s_rlast       (s_rlast), 
        .s_rid         (s_rid),
        .s_rvalid      (s_rvalid), 
        .s_rready      (s_rready)
    );

    // ---------------- Subordinates ----------------
    genvar g ;
    generate
        for (g = 0; g < NUM_SLAVES; g = g + 1) begin : gen_slaves
            axi_slave_top #(
                .ADDR_WIDTH (ADDR_WIDTH) ,
                .DATA_WIDTH (DATA_WIDTH) ,
                .ID_WIDTH   (ID_WIDTH)   ,
                .OUT_DEPTH  (OUT_DEPTH)  ,
                .MEM_DEPTH  (MEM_DEPTH)
            ) u_slave (
                .aclk(aclk), .aresetn(aresetn),
                .awaddr(s_awaddr[g]), 
                .awlen(s_awlen[g]), 
                .awburst(s_awburst[g]), 
                .awsize(s_awsize[g]), 
                .awid(s_awid[g]),
                .awvalid(s_awvalid[g]), 
                .awready(s_awready[g]),
                .wdata(s_wdata[g]), 
                .wstrb(s_wstrb[g]), 
                .wlast(s_wlast[g]), 
                .wvalid(s_wvalid[g]), 
                .wready(s_wready[g]),
                .bresp(s_bresp[g]), 
                .bid(s_bid[g]),
                .bvalid(s_bvalid[g]), 
                .bready(s_bready[g]),
                .araddr(s_araddr[g]), 
                .arlen(s_arlen[g]), 
                .arburst(s_arburst[g]), 
                .arsize(s_arsize[g]), 
                .arid(s_arid[g]),
                .arvalid(s_arvalid[g]), 
                .arready(s_arready[g]),
                .rdata(s_rdata[g]), 
                .rresp(s_rresp[g]), 
                .rlast(s_rlast[g]), 
                .rid(s_rid[g]),
                .rvalid(s_rvalid[g]), 
                .rready(s_rready[g])
            );
        end
    endgenerate

endmodule