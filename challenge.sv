/*

Put any submodules you need here.

You are not allowed to implement your own submodules or functions for the addition,
subtraction, multiplication, division, comparison or getting the square
root of floating-point numbers. For such operations you can only use the
modules from the arithmetic_block_wrappers directory.

*/

module challenge
(
    input  logic                clk,
    input  logic                rst,

    input  logic                arg_vld,
    input  logic [FLEN - 1:0]  a,
    input  logic [FLEN - 1:0]  b,
    input  logic [FLEN - 1:0]  c,

    output logic                res_vld,
    output logic [FLEN - 1:0]  res
);

    //----------------------------------------------------------------------
    // Constants
    //----------------------------------------------------------------------

    localparam logic [FLEN - 1:0] CONST_0_3 = 64'h3FD3333333333333;

    //----------------------------------------------------------------------
    // Delay lines
    //----------------------------------------------------------------------

    // a: 6 stages (needed at cycle 6 for mult4)
    logic [FLEN - 1:0] a_delay [6];

    // p (0.3*b result): 6 stages (available at cycle 3, needed at cycle 9)
    logic [FLEN - 1:0] p_delay [6];

    // c: 13 stages (needed at cycle 13 for add2)
    logic [FLEN - 1:0] c_delay [13];

    always_ff @(posedge clk) begin
        a_delay[0] <= a;
        for (int i = 1; i < 6; i++)
            a_delay[i] <= a_delay[i - 1];

        c_delay[0] <= c;
        for (int i = 1; i < 13; i++)
            c_delay[i] <= c_delay[i - 1];
    end

    //----------------------------------------------------------------------
    // Arithmetic wires
    //----------------------------------------------------------------------

    logic [FLEN - 1:0] a2, p, a4, a5, sum1, final_result;
    logic mult1_dv, mult2_dv, mult3_dv, mult4_dv;
    logic mult1_busy, mult2_busy, mult3_busy, mult4_busy;
    logic mult1_err, mult2_err, mult3_err, mult4_err;
    logic add1_dv, add2_dv;
    logic add1_busy, add2_busy;
    wire  add1_err, add2_err; // wire: f_add has dual-driver on error port

    //----------------------------------------------------------------------
    // Stage 1a: a * a -> a2 (latency 3, cycle 0 -> 3)
    //----------------------------------------------------------------------

    f_mult mult1 (
        .clk       ( clk       ),
        .rst       ( rst       ),
        .a         ( a         ),
        .b         ( a         ),
        .up_valid  ( arg_vld   ),
        .res       ( a2        ),
        .down_valid( mult1_dv  ),
        .busy      ( mult1_busy),
        .error     ( mult1_err )
    );

    //----------------------------------------------------------------------
    // Stage 1b: 0.3 * b -> p (latency 3, cycle 0 -> 3, parallel)
    //----------------------------------------------------------------------

    f_mult mult2 (
        .clk       ( clk       ),
        .rst       ( rst       ),
        .a         ( CONST_0_3 ),
        .b         ( b         ),
        .up_valid  ( arg_vld   ),
        .res       ( p         ),
        .down_valid( mult2_dv  ),
        .busy      ( mult2_busy),
        .error     ( mult2_err )
    );

    // p delay line (from mult2 output at cycle 3, needed at cycle 9)
    always_ff @(posedge clk) begin
        p_delay[0] <= p;
        for (int i = 1; i < 6; i++)
            p_delay[i] <= p_delay[i - 1];
    end

    //----------------------------------------------------------------------
    // Stage 2: a2 * a2 -> a4 (latency 3, cycle 3 -> 6)
    //----------------------------------------------------------------------

    f_mult mult3 (
        .clk       ( clk       ),
        .rst       ( rst       ),
        .a         ( a2        ),
        .b         ( a2        ),
        .up_valid  ( mult1_dv  ),
        .res       ( a4        ),
        .down_valid( mult3_dv  ),
        .busy      ( mult3_busy),
        .error     ( mult3_err )
    );

    //----------------------------------------------------------------------
    // Stage 3: a4 * a_delay[5] -> a5 (latency 3, cycle 6 -> 9)
    //----------------------------------------------------------------------

    f_mult mult4 (
        .clk       ( clk        ),
        .rst       ( rst        ),
        .a         ( a4         ),
        .b         ( a_delay[5] ),
        .up_valid  ( mult3_dv   ),
        .res       ( a5         ),
        .down_valid( mult4_dv   ),
        .busy      ( mult4_busy ),
        .error     ( mult4_err  )
    );

    //----------------------------------------------------------------------
    // Stage 4: a5 + p_delay[5] -> sum1 (latency 4, cycle 9 -> 13)
    //----------------------------------------------------------------------

    f_add add1 (
        .clk       ( clk        ),
        .rst       ( rst        ),
        .a         ( a5         ),
        .b         ( p_delay[5] ),
        .up_valid  ( mult4_dv   ),
        .res       ( sum1       ),
        .down_valid( add1_dv    ),
        .busy      ( add1_busy  ),
        .error     ( add1_err   )
    );

    //----------------------------------------------------------------------
    // Stage 5: sum1 + c_delay[12] -> final_result (latency 4, cycle 13 -> 17)
    //----------------------------------------------------------------------

    f_add add2 (
        .clk       ( clk          ),
        .rst       ( rst          ),
        .a         ( sum1         ),
        .b         ( c_delay[12]  ),
        .up_valid  ( add1_dv      ),
        .res       ( final_result ),
        .down_valid( add2_dv      ),
        .busy      ( add2_busy    ),
        .error     ( add2_err     )
    );

    //----------------------------------------------------------------------
    // Output
    //----------------------------------------------------------------------

    assign res_vld = add2_dv;
    assign res     = final_result;

endmodule
