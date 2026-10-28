`default_nettype none

module tt_um_cordic_iter (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // DSP selected by uio_in[0]; completely independent streaming lane.
  wire dsp_sel = uio_in[0];
  wire [7:0] dsp_result;
  dsp_fir_iir dsp_unit (
      .clk(clk), .rst_n(rst_n), .sel(dsp_sel),
      .data_in(ui_in), .data_out(dsp_result)
  );
  // Block CORDIC commands while DSP is selected.
  wire [7:0] cordic_ui = dsp_sel ? 8'b0 : ui_in;

  localparam [1:0] S_RDY = 2'd0, S_PRE = 2'd1, S_ITER = 2'd2, S_COMP = 2'd3;
  reg signed [15:0] x, y;
  reg        [15:0] z;
  reg        [3:0]  i;
  reg        [1:0]  state;
  reg               mode_q, comp_q, done_q, start_q;
  reg        [3:0]  last_q;

  wire sdi    = cordic_ui[0];
  wire sh_en  = cordic_ui[1];
  wire start  = cordic_ui[2];
  wire start_pe = start & ~start_q;

  wire in_pre  = (state == S_PRE);
  wire in_comp = (state == S_COMP);

  // ------------------------------------------------------- constant tables
  // atan(2^-i) scaled so that pi = 2^15
  reg [15:0] alpha;
  always @* begin
    case (i)
      4'd0:  alpha = 16'd8192;
      4'd1:  alpha = 16'd4836;
      4'd2:  alpha = 16'd2555;
      4'd3:  alpha = 16'd1297;
      4'd4:  alpha = 16'd651;
      4'd5:  alpha = 16'd326;
      4'd6:  alpha = 16'd163;
      4'd7:  alpha = 16'd81;
      4'd8:  alpha = 16'd41;
      4'd9:  alpha = 16'd20;
      4'd10: alpha = 16'd10;
      default: alpha = 16'd5;
    endcase
  end

  reg       c_sub;
  reg [3:0] c_k;
  always @* begin
    case (i[2:0])
      3'd0:    {c_sub, c_k} = {1'b1, 4'd1};
      3'd1:    {c_sub, c_k} = {1'b0, 4'd2};
      3'd2:    {c_sub, c_k} = {1'b1, 4'd5};
      3'd3:    {c_sub, c_k} = {1'b0, 4'd9};
      default: {c_sub, c_k} = {1'b0, 4'd10};
    endcase
  end


  wire [3:0] sh = in_comp ? c_k : i;
  wire signed [15:0] xsh = x >>> sh;
  wire signed [15:0] ysh = y >>> sh;


  wire d_pos = mode_q ? y[15] : ~z[15];

  wire flip  = mode_q ? x[15] : (z[15] ^ z[14]);

  wire sub_x = in_pre ? 1'b1 : (in_comp ? c_sub : d_pos);
  wire sub_y = in_pre ? 1'b1 : (in_comp ? c_sub : ~d_pos);
  wire [15:0] ax = in_pre ? 16'd0 : x;
  wire [15:0] ay = in_pre ? 16'd0 : y;
  wire [15:0] bx = in_pre ? x : (in_comp ? xsh : ysh);
  wire [15:0] by = in_pre ? y : (in_comp ? ysh : xsh);

  wire [15:0] x_nx = ax + (bx ^ {16{sub_x}}) + {15'd0, sub_x};
  wire [15:0] y_nx = ay + (by ^ {16{sub_y}}) + {15'd0, sub_y};
  wire [15:0] z_nx = z  + (alpha ^ {16{d_pos}}) + {15'd0, d_pos};

  wire at_last = (i == last_q);
  wire comp_last = (i == 4'd4);


  always @(posedge clk) begin
    if (!rst_n) begin
      x <= 16'sd0; y <= 16'sd0; z <= 16'd0;
      i <= 4'd0; state <= S_RDY;
      mode_q <= 1'b0; comp_q <= 1'b0; done_q <= 1'b0;
      start_q <= 1'b0; last_q <= 4'd0;
    end else begin
      start_q <= start;
      case (state)
        S_RDY: begin
          if (start_pe) begin
            mode_q <= cordic_ui[3];
            comp_q <= cordic_ui[4];
            last_q <= {1'b0, cordic_ui[7:5]} + 4'd4;   // N-1
            done_q <= 1'b0;
            i      <= 4'd0;
            state  <= S_PRE;
          end else if (sh_en) begin
            x <= {x[14:0], y[15]};
            y <= {y[14:0], z[15]};
            z <= {z[14:0], sdi};
          end
        end
        S_PRE: begin
          if (flip) begin
            x <= x_nx;
            y <= y_nx;
            z <= {~z[15], z[14:0]};
          end
          state <= S_ITER;
        end
        S_ITER: begin
          x <= x_nx;
          y <= y_nx;
          z <= z_nx;
          if (at_last) begin
            i <= 4'd0;
            if (comp_q) state <= S_COMP;
            else begin state <= S_RDY; done_q <= 1'b1; end
          end else i <= i + 4'd1;
        end
        S_COMP: begin
          x <= x_nx;
          y <= y_nx;
          if (comp_last) begin
            i <= 4'd0; state <= S_RDY; done_q <= 1'b1;
          end else i <= i + 4'd1;
        end
      endcase
    end
  end


  wire busy = (state != S_RDY);
  assign uo_out  = dsp_sel ? dsp_result : {i, 1'b0, done_q, busy, x[15]};
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  wire _unused = &{ena, uio_in, 1'b0};

endmodule
