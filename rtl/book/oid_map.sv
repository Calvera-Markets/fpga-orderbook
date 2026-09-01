`default_nettype none

// oid → symbol. Spec: design/pattern-4.md
module oid_map
  import exch_pkg::*;
#(
  parameter int N = 64
) (
  input  wire                clk,
  input  wire                rst_n,
  input  wire                wr_en,
  input  wire                wr_clear,
  input  wire [OID_W-1:0]    wr_oid,
  input  wire [SYMBOL_W-1:0] wr_symbol,
  input  wire [OID_W-1:0]    rd_oid,
  output logic               rd_hit,
  output logic [SYMBOL_W-1:0] rd_symbol
);

  logic             valid_q [N];
  logic [OID_W-1:0] oid_q   [N];
  logic [SYMBOL_W-1:0] sym_q [N];

  always_comb begin
    rd_hit    = 1'b0;
    rd_symbol = '0;
    for (int i = 0; i < N; i++) begin
      if (valid_q[i] && oid_q[i] == rd_oid) begin
        rd_hit    = 1'b1;
        rd_symbol = sym_q[i];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < N; i++) begin
        valid_q[i] <= 1'b0;
        oid_q[i]   <= '0;
        sym_q[i]   <= '0;
      end
    end else if (wr_clear) begin
      for (int i = 0; i < N; i++) begin
        if (valid_q[i] && oid_q[i] == wr_oid) begin
          valid_q[i] <= 1'b0;
        end
      end
    end else if (wr_en) begin
      automatic logic placed = 1'b0;
      for (int i = 0; i < N; i++) begin
        if (!placed && !valid_q[i]) begin
          valid_q[i] <= 1'b1;
          oid_q[i]   <= wr_oid;
          sym_q[i]   <= wr_symbol;
          placed     = 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire
