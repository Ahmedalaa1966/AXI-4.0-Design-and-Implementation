module axi_wstrb_gen #(
    parameter DATA_WIDTH   = 32            ,
    parameter STROBE_WIDTH = DATA_WIDTH/8
) (
    // inputs
    input           logic [31:0]                        beat_addr         ,           // address of the current beat, comes from axi_burst_addr_gen's addr_out
    input           logic [$clog2(DATA_WIDTH/8):0]      size_in           ,           // AWSIZE/ARSIZE, encodes bytes per beat (Table A3.2)

    // outputs
    output          logic [STROBE_WIDTH-1:0]            wstrb                         // byte lanes active for this beat
);

    // internal signals
    logic [31:0] size_bytes       ;
    logic [31:0] lower_byte_lane  ;
    logic [31:0] upper_byte_lane  ;
    integer      i                ;


    // -------------------------------------------------------------------------
    // Combinational: size_bytes from AxSIZE (Table A3.2 encoding)
    // -------------------------------------------------------------------------
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


    // Combinational: generate WSTRB
    always_comb begin : wstrb_gen
        if (size_bytes == STROBE_WIDTH) begin
            wstrb = {STROBE_WIDTH{1'b1}} ;                                              // fast path - full width transfer
        end
        else begin
            lower_byte_lane = beat_addr - (beat_addr / STROBE_WIDTH) * STROBE_WIDTH ;   // Address_N mod Data_Bytes
            upper_byte_lane = lower_byte_lane + size_bytes - 1 ;

            wstrb = {STROBE_WIDTH{1'b0}} ;
            for (i = 0; i < STROBE_WIDTH; i = i + 1) begin
                if ((i >= lower_byte_lane) && (i <= upper_byte_lane))
                    wstrb[i] = 1'b1 ;
            end
        end
    end

endmodule