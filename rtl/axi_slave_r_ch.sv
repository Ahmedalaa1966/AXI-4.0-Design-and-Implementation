module axi_slave_r_ch #(
    parameter DATA_WIDTH = 32
) (
    // inputs
    input           logic                                aclk              ,           // global clock for all the protocol
    input           logic                                aresetn           ,           // asynchronous active low reset for all the protocol
    input           logic                                rready            ,           // ready signal comes from the manager
    input           logic                                arvalid_ready     ,           // comes from the AR channel, triggers this FSM to move from IDLE to SEND
    input           logic [7:0]                          beat_cnt          ,           // current beat index from axi_burst_addr_gen
    input           logic [7:0]                          arlen             ,           // latched burst length, used to know when RLAST fires

    // Memory / FIFO signals
    input           logic [DATA_WIDTH-1:0]               mem_rd_data       ,           // data read from memory for the current beat
    output          logic                                mem_rd_en         ,           // pulse to fetch the next beat from memory

    // outputs
    output          logic [DATA_WIDTH-1:0]               rdata             ,           // data returned to the manager
    output          logic [1:0]                          rresp             ,           // read response code
    output          logic                                rlast             ,           // asserted on the final beat of the burst
    output          logic                                rvalid            ,           // valid signal driven by the subordinate as part of handshake

    output          logic                                beat_cnt_en                    // tells axi_burst_addr_gen to advance to the next beat
);

   typedef enum logic [1:0] {
        IDLE = 2'b00 ,
        SEND = 2'b01 ,
        DONE = 2'b10
    } state_t ;

    state_t cs , ns ;


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
                if (arvalid_ready)
                    ns = SEND ;
                else
                    ns = IDLE ;
            end

            SEND: begin
                if (rvalid && rready && rlast)
                    ns = DONE ;
                else
                    ns = SEND ;
            end

            DONE: begin
                ns = IDLE ;
            end

            default: ns = IDLE ;
        endcase
    end


    always_comb begin : output_logic
        rvalid      = 1'b0 ;
        rdata       = {DATA_WIDTH{1'b0}} ;
        rresp       = 2'b00 ;                            // OKAY by default
        rlast       = 1'b0 ;
        mem_rd_en   = 1'b0 ;
        beat_cnt_en = 1'b0 ;

        case (cs)
            SEND: begin
                rvalid = 1'b1 ;                           
                rdata  = mem_rd_data ;
                rlast  = (beat_cnt == arlen) ;             // last beat when counter reaches burst length
                if (rvalid && rready) begin
                    mem_rd_en   = 1'b1 ;                   // fetch next beat from memory
                    beat_cnt_en = 1'b1 ;                   // advance burst_addr_gen counter
                end
            end

            default: ;
        endcase
    end

endmodule