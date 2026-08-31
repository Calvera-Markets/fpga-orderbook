`default_nettype none

// One-symbol price-time book. Spec: design/one-symbol-book.md
module one_symbol_book
  import exch_pkg::*;
(
  input  wire                clk,
  input  wire                rst_n,

  input  wire                cmd_valid,
  output wire                cmd_ready,
  input  wire                cmd_op,
  input  wire                cmd_side,
  input  wire [PRICE_W-1:0]  cmd_price,
  input  wire [QTY_W-1:0]    cmd_qty,
  input  wire [OID_W-1:0]    cmd_oid,

  output logic               rsp_valid,
  output logic               rsp_ok,
  output logic [OID_W-1:0]   rsp_oid,
  output logic [QTY_W-1:0]   rsp_filled_qty,
  output logic [QTY_W-1:0]   rsp_rest_qty,
  output logic [QTY_W-1:0]   rsp_unrested_qty,

  output logic               evt_valid,
  input  wire                evt_ready,
  output logic [OID_W-1:0]   evt_maker_oid,
  output logic [OID_W-1:0]   evt_taker_oid,
  output logic [PRICE_W-1:0] evt_price,
  output logic [QTY_W-1:0]   evt_qty,

  output wire                bbo_bid_valid,
  output wire [PRICE_W-1:0]  bbo_bid_px,
  output wire [QTY_W-1:0]    bbo_bid_qty,
  output wire                bbo_ask_valid,
  output wire [PRICE_W-1:0]  bbo_ask_px,
  output wire [QTY_W-1:0]    bbo_ask_qty
);

  typedef enum logic [3:0] {
    ST_IDLE         = 4'd0,
    ST_ISSUE_MATCH  = 4'd1,
    ST_WAIT_MATCH   = 4'd2,
    ST_DECIDE       = 4'd3,
    ST_ISSUE_REST   = 4'd4,
    ST_WAIT_REST    = 4'd5,
    ST_ISSUE_CANCEL = 4'd6,
    ST_WAIT_CANCEL  = 4'd7,
    ST_DONE         = 4'd8
  } state_e;

  state_e state;

  assign cmd_ready = (state == ST_IDLE) && rst_n;

  logic [N_LEVELS-1:0] bid_used, ask_used;
  logic [PRICE_W-1:0]  bid_px [N_LEVELS];
  logic [PRICE_W-1:0]  ask_px [N_LEVELS];

  logic [N_LEVELS-1:0] bid_cmd_valid, ask_cmd_valid;
  logic [1:0]          bid_cmd_op [N_LEVELS];
  logic [1:0]          ask_cmd_op [N_LEVELS];
  logic [OID_W-1:0]    fifo_oid;
  logic [QTY_W-1:0]    fifo_qty;

  logic [N_LEVELS-1:0] bid_rsp_valid, ask_rsp_valid;
  logic [N_LEVELS-1:0] bid_rsp_ok, ask_rsp_ok;
  logic [OID_W-1:0]    bid_rsp_oid [N_LEVELS];
  logic [OID_W-1:0]    ask_rsp_oid [N_LEVELS];
  logic [QTY_W-1:0]    bid_rsp_qty [N_LEVELS];
  logic [QTY_W-1:0]    ask_rsp_qty [N_LEVELS];
  logic [N_LEVELS-1:0] bid_empty, ask_empty;
  logic [N_LEVELS-1:0] bid_full, ask_full;
  logic [QTY_W-1:0]    bid_total [N_LEVELS];
  logic [QTY_W-1:0]    ask_total [N_LEVELS];

  /* verilator lint_off UNUSEDSIGNAL */
  logic [N_LEVELS-1:0] bid_cmd_ready, ask_cmd_ready;
  logic [CNT_W-1:0]    bid_depth [N_LEVELS];
  logic [CNT_W-1:0]    ask_depth [N_LEVELS];
  logic [OID_W-1:0]    bid_head_oid [N_LEVELS];
  logic [OID_W-1:0]    ask_head_oid [N_LEVELS];
  logic [QTY_W-1:0]    bid_head_qty [N_LEVELS];
  logic [QTY_W-1:0]    ask_head_qty [N_LEVELS];
  /* verilator lint_on UNUSEDSIGNAL */

  genvar gi;
  generate
    for (gi = 0; gi < N_LEVELS; gi++) begin : gen_bid
      price_level_fifo u_bid (
        .clk, .rst_n,
        .cmd_valid (bid_cmd_valid[gi]),
        .cmd_ready (bid_cmd_ready[gi]),
        .cmd_op    (bid_cmd_op[gi]),
        .cmd_oid   (fifo_oid),
        .cmd_qty   (fifo_qty),
        .rsp_valid (bid_rsp_valid[gi]),
        .rsp_ok    (bid_rsp_ok[gi]),
        .rsp_oid   (bid_rsp_oid[gi]),
        .rsp_qty   (bid_rsp_qty[gi]),
        .empty     (bid_empty[gi]),
        .full      (bid_full[gi]),
        .depth     (bid_depth[gi]),
        .head_oid  (bid_head_oid[gi]),
        .head_qty  (bid_head_qty[gi]),
        .total_qty (bid_total[gi])
      );
    end
    for (gi = 0; gi < N_LEVELS; gi++) begin : gen_ask
      price_level_fifo u_ask (
        .clk, .rst_n,
        .cmd_valid (ask_cmd_valid[gi]),
        .cmd_ready (ask_cmd_ready[gi]),
        .cmd_op    (ask_cmd_op[gi]),
        .cmd_oid   (fifo_oid),
        .cmd_qty   (fifo_qty),
        .rsp_valid (ask_rsp_valid[gi]),
        .rsp_ok    (ask_rsp_ok[gi]),
        .rsp_oid   (ask_rsp_oid[gi]),
        .rsp_qty   (ask_rsp_qty[gi]),
        .empty     (ask_empty[gi]),
        .full      (ask_full[gi]),
        .depth     (ask_depth[gi]),
        .head_oid  (ask_head_oid[gi]),
        .head_qty  (ask_head_qty[gi]),
        .total_qty (ask_total[gi])
      );
    end
  endgenerate

  logic               bbo_bid_valid_c, bbo_ask_valid_c;
  logic [PRICE_W-1:0] bbo_bid_px_c, bbo_ask_px_c;
  logic [QTY_W-1:0]   bbo_bid_qty_c, bbo_ask_qty_c;
  logic [LVL_IDX_W-1:0] best_bid_idx, best_ask_idx;

  assign bbo_bid_valid = bbo_bid_valid_c;
  assign bbo_bid_px    = bbo_bid_px_c;
  assign bbo_bid_qty   = bbo_bid_qty_c;
  assign bbo_ask_valid = bbo_ask_valid_c;
  assign bbo_ask_px    = bbo_ask_px_c;
  assign bbo_ask_qty   = bbo_ask_qty_c;

  always_comb begin
    bbo_bid_valid_c = 1'b0;
    bbo_bid_px_c    = '0;
    bbo_bid_qty_c   = '0;
    best_bid_idx    = '0;
    bbo_ask_valid_c = 1'b0;
    bbo_ask_px_c    = '0;
    bbo_ask_qty_c   = '0;
    best_ask_idx    = '0;
    for (int i = 0; i < N_LEVELS; i++) begin
      if (bid_used[i] && !bid_empty[i]) begin
        if (!bbo_bid_valid_c || bid_px[i] > bbo_bid_px_c) begin
          bbo_bid_valid_c = 1'b1;
          bbo_bid_px_c    = bid_px[i];
          bbo_bid_qty_c   = bid_total[i];
          best_bid_idx    = LVL_IDX_W'(i);
        end
      end
      if (ask_used[i] && !ask_empty[i]) begin
        if (!bbo_ask_valid_c || ask_px[i] < bbo_ask_px_c) begin
          bbo_ask_valid_c = 1'b1;
          bbo_ask_px_c    = ask_px[i];
          bbo_ask_qty_c   = ask_total[i];
          best_ask_idx    = LVL_IDX_W'(i);
        end
      end
    end
  end

  logic               latched_side;
  logic [PRICE_W-1:0] latched_px;
  logic [OID_W-1:0]   latched_oid;
  logic [QTY_W-1:0]   remaining;
  logic [QTY_W-1:0]   filled_acc, rest_acc, unrested_acc;

  logic               match_is_ask;
  logic [LVL_IDX_W-1:0] match_idx;
  logic [PRICE_W-1:0] match_px;
  logic               rest_is_ask;
  logic [LVL_IDX_W-1:0] rest_idx_r;

  logic               rest_found, rest_alloc;
  logic [LVL_IDX_W-1:0] rest_idx;

  always_comb begin
    rest_found = 1'b0;
    rest_alloc = 1'b0;
    rest_idx   = '0;
    if (latched_side == SIDE_BUY) begin
      for (int i = 0; i < N_LEVELS; i++) begin
        if (bid_used[i] && bid_px[i] == latched_px) begin
          rest_found = 1'b1;
          rest_alloc = 1'b0;
          rest_idx   = LVL_IDX_W'(i);
        end
      end
      if (!rest_found) begin
        for (int i = 0; i < N_LEVELS; i++) begin
          if (!rest_found && !bid_used[i]) begin
            rest_found = 1'b1;
            rest_alloc = 1'b1;
            rest_idx   = LVL_IDX_W'(i);
          end
        end
      end
    end else begin
      for (int i = 0; i < N_LEVELS; i++) begin
        if (ask_used[i] && ask_px[i] == latched_px) begin
          rest_found = 1'b1;
          rest_alloc = 1'b0;
          rest_idx   = LVL_IDX_W'(i);
        end
      end
      if (!rest_found) begin
        for (int i = 0; i < N_LEVELS; i++) begin
          if (!rest_found && !ask_used[i]) begin
            rest_found = 1'b1;
            rest_alloc = 1'b1;
            rest_idx   = LVL_IDX_W'(i);
          end
        end
      end
    end
  end

  wire limit_crosses_now = (cmd_side == SIDE_BUY)
      ? (bbo_ask_valid_c && cmd_price >= bbo_ask_px_c)
      : (bbo_bid_valid_c && cmd_price <= bbo_bid_px_c);

  wire latched_crosses = (latched_side == SIDE_BUY)
      ? (bbo_ask_valid_c && latched_px >= bbo_ask_px_c)
      : (bbo_bid_valid_c && latched_px <= bbo_bid_px_c);

  wire rest_level_full = rest_found && !rest_alloc &&
      ((latched_side == SIDE_BUY) ? bid_full[rest_idx] : ask_full[rest_idx]);

  wire sel_rsp_valid = match_is_ask ? ask_rsp_valid[match_idx] : bid_rsp_valid[match_idx];
  wire sel_rsp_ok    = match_is_ask ? ask_rsp_ok[match_idx]    : bid_rsp_ok[match_idx];
  wire [OID_W-1:0] sel_rsp_oid = match_is_ask ? ask_rsp_oid[match_idx] : bid_rsp_oid[match_idx];
  wire [QTY_W-1:0] sel_rsp_qty = match_is_ask ? ask_rsp_qty[match_idx] : bid_rsp_qty[match_idx];
  wire sel_empty = match_is_ask ? ask_empty[match_idx] : bid_empty[match_idx];

  wire rest_rsp_valid = rest_is_ask ? ask_rsp_valid[rest_idx_r] : bid_rsp_valid[rest_idx_r];
  wire rest_rsp_ok    = rest_is_ask ? ask_rsp_ok[rest_idx_r]    : bid_rsp_ok[rest_idx_r];
  wire rest_empty     = rest_is_ask ? ask_empty[rest_idx_r]     : bid_empty[rest_idx_r];

  always_comb begin
    for (int i = 0; i < N_LEVELS; i++) begin
      bid_cmd_valid[i] = 1'b0;
      ask_cmd_valid[i] = 1'b0;
      bid_cmd_op[i]    = OP_NOP;
      ask_cmd_op[i]    = OP_NOP;
    end
    fifo_oid = latched_oid;
    fifo_qty = remaining;
    unique case (state)
      ST_ISSUE_MATCH: begin
        if (latched_side == SIDE_BUY) begin
          ask_cmd_valid[best_ask_idx] = 1'b1;
          ask_cmd_op[best_ask_idx]    = OP_MATCH;
        end else begin
          bid_cmd_valid[best_bid_idx] = 1'b1;
          bid_cmd_op[best_bid_idx]    = OP_MATCH;
        end
      end
      ST_ISSUE_REST: begin
        if (rest_found && !rest_level_full) begin
          if (latched_side == SIDE_BUY) begin
            bid_cmd_valid[rest_idx] = 1'b1;
            bid_cmd_op[rest_idx]    = OP_ADD;
          end else begin
            ask_cmd_valid[rest_idx] = 1'b1;
            ask_cmd_op[rest_idx]    = OP_ADD;
          end
        end
      end
      ST_ISSUE_CANCEL: begin
        fifo_qty = '0;
        for (int i = 0; i < N_LEVELS; i++) begin
          bid_cmd_valid[i] = 1'b1;
          ask_cmd_valid[i] = 1'b1;
          bid_cmd_op[i]    = OP_CANCEL;
          ask_cmd_op[i]    = OP_CANCEL;
        end
      end
      default: begin
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state          <= ST_IDLE;
      bid_used       <= '0;
      ask_used       <= '0;
      for (int i = 0; i < N_LEVELS; i++) begin
        bid_px[i] <= '0;
        ask_px[i] <= '0;
      end
      latched_side   <= SIDE_BUY;
      latched_px     <= '0;
      latched_oid    <= '0;
      remaining      <= '0;
      filled_acc     <= '0;
      rest_acc       <= '0;
      unrested_acc   <= '0;
      match_is_ask   <= 1'b0;
      match_idx      <= '0;
      match_px       <= '0;
      rest_is_ask    <= 1'b0;
      rest_idx_r     <= '0;
      rsp_valid      <= 1'b0;
      rsp_ok         <= 1'b0;
      rsp_oid        <= '0;
      rsp_filled_qty <= '0;
      rsp_rest_qty   <= '0;
      rsp_unrested_qty <= '0;
      evt_valid      <= 1'b0;
      evt_maker_oid  <= '0;
      evt_taker_oid  <= '0;
      evt_price      <= '0;
      evt_qty        <= '0;
    end else begin
      rsp_valid <= 1'b0;
      if (evt_valid && !evt_ready) begin
        evt_valid <= 1'b1;
      end else begin
        evt_valid <= 1'b0;
      end

      unique case (state)
        ST_IDLE: begin
          if (cmd_valid) begin
            latched_side <= cmd_side;
            latched_px   <= cmd_price;
            latched_oid  <= cmd_oid;
            remaining    <= cmd_qty;
            filled_acc   <= '0;
            rest_acc     <= '0;
            unrested_acc <= '0;
            rsp_ok       <= 1'b1;
            if (cmd_op == BOOK_CANCEL) begin
              remaining <= '0;
              state     <= ST_ISSUE_CANCEL;
            end else if (cmd_op == BOOK_LIMIT && cmd_qty == '0) begin
              rsp_ok <= 1'b0;
              state  <= ST_DONE;
            end else if (cmd_op == BOOK_LIMIT && limit_crosses_now) begin
              state <= ST_ISSUE_MATCH;
            end else if (cmd_op == BOOK_LIMIT) begin
              state <= ST_ISSUE_REST;
            end else begin
              rsp_ok <= 1'b0;
              state  <= ST_DONE;
            end
          end
        end
        ST_ISSUE_MATCH: begin
          match_is_ask <= (latched_side == SIDE_BUY);
          if (latched_side == SIDE_BUY) begin
            match_idx <= best_ask_idx;
            match_px  <= bbo_ask_px_c;
          end else begin
            match_idx <= best_bid_idx;
            match_px  <= bbo_bid_px_c;
          end
          state <= ST_WAIT_MATCH;
        end
        ST_WAIT_MATCH: begin
          if (sel_rsp_valid) begin
            if (sel_rsp_ok) begin
              remaining  <= remaining - sel_rsp_qty;
              filled_acc <= filled_acc + sel_rsp_qty;
              evt_valid     <= 1'b1;
              evt_maker_oid <= sel_rsp_oid;
              evt_taker_oid <= latched_oid;
              evt_price     <= match_px;
              evt_qty       <= sel_rsp_qty;
              if (sel_empty) begin
                if (match_is_ask) ask_used[match_idx] <= 1'b0;
                else              bid_used[match_idx] <= 1'b0;
              end
              state <= ST_DECIDE;
            end else begin
              rsp_ok <= 1'b0;
              state  <= ST_DONE;
            end
          end
        end
        ST_DECIDE: begin
          if (!(evt_valid && !evt_ready)) begin
            if (remaining == '0) begin
              state <= ST_DONE;
            end else if (latched_crosses) begin
              state <= ST_ISSUE_MATCH;
            end else begin
              state <= ST_ISSUE_REST;
            end
          end
        end
        ST_ISSUE_REST: begin
          if (!rest_found || rest_level_full) begin
            unrested_acc <= remaining;
            rsp_ok       <= 1'b0;
            state        <= ST_DONE;
          end else begin
            rest_idx_r  <= rest_idx;
            rest_is_ask <= (latched_side == SIDE_SELL);
            if (rest_alloc) begin
              if (latched_side == SIDE_BUY) begin
                bid_used[rest_idx] <= 1'b1;
                bid_px[rest_idx]   <= latched_px;
              end else begin
                ask_used[rest_idx] <= 1'b1;
                ask_px[rest_idx]   <= latched_px;
              end
            end
            state <= ST_WAIT_REST;
          end
        end
        ST_WAIT_REST: begin
          if (rest_rsp_valid) begin
            if (rest_rsp_ok) begin
              rest_acc <= remaining;
            end else begin
              unrested_acc <= remaining;
              rsp_ok       <= 1'b0;
              if (rest_empty) begin
                if (rest_is_ask) ask_used[rest_idx_r] <= 1'b0;
                else             bid_used[rest_idx_r] <= 1'b0;
              end
            end
            state <= ST_DONE;
          end
        end
        ST_ISSUE_CANCEL: begin
          state <= ST_WAIT_CANCEL;
        end
        ST_WAIT_CANCEL: begin
          rsp_ok   <= 1'b0;
          rest_acc <= '0;
          for (int i = 0; i < N_LEVELS; i++) begin
            if (bid_rsp_valid[i] && bid_rsp_ok[i]) begin
              rsp_ok   <= 1'b1;
              rest_acc <= bid_rsp_qty[i];
              if (bid_empty[i]) bid_used[i] <= 1'b0;
            end
            if (ask_rsp_valid[i] && ask_rsp_ok[i]) begin
              rsp_ok   <= 1'b1;
              rest_acc <= ask_rsp_qty[i];
              if (ask_empty[i]) ask_used[i] <= 1'b0;
            end
          end
          state <= ST_DONE;
        end
        ST_DONE: begin
          rsp_valid        <= 1'b1;
          rsp_oid          <= latched_oid;
          rsp_filled_qty   <= filled_acc;
          rsp_rest_qty     <= rest_acc;
          rsp_unrested_qty <= unrested_acc;
          state            <= ST_IDLE;
        end
        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
