module axi_master_top #(
    parameter ADDR_WIDTH = 32 ,
    parameter DATA_WIDTH = 32 ,
    parameter ID_WIDTH   = 4  ,
    parameter FIFO_DEPTH = 16 ,
    parameter OUT_DEPTH  = 2               // number of outstanding transactions (must match AW/AR/W/B channel DEPTH)
) (
    input  logic                          aclk           ,
    input  logic                          aresetn        ,

    // AXI write address channel
    output logic [ADDR_WIDTH-1:0]         awaddr         ,
    output logic [7:0]                    awlen          ,
    output logic [1:0]                    awburst        ,
    output logic [2:0]                    awsize         ,
    output logic [ID_WIDTH-1:0]           awid           ,
    output logic                          awvalid        ,
    input  logic                          awready        ,

    // AXI write data channel
    output logic [DATA_WIDTH-1:0]         wdata          ,
    output logic [DATA_WIDTH/8-1:0]       wstrb          ,
    output logic                          wlast          ,
    output logic                          wvalid         ,
    input  logic                          wready         ,

    // AXI write response channel
    input  logic [1:0]                    bresp          ,
    input  logic [ID_WIDTH-1:0]           bid            ,
    input  logic                          bvalid         ,
    output logic                          bready         ,

    // AXI read address channel
    output logic [ADDR_WIDTH-1:0]         araddr         ,
    output logic [7:0]                    arlen          ,
    output logic [1:0]                    arburst        ,
    output logic [2:0]                    arsize         ,
    output logic [ID_WIDTH-1:0]           arid           ,
    output logic                          arvalid        ,
    input  logic                          arready        ,

    // AXI read data channel
    input  logic [DATA_WIDTH-1:0]         rdata          ,
    input  logic [1:0]                    rresp          ,
    input  logic                          rlast          ,
    input  logic [ID_WIDTH-1:0]           rid            ,
    input  logic                          rvalid         ,
    output logic                          rready         ,

    // user-facing write side
    input  logic                          start_wr       ,
    input  logic [ADDR_WIDTH-1:0]         wr_addr        ,
    input  logic [7:0]                    wr_len         ,
    input  logic [1:0]                    wr_burst       ,
    input  logic [2:0]                    wr_size        ,
    input  logic [ID_WIDTH-1:0]           wr_id          ,
    output logic                          wr_aw_fifo_full ,
    input  logic                          wr_push        ,
    input  logic [DATA_WIDTH-1:0]         wr_push_data   ,
    output logic                          wr_fifo_full   ,
    output logic                          tx_done        ,
    output logic [ID_WIDTH-1:0]           tx_done_id     ,
    output logic [1:0]                    tx_resp        ,
    output logic [$clog2(OUT_DEPTH+1)-1:0] wr_outstanding_cnt ,

    // user-facing read side
    input  logic                          start_rd       ,
    input  logic [ADDR_WIDTH-1:0]         rd_addr        ,
    input  logic [7:0]                    rd_len         ,
    input  logic [1:0]                    rd_burst       ,
    input  logic [2:0]                    rd_size        ,
    input  logic [ID_WIDTH-1:0]           rd_id          ,
    output logic                          rd_ar_fifo_full ,
    input  logic                          rd_pop         ,
    output logic [DATA_WIDTH-1:0]         rd_pop_data    ,
    output logic                          rd_fifo_empty  ,
    output logic                          rx_done        ,
    output logic [ID_WIDTH-1:0]           rx_done_id
);

    // write-side internal wires
    logic                      awvalid_ready   ;
    logic [7:0]                awlength_w      ;
    logic [1:0]                awburst_w       ;
    logic [2:0]                awsize_w        ;
    logic [ID_WIDTH-1:0]       awid_w          ;           // NEW: ID handed off from aw_ch to w_ch
    logic [DATA_WIDTH-1:0]     wfifo_rd_data   ;
    logic                      wfifo_empty     ;
    logic                      wfifo_rd_en     ;
    logic [7:0]                w_beat_cnt      ;
    logic                      w_beat_cnt_en   ;
    logic                      wlast_done      ;           // CHANGED: now driven by u_w_ch, not a manual assign
    logic [ID_WIDTH-1:0]       wlast_done_id_w ;          // NEW: ID paired with wlast_done, from w_ch's job queue
    logic [ADDR_WIDTH-1:0]     w_beat_addr     ;
    logic [DATA_WIDTH/8-1:0]   wstrb_computed  ;

    // read-side internal wires
    logic                      arvalid_ready ;
    logic [DATA_WIDTH-1:0]     rfifo_wr_data ;
    logic                      rfifo_wr_en   ;
    logic                      rfifo_full    ;


    // ---------------- write address channel ----------------
    axi_master_aw_ch #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH), .DEPTH(OUT_DEPTH)) u_aw_ch (
        .aclk          (aclk)          ,
        .aresetn       (aresetn)       ,
        .awready       (awready)       ,
        .addr_in       (wr_addr)       ,
        .len_in        (wr_len)        ,
        .burst_in      (wr_burst)      ,
        .size_in       (wr_size)       ,
        .id_in         (wr_id)         ,
        .start_tx      (start_wr)      ,
        .awaddr        (awaddr)        ,
        .awlen         (awlen)         ,
        .awburst       (awburst)       ,
        .awsize        (awsize)        ,
        .awid          (awid)          ,
        .awvalid       (awvalid)       ,
        .awvalid_ready (awvalid_ready) ,
        .awlength_out  (awlength_w)    ,
        .awburst_out   (awburst_w)     ,
        .awsize_out    (awsize_w)      ,
        .awid_out      (awid_w)        ,          // CHANGED: was dangling
        .aw_fifo_full  (wr_aw_fifo_full)
    );

    // ---------------- write data fifo ----------------
    axi_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(FIFO_DEPTH)) u_wfifo (
        .aclk    (aclk)    ,
        .aresetn (aresetn) ,
        .wr_en   (wr_push) ,
        .wr_data (wr_push_data) ,
        .rd_en   (wfifo_rd_en)  ,
        .rd_data (wfifo_rd_data) ,
        .full    (wr_fifo_full) ,
        .empty   (wfifo_empty)
    );

    // ---------------- write beat address/counter (WLAST + WSTRB generation) ----------------
    axi_burst_addr_gen #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_w_beat_gen (
        .aclk        (aclk)          ,
        .aresetn     (aresetn)       ,
        .start       (awvalid_ready) ,
        .addr_in     (awaddr)        ,
        .len_in      (awlength_w)    ,
        .burst_in    (awburst_w)     ,
        .size_in     (awsize_w)      ,
        .beat_cnt_en (w_beat_cnt_en) ,
        .addr_out    (w_beat_addr)   ,
        .beat_cnt    (w_beat_cnt)
    );

    // ---------------- write strobe generator ----------------
    axi_wstrb_gen #(.DATA_WIDTH(DATA_WIDTH)) u_wstrb_gen (
        .beat_addr (w_beat_addr)    ,
        .size_in   (awsize_w)       ,
        .wstrb     (wstrb_computed)
    );

    // ---------------- write data channel ----------------
    axi_master_w_ch #(.DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH), .DEPTH(OUT_DEPTH)) u_w_ch (
        .aclk          (aclk)          ,
        .aresetn       (aresetn)       ,
        .wready        (wready)        ,
        .awvalid_ready (awvalid_ready) ,
        .awlength      (awlength_w)    ,
        .awburst       (awburst_w)     ,
        .awid          (awid_w)        ,                  // CHANGED: added awid
        .wstrb_in      (wstrb_computed),
        .wdata         (wdata)         ,
        .wvalid        (wvalid)        ,
        .wstrb         (wstrb)         ,
        .wlast         (wlast)         ,
        .fifo_rd_data  (wfifo_rd_data) ,
        .fifo_empty    (wfifo_empty)   ,
        .fifo_rd_en    (wfifo_rd_en)   ,
        .beat_cnt      (w_beat_cnt)    ,
        .beat_cnt_en   (w_beat_cnt_en) ,
        .wlast_done    (wlast_done)    ,
        .wlast_done_id (wlast_done_id_w)                  // NEW
    );

    // REMOVED: assign wlast_done = wvalid && wready && wlast ;
    // wlast_done is now driven directly by u_w_ch above - the manual version
    // carried no ID and is superseded by the module's own output.

    // ---------------- write response channel ----------------
    axi_master_b_ch #(.ID_WIDTH(ID_WIDTH), .DEPTH(OUT_DEPTH)) u_b_ch (
        .aclk            (aclk)             ,
        .aresetn         (aresetn)          ,
        .bvalid          (bvalid)           ,
        .bresp           (bresp)            ,
        .bid             (bid)              ,
        .wlast_done      (wlast_done)       ,
        .wlast_done_id   (wlast_done_id_w)  ,                   // CHANGED: added wlast_done_id
        .bready          (bready)           ,
        .tx_done         (tx_done)          ,
        .tx_done_id      (tx_done_id)       ,
        .outstanding_cnt (wr_outstanding_cnt)


    );
    assign tx_resp = bresp ;

    // ---------------- read address channel ----------------
    axi_master_ar_ch #(.ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH), .DEPTH(OUT_DEPTH)) u_ar_ch (
        .aclk          (aclk)      ,
        .aresetn       (aresetn)   ,
        .arready       (arready)   ,
        .addr_in       (rd_addr)   ,
        .len_in        (rd_len)    ,
        .burst_in      (rd_burst)  ,
        .size_in       (rd_size)   ,
        .id_in         (rd_id)     ,
        .start_tx      (start_rd)  ,
        .araddr        (araddr)    ,
        .arlen         (arlen)     ,
        .arburst       (arburst)   ,
        .arsize        (arsize)    ,
        .arid          (arid)      ,
        .arvalid       (arvalid)   ,
        .arvalid_ready (arvalid_ready) ,
        .ar_fifo_full  (rd_ar_fifo_full)
    );

    // ---------------- read data channel ----------------
    axi_master_r_ch #(.DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)) u_r_ch (
        .aclk          (aclk)          ,
        .aresetn       (aresetn)       ,
        .rvalid        (rvalid)        ,
        .rdata         (rdata)         ,
        .rresp         (rresp)         ,
        .rlast         (rlast)         ,
        .rid           (rd_id)         ,
        .arvalid_ready (arvalid_ready) ,
        .rready        (rready)        ,
        .fifo_wr_data  (rfifo_wr_data) ,
        .fifo_wr_en    (rfifo_wr_en)   ,
        .fifo_full     (rfifo_full)    ,
        .rx_done       (rx_done)       ,
        .rx_done_id    (rx_done_id)
    );

    // ---------------- read data fifo ----------------
    axi_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(FIFO_DEPTH)) u_rfifo (
        .aclk    (aclk)           ,
        .aresetn (aresetn)        ,
        .wr_en   (rfifo_wr_en)    ,
        .wr_data (rfifo_wr_data)  ,
        .rd_en   (rd_pop)         ,
        .rd_data (rd_pop_data)    ,
        .full    (rfifo_full)     ,
        .empty   (rd_fifo_empty)
    );

endmodule