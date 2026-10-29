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
    reg signed [8:0] iir_prev;

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
    // IIR steady-state bound from reset: -205..203 for signed 8-bit input.
    // Keep the tripled-feedback intermediate wide enough (-615..609).
    wire signed [10:0] prev_ext = {{2{iir_prev[8]}}, iir_prev};
    wire signed [10:0] prev_triple = prev_ext + (prev_ext <<< 1);
    wire signed [8:0] iir_val =
        $signed({sample[7], sample}) + (prev_triple >>> 3);

    wire signed [8:0] lp_9 = fir_lp[8:0];
    reg signed [8:0] core;
    always @* begin
        case (mode_q)
            2'd0: core = lp_9;
            2'd1: core = iir_val;
            2'd2: core = $signed({sample[7], sample}) - lp_9;
            2'd3: core = $signed({sample[7], sample});
            default: core = 9'sd0;
        endcase
    end

    // For a signed 9-bit result, bits 8 and 7 are equal exactly when
    // the value fits signed 8-bit range. Otherwise saturate by sign.
    function [7:0] clip8;
        input signed [8:0] val;
        begin
            if (val[8] == val[7]) clip8 = val[7:0];
            else clip8 = val[8] ? 8'h80 : 8'h7f;
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
            iir_prev <= 9'sd0;
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
