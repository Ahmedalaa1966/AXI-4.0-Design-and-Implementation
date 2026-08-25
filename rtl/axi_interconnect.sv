module axi_interconnect #(
    parameter ADDR_WIDTH = 32 ,
    parameter DATA_WIDTH = 32 ,
    parameter ID_WIDTH   = 4  ,
    parameter NUM_SLAVES = 3
) (
    input  logic                              aclk           ,
    input  logic                              aresetn        ,

    // slave region map
    input  logic [ADDR_WIDTH-1:0]             base_addr   [0:NUM_SLAVES-1] ,
    input  logic [ADDR_WIDTH-1:0]             region_size [0:NUM_SLAVES-1] ,

    // -------- Manager-facing ports (single manager) --------
    // write address
    input  logic [ADDR_WIDTH-1:0]             m_awaddr       ,
    input  logic [7:0]                        m_awlen        ,
    input  logic [1:0]                        m_awburst      ,
    input  logic [2:0]                        m_awsize       ,
    input  logic [ID_WIDTH-1:0]               m_awid         ,
    input  logic                              m_awvalid      ,
    output logic                              m_awready      ,
    // write data
    input  logic [DATA_WIDTH-1:0]             m_wdata        ,
    input  logic [DATA_WIDTH/8-1:0]           m_wstrb        ,
    input  logic                              m_wlast        ,
    input  logic                              m_wvalid       ,
    output logic                              m_wready       ,
    // write response
    output logic [1:0]                        m_bresp        ,
    output logic [ID_WIDTH-1:0]               m_bid          ,
    output logic                              m_bvalid       ,
    input  logic                              m_bready       ,
    // read address
    input  logic [ADDR_WIDTH-1:0]             m_araddr       ,
    input  logic [7:0]                        m_arlen        ,
    input  logic [1:0]                        m_arburst      ,
    input  logic [2:0]                        m_arsize       ,
    input  logic [ID_WIDTH-1:0]               m_arid         ,
    input  logic                              m_arvalid      ,
    output logic                              m_arready      ,
    // read data
    output logic [DATA_WIDTH-1:0]             m_rdata        ,
    output logic [1:0]                        m_rresp        ,
    output logic                              m_rlast        ,
    output logic [ID_WIDTH-1:0]               m_rid          ,
    output logic                              m_rvalid       ,
    input  logic                              m_rready       ,

    // -------- Slave-facing ports (arrayed, NUM_SLAVES wide) --------
    output logic [ADDR_WIDTH-1:0]             s_awaddr    [0:NUM_SLAVES-1] ,
    output logic [7:0]                        s_awlen     [0:NUM_SLAVES-1] ,
    output logic [1:0]                        s_awburst   [0:NUM_SLAVES-1] ,
    output logic [2:0]                        s_awsize    [0:NUM_SLAVES-1] ,
    output logic [ID_WIDTH-1:0]               s_awid      [0:NUM_SLAVES-1] ,
    output logic                              s_awvalid   [0:NUM_SLAVES-1] ,
    input  logic                              s_awready   [0:NUM_SLAVES-1] ,

    output logic [DATA_WIDTH-1:0]             s_wdata     [0:NUM_SLAVES-1] ,
    output logic [DATA_WIDTH/8-1:0]           s_wstrb     [0:NUM_SLAVES-1] ,
    output logic                              s_wlast     [0:NUM_SLAVES-1] ,
    output logic                              s_wvalid    [0:NUM_SLAVES-1] ,
    input  logic                              s_wready    [0:NUM_SLAVES-1] ,

    input  logic [1:0]                        s_bresp     [0:NUM_SLAVES-1] ,
    input  logic [ID_WIDTH-1:0]               s_bid       [0:NUM_SLAVES-1] ,
    input  logic                              s_bvalid    [0:NUM_SLAVES-1] ,
    output logic                              s_bready    [0:NUM_SLAVES-1] ,

    output logic [ADDR_WIDTH-1:0]             s_araddr    [0:NUM_SLAVES-1] ,
    output logic [7:0]                        s_arlen     [0:NUM_SLAVES-1] ,
    output logic [1:0]                        s_arburst   [0:NUM_SLAVES-1] ,
    output logic [2:0]                        s_arsize    [0:NUM_SLAVES-1] ,
    output logic [ID_WIDTH-1:0]               s_arid      [0:NUM_SLAVES-1] ,
    output logic                              s_arvalid   [0:NUM_SLAVES-1] ,
    input  logic                              s_arready   [0:NUM_SLAVES-1] ,

    input  logic [DATA_WIDTH-1:0]             s_rdata     [0:NUM_SLAVES-1] ,
    input  logic [1:0]                        s_rresp     [0:NUM_SLAVES-1] ,
    input  logic                              s_rlast     [0:NUM_SLAVES-1] ,
    input  logic [ID_WIDTH-1:0]               s_rid       [0:NUM_SLAVES-1] ,
    input  logic                              s_rvalid    [0:NUM_SLAVES-1] ,
    output logic                              s_rready    [0:NUM_SLAVES-1]
);

    localparam SEL_WIDTH = $clog2(NUM_SLAVES) ;

    // ---------------- write-side selection ----------------
    logic [SEL_WIDTH-1:0] awsel_decode   ;
    logic                  awsel_valid   ;
    logic [SEL_WIDTH-1:0] slave_sel_wr   ;           // latched selection, held for the whole write transaction
    logic                  wr_busy       ;           // 1 = a write transaction is currently owning slave_sel_wr

    axi_addr_decoder #(.ADDR_WIDTH(ADDR_WIDTH), .NUM_SLAVES(NUM_SLAVES)) u_wr_decoder (
        .addr(m_awaddr), 
        .base_addr   (base_addr)    , 
        .region_size (region_size)  ,
        .slave_sel   (awsel_decode) , 
        .addr_valid  (awsel_valid)
    );

    // latch slave_sel_wr on the AW handshake, release it once B completes
    always_ff @(posedge aclk or negedge aresetn) begin : wr_sel_block
        if (!aresetn) begin
            slave_sel_wr <= '0 ;
            wr_busy      <= 1'b0 ;
        end
        else if (m_awvalid && m_awready && !wr_busy) begin
            slave_sel_wr <= awsel_decode ;
            wr_busy      <= 1'b1 ;
        end
        else if (m_bvalid && m_bready) begin
            wr_busy <= 1'b0 ;
        end
    end

    // ---------------- read-side selection ----------------
    logic [SEL_WIDTH-1:0] arsel_decode   ;
    logic                  arsel_valid   ;
    logic [SEL_WIDTH-1:0] slave_sel_rd   ;
    logic                  rd_busy       ;

    axi_addr_decoder #(.ADDR_WIDTH(ADDR_WIDTH), .NUM_SLAVES(NUM_SLAVES)) u_rd_decoder (
        .addr(m_araddr), 
        .base_addr    (base_addr)     , 
        .region_size  (region_size)   ,
        .slave_sel    (arsel_decode)  , 
        .addr_valid   (arsel_valid)
    );

    always_ff @(posedge aclk or negedge aresetn) begin : rd_sel_block
        if (!aresetn) begin
            slave_sel_rd <= '0 ;
            rd_busy      <= 1'b0 ;
        end
        else if (m_arvalid && m_arready && !rd_busy) begin
            slave_sel_rd <= arsel_decode ;
            rd_busy      <= 1'b1 ;
        end
        else if (m_rvalid && m_rready && m_rlast) begin
            rd_busy <= 1'b0 ;
        end
    end

    // which slave AWREADY/ARREADY should reflect - before the handshake
    // latches, use the live decode; the actual selected slave only matters
    // once wr_busy/rd_busy is set
    logic [SEL_WIDTH-1:0] awsel_active ;
    logic [SEL_WIDTH-1:0] arsel_active ;
    assign awsel_active = wr_busy ? slave_sel_wr : awsel_decode ;
    assign arsel_active = rd_busy ? slave_sel_rd : arsel_decode ;


    // ---------------- demux: manager -> slaves ----------------
    integer i ;
    always_comb begin : demux_block
        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            // write address channel
            s_awaddr[i]  = m_awaddr  ;
            s_awlen[i]   = m_awlen   ;
            s_awburst[i] = m_awburst ;
            s_awsize[i]  = m_awsize  ;
            s_awid[i]    = m_awid    ;
            s_awvalid[i] = (i == awsel_active) ? (m_awvalid && awsel_valid) : 1'b0 ;

            // write data channel - only the selected slave sees WVALID
            s_wdata[i]  = m_wdata  ;
            s_wstrb[i]  = m_wstrb  ;
            s_wlast[i]  = m_wlast  ;
            s_wvalid[i] = (i == slave_sel_wr && wr_busy) ? m_wvalid : 1'b0 ;

            // write response ready - only the selected slave sees BREADY
            s_bready[i] = (i == slave_sel_wr && wr_busy) ? m_bready : 1'b0 ;

            // read address channel
            s_araddr[i]  = m_araddr  ;
            s_arlen[i]   = m_arlen   ;
            s_arburst[i] = m_arburst ;
            s_arsize[i]  = m_arsize  ;
            s_arid[i]    = m_arid    ;
            s_arvalid[i] = (i == arsel_active) ? (m_arvalid && arsel_valid) : 1'b0 ;

            // read ready - only the selected slave sees RREADY
            s_rready[i] = (i == slave_sel_rd && rd_busy) ? m_rready : 1'b0 ;
        end
    end


    // ---------------- mux: slaves -> manager ----------------
    assign m_awready = s_awready[awsel_active] ;
    assign m_wready   = s_wready[slave_sel_wr]  ;
    assign m_bvalid   = s_bvalid[slave_sel_wr]  ;
    assign m_bresp    = s_bresp[slave_sel_wr]   ;
    assign m_bid      = s_bid[slave_sel_wr]     ;

    assign m_arready = s_arready[arsel_active] ;
    assign m_rvalid   = s_rvalid[slave_sel_rd]  ;
    assign m_rdata    = s_rdata[slave_sel_rd]   ;
    assign m_rresp    = s_rresp[slave_sel_rd]   ;
    assign m_rlast    = s_rlast[slave_sel_rd]   ;
    assign m_rid      = s_rid[slave_sel_rd]     ;

endmodule