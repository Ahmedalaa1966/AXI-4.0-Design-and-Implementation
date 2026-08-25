module axi_addr_decoder #(
    parameter ADDR_WIDTH  = 32 ,
    parameter NUM_SLAVES  = 3
) (
    input           logic [ADDR_WIDTH-1:0]              addr                          ,                 // address to decode (AWADDR or ARADDR)
    input           logic [ADDR_WIDTH-1:0]              base_addr [0:NUM_SLAVES-1]    ,                 // base address of each slave's region
    input           logic [ADDR_WIDTH-1:0]              region_size [0:NUM_SLAVES-1]  ,                 // size in bytes of each slave's region (must be power of 2, 4KB minimum)

    output          logic [$clog2(NUM_SLAVES)-1:0]      slave_sel                     ,                 // which slave this address belongs to
    output          logic                               addr_valid                                      // 1 if the address matched a slave, 0 if no slave owns this address (DECERR case)
);

    integer i ;

    always_comb begin : decode_block
        slave_sel  = '0 ;
        addr_valid = 1'b0 ;

        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            if ((addr >= base_addr[i]) && (addr < (base_addr[i] + region_size[i]))) begin
                slave_sel  = i[$clog2(NUM_SLAVES)-1:0] ;
                addr_valid = 1'b1 ;
            end
        end
    end




endmodule