module axi_slave_b_ch #(
    parameter ID_WIDTH = 4 ,
    parameter DEPTH    = 2      // max writes that can be outstanding awaiting a B response
) (
    // inputs
    input           logic                                aclk              ,
    input           logic                                aresetn           ,
    input           logic                                bready            ,           // ready signal comes from the manager
    input           logic                                wlast_done        ,           // pulse from W channel: a write's data phase just finished
    input           logic [ID_WIDTH-1:0]                 wlast_done_id     ,           // ID of the job that just finished its data phase
    input           logic [1:0]                          bresp_in          ,            // response code to send (e.g. OKAY, computed elsewhere)
    // outputs
    output          logic                                bvalid            ,           // valid signal driven by the subordinate as part of handshake
    output          logic [1:0]                          bresp             ,           // write response code sent to the manager
    output          logic [ID_WIDTH-1:0]                 bid                           // ID echoed back on the response
    );

    // ---------------- pending-response queue ----------------
    // one entry per completed write (wlast_done), popped once its B response is sent
    logic [ID_WIDTH-1:0] id_q [DEPTH] ;

    localparam PTR_W = $clog2(DEPTH);
    logic [PTR_W-1:0] wr_ptr, rd_ptr ;
    logic [$clog2(DEPTH+1)-1:0] cnt ;

    logic push, pop ;
    assign push = wlast_done       ;   // one more write now awaiting a response
    assign pop  = bvalid && bready ;   // one response consumed

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

    assign bvalid = (cnt != 0) ;          // respond whenever a completed write is waiting
    assign bid    = id_q[rd_ptr] ;        // ID of the oldest still-pending response, in FIFO order
    assign bresp  = bresp_in ;            // OKAY, or whatever was computed for the write in progress

endmodule