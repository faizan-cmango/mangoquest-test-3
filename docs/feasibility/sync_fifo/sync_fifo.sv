// Proxy of the sync_fifo architecture (ADR-04): head output register plus 15-word store.
module sync_fifo (
  input  logic        core_clk,
  input  logic        rst_n,
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [31:0] in_data,
  output logic        out_valid,
  input  logic        out_ready,
  output logic [31:0] out_data
);
  logic [31:0] mem [0:14];
  logic [3:0]  rp, wp, cnt;

  wire full = out_valid && (cnt == 4'd15);
  assign in_ready = rst_n && (!full || out_ready);
  wire enq  = in_valid && in_ready;
  wire deq  = out_valid && out_ready;
  wire pop  = deq && (cnt != 4'd0);
  wire push = enq && out_valid && !(deq && cnt == 4'd0);

  always_ff @(posedge core_clk) begin
    if (!rst_n) begin
      out_valid <= 1'b0;
      out_data  <= 32'd0;
      rp <= 4'd0; wp <= 4'd0; cnt <= 4'd0;
    end else begin
      if (!out_valid) begin
        if (enq) begin out_data <= in_data; out_valid <= 1'b1; end
      end else if (deq) begin
        if (cnt != 4'd0) out_data <= mem[rp];
        else if (enq)    out_data <= in_data;
        else             out_valid <= 1'b0;
      end
      if (push) begin
        mem[wp] <= in_data;
        wp <= (wp == 4'd14) ? 4'd0 : wp + 4'd1;
      end
      if (pop) rp <= (rp == 4'd14) ? 4'd0 : rp + 4'd1;
      cnt <= cnt + {3'd0, push} - {3'd0, pop};
    end
  end
endmodule
