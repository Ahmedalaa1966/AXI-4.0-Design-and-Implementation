module axi_master_b_ch #(
    parameter ID_WIDTH = 4    ,
    parameter DEPTH    = 2      // max writes that can be outstanding awaiting a B response
) (
// Interface signals
    // inputs
    input           logic                                 aclk              , // System clock
    input           logic                                 aresetn           , // Active-low async reset (AXI convention)
    input           logic                                 bvalid            , // AXI B channel: subordinate indicates a write response is valid
    input           logic [1:0]                           bresp             , // AXI B channel: write response code (e.g. OKAY/SLVERR) from subordinate
    input           logic [ID_WIDTH-1:0]                  bid               ,   // subordinate-supplied ID - now only used for a compliance check, not trusted as source of truth
    input           logic                                 wlast_done        ,   // pulse from W channel: a write's data phase just finished
    input           logic [ID_WIDTH-1:0]                  wlast_done_id     ,   // NEW: ID of the job that just finished its data phase, from the master's OWN bookkeeping (e.g. axi_master_w_ch's job queue)

    // outputs
    output          logic                                bready            , // AXI B channel: master ready to accept the write response

// Status signals (to top level / ID_manager)
    output          logic                                 tx_done           ,   // pulses when ANY write completes
    output          logic [ID_WIDTH-1:0]                  tx_done_id        ,   // CHANGED: now sourced from this module's own ID queue, not from bid
    output          logic [1:0]                           bresp_out         , // Registered/forwarded copy of bresp for the completed write, output alongside tx_done
    output          logic [$clog2(DEPTH+1)-1:0]           outstanding_cnt   ,   // how many writes are currently awaiting a response
    output          logic                                 bid_mismatch          // NEW: pulses if the subordinate's bid disagrees with the ID we expected - protocol violation flag
);
    localparam PTR_W = $clog2(DEPTH);

    logic [ID_WIDTH-1:0] id_q [DEPTH] ;

    logic [PTR_W-1:0] wr_ptr, rd_ptr ;
    logic [$clog2(DEPTH+1)-1:0] cnt ;

    logic push, pop ;
    assign push = wlast_done             ;   // one more write now awaiting a response
    assign pop  = bvalid && bready       ;   // one response consumed

    always_ff @( posedge aclk or negedge aresetn ) begin : id_push
        if (!aresetn) begin
            wr_ptr <= '0 ;
        end
        else if (push) begin
            id_q[wr_ptr] <= wlast_done_id ;
            wr_ptr       <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1 ;
        end
    end

    always_ff @( posedge aclk or negedge aresetn ) begin : id_pop
        if (!aresetn)
            rd_ptr <= '0 ;
        else if (pop)
            rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1 ;
    end

    always_ff @( posedge aclk or negedge aresetn ) begin : count_block
        if (!aresetn)
            cnt <= '0 ;
        else if (push && !pop)
            cnt <= cnt + 1'b1 ;
        else if (pop && !push)
            cnt <= cnt - 1'b1 ;
    end

    assign bready          = (cnt != 0) ;      // ready to accept a response any time something is outstanding
    assign tx_done         = pop        ;
    assign tx_done_id      = id_q[rd_ptr] ;    // CHANGED: our own record of the oldest outstanding ID, not bid
    assign bresp_out       = bresp      ;
    assign outstanding_cnt = cnt        ;

    
    assign bid_mismatch = pop && (bid !== id_q[rd_ptr]) ;

endmodule