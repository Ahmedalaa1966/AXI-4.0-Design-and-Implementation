module axi_slave_w_ch #(
    parameter DATA_WIDTH   = 32             ,
    parameter STROBE_WIDTH = DATA_WIDTH/8   ,
    parameter ID_WIDTH     = 4              ,
    parameter DEPTH        = 2                // must match AW channel's DEPTH
) (
    // inputs
    input           logic                               aclk              ,
    input           logic                               aresetn           ,
    input           logic                               wvalid            ,
    input           logic [DATA_WIDTH-1:0]              wdata             ,
    input           logic [STROBE_WIDTH-1:0]            wstrb             ,
    input           logic                               wlast             ,
    input           logic                               awvalid_ready     , // pulses once per completed AW handshake
    input           logic [7:0]                         awlength          , // sampled same cycle awvalid_ready pulses
    input           logic [ID_WIDTH-1:0]                awid              , // ID of the AW request
    // outputs
    output          logic                               wready            ,

    // FIFO / memory signals
    output          logic [DATA_WIDTH-1:0]              mem_wr_data       ,
    output          logic [STROBE_WIDTH-1:0]            mem_wr_strb       ,
    output          logic                               mem_wr_en         ,
    input           logic                               mem_full          ,

    // Status
    output          logic                               wlast_done        , // pulse: last beat accepted
    output          logic [ID_WIDTH-1:0]                wlast_done_id     ,  // ID of job completing data phase
    output          logic                               aw_pop_out 
);

    localparam PTR_W = $clog2(DEPTH);

    // ---------------- Job Queue ----------------
    logic [7:0]          len_q [DEPTH] ;
    logic [ID_WIDTH-1:0] id_q  [DEPTH] ;

    logic [PTR_W-1:0] wr_ptr, rd_ptr ;
    logic [PTR_W:0]   count ;

    logic push, pop ;
    logic job_fifo_empty ;

    assign push           = awvalid_ready ;
    assign job_fifo_empty = (count == 0) ;
    assign aw_pop_out = pop ;


    always_ff @(posedge aclk or negedge aresetn) begin : job_push
        if (!aresetn) begin
            wr_ptr <= '0 ;
        end else if (push) begin
            len_q[wr_ptr] <= awlength ;
            id_q[wr_ptr]  <= awid     ;
            wr_ptr        <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1 ;
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin : job_pop
        if (!aresetn)
            rd_ptr <= '0 ;
        else if (pop)
            rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1 ;
    end

    always_ff @(posedge aclk or negedge aresetn) begin : job_count
        if (!aresetn)
            count <= '0 ;
        else if (push && !pop)
            count <= count + 1'b1 ;
        else if (pop && !push)
            count <= count - 1'b1 ;
    end

    // ---------------- FSM Logic ----------------
    typedef enum logic {
        IDLE = 1'b0,
        RECV = 1'b1
    } state_t ;

    state_t cs, ns ;

    // Free job slot on final accepted burst beat
    assign pop = (cs == RECV) && wvalid && wready && wlast ;

    always_ff @(posedge aclk or negedge aresetn) begin : reset_block
        if (!aresetn)
            cs <= IDLE ;
        else
            cs <= ns ;
    end

    always_comb begin : next_state_logic
        case (cs)
            IDLE: ns = !job_fifo_empty ? RECV : IDLE ;
            
            RECV: begin
                // On last beat handshake, check if more jobs are available to stay in RECV
                if (wvalid && wready && wlast)
                    ns = (count > 1 || push) ? RECV : IDLE ;
                else
                    ns = RECV ;
            end

            default: ns = IDLE ;
        endcase
    end

    // ---------------- Output Assignments ----------------
    always_comb begin : output_logic
        wready      = 1'b0 ;
        mem_wr_data = '0 ;
        mem_wr_strb = '0 ;
        mem_wr_en   = 1'b0 ;
        wlast_done  = 1'b0 ;

        if (cs == RECV) begin
            wready = ~mem_full ;

            if (wvalid && wready) begin
                mem_wr_data = wdata ;
                mem_wr_strb = wstrb ;
                mem_wr_en   = 1'b1 ;
                wlast_done  = wlast ;
            end
        end
    end

    // Output current transaction ID directly from FIFO head
    assign wlast_done_id = id_q[rd_ptr] ;

endmodule