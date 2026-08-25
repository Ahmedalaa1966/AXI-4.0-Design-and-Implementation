module axi_slave_ar_ch #(
    parameter ADDR_WIDTH = 32 ,
    parameter ID_WIDTH   = 4  ,
    parameter DEPTH      = 2    // number of outstanding read requests
) (
    // inputs
    input           logic                               aclk              ,
    input           logic                               aresetn           ,
    input           logic                               arvalid           ,
    input           logic [ADDR_WIDTH-1:0]              araddr            ,
    input           logic [7:0]                         arlen             ,
    input           logic [1:0]                         arburst           ,
    input           logic [2:0]                         arsize            ,
    input           logic [ID_WIDTH-1:0]                arid              ,
    // outputs
    output          logic                               arready           ,

    // Handoff signals (to R channel / burst_addr_gen)
    input           logic                               ar_pop            , // pulse from R channel to consume current head
    output          logic                               arvalid_ready     , // pulse on AR channel handshake
    output          logic [ADDR_WIDTH-1:0]              araddr_out        ,
    output          logic [7:0]                         arlen_out         ,
    output          logic [1:0]                         arburst_out       ,
    output          logic [2:0]                         arsize_out        ,
    output          logic [ID_WIDTH-1:0]                arid_out
);

    localparam PTR_W = $clog2(DEPTH);

    // ---------------- FIFO storage ----------------
    logic [ADDR_WIDTH-1:0]  addr_q  [DEPTH-1:0] ;
    logic [7:0]             len_q   [DEPTH-1:0] ;
    logic [1:0]             burst_q [DEPTH-1:0] ;
    logic [2:0]             size_q  [DEPTH-1:0] ;
    logic [ID_WIDTH-1:0]    id_q    [DEPTH-1:0] ;

    logic [PTR_W-1:0] wr_ptr, rd_ptr ;
    logic [PTR_W:0]   count ;

    logic push, pop ;
    logic fifo_empty, fifo_full ;

    // Exact handshake condition requested
    assign arvalid_ready = arvalid && arready ;

    assign push        = arvalid_ready ;
    assign fifo_full   = (count == DEPTH) ;
    assign fifo_empty  = (count == 0) ;
    assign arready     = !fifo_full ;

    // Only allow pop when FIFO is non-empty
    assign pop = ar_pop && !fifo_empty ;

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
            addr_q[wr_ptr]  <= araddr  ;
            len_q[wr_ptr]   <= arlen   ;
            burst_q[wr_ptr] <= arburst ;
            size_q[wr_ptr]  <= arsize  ;
            id_q[wr_ptr]    <= arid    ;
            wr_ptr          <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1 ;
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin : fifo_pop
        if (!aresetn)
            rd_ptr <= '0 ;
        else if (pop)
            rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1 ;
    end

    always_ff @(posedge aclk or negedge aresetn) begin : fifo_count
        if (!aresetn)
            count <= '0 ;
        else if (push && !pop)
            count <= count + 1'b1 ;
        else if (pop && !push)
            count <= count - 1'b1 ;
    end

    // ---------------- Combinational MUX Outputs ----------------
    // If FIFO is empty, pass input bus directly on handshake to prevent 'x
    // If FIFO has items queued, output the queue head (rd_ptr)
    assign araddr_out  = fifo_empty ? (push ? araddr  : '0) : addr_q[rd_ptr]  ;
    assign arlen_out   = fifo_empty ? (push ? arlen   : '0) : len_q[rd_ptr]   ;
    assign arburst_out = fifo_empty ? (push ? arburst : '0) : burst_q[rd_ptr] ;
    assign arsize_out  = fifo_empty ? (push ? arsize  : '0) : size_q[rd_ptr]  ;
    assign arid_out    = fifo_empty ? (push ? arid    : '0) : id_q[rd_ptr]    ;

endmodule