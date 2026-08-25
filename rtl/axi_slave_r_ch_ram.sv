module axi_slave_r_ch_ram #(
    parameter DATA_WIDTH = 32 ,
    parameter ID_WIDTH   = 4
) (
    input           logic                                  aclk              , // System clock
    input           logic                                  aresetn           , // Active-low async reset (AXI convention)

    input           logic                                  rready            , // Master ready to accept read data (AXI R channel handshake)
    input           logic                                  arvalid_ready     , // AR channel handshake complete (address accepted), qualifies latched arlen/arid for this transaction
    input           logic [7:0]                            arlen             , // Burst length from AR channel (number of beats - 1), latched for the transfer
    input           logic [ID_WIDTH-1:0]                   arid              , // Transaction ID from AR channel, to be echoed back on rid
    input           logic [7:0]                            beat_cnt          , // Current beat counter value for the ongoing burst, used to detect last beat / drive addressing

    input           logic [DATA_WIDTH-1:0]                 mem_rd_data       , // Data read back from RAM, presented when mem_rd_valid is high
    input           logic                                  mem_rd_valid      , // Indicates mem_rd_data is valid this cycle (RAM read latency completed)
    output          logic                                  mem_rd_en         , // Read enable to RAM, asserted to issue a read request for the next beat

    output          logic [DATA_WIDTH-1:0]                 rdata             , // AXI R channel: read data returned to master
    output          logic [1:0]                            rresp             , // AXI R channel: read response (e.g. OKAY/SLVERR), tied/generated per beat
    output          logic                                  rlast             , // AXI R channel: asserted on the final beat of the burst
    output          logic [ID_WIDTH-1:0]                   rid               , // AXI R channel: transaction ID, echoed from arid
    output          logic                                  rvalid            , // AXI R channel: indicates rdata/rresp/rlast/rid are valid

    output          logic                                  req_beat_cnt_en   , // Level signal, high alongside mem_rd_valid whenever another beat remains to be requested; enables beat counter increment
    output          logic                                  ar_pop            , // Pops/acknowledges the AR FIFO entry once the read burst has been accepted/started
    output          logic                                  start_beat_gen      // Kicks off the beat generation/counting FSM for a new burst
);

    typedef enum logic [1:0] {
        IDLE       = 2'b00 ,
        WAIT_FIRST = 2'b01 ,           
        BURST      = 2'b10            
    } state_t ;

    state_t cs, ns ;

    logic [ID_WIDTH-1:0]  id_reg            ;
    logic [7:0]           arlength_latch    ;
    logic [7:0]           req_cnt           ;                 // beats requested so far this burst
    logic [7:0]           resp_cnt          ;                 // beats accepted (rvalid && rready) so far this burst
    logic                 requesting_done   ;
    logic                 advance_next_beat ;



    assign requesting_done = (req_cnt > arlength_latch) ;    
    assign advance_next_beat = mem_rd_valid && !requesting_done ;


    always_ff @(posedge aclk or negedge aresetn) begin : state_reg
        if (!aresetn)
            cs <= IDLE ;
        else
            cs <= ns ;
    end

    always_comb begin : next_state_logic
        case (cs)

            IDLE:       ns = arvalid_ready               ? WAIT_FIRST : IDLE ;
            WAIT_FIRST: ns = mem_rd_valid                ? BURST      : WAIT_FIRST ;
            BURST:      ns = (rvalid && rready && rlast) ? IDLE : BURST ;
            default:    ns = IDLE ;

        endcase
    end

    always_ff @(posedge aclk or negedge aresetn) begin : ctrl_regs
        if (!aresetn) begin
            id_reg         <= '0 ;
            arlength_latch <= '0 ;
            req_cnt        <= '0 ;
            resp_cnt       <= '0 ;
        end
        else if (cs == IDLE && arvalid_ready) begin
            id_reg         <= arid  ;
            arlength_latch <= arlen ;
            req_cnt        <= 8'd1  ;           // beat 0's request is issued this same cycle (see output_logic) - count it now
            resp_cnt       <= '0    ;
        end
        else begin
            if (advance_next_beat)
                req_cnt <= req_cnt + 1'b1 ;

            if (rvalid && rready)
                resp_cnt <= resp_cnt + 1'b1 ;
        end
    end

    always_comb begin : output_logic
        mem_rd_en        = 1'b0        ;
        rvalid           = 1'b0        ;
        rdata            = mem_rd_data ;
        rresp            = 2'b00       ;
        rlast            = 1'b0        ;
        req_beat_cnt_en  = 1'b0        ;
        ar_pop           = 1'b0        ;

        case (cs)
            IDLE: begin
                if (arvalid_ready) 
                    ar_pop    = 1'b1 ;
            end

            WAIT_FIRST, BURST: begin
                rvalid          = mem_rd_valid        ;
                rlast           = (resp_cnt == arlen) ;
                mem_rd_en       = 'b1                 ;
                req_beat_cnt_en = 1                   ;
            end
            
            default: ;
        endcase
    end

    assign rid = id_reg ;

    always_ff @( posedge aclk or  negedge aresetn ) begin 
        if(!aresetn)
            start_beat_gen <= 'b0    ;
        else 
            start_beat_gen <= ar_pop ;
    end



endmodule