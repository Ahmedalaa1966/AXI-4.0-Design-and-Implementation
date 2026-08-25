module axi_burst_addr_gen #(
    parameter ADDR_WIDTH = 32 ,
    parameter DATA_WIDTH = 32
) (
    // inputs
    input           logic                                aclk              ,           // global clock for all the protocol
    input           logic                                aresetn           ,           // asynchronous active low reset for all the protocol
    input           logic                                start             ,           // pulse from AW/AR channel (awvalid_ready / arvalid_ready), latches a new transaction
    input           logic [ADDR_WIDTH-1:0]               addr_in           ,           // start address of the transaction (AWADDR/ARADDR)
    input           logic [7:0]                          len_in            ,           // burst length (number of beats), from AWLEN/ARLEN
    input           logic [1:0]                          burst_in          ,           // AWBURST/ARBURST: 00 = FIXED, 01 = INCR, 10 = WRAP, 11 = reserved
    input           logic [2:0]                          size_in           ,           // AWSIZE/ARSIZE, encodes bytes per beat (Table A3.2)
    input           logic                                beat_cnt_en       ,           // pulse from W/R channel, advance to the next beat

    // outputs
    output          logic [ADDR_WIDTH-1:0]               addr_out          ,           // address of the current beat
    output          logic [7:0]                          beat_cnt                      // current beat index, fed back to W/R channel for WLAST/RLAST comparison
);

    // internal signals
    logic [ADDR_WIDTH-1:0]  size_bytes     ;
    logic [ADDR_WIDTH-1:0]  wrap_boundary  ;
    logic [ADDR_WIDTH-1:0]  wrap_base      ;
    logic [ADDR_WIDTH-1:0]  addr_reg       ;
    logic [1:0]             burst_reg      ;
    logic [7:0]             beat_cnt_reg   ;


    
    // Combinational: size_bytes from AxSIZE 
    always_comb begin
        case (size_in)
            3'b000:  size_bytes = 32'd1   ;   // 1   byte  per transfer
            3'b001:  size_bytes = 32'd2   ;   // 2   bytes per transfer
            3'b010:  size_bytes = 32'd4   ;   // 4   bytes per transfer
            3'b011:  size_bytes = 32'd8   ;   // 8   bytes per transfer
            3'b100:  size_bytes = 32'd16  ;   // 16  bytes per transfer
            3'b101:  size_bytes = 32'd32  ;   // 32  bytes per transfer
            3'b110:  size_bytes = 32'd64  ;   // 64  bytes per transfer
            3'b111:  size_bytes = 32'd128 ;   // 128 bytes per transfer
            default: size_bytes = 32'd1   ;   // safe fallback
        endcase
    end


    
    // Sequential: latch transaction info, generate wrap window, walk the address
    always_ff @(posedge aclk or negedge aresetn) begin : addr_gen_block
        if (!aresetn) begin
            addr_reg      <= {ADDR_WIDTH{1'b0}} ;
            burst_reg     <= 2'b00 ;
            beat_cnt_reg  <= 8'b0  ;
            wrap_boundary <= {ADDR_WIDTH{1'b0}} ;
            wrap_base     <= {ADDR_WIDTH{1'b0}} ;
        end

        else if (start) begin
            // latch the transaction, same pattern as the AHB IDLE/address_state entry
            addr_reg     <= addr_in  ;
            burst_reg    <= burst_in ;
            beat_cnt_reg <= 8'b0     ;

            if (burst_in == 2'b10) begin                              // WRAP
                wrap_boundary <= size_bytes * (len_in + 1)                ;
                wrap_base     <= addr_in & (~(size_bytes * (len_in + 1) - 1)) ;
            end
            else begin
                wrap_boundary <= {ADDR_WIDTH{1'b0}} ;
                wrap_base     <= {ADDR_WIDTH{1'b0}} ;
            end
        end

        else if (beat_cnt_en) begin
            beat_cnt_reg <= beat_cnt_reg + 1'b1 ;

            case (burst_reg)
                2'b00: begin                                          // FIXED - address never changes
                    addr_reg <= addr_reg ;
                end

                2'b01: begin                                          // INCR
                    addr_reg <= addr_reg + size_bytes ;
                end

                2'b10: begin                                          // WRAP
                    if (((addr_reg + size_bytes) % wrap_boundary == 0) && (addr_reg != {ADDR_WIDTH{1'b0}}))
                        addr_reg <= wrap_base ;
                    else
                        addr_reg <= addr_reg + size_bytes ;
                end

                default: addr_reg <= addr_reg ;                       // 2'b11 reserved - hold address
            endcase
        end
    end

    assign addr_out = addr_reg     ;
    assign beat_cnt = beat_cnt_reg ;

endmodule