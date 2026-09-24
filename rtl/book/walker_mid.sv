`default_nettype none

// Integer midpoint. Remainder goes toward zero. No trade unless both sides exist.
module walker_mid (
  input  wire [31:0] bid,
  input  wire [31:0] ask,
  input  wire        bid_ok,
  input  wire        ask_ok,
  output wire [31:0] px,
  output wire        ok
);
  assign ok = bid_ok && ask_ok;
  assign px = (bid + ask) >> 1;
endmodule

`default_nettype wire
