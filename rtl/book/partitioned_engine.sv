`default_nettype none

// Pattern 4: K symbol_bank pipes. pipe = cmd_symbol % N_PIPES.
module partitioned_engine
  import exch_pkg::*;
(
  input  wire                clk,
  input  wire                rst_n,

  input  wire                cmd_valid,
  output wire                cmd_ready,
  input  wire [SYMBOL_W-1:0] cmd_symbol,
  input  wire                cmd_op,
  input  wire                cmd_side,
  input  wire [PRICE_W-1:0]  cmd_price,
  input  wire [QTY_W-1:0]    cmd_qty,
  input  wire [OID_W-1:0]    cmd_oid,

  output logic [N_PIPES-1:0] rsp_valid,
  output logic [N_PIPES-1:0] rsp_ok,
  output logic [OID_W-1:0]   rsp_oid [N_PIPES],
  output logic [QTY_W-1:0]   rsp_filled_qty [N_PIPES],
  output logic [QTY_W-1:0]   rsp_rest_qty [N_PIPES],
  output logic [QTY_W-1:0]   rsp_unrested_qty [N_PIPES],

  output logic [N_PIPES-1:0] evt_valid,
  input  wire                evt_ready,
  output logic [OID_W-1:0]   evt_maker_oid [N_PIPES],
  output logic [OID_W-1:0]   evt_taker_oid [N_PIPES],
  output logic [PRICE_W-1:0] evt_price [N_PIPES],
  output logic [QTY_W-1:0]   evt_qty [N_PIPES]
);

  logic               map_hit;
  logic [SYMBOL_W-1:0] map_sym;
  logic               wr_en, wr_clear;
  logic [OID_W-1:0]   wr_oid_r;
  logic [SYMBOL_W-1:0] wr_sym_r;
  logic [OID_W-1:0]   last_oid [N_PIPES];
  logic [SYMBOL_W-1:0] last_sym [N_PIPES];
  logic               last_op  [N_PIPES];

  wire [SYMBOL_W-1:0] route_sym =
      (cmd_op == BOOK_CANCEL && map_hit) ? map_sym : cmd_symbol;
  wire [PIPE_W-1:0] pipe_sel = PIPE_W'(32'(route_sym) % 32'(N_PIPES));
  logic [N_PIPES-1:0] bank_ready;
  logic [N_PIPES-1:0] bank_cmd_valid;

  assign cmd_ready = bank_ready[pipe_sel];

  oid_map u_oids (
    .clk, .rst_n,
    .wr_en, .wr_clear,
    .wr_oid    (wr_oid_r),
    .wr_symbol (wr_sym_r),
    .rd_oid    (cmd_oid),
    .rd_hit    (map_hit),
    .rd_symbol (map_sym)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int p = 0; p < N_PIPES; p++) begin
        last_oid[p] <= '0;
        last_sym[p] <= '0;
        last_op[p]  <= BOOK_LIMIT;
      end
    end else if (cmd_valid && cmd_ready) begin
      last_oid[pipe_sel] <= cmd_oid;
      last_sym[pipe_sel] <= route_sym;
      last_op[pipe_sel]  <= cmd_op;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_en    <= 1'b0;
      wr_clear <= 1'b0;
      wr_oid_r <= '0;
      wr_sym_r <= '0;
    end else begin
      wr_en    <= 1'b0;
      wr_clear <= 1'b0;
      for (int p = 0; p < N_PIPES; p++) begin
        if (rsp_valid[p] && last_op[p] == BOOK_LIMIT && rsp_rest_qty[p] != '0) begin
          wr_en    <= 1'b1;
          wr_oid_r <= last_oid[p];
          wr_sym_r <= last_sym[p];
        end
        if (rsp_valid[p] && last_op[p] == BOOK_CANCEL && rsp_ok[p]) begin
          wr_clear <= 1'b1;
          wr_oid_r <= last_oid[p];
        end
      end
    end
  end

  genvar gi;
  generate
    for (gi = 0; gi < N_PIPES; gi++) begin : gen_pipes
      assign bank_cmd_valid[gi] = cmd_valid && cmd_ready && (pipe_sel == PIPE_W'(gi));
      /* verilator lint_off UNUSEDSIGNAL */
      logic unused_bid_v, unused_ask_v;
      logic [PRICE_W-1:0] unused_bid_px, unused_ask_px;
      logic [QTY_W-1:0] unused_bid_qty, unused_ask_qty;
      /* verilator lint_on UNUSEDSIGNAL */
      symbol_bank #(
        .PIPE_ID   (gi),
        .N_PIPES_P (N_PIPES),
        .N_SYMS    (N_SYMS_PER_PIPE)
      ) u_bank (
        .clk, .rst_n,
        .cmd_valid (bank_cmd_valid[gi]),
        .cmd_ready (bank_ready[gi]),
        .cmd_symbol (route_sym),
        .cmd_op, .cmd_side, .cmd_price, .cmd_qty, .cmd_oid,
        .rsp_valid (rsp_valid[gi]),
        .rsp_ok    (rsp_ok[gi]),
        .rsp_oid   (rsp_oid[gi]),
        .rsp_filled_qty (rsp_filled_qty[gi]),
        .rsp_rest_qty   (rsp_rest_qty[gi]),
        .rsp_unrested_qty (rsp_unrested_qty[gi]),
        .evt_valid (evt_valid[gi]),
        .evt_ready,
        .evt_maker_oid (evt_maker_oid[gi]),
        .evt_taker_oid (evt_taker_oid[gi]),
        .evt_price (evt_price[gi]),
        .evt_qty   (evt_qty[gi]),
        .bbo_bid_valid (unused_bid_v),
        .bbo_bid_px    (unused_bid_px),
        .bbo_bid_qty   (unused_bid_qty),
        .bbo_ask_valid (unused_ask_v),
        .bbo_ask_px    (unused_ask_px),
        .bbo_ask_qty   (unused_ask_qty)
      );
    end
  endgenerate

endmodule

`default_nettype wire
