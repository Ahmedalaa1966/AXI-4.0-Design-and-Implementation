`timescale 1ns/1ps

module axi_top_tb ;

    // parameters matching the DUT
    localparam ADDR_WIDTH = 32 ;
    localparam DATA_WIDTH = 32 ;
    localparam ID_WIDTH   = 4  ;          
    localparam FIFO_DEPTH = 16 ;
    localparam OUT_DEPTH  = 2  ;           
    localparam MEM_DEPTH  = 256 ;

    // clock / reset
    logic aclk    ;
    logic aresetn ;

    // write side
    logic                     start_wr      ;
    logic [ADDR_WIDTH-1:0]    wr_addr       ;
    logic [7:0]               wr_len        ;
    logic [1:0]               wr_burst      ;
    logic [2:0]               wr_size       ;
    logic [ID_WIDTH-1:0]      wr_id         ;           
    logic                     wr_aw_fifo_full ;          
    logic                     wr_push       ;
    logic [DATA_WIDTH-1:0]    wr_push_data  ;
    logic                     wr_fifo_full  ;
    logic                     tx_done       ;
    logic [ID_WIDTH-1:0]      tx_done_id    ;           
    logic [1:0]               tx_resp       ;
    logic [$clog2(OUT_DEPTH+1)-1:0] wr_outstanding_cnt ; 

    // read side
    logic                     start_rd      ;
    logic [ADDR_WIDTH-1:0]    rd_addr       ;
    logic [7:0]               rd_len        ;
    logic [1:0]               rd_burst      ;
    logic [2:0]               rd_size       ;
    logic [ID_WIDTH-1:0]      rd_id         ;          
    logic                     rd_ar_fifo_full ;        
    logic                     rd_pop        ;
    logic [DATA_WIDTH-1:0]   rd_pop_data   ;
    logic                     rd_fifo_empty ;
    logic                     rx_done       ;
    logic [ID_WIDTH-1:0]      rx_done_id    ;        

    integer errors     ;
    integer test_count ;


    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    axi_top #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH), .OUT_DEPTH(OUT_DEPTH), .MEM_DEPTH(MEM_DEPTH)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .start_wr(start_wr),
        .wr_addr(wr_addr),
        .wr_len(wr_len),
        .wr_burst(wr_burst),
        .wr_size(wr_size),
        .wr_id(wr_id),                             
        .wr_aw_fifo_full(wr_aw_fifo_full),       
        .wr_push(wr_push),
        .wr_push_data(wr_push_data),
        .wr_fifo_full(wr_fifo_full),
        .tx_done(tx_done),
        .tx_done_id(tx_done_id),                
        .tx_resp(tx_resp),
        .wr_outstanding_cnt(wr_outstanding_cnt),  
        .start_rd(start_rd),
        .rd_addr(rd_addr),
        .rd_len(rd_len),
        .rd_burst(rd_burst),
        .rd_size(rd_size),
        .rd_id(rd_id),                             
        .rd_ar_fifo_full(rd_ar_fifo_full),        
        .rd_pop(rd_pop),
        .rd_pop_data(rd_pop_data),
        .rd_fifo_empty(rd_fifo_empty),
        .rx_done(rx_done),
        .rx_done_id(rx_done_id)                  
    );


    // -------------------------------------------------------------------------
    // Clock generation - 10ns period (100 MHz)
    // -------------------------------------------------------------------------
    initial aclk = 1'b0 ;
    always #5 aclk = ~aclk ;


    // -------------------------------------------------------------------------
    // Reset task
    // -------------------------------------------------------------------------
    task do_reset ;
        begin
            aresetn = 1'b0 ;

            start_wr     = 1'b0 ;
            wr_addr      = {ADDR_WIDTH{1'b0}} ;
            wr_len       = 8'b0 ;
            wr_burst     = 2'b0 ;
            wr_size      = 3'b0 ;
            wr_id        = {ID_WIDTH{1'b0}} ;       
            wr_push      = 1'b0 ;
            wr_push_data = {DATA_WIDTH{1'b0}} ;

            start_rd = 1'b0 ;
            rd_addr  = {ADDR_WIDTH{1'b0}} ;
            rd_len   = 8'b0 ;
            rd_burst = 2'b0 ;
            rd_size  = 3'b0 ;
            rd_id    = {ID_WIDTH{1'b0}} ;         
            rd_pop   = 1'b0 ;

            errors = 0 ;

            repeat (5) @(posedge aclk) ;
            aresetn = 1'b1 ;
            @(posedge aclk) ;
        end
    endtask


    // -------------------------------------------------------------------------
    // Mask a data word down to only the byte lanes valid for a given size,
    // starting at byte offset 0 (used to trim the expected value for narrow
    // transfers, since untouched bytes in memory stay at their reset value)
    // -------------------------------------------------------------------------
    function automatic [DATA_WIDTH-1:0] mask_narrow (
        input [2:0]              size ,
        input [DATA_WIDTH-1:0]  data
    ) ;
        integer size_bytes ;
        integer i ;
        logic [DATA_WIDTH-1:0] masked ;
        begin
            case (size)
                3'b000:  size_bytes = 1 ;
                3'b001:  size_bytes = 2 ;
                default: size_bytes = DATA_WIDTH/8 ;
            endcase

            masked = {DATA_WIDTH{1'b0}} ;
            for (i = 0; i < DATA_WIDTH/8; i = i + 1) begin
                if (i < size_bytes)
                    masked[i*8 +: 8] = data[i*8 +: 8] ;
            end

            mask_narrow = masked ;
        end
    endfunction


    task automatic do_write (
        input [ADDR_WIDTH-1:0]   addr       ,
        input [7:0]              len        ,
        input [1:0]              burst      ,
        input [2:0]              size       ,
        input [ID_WIDTH-1:0]     id         ,           
        input [DATA_WIDTH-1:0]   data_seed  ,
        input                    increment              
    ) ;
        integer k ;
        logic [DATA_WIDTH-1:0] beat_data ;
        begin
            for (k = 0; k <= len; k = k + 1) begin
                @(posedge aclk) ;
                beat_data    = increment ? (data_seed + k) : data_seed ;
                wr_push      = 1'b1                                    ;
                wr_push_data = beat_data                               ;
            end
            @(posedge aclk) ;
            wr_push = 1'b0 ;

            wr_addr  = addr  ;
            wr_len   = len   ;
            wr_burst = burst ;
            wr_size  = size  ;
            wr_id    = id    ;                 
            start_wr = 1'b1  ;
            @(posedge aclk) ;
            start_wr = 1'b0  ;

            wait (tx_done == 1'b1) ;
            @(posedge aclk) ;

            if (tx_resp !== 2'b00)
                $display("[%0t] ERROR: write response not OKAY, got %0b", $time, tx_resp) ;
            else
                $display("[%0t] Write transaction complete, resp = OKAY", $time) ;

            if (tx_done_id !== id) begin                
                $display("[%0t] ERROR: tx_done_id mismatch - expected %0d, got %0d",
                          $time, id, tx_done_id) ;
                errors = errors + 1 ;
            end
        end
    endtask


    task automatic do_read (
        input [ADDR_WIDTH-1:0] addr          ,
        input [7:0]             len          ,
        input [1:0]              burst       ,
        input [2:0]              size        ,
        input [ID_WIDTH-1:0]    id           ,       
        input [DATA_WIDTH-1:0]  data_seed    ,
        input                   increment    ,
        input [DATA_WIDTH-1:0]  add_input     
    ) ;
        integer k ;
        logic [DATA_WIDTH-1:0] beat_data ;
        logic [DATA_WIDTH-1:0] expected ;
        begin
            rd_addr  = addr  ;
            rd_len   = len   ;
            rd_burst = burst ;
            rd_size  = size  ;
            rd_id    = id    ;                         
            start_rd = 1'b1  ;
            @(posedge aclk) ;
            start_rd = 1'b0  ;

            wait (rx_done == 1'b1) ;                                     
            @(posedge aclk) ;

            if (rx_done_id !== id) begin              
                $display("[%0t] ERROR: rx_done_id mismatch - expected %0d, got %0d",
                          $time, id, rx_done_id) ;
                errors = errors + 1 ;
            end

            for (k = 0; k <= len; k = k + 1) begin
                @(posedge aclk) ;
                rd_pop = 1'b1 ;
                @(posedge aclk) ;
                rd_pop = 1'b0 ;

                beat_data = increment ? (data_seed + k) : data_seed ;
                if(!increment)
                    expected = add_input ;
                else
                    expected  = mask_narrow(size, beat_data) ;

                if (rd_pop_data !== expected) begin
                    $display("[%0t] ERROR: beat %0d mismatch - expected %h, got %h",
                              $time, k, expected, rd_pop_data) ;
                    errors = errors + 1 ;
                end
                else begin
                    $display("[%0t] beat %0d OK - data = %h", $time, k, rd_pop_data) ;
                end
            end
        end
    endtask

    task run_test (
        input [127:0]             test_name   ,
        input [ADDR_WIDTH-1:0]    addr        ,
        input [7:0]               len         ,
        input [1:0]               burst       ,
        input [2:0]               size        ,
        input [ID_WIDTH-1:0]      id          ,          // NEW
        input [DATA_WIDTH-1:0]    data_seed   ,
        input                     increment   ,
        input [DATA_WIDTH-1:0]    add_input
    ) ;
        integer errors_before ;
        begin
            test_count    = test_count + 1 ;
            errors_before = errors ;

            $display("\n=== TEST %0d: %0s ===", test_count, test_name) ;
            $display("addr=%h len=%0d burst=%0b size=%0b id=%0d", addr, len, burst, size, id) ;

            do_write ( addr , len , burst , size , id , data_seed , increment ) ;
            do_read  ( addr , len , burst , size , id , data_seed , increment , add_input ) ;

            if (errors == errors_before)
                $display("--- TEST %0d PASSED ---", test_count) ;
            else
                $display("--- TEST %0d FAILED (%0d new errors) ---", test_count, errors - errors_before) ;
        end
    endtask

        // -------------------------------------------------------------------------
    // Concurrent write/read task - runs do_write and do_read in parallel
    // to test that the write channel and read channel operate independently
    // (AXI multitasking / overlapping outstanding transactions)
    // -------------------------------------------------------------------------
    task automatic do_concurrent_test (
        input [127:0]            test_name     ,
        input [ADDR_WIDTH-1:0]    wr_addr_c    ,
        input [7:0]               wr_len_c     ,
        input [1:0]               wr_burst_c   ,
        input [2:0]               wr_size_c    ,
        input [ID_WIDTH-1:0]      wr_id_c      ,
        input [DATA_WIDTH-1:0]    wr_seed_c    ,
        input                     wr_inc_c     ,

        input [ADDR_WIDTH-1:0]    rd_addr_c    ,
        input [7:0]               rd_len_c     ,
        input [1:0]               rd_burst_c   ,
        input [2:0]               rd_size_c    ,
        input [ID_WIDTH-1:0]      rd_id_c      ,
        input [DATA_WIDTH-1:0]    rd_seed_c    ,
        input                     rd_inc_c     ,
        input [DATA_WIDTH-1:0]    rd_add_c
    ) ;
        integer errors_before ;
        begin
            test_count    = test_count + 1 ;
            errors_before = errors ;

            $display("\n=== TEST %0d (CONCURRENT): %0s ===", test_count, test_name) ;
            $display("  WRITE: addr=%h len=%0d id=%0d", wr_addr_c, wr_len_c, wr_id_c) ;
            $display("  READ : addr=%h len=%0d id=%0d", rd_addr_c, rd_len_c, rd_id_c) ;

            fork
                do_write ( wr_addr_c , wr_len_c , wr_burst_c , wr_size_c , wr_id_c ,
                           wr_seed_c , wr_inc_c ) ;

                do_read  ( rd_addr_c , rd_len_c , rd_burst_c , rd_size_c , rd_id_c ,
                           rd_seed_c , rd_inc_c , rd_add_c ) ;
            join

            if (errors == errors_before)
                $display("--- TEST %0d PASSED (concurrent) ---", test_count) ;
            else
                $display("--- TEST %0d FAILED (%0d new errors, concurrent) ---",
                          test_count, errors - errors_before) ;
        end
    endtask
    
    

     

   


    // -------------------------------------------------------------------------
    // VCD Dump Generation
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("axi_top_tb.vcd"); // Specifies the name of the output VCD file
        $dumpvars(0, axi_top_tb);     // Dumps all signals in axi_top_tb and child modules
    end

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        errors     = 0 ;
        test_count = 0 ;

        do_reset ;

        run_test ( "4-beat INCR write/read at addr 0" ,
            32'h0000_0000 , 8'd3 , 2'b01 , 3'b010 , 4'd1 , 32'hA0A0_0000 , 1'b1 , 'b0 ) ;

        run_test ( "single-beat INCR write/read at addr 0x40" ,
            32'h0000_0040 , 8'd0 , 2'b01 , 3'b010 , 4'd2 , 32'hDEAD_0000  , 1'b1 , 'b0 ) ;

        run_test ( "8-beat INCR write/read at addr 0x100" ,
            32'h0000_0100 , 8'd7 , 2'b01 , 3'b010 , 4'd3 , 32'hCAFE_0000  , 1'b1 , 'b0 ) ;

        run_test ( "4-beat WRAP write/read at addr 0x200" ,
            32'h0000_0200 , 8'd3 , 2'b10 , 3'b010 , 4'd4 , 32'hBEEF_0000  , 1'b1 , 'b0  ) ;

        run_test ( "8-beat WRAP write/read at addr 0x318 (mid-boundary start)" ,
            32'h0000_0318 , 8'd7 , 2'b10 , 3'b010 , 4'd5 , 32'hFACE_0000  , 1'b1 , 'b0  ) ;

        run_test ( "2-beat WRAP write/read at addr 0x500" ,
            32'h0000_0500 , 8'd1 , 2'b10 , 3'b010 , 4'd6 , 32'h2222_0000 , 1'b1 , 'b0  ) ;

        run_test ( "4-beat INCR write/read near upper address bound" ,
            32'h0000_FFE0 , 8'd3 , 2'b01 , 3'b010 , 4'd7 , 32'h4444_0000  , 1'b1 , 'b0 ) ;

        run_test ( "single-beat WRAP write/read at addr 0x700" ,
            32'h0000_0700 , 8'd0 , 2'b10 , 3'b010 , 4'd8 , 32'h5555_0000  , 1'b1 , 'b0 ) ;

        run_test ( "4-beat narrow (2-byte) INCR write/read at addr 0xA00" ,
            32'h0000_0A00 , 8'd3 , 2'b01 , 3'b001 , 4'd9 , 32'h8888_0000  , 1'b0 , 32'h8888_0000 ) ;

        run_test ( "4-beat narrow (1-byte) INCR write/read at addr 0xB00" ,
            32'h0000_0B00 , 8'd3 , 2'b01 , 3'b000 , 4'd10 , 32'h9999_0000,  1'b0  , 32'h9999_0000 ) ;

        run_test ( "4-beat narrow (1-byte) INCR write/read at addr 0xB00" ,
                 32'h0000_0BB0 , 8'd3 , 2'b01 , 3'b000 , 4'd11 , 32'hFFFF_01AA,  1'b0  , 32'hFFFF_01AA  ) ;

        run_test ( "16-beat INCR write/read at addr 0x1400" ,
            32'h0000_1400 , 8'd15 , 2'b01 , 3'b010 , 4'd12 , 32'h6789_0000 , 1'b1 , 'b0 ) ;

        // three writes in a row
        run_test ( "write 1 at addr 0x1500" , 32'h0000_1500 , 8'd3 , 2'b01 , 3'b010 , 4'd1 , 32'h1010_0000 , 1'b1 , 'b0 ) ;
        run_test ( "write 2 at addr 0x1540" , 32'h0000_1540 , 8'd3 , 2'b01 , 3'b010 , 4'd2 , 32'h2020_0000 , 1'b1 , 'b0 ) ;
        run_test ( "write 3 at addr 0x1580" , 32'h0000_1580 , 8'd3 , 2'b01 , 3'b010 , 4'd3 , 32'h3030_0000 , 1'b1 , 'b0 ) ;

        // three reads in a row
        run_test ( "read 1 at addr 0x1600" , 32'h0000_1600 , 8'd3 , 2'b01 , 3'b010 , 4'd4 , 32'h4040_0000 , 1'b1 , 'b0 ) ;
        run_test ( "read 2 at addr 0x1640" , 32'h0000_1640 , 8'd3 , 2'b01 , 3'b010 , 4'd5 , 32'h5050_0000 , 1'b1 , 'b0 ) ;
        run_test ( "read 3 at addr 0x1680" , 32'h0000_1680 , 8'd3 , 2'b01 , 3'b010 , 4'd6 , 32'h6060_0000 , 1'b1 , 'b0 ) ;

        // rapid single-beat writes back to back
        run_test ( "rapid write at addr 0x1800" , 32'h0000_1800 , 8'd0 , 2'b01 , 3'b010 , 4'd7 , 32'hA1A1_0000 , 1'b1 , 'b0 ) ;
        run_test ( "rapid write at addr 0x1804" , 32'h0000_1804 , 8'd0 , 2'b01 , 3'b010 , 4'd8 , 32'hA2A2_0000 , 1'b1 , 'b0 ) ;
        run_test ( "rapid write at addr 0x1808" , 32'h0000_1808 , 8'd0 , 2'b01 , 3'b010 , 4'd9 , 32'hA3A3_0000 , 1'b1 , 'b0 ) ;

        // WRAP burst, 4 beats, aligned start at a fresh address
        run_test ( "4-beat WRAP write/read at addr 0x1900" ,
            32'h0000_1900 , 8'd3 , 2'b10 , 3'b010 , 4'd10 , 32'hB1B1_0000 , 1'b1 , 'b0 ) ;

        // WRAP burst, 8 beats, starting exactly at the boundary
        run_test ( "8-beat WRAP write/read at addr 0x1A00" ,
            32'h0000_1A00 , 8'd7 , 2'b10 , 3'b010 , 4'd11 , 32'hB2B2_0000 , 1'b1 , 'b0 ) ;

        // WRAP burst, 4 beats, starting one word before the boundary -
        // wraps almost immediately (on beat 2)
        run_test ( "4-beat WRAP write/read at addr 0x1B0C (wrap early)" ,
            32'h0000_1B0C , 8'd3 , 2'b10 , 3'b010 , 4'd12 , 32'hB3B3_0000 , 1'b1 , 'b0 ) ;

        // WRAP burst, 8 beats, starting near the end of the window -
        // wraps with only 1 beat before hitting the boundary
        run_test ( "8-beat WRAP write/read at addr 0x1C1C (wrap after 1 beat)" ,
            32'h0000_1C1C , 8'd7 , 2'b10 , 3'b010 , 4'd13 , 32'hB4B4_0000 , 1'b1 , 'b0 ) ;

        // WRAP burst, 16 beats, starting mid-window
        run_test ( "16-beat WRAP write/read at addr 0x1D20 (mid-boundary start)" ,
            32'h0000_1D20 , 8'd15 , 2'b10 , 3'b010 , 4'd14 , 32'hB5B5_0000 , 1'b1 , 'b0 ) ;

        // two WRAP bursts back to back, no writes/reads in between
        run_test ( "WRAP write/read 1 of 2 at addr 0x1E00" ,
            32'h0000_1E00 , 8'd3 , 2'b10 , 3'b010 , 4'd15 , 32'hB6B6_0000 , 1'b1 , 'b0 ) ;
        run_test ( "WRAP write/read 2 of 2 at addr 0x1E40" ,
            32'h0000_1E40 , 8'd3 , 2'b10 , 3'b010 , 4'd0 , 32'hB7B7_0000 , 1'b1 , 'b0 ) ;
        
                // -------------------------------------------------------------------
        // Prime a location so the concurrent read has known data to check
        // -------------------------------------------------------------------
        run_test ( "prime addr 0x2000 for concurrent read test" ,
            32'h0000_2000 , 8'd3 , 2'b01 , 3'b010 , 4'd1 , 32'h7777_0000 , 1'b1 , 'b0 ) ;

        // -------------------------------------------------------------------
        // Concurrent write (new address) + read (primed address) using fork/join
        // Exercises independent AW/W and AR/R channel handling at the same time
        // -------------------------------------------------------------------
        do_concurrent_test (
            "concurrent write @0x2100 / read @0x2000" ,
            32'h0000_2100 , 8'd3 , 2'b01 , 3'b010 , 4'd13 , 32'hC0C0_0000 , 1'b1 ,   // write args
            32'h0000_2000 , 8'd3 , 2'b01 , 3'b010 , 4'd1  , 32'h7777_0000 , 1'b1 , 'b0  // read args
        ) ;

        // second concurrent case: overlapping IDs on write vs read side,
        // different addresses, to stress arbitration further
        do_concurrent_test (
            "concurrent write @0x2200 / read @0x2100" ,
            32'h0000_2200 , 8'd7 , 2'b10 , 3'b010 , 4'd14 , 32'hD0D0_0000 , 1'b1 ,   // write args
            32'h0000_2100 , 8'd3 , 2'b01 , 3'b010 , 4'd13 , 32'hC0C0_0000 , 1'b1 , 'b0  // read args
        ) ;
         
        run_test ( "4-beat narrow (1-byte) INCR write/read at addr 0xC00" ,
            32'h0000_0C00 , 8'd3 , 2'b01 , 3'b000 , 4'd11 , 32'hAABB_0000,  1'b0  , 32'hAABB_0000 ) ;

run_test ( "4-beat narrow (1-byte) INCR write/read at addr 0xC40" ,
            32'h0000_0C40 , 8'd3 , 2'b01 , 3'b000 , 4'd12 , 32'hCCDD_0000,  1'b0  , 32'hCCDD_0000 ) ;

run_test ( "4-beat narrow (2-byte) INCR write/read at addr 0xD00" ,
            32'h0000_0D00 , 8'd3 , 2'b01 , 3'b001 , 4'd13 , 32'hEEFF_0000,  1'b0  , 32'hEEFF_0000 ) ;

run_test ( "4-beat narrow (2-byte) INCR write/read at addr 0xD40" ,
            32'h0000_0D40 , 8'd3 , 2'b01 , 3'b001 , 4'd14 , 32'h1122_0000,  1'b0  , 32'h1122_0000 ) ;

run_test ( "8-beat narrow (1-byte) INCR write/read at addr 0xE00" ,
            32'h0000_0E00 , 8'd7 , 2'b01 , 3'b000 , 4'd15 , 32'h3344_0000,  1'b0  , 32'h3344_0000 ) ;






        repeat (10) @(posedge aclk) ;

        $display("\n=====================================") ;
        if (errors == 0)
            $display("=== ALL %0d TESTS PASSED ===", test_count) ;
        else
            $display("=== TESTS FAILED: %0d total errors across %0d tests ===", errors, test_count) ;
        $display("=====================================") ;

        $stop ;
    end

endmodule