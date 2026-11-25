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
  logic [31:0] mem [0:15];
  logic [3:0]  wp, rp;
  logic [4:0]  cnt;
  wire full  = cnt[4];
  wire empty = (cnt == 5'd0);
  assign in_ready  = rst_n & (~full | out_ready);
  assign out_valid = rst_n & ~empty;
  wire push = in_valid & in_ready;
  wire pop  = out_valid & out_ready;
  always_ff @(posedge core_clk) begin
    if (!rst_n) begin
      wp <= 4'd0; rp <= 4'd0; cnt <= 5'd0;
    end else begin
      if (push) begin mem[wp] <= in_data; wp <= wp + 4'd1; end
      if (pop)  rp <= rp + 4'd1;
      cnt <= cnt + {4'd0, push} - {4'd0, pop};
    end
  end
  assign out_data = mem[rp];
endmodule
