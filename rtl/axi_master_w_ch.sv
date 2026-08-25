module axi_master_w_ch #(
    parameter DATA_WIDTH   = 32            ,
    parameter STROBE_WIDTH = DATA_WIDTH/8  ,
    parameter ID_WIDTH     = 4             ,           
    parameter DEPTH        = 2
) (
// Interface signals
    // inputs
    input           logic                                aclk              ,              // global clock for all the system 
    input           logic                                aresetn           ,              // global asynchronous active low reset for all the system
    input           logic                                wready            ,              // signal comes from the slave indicating that it is ready to receive data 
    input           logic                                awvalid_ready     ,              // signal from the slave which is the anding of the valid and ready signals 
    input           logic [7:0]                          awlength          ,              // signal indicated the lenth of the burst in case of burst transaction
    input           logic [1:0]                          awburst           ,              // Indicates the birst transaction when asserted 
    input           logic [ID_WIDTH-1:0]                 awid              ,              // id of the transaction 
    input           logic [STROBE_WIDTH-1:0]             wstrb_in          ,              // strobe of the data
    // outputs
    output          logic [DATA_WIDTH-1:0]               wdata             ,              // data to be written to the salve 
    output          logic                                wvalid            ,              // valid signal which indicate that the data in the bus is valid
    output          logic [STROBE_WIDTH-1:0]             wstrb             ,              // strobe of the data
    output          logic                                wlast             ,              // sinal of the AXI protocol indicating last beat in a burst transaction

// FIFO signals (write-data FIFO, unrelated to the job queue below)
    input           logic [DATA_WIDTH-1:0]               fifo_rd_data      ,             // data read form the fifo
    input           logic                                fifo_empty        ,             // empty signal of a FIFO 
    output          logic                                fifo_rd_en        ,             // read enable of a fifo 

// Burst address signals
    input           logic [7:0]                          beat_cnt          ,            // beat counter from the address generator block
    output          logic                                beat_cnt_en       ,            // count enable to the address generator block

// Status (to B channel)                                                              
    output          logic                                wlast_done        ,            
    output          logic [ID_WIDTH-1:0]                 wlast_done_id
);



    localparam PTR_W = $clog2(DEPTH); 

    logic [7:0]            len_q   [DEPTH] ;
    logic [1:0]            burst_q [DEPTH] ;
    logic [ID_WIDTH-1:0]   id_q    [DEPTH] ;           // ADD THIS

    logic [PTR_W-1:0] wr_ptr, rd_ptr ;
    logic [PTR_W:0]   count ;

    logic push, pop ;
    logic job_fifo_empty ;

    assign push           = awvalid_ready ;
    assign job_fifo_empty = (count == 0) ;

    always_ff @( posedge aclk or negedge aresetn ) begin : job_push
        if (!aresetn) begin
            wr_ptr <= '0 ;
        end
        else if (push) begin
            len_q[wr_ptr]   <= awlength ;
            burst_q[wr_ptr] <= awburst  ;
            id_q[wr_ptr]    <= awid     ;               
            wr_ptr          <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1 ;
        end
    end

    always_ff @( posedge aclk or negedge aresetn ) begin : job_pop
        if (!aresetn)
            rd_ptr <= '0 ;
        else if (pop)
            rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1 ;
    end

    always_ff @( posedge aclk or negedge aresetn ) begin : job_count
        if (!aresetn)
            count <= '0 ;
        else if (push && !pop)
            count <= count + 1'b1 ;
        else if (pop && !push)
            count <= count - 1'b1 ;
    end

    // ---------------- FSM ----------------
    typedef enum logic [1:0] {
        IDLE = 2'b00 ,
        SEND = 2'b01 ,
        DONE = 2'b10
    } state_t ;

    state_t cs , ns ;

    logic [7:0]            awlength_reg ;
    logic [1:0]            awburst_reg  ;
    logic [ID_WIDTH-1:0]   awid_reg     ;              

    assign pop = (cs == SEND) && wvalid && wready && wlast ;

    always_ff @( posedge aclk or negedge aresetn ) begin : reset_block
        if (!aresetn) cs <= IDLE ;
        else          cs <= ns   ;
    end

    always_comb begin : next_state_logic
        case (cs)
            IDLE: ns = !job_fifo_empty ? SEND : IDLE ;
            SEND: ns = (wvalid && wready && wlast) ? DONE : SEND ;
            DONE: ns = IDLE ;
            default: ns = IDLE ;
        endcase
    end

    always_ff @( posedge aclk or negedge aresetn ) begin : latch_block
        if (!aresetn) begin
            awlength_reg <= 8'b0 ;
            awburst_reg  <= 2'b0 ;
            awid_reg     <= {ID_WIDTH{1'b0}} ;          // ADD THIS
        end
        else if (cs == IDLE && !job_fifo_empty) begin
            awlength_reg <= len_q[rd_ptr]   ;
            awburst_reg  <= burst_q[rd_ptr] ;
            awid_reg     <= id_q[rd_ptr]    ;           // ADD THIS
        end
    end

    always_comb begin : output_logic
        wvalid      = 1'b0 ;
        wdata       = {DATA_WIDTH{1'b0}} ;
        wstrb       = {STROBE_WIDTH{1'b0}} ;
        wlast       = 1'b0 ;
        fifo_rd_en  = 1'b0 ;
        beat_cnt_en = 1'b0 ;

        case (cs)
            SEND: begin
                wvalid = ~fifo_empty                 ;
                wdata  = fifo_rd_data                ;
                wstrb  = wstrb_in                    ;
                wlast  = (beat_cnt == awlength_reg)  ;

                if (wvalid && wready) begin
                    fifo_rd_en  = 1'b1 ;
                    beat_cnt_en = 1'b1 ;
                end
            end

            default: ;
        endcase
    end

    assign wlast_done    = pop      ;                  
    assign wlast_done_id = awid_reg ;                   

endmodule