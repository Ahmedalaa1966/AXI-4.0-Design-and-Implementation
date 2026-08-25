module axi_fifo #(
    parameter DATA_WIDTH = 32 ,
    parameter DEPTH      = 16 ,
    parameter PTR_WIDTH  = $clog2(DEPTH)
) (
    // inputs
    input           logic                                aclk              ,           // global clock for all the protocol
    input           logic                                aresetn           ,           // asynchronous active low reset for all the protocol
    input           logic                                wr_en             ,           // push a new entry into the FIFO
    input           logic [DATA_WIDTH-1:0]               wr_data           ,           // data to be pushed
    input           logic                                rd_en             ,           // pop the oldest entry from the FIFO

    // outputs
    output          logic [DATA_WIDTH-1:0]               rd_data           ,           // data at the head of the FIFO
    output          logic                                full              ,           // FIFO has no room left
    output          logic                                empty                         // FIFO has no data left
);

    // internal signals
    logic [DATA_WIDTH-1:0]  mem [0:DEPTH-1] ;   // storage array
    logic [PTR_WIDTH-1:0]   wr_ptr          ;   // write pointer
    logic [PTR_WIDTH-1:0]   rd_ptr          ;   // read pointer
    logic [PTR_WIDTH:0]     count           ;   // number of valid entries, one extra bit to count up to DEPTH

    integer i ;


    // -------------------------------------------------------------------------
    // Write side
    // -------------------------------------------------------------------------
    always_ff @( posedge aclk or negedge aresetn ) begin : write_block
        if (!aresetn) begin
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {DATA_WIDTH{1'b0}} ;
            wr_ptr <= {PTR_WIDTH{1'b0}} ;
        end
        else if (wr_en && !full) begin
            mem[wr_ptr] <= wr_data ;
            wr_ptr      <= wr_ptr + 1'b1 ;
        end
    end


    // -------------------------------------------------------------------------
    // Read side
    // -------------------------------------------------------------------------
    always_ff @( posedge aclk or negedge aresetn ) begin : read_block
        if (!aresetn) begin
            rd_ptr <= {PTR_WIDTH{1'b0}} ;
        end
        else if (rd_en && !empty) begin
            rd_ptr <= rd_ptr + 1'b1 ;
        end
    end

    assign rd_data = mem[rd_ptr] ;


    // -------------------------------------------------------------------------
    // Count tracking (used to derive full/empty)
    // -------------------------------------------------------------------------
    always_ff @( posedge aclk or negedge aresetn ) begin : count_block
        if (!aresetn) begin
            count <= {(PTR_WIDTH+1){1'b0}} ;
        end
        else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10:   count <= count + 1'b1 ;          // push only
                2'b01:   count <= count - 1'b1 ;          // pop only
                default: count <= count       ;          // both or neither -> unchanged
            endcase
        end
    end

    assign full  = (count == DEPTH) ;
    assign empty = (count == 0)     ;

endmodule