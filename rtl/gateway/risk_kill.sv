`default_nettype none

// Per-session quantity cap and a kill bit. Neither reads a book.
module risk_kill #(
  parameter int NSESS = 4,
  parameter int CAP = 10
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        valid,
  input  wire [7:0]  session,
  input  wire [31:0] qty,
  input  wire        kill,
  output wire        pass,
  output wire        reject,
  output wire [7:0]  reason
);

  logic killed [NSESS];
  wire in = (session < 8'(NSESS));
  wire [1:0] sid = session[1:0];
  wire dead = in && killed[sid];
  wire over = (qty > 32'(CAP));

  assign pass   = valid && in && !kill && !dead && !over;
  assign reject = valid && (!in || kill || dead || over);
  assign reason = (!in) ? 8'd3 : (kill || dead) ? 8'd5 : 8'd4;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < NSESS; i++) killed[i] <= 1'b0;
    end else if (valid && in && kill) begin
      killed[sid] <= 1'b1;
    end
  end

endmodule

`default_nettype wire
