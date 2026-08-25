`timescale 1ns/1ps

module axi_top_1m3s_tb ;

    // parameters matching the DUT
    localparam ADDR_WIDTH = 32 ;
    localparam DATA_WIDTH = 32 ;
    localparam ID_WIDTH   = 4  ;
    localparam FIFO_DEPTH = 16 ;
    localparam OUT_DEPTH  = 2  ;
    localparam MEM_DEPTH  = 256 ;
    localparam NUM_SLAVES = 3 ;

    // clock / reset
    logic aclk    ;
    logic aresetn ;

    // write side
    logic                     start_wr        ;
    logic [ADDR_WIDTH-1:0]    wr_addr         ;
    logic [7:0]               wr_len          ;
    logic [1:0]               wr_burst        ;
    logic [2:0]               wr_size         ;
    logic [ID_WIDTH-1:0]      wr_id           ;
    logic                     wr_aw_fifo_full ;
    logic                     wr_push         ;
    logic [DATA_WIDTH-1:0]    wr_push_data    ;
    logic                     wr_fifo_full    ;
    logic                     tx_done         ;
    logic [ID_WIDTH-1:0]      tx_done_id      ;
    logic [1:0]               tx_resp         ;
    logic [$clog2(OUT_DEPTH+1)-1:0] wr_outstanding_cnt ;

    // read side
    logic                     start_rd        ;
    logic [ADDR_WIDTH-1:0]    rd_addr         ;
    logic [7:0]               rd_len          ;
    logic [1:0]               rd_burst        ;
    logic [2:0]               rd_size         ;
    logic [ID_WIDTH-1:0]      rd_id           ;
    logic                     rd_ar_fifo_full ;
    logic                     rd_pop          ;
    logic [DATA_WIDTH-1:0]    rd_pop_data     ;
    logic                     rd_fifo_empty   ;
    logic                     rx_done         ;
    logic [ID_WIDTH-1:0]      rx_done_id      ;

    integer errors     ;
    integer test_count ;


    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    axi_top_1m3s #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH), .OUT_DEPTH(OUT_DEPTH), .MEM_DEPTH(MEM_DEPTH),
        .NUM_SLAVES(NUM_SLAVES)
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


    // -------------------------------------------------------------------------
    // Write task - generic: any address, length, burst type, size, id, data seed
    // -------------------------------------------------------------------------
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


    // -------------------------------------------------------------------------
    // Read task - generic, checks against data_seed
    // -------------------------------------------------------------------------
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


    // -------------------------------------------------------------------------
    // Combined write+read+check task
    // -------------------------------------------------------------------------
    task run_test (
        input [127:0]             test_name   ,
        input [ADDR_WIDTH-1:0]    addr        ,
        input [7:0]               len         ,
        input [1:0]               burst       ,
        input [2:0]               size        ,
        input [ID_WIDTH-1:0]      id          ,
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
    // Concurrent write/read task - runs do_write and do_read in parallel to
    // check that a write to one slave and a read from another slave can be
    // in flight at the same time through the shared interconnect
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
        $dumpfile("axi_top_1m3s_tb.vcd") ;
        $dumpvars(0, axi_top_1m3s_tb) ;
    end


    // -------------------------------------------------------------------------
    // Main test sequence
    // Slave map (set in axi_top_1m3s):
    //   slave 0: 0x0000_0000 - 0x0000_0FFF
    //   slave 1: 0x0000_1000 - 0x0000_1FFF
    //   slave 2: 0x0000_2000 - 0x0000_2FFF
    // -------------------------------------------------------------------------
    initial begin
        errors     = 0 ;
        test_count = 0 ;

        do_reset ;

        // Test 1: write/read to slave 0's region
        run_test ( "4-beat INCR write/read at addr 0x0000 (slave 0)" ,
            32'h0000_0000 , 8'd3 , 2'b01 , 3'b010 , 4'd1 , 32'hA0A0_0000 , 1'b1 , 'b0 ) ;

        // Test 2: write/read to slave 1's region
        run_test ( "4-beat INCR write/read at addr 0x1000 (slave 1)" ,
            32'h0000_1000 , 8'd3 , 2'b01 , 3'b010 , 4'd2 , 32'hB0B0_0000 , 1'b1 , 'b0 ) ;

        // Test 3: write/read to slave 2's region
        run_test ( "4-beat INCR write/read at addr 0x2000 (slave 2)" ,
            32'h0000_2000 , 8'd3 , 2'b01 , 3'b010 , 4'd3 , 32'hC0C0_0000 , 1'b1 , 'b0 ) ;

        // Test 4: write near the top of slave 0's region, close to the
        // boundary with slave 1, to check the decoder's edge behavior
        run_test ( "4-beat INCR write/read near top of slave 0 (addr 0x0FE0)" ,
            32'h0000_0FE0 , 8'd3 , 2'b01 , 3'b010 , 4'd4 , 32'hD0D0_0000 , 1'b1 , 'b0 ) ;

        // Test 5: write near the bottom of slave 1's region, right after
        // the boundary from slave 0
        run_test ( "4-beat INCR write/read near bottom of slave 1 (addr 0x1000)" ,
            32'h0000_1000 , 8'd3 , 2'b01 , 3'b010 , 4'd5 , 32'hE0E0_0000 , 1'b1 , 'b0 ) ;

        // Test 6: WRAP burst inside slave 1's region
        run_test ( "4-beat WRAP write/read at addr 0x1200 (slave 1)" ,
            32'h0000_1200 , 8'd3 , 2'b10 , 3'b010 , 4'd6 , 32'hF0F0_0000 , 1'b1 , 'b0 ) ;

        // Test 7: interleaved - write to slave 0, then slave 2, then slave 1,
        // then read each back in a different order, to check the interconnect
        // correctly tracks slave_sel across separate, sequential transactions
        run_test ( "interleave step A - write slave 0 (addr 0x0100)" ,
            32'h0000_0100 , 8'd3 , 2'b01 , 3'b010 , 4'd7 , 32'h1111_0000 , 1'b1 , 'b0 ) ;
        run_test ( "interleave step B - write slave 2 (addr 0x2100)" ,
            32'h0000_2100 , 8'd3 , 2'b01 , 3'b010 , 4'd8 , 32'h2222_0000 , 1'b1 , 'b0 ) ;
        run_test ( "interleave step C - write slave 1 (addr 0x1100)" ,
            32'h0000_1100 , 8'd3 , 2'b01 , 3'b010 , 4'd9 , 32'h3333_0000 , 1'b1 , 'b0 ) ;

        begin
            integer errors_before ;
            test_count    = test_count + 1 ;
            errors_before = errors ;
            $display("\n=== TEST %0d: interleave step D - read back slave 1, then slave 0, then slave 2 ===", test_count) ;

            do_read ( 32'h0000_1100 , 8'd3 , 2'b01 , 3'b010 , 4'd9 , 32'h3333_0000 , 1'b1 , 'b0 ) ;
            do_read ( 32'h0000_0100 , 8'd3 , 2'b01 , 3'b010 , 4'd7 , 32'h1111_0000 , 1'b1 , 'b0 ) ;
            do_read ( 32'h0000_2100 , 8'd3 , 2'b01 , 3'b010 , 4'd8 , 32'h2222_0000 , 1'b1 , 'b0 ) ;

            if (errors == errors_before)
                $display("--- TEST %0d PASSED ---", test_count) ;
            else
                $display("--- TEST %0d FAILED (%0d new errors) ---", test_count, errors - errors_before) ;
        end

        // Test 8: single-beat transfers to each slave in quick succession
        run_test ( "single-beat write/read slave 0 (addr 0x0300)" ,
            32'h0000_0300 , 8'd0 , 2'b01 , 3'b010 , 4'd10 , 32'h4444_0000 , 1'b1 , 'b0 ) ;
        run_test ( "single-beat write/read slave 1 (addr 0x1300)" ,
            32'h0000_1300 , 8'd0 , 2'b01 , 3'b010 , 4'd11 , 32'h5555_0000 , 1'b1 , 'b0 ) ;
        run_test ( "single-beat write/read slave 2 (addr 0x2300)" ,
            32'h0000_2300 , 8'd0 , 2'b01 , 3'b010 , 4'd12 , 32'h6666_0000 , 1'b1 , 'b0 ) ;

        // Test 9: narrow (1-byte) transfer into slave 2's region
        run_test ( "4-beat narrow (1-byte) INCR write/read at addr 0x2400 (slave 2)" ,
            32'h0000_2400 , 8'd3 , 2'b01 , 3'b000 , 4'd13 , 32'h9999_0000 , 1'b0 , 32'h9999_0000 ) ;

        // Test 10: concurrent write to slave 2 while reading back a
        // previously-primed location in slave 0 - checks that the two
        // channels aren't serialized incorrectly by the interconnect
        run_test ( "prime addr 0x0500 in slave 0 for concurrent read" ,
            32'h0000_0500 , 8'd3 , 2'b01 , 3'b010 , 4'd14 , 32'h7777_0000 , 1'b1 , 'b0 ) ;

        do_concurrent_test (
            "concurrent write @0x2500 (slave 2) / read @0x0500 (slave 0)" ,
            32'h0000_2500 , 8'd3 , 2'b01 , 3'b010 , 4'd15 , 32'h8A8A_0000 , 1'b1 ,   // write args
            32'h0000_0500 , 8'd3 , 2'b01 , 3'b010 , 4'd14 , 32'h7777_0000 , 1'b1 , 'b0  // read args
        ) ;

        // Test 11: concurrent write to slave 1 while reading back from
        // slave 2, to exercise a different pair of slaves at once
        do_concurrent_test (
            "concurrent write @0x1500 (slave 1) / read @0x2500 (slave 2)" ,
            32'h0000_1500 , 8'd7 , 2'b10 , 3'b010 , 4'd0 , 32'h9B9B_0000 , 1'b1 ,   // write args
            32'h0000_2500 , 8'd3 , 2'b01 , 3'b010 , 4'd15 , 32'h8A8A_0000 , 1'b1 , 'b0  // read args
        ) ;

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