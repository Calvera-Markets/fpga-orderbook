`default_nettype none

// Per-session sequence. A gap or a replay rejects and leaves the next number.
module session_table #(
  parameter int NSESS = 4
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        valid,
  input  wire        take,
  input  wire [7:0]  session,
  input  wire [31:0] seq,
  output wire        pass,
  output wire        reject,
  output wire [7:0]  reason
);

  logic [31:0] next_seq [NSESS];
  wire in = (session < 8'(NSESS));
  wire [1:0] sid = session[1:0];
  wire match = in && (seq == next_seq[sid]);

  assign pass   = valid && match;
  assign reject = valid && !match;
  assign reason = in ? 8'd2 : 8'd3;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < NSESS; i++) next_seq[i] <= 32'd1;
    end else if (take && match) begin
      next_seq[sid] <= next_seq[sid] + 32'd1;
    end
  end

endmodule

`default_nettype wire
