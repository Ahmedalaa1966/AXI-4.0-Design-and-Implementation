module axi_slave_ram #(
    parameter ADDR_WIDTH = 32  ,
    parameter DATA_WIDTH = 32  ,
    parameter MEM_DEPTH  = 256 ,
    parameter LATENCY    = 3
) (
    input  logic                          aclk           ,
    input  logic                          aresetn        ,

    input  logic [ADDR_WIDTH-1:0]         wr_addr        ,
    input  logic [DATA_WIDTH-1:0]         wr_data        ,
    input  logic [DATA_WIDTH/8-1:0]       wr_strb        ,
    input  logic                          wr_en          ,

    input  logic [ADDR_WIDTH-1:0]         rd_addr        ,
    input  logic                          rd_en          ,           
    output logic [DATA_WIDTH-1:0]         rd_data        ,
    output logic                          rd_valid
);

    localparam WORD_OFFSET  = $clog2(DATA_WIDTH/8) ;
    localparam INDEX_WIDTH  = $clog2(MEM_DEPTH)    ;
    localparam STROBE_WIDTH = DATA_WIDTH/8         ;

    logic [DATA_WIDTH-1:0]  mem [0:MEM_DEPTH-1] ;
    logic [INDEX_WIDTH-1:0] wr_index ;
    logic [INDEX_WIDTH-1:0] rd_index ;
    logic [DATA_WIDTH-1:0]  wr_data_merged ;
    integer i , b ;

    assign wr_index = wr_addr[WORD_OFFSET+INDEX_WIDTH-1:WORD_OFFSET] ;
    assign rd_index = rd_addr[WORD_OFFSET+INDEX_WIDTH-1:WORD_OFFSET] ;

    always_comb begin : byte_merge
        wr_data_merged = mem[wr_index] ;
        for (b = 0; b < STROBE_WIDTH; b = b + 1) begin
            if (wr_strb[b])
                wr_data_merged[b*8 +: 8] = wr_data[b*8 +: 8] ;
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin : mem_write_block
        if (!aresetn) begin
            for (i = 0; i < MEM_DEPTH; i = i + 1)
                mem[i] <= {DATA_WIDTH{1'b0}} ;
        end
        else if (wr_en) begin
            mem[wr_index] <= wr_data_merged ;
        end
    end

    
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] data_pipe  [0:LATENCY-1] ;
    logic                   valid_pipe [0:LATENCY-1] ;
    integer p ;

    always_ff @(posedge aclk or negedge aresetn) begin : read_pipeline
        if (!aresetn) begin
            for (p = 0; p < LATENCY; p = p + 1) begin
                data_pipe[p]  <= {DATA_WIDTH{1'b0}} ;
                valid_pipe[p] <= 1'b0 ;
            end
        end
        else begin
            data_pipe[0]  <= mem[rd_index] ;
            valid_pipe[0] <= rd_en ;

            for (p = 1; p < LATENCY; p = p + 1) begin
                data_pipe[p]  <= data_pipe[p-1] ;
                valid_pipe[p] <= valid_pipe[p-1] ;
            end
        end
    end

    assign rd_data  = data_pipe[LATENCY-1]  ;
    assign rd_valid = valid_pipe[LATENCY-1] ;

endmodule