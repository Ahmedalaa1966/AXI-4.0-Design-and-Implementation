module axi_top #(
    parameter ADDR_WIDTH = 32 ,
    parameter DATA_WIDTH = 32 ,
    parameter ID_WIDTH   = 4  ,           // transaction ID width, threaded through master + slave
    parameter FIFO_DEPTH = 16 ,
    parameter OUT_DEPTH  = 2  ,           // number of outstanding transactions supported by master's AND slave's AW/AR/W/B queues
    parameter MEM_DEPTH  = 256
) (

    input  logic                          aclk                ,
    input  logic                          aresetn             ,

    // user-facing write side (into the master)
    input  logic                          start_wr            ,
    input  logic [ADDR_WIDTH-1:0]         wr_addr             ,
    input  logic [7:0]                    wr_len              ,
    input  logic [1:0]                    wr_burst            ,
    input  logic [2:0]                    wr_size             ,
    input  logic [ID_WIDTH-1:0]           wr_id               ,
    output logic                          wr_aw_fifo_full     ,
    input  logic                          wr_push             ,
    input  logic [DATA_WIDTH-1:0]         wr_push_data        ,
    output logic                          wr_fifo_full        ,
    output logic                          tx_done             ,
    output logic [ID_WIDTH-1:0]           tx_done_id          ,
    output logic [1:0]                    tx_resp             ,
    output logic [$clog2(OUT_DEPTH+1)-1:0] wr_outstanding_cnt ,

    // user-facing read side (into the master)
    input  logic                          start_rd            ,
    input  logic [ADDR_WIDTH-1:0]         rd_addr             ,
    input  logic [7:0]                    rd_len              ,
    input  logic [1:0]                    rd_burst            ,
    input  logic [2:0]                    rd_size             ,
    input  logic [ID_WIDTH-1:0]           rd_id               ,
    output logic                          rd_ar_fifo_full     ,
    input  logic                          rd_pop              ,
    output logic [DATA_WIDTH-1:0]         rd_pop_data         ,
    output logic                          rd_fifo_empty       ,
    output logic                          rx_done             ,
    output logic [ID_WIDTH-1:0]           rx_done_id
);

    // AXI wires connecting master <-> slave
    logic [ADDR_WIDTH-1:0]    awaddr  ;
    logic [7:0]               awlen   ;
    logic [1:0]               awburst ;
    logic [2:0]               awsize  ;
    logic [ID_WIDTH-1:0]      awid    ;
    logic                     awvalid ;
    logic                     awready ;

    logic [DATA_WIDTH-1:0]   wdata    ;
    logic [DATA_WIDTH/8-1:0] wstrb    ;
    logic                     wlast   ;
    logic                     wvalid  ;
    logic                     wready  ;

    logic [1:0]               bresp   ;
    logic [ID_WIDTH-1:0]      bid     ;
    logic                     bvalid  ;
    logic                     bready  ;

    logic [ADDR_WIDTH-1:0]   araddr   ;
    logic [7:0]               arlen   ;
    logic [1:0]               arburst ;
    logic [2:0]               arsize  ;
    logic [ID_WIDTH-1:0]      arid    ;
    logic                     arvalid ;
    logic                     arready ;

    logic [DATA_WIDTH-1:0]    rdata   ;
    logic [1:0]               rresp   ;
    logic                     rlast   ;
    logic [ID_WIDTH-1:0]      rid     ;
    logic                     rvalid  ;
    logic                     rready  ;


    // ---------------- Manager ----------------
    axi_master_top #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH), .OUT_DEPTH(OUT_DEPTH)
    ) u_master (
        .aclk           (aclk)                    ,
        .aresetn        (aresetn)                 ,
        .awaddr         (awaddr)                  ,
        .awlen          (awlen)                   ,
        .awburst        (awburst)                 ,
        .awsize         (awsize)                  ,
        .awid           (awid)                    ,
        .awvalid        (awvalid)                 ,
        .awready        (awready)                 ,
        .wdata          (wdata)                   ,
        .wstrb          (wstrb)                   ,
        .wlast          (wlast)                   ,
        .wvalid         (wvalid)                  ,
        .wready         (wready)                  ,
        .bresp          (bresp)                   ,
        .bid            (bid)                     ,
        .bvalid         (bvalid)                  ,
        .bready         (bready)                  ,
        .araddr         (araddr)                  ,
        .arlen          (arlen)                   ,
        .arburst        (arburst)                 ,
        .arsize         (arsize)                  ,
        .arid           (arid)                    ,
        .arvalid        (arvalid)                 ,
        .arready        (arready)                 ,
        .rdata          (rdata)                   ,
        .rresp          (rresp)                   ,
        .rlast          (rlast)                   ,
        .rid            (rid)                     ,
        .rvalid         (rvalid)                  ,
        .rready         (rready)                  ,
        .start_wr       (start_wr)                ,
        .wr_addr        (wr_addr)                 ,
        .wr_len         (wr_len)                  ,
        .wr_burst       (wr_burst)                ,
        .wr_size        (wr_size)                 ,
        .wr_id          (wr_id)                   ,
        .wr_aw_fifo_full(wr_aw_fifo_full)         ,
        .wr_push        (wr_push)                 ,
        .wr_push_data   (wr_push_data)            ,
        .wr_fifo_full   (wr_fifo_full)            ,
        .tx_done        (tx_done)                 ,
        .tx_done_id     (tx_done_id)              ,
        .tx_resp        (tx_resp)                 ,
        .wr_outstanding_cnt(wr_outstanding_cnt)   ,
        .start_rd       (start_rd)                ,
        .rd_addr        (rd_addr)                 ,
        .rd_len         (rd_len)                  ,
        .rd_burst       (rd_burst)                ,
        .rd_size        (rd_size)                 ,
        .rd_id          (rd_id)                   ,
        .rd_ar_fifo_full(rd_ar_fifo_full)         ,
        .rd_pop         (rd_pop)                  ,
        .rd_pop_data    (rd_pop_data)             ,
        .rd_fifo_empty  (rd_fifo_empty)           ,
        .rx_done        (rx_done)                 ,
        .rx_done_id     (rx_done_id)
    );

    // ---------------- Subordinate ----------------
    axi_slave_top #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .OUT_DEPTH(OUT_DEPTH), .MEM_DEPTH(MEM_DEPTH)                          
    ) u_slave (
        .aclk(aclk)        ,
        .aresetn(aresetn)  ,
        .awaddr(awaddr)    ,
        .awlen(awlen)      ,
        .awburst(awburst)  ,
        .awsize(awsize)    ,
        .awid(awid)        ,
        .awvalid(awvalid)  ,
        .awready(awready)  ,
        .wdata(wdata)      ,
        .wstrb(wstrb)      ,
        .wlast(wlast)      ,
        .wvalid(wvalid)    ,
        .wready(wready)    ,
        .bresp(bresp)      ,
        .bid(bid)          ,
        .bvalid(bvalid)    ,
        .bready(bready)    ,
        .araddr(araddr)    ,
        .arlen(arlen)      ,
        .arburst(arburst)  ,
        .arsize(arsize)    ,
        .arid(arid)        ,
        .arvalid(arvalid)  ,
        .arready(arready)  ,
        .rdata(rdata)      ,
        .rresp(rresp)      ,
        .rlast(rlast)      ,
        .rid(rid)          ,
        .rvalid(rvalid)    ,
        .rready(rready)
    );

endmodule