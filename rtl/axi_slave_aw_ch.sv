module axi_slave_aw_ch #(
    parameter ADDR_WIDTH = 32 ,
    parameter DATA_WIDTH = 32 ,
    parameter ID_WIDTH   = 4  ,
    parameter DEPTH      = 2    // number of outstanding write requests the FIFO can hold
) (
    // inputs
    input           logic                               aclk              ,
    input           logic                               aresetn           ,
    input           logic                               awvalid           ,
    input           logic [ADDR_WIDTH-1:0]              awaddr            ,
    input           logic [7:0]                         awlen             ,
    input           logic [1:0]                         awburst           ,
    input           logic [2:0]                         awsize            ,
    input           logic [ID_WIDTH-1:0]                awid              ,
    // outputs
    output          logic                               awready           ,

    // Handoff signals (to W channel / burst_addr_gen)
    input           logic                               aw_pop            , // pulse from W channel/address gen to advance FIFO
    output          logic                               awvalid_ready     , // LEVEL signal: high whenever a valid AW request is waiting
    output          logic [ADDR_WIDTH-1:0]              awaddr_out        ,
    output          logic [7:0]                         awlen_out         ,
    output          logic [1:0]                         awburst_out       ,
    output          logic [2:0]                         awsize_out        ,
    output          logic [ID_WIDTH-1:0]                awid_out          ,
    output          logic                               start_addr_gen    
);

    localparam PTR_W = $clog2(DEPTH);

    // ---------------- FIFO storage ----------------
    logic [ADDR_WIDTH-1:0]  addr_q  [DEPTH-1:0] ;
    logic [7:0]             len_q   [DEPTH-1:0] ;
    logic [1:0]             burst_q [DEPTH-1:0] ;
    logic [2:0]             size_q  [DEPTH-1:0] ;
    logic [ID_WIDTH-1:0]    id_q    [DEPTH-1:0] ;

    logic             wr_ptr, rd_ptr ;
    logic [PTR_W:0]   count ;

    logic push, pop ;
    logic fifo_empty, fifo_full ;

    assign push       = awvalid && awready ;
    assign fifo_full   = (count == DEPTH) ;
    assign fifo_empty  = (count == 0) ;
    assign awready     = !fifo_full ;

    // Only pop when downstream signals consumption AND FIFO is non-empty
    assign pop = aw_pop && !fifo_empty ;

    always_ff @(posedge aclk or negedge aresetn) begin : fifo_push
        if (!aresetn) begin
            wr_ptr <= '0 ;
            for (int i = 0; i < DEPTH; i++) begin
                addr_q[i]  <= '0 ;
                len_q[i]   <= '0 ;
                burst_q[i] <= '0 ;
                size_q[i]  <= '0 ;
                id_q[i]    <= '0 ;
            end
        end
        else if (push) begin
            addr_q[wr_ptr]  <= awaddr  ;
            len_q[wr_ptr]   <= awlen   ;
            burst_q[wr_ptr] <= awburst ;
            size_q[wr_ptr]  <= awsize  ;
            id_q[wr_ptr]    <= awid    ;
            wr_ptr          <= (wr_ptr == DEPTH-1) ? '0 : 1 ;
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin : fifo_pop
        if (!aresetn)
            rd_ptr <= '0 ;
        else if (pop)
            rd_ptr <= (rd_ptr == DEPTH-1) ? '0 :  1'b1 ;
    end

    always_ff @(posedge aclk or negedge aresetn) begin : fifo_count
        if (!aresetn)
            count <= '0 ;
        else if (push && !pop)
            count <= count + 1'b1 ;
        else if (pop && !push)
            count <= count - 1'b1 ;
    end

    always_ff @( posedge aclk or negedge aresetn ) begin : start_address_generator
        if (!aresetn) 
            start_addr_gen <= 0 ;
        else 
            start_addr_gen <= awvalid_ready ;
    end

    // ---------------- Outputs ----------------
    // Level signal indicating buffered requests exist
    assign awvalid_ready = awvalid  &&  awready ;

    // Drive head-of-queue outputs safely (zero out when empty to avoid 'X)
    assign awaddr_out  = !fifo_empty ? addr_q[rd_ptr]  : '0 ;
    assign awlen_out   = !fifo_empty ? len_q[rd_ptr]   : '0 ;
    assign awburst_out = !fifo_empty ? burst_q[rd_ptr] : '0 ;
    assign awsize_out  = !fifo_empty ? size_q[rd_ptr]  : '0 ;
    assign awid_out    = !fifo_empty ? id_q[rd_ptr]    : '0 ;

endmodule