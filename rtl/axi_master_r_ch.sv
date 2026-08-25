module axi_master_r_ch #(
    parameter DATA_WIDTH = 32 ,
    parameter ID_WIDTH   = 4
) (
// Interface signals
    // inputs
    input           logic                                aclk              ,           // global clock for all the protocol
    input           logic                                aresetn           ,           // asynchronous active low reset for all the protocol
    input           logic                                rvalid            ,           // valid signal comes from the subordinate, read data is available
    input           logic [DATA_WIDTH-1:0]               rdata             ,           // data returned from the subordinate
    input           logic [1:0]                          rresp             ,           // read response code (OKAY/EXOKAY/SLVERR/DECERR)
    input           logic                                rlast             ,           // asserted by the subordinate on the final beat of the burst
    input           logic [ID_WIDTH-1:0]                 rid               ,           // ID tag returned alongside RDATA - passed through, not matched here
    input           logic                                arvalid_ready     ,           // comes from the AR channel, triggers this FSM to move form IDLE to RECV
    // outputs
    output          logic                                rready            ,           // ready signal driven by the manager as part of handshake

// FIFO signals
    output          logic [DATA_WIDTH-1:0]               fifo_wr_data      ,           // data pushed into the FIFO, taken from RDATA
    output          logic                                fifo_wr_en        ,           // push the current beat into the FIFO
    input           logic                                fifo_full         ,           // FIFO has no room left for another beat

// Status signals (to top level / other FSMs)
    output          logic                                rx_done           ,           // pulses high for one cycle when the read transaction fully completes
    output          logic [ID_WIDTH-1:0]                 rx_done_id                    // the ID of the transaction that just completed
);

   // FSM state
    typedef enum logic [1:0] {
        IDLE = 2'b00 ,
        RECV = 2'b01 ,
        DONE = 2'b10
    } state_t ;

    // state register declaration
    state_t cs , ns ;

    logic [ID_WIDTH-1:0] rid_reg ;


    always_ff @( posedge aclk or negedge aresetn ) begin : reset_block
        if(!aresetn) begin
            cs <= IDLE ;
        end
        else begin
            cs <= ns   ;
        end
    end


    always_comb begin : next_state_logic
        case (cs)

            IDLE: begin
                if (rvalid )
                    ns = RECV ;
                else
                    ns = IDLE ;
            end

            RECV: begin
                if (rvalid && rready && rlast)              // fixed: now checks rready too, matching a real handshake
                    ns = DONE ;
                else
                    ns = RECV ;
            end

            DONE: begin
                ns = IDLE ;
            end

            default: ns = IDLE ;
        endcase
    end


    
    always_ff @( posedge aclk or negedge aresetn ) begin : id_latch_block
        if (!aresetn) begin
            rid_reg <= {ID_WIDTH{1'b0}} ;
        end
        else if (cs == RECV && rvalid && rready && rlast) begin
            rid_reg <= rid ;
        end
    end


    always_comb begin : output_logic
        // defaults
        rready       = 1'b0 ;
        fifo_wr_data = {DATA_WIDTH{1'b0}} ;
        fifo_wr_en   = 1'b0 ;
        rx_done      = 1'b0 ;

        case (cs)
            RECV: begin
                rready = ~fifo_full ;        // only accept a beat if there's room to store it

                if (rvalid && rready) begin
                    fifo_wr_data = rdata ;
                    fifo_wr_en   = 1'b1 ;    // push this beat into the FIFO
                end
            end

            DONE: begin
                rx_done = 1'b1 ;             // one-cycle pulse telling the rest of the design the read is complete
            end

            default: ;                      // outputs stay at default (all zero / idle)
        endcase
    end

    assign rx_done_id = rid_reg ;

endmodule