module axi_master_aw_ch #(
    parameter ADDR_WIDTH = 32 ,
    parameter DATA_WIDTH = 32 ,
    parameter ID_WIDTH   = 4  ,
    parameter DEPTH      = 2      // number of outstanding requests the FIFO can hold
) (
    // inputs
    input           logic                                aclk              ,
    input           logic                                aresetn           ,
    input           logic                                awready           ,
    input           logic [ADDR_WIDTH-1:0]               addr_in           ,
    input           logic [7:0]                          len_in            ,
    input           logic [1:0]                          burst_in          ,
    input           logic [2:0]                          size_in           ,
    input           logic [ID_WIDTH-1:0]                 id_in             ,
    input           logic                                start_tx          ,   // "push a request" pulse — can fire anytime FIFO isn't full

    // outputs
    output          logic [ADDR_WIDTH-1:0]               awaddr            ,
    output          logic [7:0]                          awlen             ,
    output          logic [1:0]                          awburst           ,
    output          logic [$clog2(DATA_WIDTH/8):0]       awsize            ,
    output          logic [ID_WIDTH-1:0]                 awid              ,
    output          logic                                awvalid           ,

    // Handoff signals (to W channel / burst_addr_gen)
    output          logic                                awvalid_ready     ,
    output          logic [7:0]                          awlength_out      ,
    output          logic [1:0]                          awburst_out       ,
    output          logic [2:0]                          awsize_out        ,
    output          logic [ID_WIDTH-1:0]                 awid_out          ,

    output          logic                                aw_fifo_full        // tell the caller not to pulse start_tx
);

    localparam PTR_W = $clog2(DEPTH);

    // ---------------- FIFO of the requests storage (input side, independent of the FSM) ----------------
    logic [ADDR_WIDTH-1:0]  addr_q  [DEPTH] ;
    logic [7:0]             len_q   [DEPTH] ;
    logic [1:0]             burst_q [DEPTH] ;
    logic [2:0]             size_q  [DEPTH] ;
    logic [ID_WIDTH-1:0]    id_q    [DEPTH] ;

    logic [PTR_W-1:0] wr_ptr, rd_ptr ;
    logic [PTR_W:0]   count ;

    logic push, pop ;
    logic fifo_empty ;

    assign push        = start_tx && !aw_fifo_full ;
    assign aw_fifo_full = (count == DEPTH) ;
    assign fifo_empty   = (count == 0) ;

    always_ff @( posedge aclk or negedge aresetn ) begin : fifo_push
        if (!aresetn) begin
            wr_ptr <= '0 ;
        end
        else if (push) begin
            addr_q[wr_ptr]  <= addr_in  ;
            len_q[wr_ptr]   <= len_in   ;
            burst_q[wr_ptr] <= burst_in ;
            size_q[wr_ptr]  <= size_in  ;
            id_q[wr_ptr]    <= id_in    ;
            wr_ptr          <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1 ;
        end
    end

    always_ff @( posedge aclk or negedge aresetn ) begin : fifo_pop
        if (!aresetn)
            rd_ptr <= '0 ;
        else if (pop)
            rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1 ;
    end

    always_ff @( posedge aclk or negedge aresetn ) begin : fifo_count
        if (!aresetn)
            count <= '0 ;
        else if (push && !pop)
            count <= count + 1'b1 ;
        else if (pop && !push)
            count <= count - 1'b1 ;
    end

    // --------------- State regirsters  ----------
    typedef enum logic [1:0] {
        IDLE = 2'b00 ,
        SEND = 2'b01 ,
        DONE = 2'b10
    } state_t ;

    state_t cs, ns ;

    // latched "currently being sent" entry — grabbed from the FIFO head when we leave IDLE
    logic [ADDR_WIDTH-1:0]  addr_reg  ;
    logic [7:0]             len_reg   ;
    logic [1:0]             burst_reg ;
    logic [2:0]             size_reg  ;
    logic [ID_WIDTH-1:0]    id_reg    ;

    assign pop = (cs == IDLE) && !fifo_empty ;   // FSM consumes one FIFO entry each time it leaves IDLE

    always_ff @( posedge aclk or negedge aresetn ) begin : reset_block
        if (!aresetn) cs <= IDLE ;
        else          cs <= ns   ;
    end

    always_comb begin : next_state_logic
        case (cs)
            IDLE:    ns = (!fifo_empty) ? SEND : IDLE ;   // used to check start_tx directly; now checks the FIFO instead
            SEND:    ns = (awvalid && awready) ? DONE : SEND ;
            DONE:    ns = IDLE ;
            default: ns = IDLE ;
        endcase
    end

    // latch the FIFO head into the "in-flight" registers the moment we leave IDLE
    always_ff @( posedge aclk or negedge aresetn ) begin : latch_block
        if (!aresetn) begin
            addr_reg  <= {ADDR_WIDTH{1'b0}} ;
            len_reg   <= 8'b0 ;
            burst_reg <= 2'b0 ;
            size_reg  <= 3'b0 ;
            id_reg    <= {ID_WIDTH{1'b0}} ;
        end
        else if (cs == IDLE && !fifo_empty) begin
            addr_reg  <= addr_q[rd_ptr]  ;
            len_reg   <= len_q[rd_ptr]   ;
            burst_reg <= burst_q[rd_ptr] ;
            size_reg  <= size_q[rd_ptr]  ;
            id_reg    <= id_q[rd_ptr]    ;
        end
    end

    always_comb begin : output_logic
        awvalid       = 1'b0 ;
        awaddr        = addr_reg  ;
        awlen         = len_reg   ;
        awburst       = burst_reg ;
        awsize        = size_reg  ;
        awid          = id_reg    ;
        awvalid_ready = 1'b0 ;

        case (cs)
            SEND: begin
                awvalid       = 1'b1 ;
                awvalid_ready = awvalid && awready ;
            end
            default: ;
        endcase
    end

    assign awlength_out = len_reg ;
    assign awburst_out  = burst_reg ;
    assign awsize_out   = size_reg  ;
    assign awid_out     = id_reg    ;

endmodule