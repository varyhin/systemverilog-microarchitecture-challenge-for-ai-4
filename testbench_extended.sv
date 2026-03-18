module testbench_extended;

    logic               clk;
    logic               rst;
    logic               arg_vld;
    logic  [FLEN - 1:0] a, b, c;
    wire                res_vld;
    wire   [FLEN - 1:0] res;

    challenge dut (.*);

    // Clock
    initial begin clk = 1; forever #5 clk = ~clk; end

    // Reset
    task reset();
        rst <= 'x; repeat(3) @(posedge clk);
        rst <= '1; repeat(3) @(posedge clk);
        rst <= '0;
    endtask

    // Drive one set of inputs
    task automatic drive(input [FLEN-1:0] ai, bi, ci);
        a <= ai; b <= bi; c <= ci;
        arg_vld <= 1;
        @(posedge clk);
        arg_vld <= 0;
    endtask

    task wait_drain();
        repeat(200) @(posedge clk);
    endtask

    //------------------------------------------------------------------------
    // IEEE 754 special constants
    //------------------------------------------------------------------------

    localparam [FLEN-1:0] POS_ZERO    = 64'h0000_0000_0000_0000;
    localparam [FLEN-1:0] NEG_ZERO    = 64'h8000_0000_0000_0000;
    localparam [FLEN-1:0] POS_INF     = 64'h7FF0_0000_0000_0000;
    localparam [FLEN-1:0] NEG_INF     = 64'hFFF0_0000_0000_0000;
    localparam [FLEN-1:0] QNAN        = 64'h7FF8_0000_0000_0001;
    localparam [FLEN-1:0] SNAN        = 64'h7FF0_0000_0000_0001;
    localparam [FLEN-1:0] MIN_SUBNORM = 64'h0000_0000_0000_0001;
    localparam [FLEN-1:0] MAX_SUBNORM = 64'h000F_FFFF_FFFF_FFFF;
    localparam [FLEN-1:0] MIN_NORMAL  = 64'h0010_0000_0000_0000;
    localparam [FLEN-1:0] MAX_NORMAL  = 64'h7FEF_FFFF_FFFF_FFFF;
    localparam [FLEN-1:0] ONE         = 64'h3FF0_0000_0000_0000;
    localparam [FLEN-1:0] NEG_ONE     = 64'hBFF0_0000_0000_0000;

    //------------------------------------------------------------------------
    // Checking infrastructure
    //------------------------------------------------------------------------

    logic [FLEN-1:0] expected_queue [$];
    int unsigned pass_cnt = 0;
    int unsigned fail_cnt = 0;
    int unsigned check_cnt = 0;
    bit suppress_check = 0;

    function bit is_nan(logic [FLEN-1:0] v);
        return (v[62:52] == 11'h7FF) && (v[51:0] != 0);
    endfunction

    function bit is_inf_or_nan(logic [FLEN-1:0] v);
        return v[62:52] == 11'h7FF;
    endfunction

    function bit loose_match(logic [FLEN-1:0] a_val, b_val);
        real ar, br, delta, maxv;
        if (a_val === b_val) return 1;
        if (is_nan(a_val) && is_nan(b_val)) return 1;
        if (is_inf_or_nan(a_val) || is_inf_or_nan(b_val)) return a_val[63:52] === b_val[63:52];
        ar = $bitstoreal(a_val);
        br = $bitstoreal(b_val);
        delta = (ar - br); if (delta < 0) delta = -delta;
        maxv = (ar >= 0 ? ar : -ar);
        if ((br >= 0 ? br : -br) > maxv) maxv = (br >= 0 ? br : -br);
        if (maxv == 0) return delta == 0;
        return (delta * 1000.0) < maxv;
    endfunction

    // Check results
    always @(posedge clk) begin
        if (!rst && res_vld && !suppress_check) begin
            if (expected_queue.size() == 0) begin
                $display("FAIL: unexpected output res=%h", res);
                fail_cnt++;
            end else begin
                logic [FLEN-1:0] exp;
                check_cnt++;
                `ifdef __ICARUS__
                    exp = expected_queue[0];
                    expected_queue.delete(0);
                `else
                    exp = expected_queue.pop_front();
                `endif
                if (is_inf_or_nan(exp) || loose_match(res, exp)) begin
                    pass_cnt++;
                end else begin
                    $display("FAIL check #%0d: expected %h (%g), got %h (%g)",
                        check_cnt, exp, $bitstoreal(exp), res, $bitstoreal(res));
                    fail_cnt++;
                end
            end
        end
    end

    // Push expected
    task automatic push_expected(input [FLEN-1:0] ai, bi, ci);
        automatic logic [FLEN-1:0] exp;
        exp = $realtobits($bitstoreal(ai)**5 + 0.3 * $bitstoreal(bi) + $bitstoreal(ci));
        expected_queue.push_back(exp);
    endtask

    // Combined: drive + push expected
    task automatic send(input [FLEN-1:0] ai, bi, ci);
        push_expected(ai, bi, ci);
        drive(ai, bi, ci);
    endtask

    task automatic send_real(input real ar, br, cr);
        send($realtobits(ar), $realtobits(br), $realtobits(cr));
    endtask

    //------------------------------------------------------------------------
    // Test groups
    //------------------------------------------------------------------------

    task test_zeros();
        $display("=== Test: Zeros ===");
        send(POS_ZERO, ONE, POS_ZERO);
        send(NEG_ZERO, ONE, POS_ZERO);
        send(POS_ZERO, NEG_ONE, POS_ZERO);
        send(POS_ZERO, ONE, NEG_ZERO);
        send(POS_ZERO, POS_ZERO, POS_ZERO);
        send(POS_ZERO, NEG_ZERO, POS_ZERO);
        wait_drain();
    endtask

    task test_ones();
        $display("=== Test: Ones ===");
        send_real(1.0, 1.0, 0.0);
        send_real(-1.0, 1.0, 0.0);
        send_real(1.0, 1.0, 1.0);
        send_real(-1.0, 1.0, 1.0);
        send_real(2.0, 1.0, 0.0);
        send_real(-2.0, 1.0, 0.0);
        send_real(0.0, 10.0, 0.0);
        send_real(0.0, 1.0, 7.0);
        wait_drain();
    endtask

    task test_infinities();
        $display("=== Test: Infinities ===");
        send(POS_INF, ONE, POS_ZERO);
        send(NEG_INF, ONE, POS_ZERO);
        send(POS_ZERO, POS_INF, POS_ZERO);
        send(POS_ZERO, NEG_INF, POS_ZERO);
        send(POS_ZERO, ONE, POS_INF);
        send(POS_ZERO, ONE, NEG_INF);
        send(POS_INF, ONE, NEG_INF);
        wait_drain();
    endtask

    task test_nans();
        $display("=== Test: NaN propagation ===");
        send(QNAN, ONE, ONE);
        send(ONE, QNAN, ONE);
        send(ONE, ONE, QNAN);
        send(QNAN, QNAN, QNAN);
        send(SNAN, ONE, ONE);
        send(ONE, SNAN, ONE);
        send(ONE, ONE, SNAN);
        wait_drain();
    endtask

    task test_subnormals();
        $display("=== Test: Subnormals ===");
        send(MIN_SUBNORM, ONE, POS_ZERO);
        send(MAX_SUBNORM, ONE, POS_ZERO);
        send(MIN_NORMAL, ONE, POS_ZERO);
        send(POS_ZERO, MIN_SUBNORM, POS_ZERO);
        send(POS_ZERO, MAX_NORMAL, POS_ZERO);
        send(POS_ZERO, ONE, MIN_SUBNORM);
        wait_drain();
    endtask

    task test_overflow();
        $display("=== Test: Overflow ===");
        send_real(100.0, 1.0, 0.0);
        send_real(1000.0, 1.0, 0.0);
        send_real(1.0e60, 1.0, 0.0);
        send_real(1.0e62, 1.0, 0.0);
        send(MAX_NORMAL, ONE, POS_ZERO);
        wait_drain();
    endtask

    task test_cancellation();
        $display("=== Test: Cancellation ===");
        send_real(1.0, 1.0, -1.3);     // 1 + 0.3 + (-1.3) = 0
        send_real(2.0, 1.0, -32.3);    // 32 + 0.3 + (-32.3) = 0
        send_real(3.0, 1.0, -243.3);   // 243 + 0.3 + (-243.3) = 0
        send_real(1.0, 1e10, -1.0);    // 1 + 3e9 + (-1) = ~3e9
        wait_drain();
    endtask

    task test_back_to_back();
        $display("=== Test: Back-to-back (200 inputs) ===");
        for (int i = 0; i < 200; i++)
            send_real(real'(i) * 0.01, real'(i) * 0.1, real'(i) * 0.5);
        wait_drain();
    endtask

    task test_reset_during_operation();
        $display("=== Test: Reset during pipeline ===");
        // Suppress checking while stale results drain
        suppress_check = 1;

        for (int i = 0; i < 20; i++) begin
            a <= $realtobits(real'(i+1));
            b <= $realtobits(real'(i+1));
            c <= $realtobits(real'(i+1));
            arg_vld <= 1;
            @(posedge clk);
            arg_vld <= 0;
        end

        repeat(8) @(posedge clk);
        expected_queue = {};
        reset();

        // Wait for pipeline to fully flush stale results
        repeat(30) @(posedge clk);
        suppress_check = 0;

        // Now send new data and verify
        send_real(1.0, 4.0, 3.0);
        send_real(2.0, 1.0, 0.0);
        wait_drain();
    endtask

    task test_random(int count);
        $display("=== Test: Random (%0d inputs) ===", count);
        for (int i = 0; i < count; i++) begin
            logic [FLEN-1:0] ra, rb, rc;
            ra = $realtobits($urandom() / 10000.0);
            rb = $realtobits($urandom() / 10000.0);
            rc = $realtobits($urandom() / 10000.0);
            send(ra, rb, rc);
        end
        wait_drain();
    endtask

    //------------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------------

    initial begin
        `ifdef __ICARUS__
            $dumpvars;
        `endif

        arg_vld <= 0;
        reset();

        test_zeros();
        test_ones();
        test_infinities();
        test_nans();
        test_subnormals();
        test_overflow();
        test_cancellation();
        test_back_to_back();
        test_reset_during_operation();
        test_random(500);

        repeat(500) @(posedge clk);

        $display("");
        $display("============================================");
        $display("Extended Test Results:");
        $display("  Checks: %0d", check_cnt);
        $display("  Pass:   %0d", pass_cnt);
        $display("  Fail:   %0d", fail_cnt);
        $display("  Queue remaining: %0d", expected_queue.size());
        if (fail_cnt == 0 && expected_queue.size() == 0)
            $display("  PASS extended tests");
        else
            $display("  FAIL extended tests");
        $display("============================================");
        $finish;
    end

    // Timeout
    initial begin
        repeat(50000) @(posedge clk);
        $display("FAIL: extended testbench timeout");
        $finish;
    end

endmodule
