module axi_slave_top #(
    parameter ADDR_WIDTH = 32  ,
    parameter DATA_WIDTH = 32  ,
    parameter ID_WIDTH   = 4   ,
    parameter OUT_DEPTH  = 2   ,
    parameter MEM_DEPTH  = 256
) (
    input  logic                          aclk           ,
    input  logic                          aresetn        ,

    // AXI write address channel
    input  logic [ADDR_WIDTH-1:0]         awaddr         ,
    input  logic [7:0]                    awlen          ,
    input  logic [1:0]                    awburst        ,
    input  logic [2:0]                    awsize         ,
    input  logic [ID_WIDTH-1:0]           awid           ,
    input  logic                          awvalid        ,
    output logic                          awready        ,

    // AXI write data channel
    input  logic [DATA_WIDTH-1:0]         wdata          ,
    input  logic [DATA_WIDTH/8-1:0]       wstrb          ,
    input  logic                          wlast          ,
    input  logic                          wvalid         ,
    output logic                          wready         ,

    // AXI write response channel
    output logic [1:0]                    bresp          ,
    output logic [ID_WIDTH-1:0]           bid            ,
    output logic                          bvalid         ,
    input  logic                          bready         ,

    // AXI read address channel
    input  logic [ADDR_WIDTH-1:0]         araddr         ,
    input  logic [7:0]                    arlen          ,
    input  logic [1:0]                    arburst        ,
    input  logic [2:0]                    arsize         ,
    input  logic [ID_WIDTH-1:0]           arid           ,
    input  logic                          arvalid        ,
    output logic                          arready        ,

    // AXI read data channel
    output logic [DATA_WIDTH-1:0]         rdata          ,
    output logic [1:0]                    rresp          ,
    output logic                          rlast          ,
    output logic [ID_WIDTH-1:0]           rid            ,
    output logic                          rvalid         ,
    input  logic                          rready
);

    // write-side internal wires
    logic                     awvalid_ready       ;
    logic [ADDR_WIDTH-1:0]    awaddr_s            ;
    logic [7:0]               awlen_s             ;
    logic [2:0]               awsize_s            ;
    logic [ID_WIDTH-1:0]      awid_s              ;
    logic [ADDR_WIDTH-1:0]    w_addr              ;
    logic [7:0]               w_beat_cnt          ;
    logic                     w_beat_cnt_en       ;
    logic [DATA_WIDTH-1:0]    mem_wr_data         ;
    logic [DATA_WIDTH/8-1:0]  mem_wr_strb         ;
    logic                     mem_wr_en           ;
    logic                     wlast_done          ;
    logic [ID_WIDTH-1:0]      w_id_out            ;
    logic                     start_addr_gen      ;
    logic                     aw_pop_out          ;
    logic [7:0]               beat_cnt_read       ;

    // read-side internal wires
    logic                     arvalid_ready       ;
    logic [ADDR_WIDTH-1:0]    araddr_s            ;
    logic [7:0]               arlen_s             ;
    logic [2:0]               arsize_s            ;
    logic [ID_WIDTH-1:0]      arid_s              ;
    logic                     ar_pop              ;
    logic [ADDR_WIDTH-1:0]    r_addr              ;
    logic                     r_req_beat_cnt_en   ;   // renamed from r_beat_cnt_en - now driven by the request side only
    logic [DATA_WIDTH-1:0]    mem_rd_data         ;
    logic                     mem_rd_valid        ;
    logic                     mem_rd_en           ;
    logic                     mem_stall           ;
    logic                     start_beat_gen      ; 


    // ---------------- write address channel ----------------
    axi_slave_aw_ch #(.ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH)) 
    u_aw_ch (
        .aclk           (aclk)            ,  
        .aresetn        (aresetn)         ,
        .awvalid        (awvalid)         , 
        .awaddr         (awaddr)          , 
        .awlen          (awlen)           ,  
        .awburst        (awburst)         ,  
        .awsize         (awsize)          ,  
        .awid           (awid)            ,
        .awready        (awready)         , 
        .aw_pop         (aw_pop_out)      ,
        .awvalid_ready  (awvalid_ready)   ,
        .start_addr_gen (start_addr_gen)  ,
        .awaddr_out     (awaddr_s)        , 
        .awlen_out      (awlen_s)         , 
        .awsize_out     (awsize_s)        , 
        .awid_out       (awid_s)
    );

     // ---------------- write beat address generator ----------------
    axi_burst_addr_gen #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_w_addr_gen (
        .aclk        (aclk)           ,
        .aresetn     (aresetn)        ,
        .start       (start_addr_gen) ,
        .addr_in     (awaddr_s)       ,
        .len_in      (awlen_s)        ,
        .burst_in    (awburst)        ,
        .size_in     (awsize_s)       ,
        .beat_cnt_en (w_beat_cnt_en)  ,
        .addr_out    (w_addr)         ,
        .beat_cnt    (w_beat_cnt)
    );


        // ---------------- write data channel ----------------
    axi_slave_w_ch #(.DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH), .DEPTH(OUT_DEPTH)) u_w_ch (
        .aclk           (aclk)           ,
        .aresetn        (aresetn)        ,
        .wvalid         (wvalid)         ,
        .wdata          (wdata)          ,
        .wstrb          (wstrb)          ,
        .wlast          (wlast)          ,
        .awvalid_ready  (awvalid_ready)  ,
        .awid           (awid_s)         ,
        .aw_pop_out     (aw_pop_out)     ,
        .wready         (wready)         ,
        .mem_wr_data    (mem_wr_data)    ,
        .mem_wr_strb    (mem_wr_strb)    ,
        .mem_wr_en      (mem_wr_en)      ,
        .mem_full       (1'b0)           ,
        .wlast_done     (wlast_done)     ,
        .wlast_done_id  (w_id_out)
    );

    assign w_beat_cnt_en = mem_wr_en ;

    // ---------------- write response channel ----------------
    axi_slave_b_ch #(.ID_WIDTH(ID_WIDTH), .DEPTH(OUT_DEPTH)) u_b_ch (
        .aclk          (aclk)         ,
        .aresetn       (aresetn)      ,
        .bready        (bready)       ,
        .wlast_done    (wlast_done)   ,
        .wlast_done_id (w_id_out)     ,
        .bresp_in      (2'b00)        ,
        .bvalid        (bvalid)       ,
        .bresp         (bresp)        ,
        .bid           (bid)
    );

    // ---------------- read address channel ----------------
    axi_slave_ar_ch #(.ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH)) u_ar_ch (
        .aclk          (aclk)          ,
        .aresetn       (aresetn)       ,
        .arvalid       (arvalid)       ,
        .araddr        (araddr)        ,
        .arlen         (arlen)         ,
        .arburst       (arburst)       ,
        .arsize        (arsize)        ,
        .arid          (arid)          ,
        .arready       (arready)       ,
        .ar_pop        (ar_pop)        ,
        .arvalid_ready (arvalid_ready) ,
        .araddr_out    (araddr_s)      ,
        .arlen_out     (arlen_s)       ,
        .arsize_out    (arsize_s)      ,
        .arid_out      (arid_s)
    );

    // ---------------- read beat address generator ----------------
    axi_burst_addr_gen #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_r_addr_gen (
        .aclk        (aclk)            ,
        .aresetn     (aresetn)         ,
        .start       (start_beat_gen)  ,
        .addr_in     (araddr_s)        ,
        .len_in      (arlen_s)         ,
        .burst_in    (arburst)         ,
        .size_in     (arsize_s)        ,
        .beat_cnt_en (req_beat_cnt_en) ,
        .addr_out    (r_addr)          ,
        .beat_cnt    (beat_cnt_read)                                    
    );
    // ---------------- read data channel (real RAM, with latency) ----------------
    axi_slave_r_ch_ram #(.DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)) u_r_ch (
        .aclk            (aclk)            ,
        .aresetn         (aresetn)         ,
        .rready          (rready)          ,
        .beat_cnt        (beat_cnt_read)   ,
        .arvalid_ready   (arvalid_ready)   ,
        .arlen           (arlen_s)         ,
        .arid            (arid_s)          ,
        .mem_rd_data     (mem_rd_data)     ,
        .mem_rd_valid    (mem_rd_valid)    ,
        .mem_rd_en       (mem_rd_en)       ,
        .rdata           (rdata)           ,
        .rresp           (rresp)           ,
        .rlast           (rlast)           ,
        .rvalid          (rvalid)          ,
        .rid             (rid)             ,
        .req_beat_cnt_en (req_beat_cnt_en) ,
        .ar_pop          (ar_pop)          ,
        .start_beat_gen  (start_beat_gen)
    );

    // ---------------- Slave memory (real RAM, LATENCY=3) ----------------
    axi_slave_ram #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .MEM_DEPTH(MEM_DEPTH), .LATENCY(3)) u_mem (
        .aclk    (aclk)        ,
        .aresetn (aresetn)     ,
        .wr_addr (w_addr)      ,
        .wr_data (mem_wr_data) ,
        .wr_strb (mem_wr_strb) ,
        .wr_en   (mem_wr_en)   ,
        .rd_addr (r_addr)      ,
        .rd_en   (mem_rd_en)   ,
        .rd_data (mem_rd_data) ,
        .rd_valid(mem_rd_valid)
    );

endmodule