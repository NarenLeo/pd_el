`default_nettype none
// Area-oriented DSP revision: programmable output scaling removed.
// Configuration protocol remains unchanged: first selected cycle arms,
// second selected cycle captures mode from data_in[1:0]; other bits ignored.
// 00 FIR LP; 01 IIR LP; 10 FIR HP; 11 bypass.
module dsp_fir_iir (
    input wire clk,
    input wire rst_n,
    input wire sel,
    input wire [7:0] data_in,
    output reg [7:0] data_out
);
    reg sel_q, cfg_ready;
    reg [1:0] mode_q;
    reg signed [7:0] h1, h2, h3;
    reg signed [11:0] iir_prev;

    wire signed [7:0] sample = $signed(data_in);

    // Symmetric FIR: [1,3,3,1]/8.
    // 9-bit pair sums are sufficient: -256..254 each.
    wire signed [8:0] pair_outer =
        $signed({sample[7], sample}) + $signed({h3[7], h3});
    wire signed [8:0] pair_inner =
        $signed({h1[7], h1}) + $signed({h2[7], h2});
    // 11-bit numerator range: [-1024, 1016].
    wire signed [10:0] outer_ext = {{2{pair_outer[8]}}, pair_outer};
    wire signed [10:0] inner_ext = {{2{pair_inner[8]}}, pair_inner};
    wire signed [10:0] fir_numer = outer_ext + inner_ext + (inner_ext <<< 1);
    wire signed [10:0] fir_lp = fir_numer >>> 3;

    // Preserve the previous IIR fixed-point semantics (floor for negatives).
    wire signed [11:0] input_ext = {{4{sample[7]}}, sample};
    wire signed [11:0] iir_val =
        input_ext + ((iir_prev + (iir_prev <<< 1)) >>> 3);

    wire signed [11:0] lp_ext = {{1{fir_lp[10]}}, fir_lp};
    reg signed [11:0] core;
    always @* begin
        case (mode_q)
            2'd0: core = lp_ext;
            2'd1: core = iir_val;
            2'd2: core = input_ext - lp_ext;
            2'd3: core = input_ext;
            default: core = 12'sd0;
        endcase
    end

    // Clip signed 12-bit output to signed 8-bit, retaining the old behavior.
    function [7:0] clip8;
        input signed [11:0] val;
        begin
            if (val > 12'sd127) clip8 = 8'h7f;
            else if (val < -12'sd128) clip8 = 8'h80;
            else clip8 = val[7:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n || !sel) begin
            sel_q <= 1'b0;
            cfg_ready <= 1'b0;
            mode_q <= 2'd0;
            h1 <= 8'sd0;
            h2 <= 8'sd0;
            h3 <= 8'sd0;
            iir_prev <= 12'sd0;
            data_out <= 8'd0;
        end else if (!sel_q) begin
            sel_q <= 1'b1;
            cfg_ready <= 1'b0;
            data_out <= 8'd0;
        end else if (!cfg_ready) begin
            mode_q <= data_in[1:0];
            cfg_ready <= 1'b1;
            data_out <= 8'd0;
        end else begin
            data_out <= clip8(core);
            h3 <= h2;
            h2 <= h1;
            h1 <= sample;
            if (mode_q == 2'd1)
                iir_prev <= iir_val;
        end
    end
endmodule
`default_nettype wire
