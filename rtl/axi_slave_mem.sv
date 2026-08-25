module axi_slave_mem #(
    parameter ADDR_WIDTH = 32  ,
    parameter DATA_WIDTH = 32  ,
    parameter MEM_DEPTH  = 256
) (
    input  logic                          aclk           ,
    input  logic                          aresetn        ,

    // write port
    input  logic [ADDR_WIDTH-1:0]         wr_addr        ,
    input  logic [DATA_WIDTH-1:0]         wr_data        ,
    input  logic [DATA_WIDTH/8-1:0]       wr_strb        ,           // byte strobes - restored
    input  logic                          wr_en          ,

    // read port
    input  logic [ADDR_WIDTH-1:0]         rd_addr        ,
    output logic [DATA_WIDTH-1:0]         rd_data
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


    // merge incoming data with the existing word, byte by byte - only
    // strobed lanes change, everything else keeps its old value
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

    assign rd_data = mem[rd_index] ;

endmodule