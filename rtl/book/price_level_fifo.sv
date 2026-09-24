`default_nettype none

// Price-level FIFO: time-priority queue at one price / side / symbol.
// Spec: design/price-level-fifo.md
module price_level_fifo
  import exch_pkg::*;
(
  input  wire               clk,
  input  wire               rst_n,

  input  wire               cmd_valid,
  output wire               cmd_ready,
  input  wire [1:0]         cmd_op,
  input  wire [OID_W-1:0]   cmd_oid,
  input  wire [QTY_W-1:0]   cmd_qty,

  output logic              rsp_valid,
  output logic              rsp_ok,
  output logic [OID_W-1:0]  rsp_oid,
  output logic [QTY_W-1:0]  rsp_qty,

  output wire               empty,
  output wire               full,
  output wire [CNT_W-1:0]   depth,
  output wire [OID_W-1:0]   head_oid,
  output wire [QTY_W-1:0]   head_qty,
  output logic [QTY_W-1:0]  total_qty,

  input  wire               alloc_en,
  input  wire [QTY_W-1:0]   alloc_qty [MAX_ORDERS],
  output logic [QTY_W-1:0]  slot_qty [MAX_ORDERS],
  output logic [OID_W-1:0]  slot_oid [MAX_ORDERS]
);

  order_entry_t slots   [MAX_ORDERS];
  order_entry_t slots_n [MAX_ORDERS];
  order_entry_t pack_slot [MAX_ORDERS];

  logic [CNT_W-1:0] count;
  logic [CNT_W-1:0] count_n;

  logic              rsp_ok_c;
  logic [OID_W-1:0]  rsp_oid_c;
  logic [QTY_W-1:0]  rsp_qty_c;

  wire do_cmd = cmd_valid && cmd_ready;
  assign cmd_ready = rst_n;

  assign empty    = (count == '0);
  assign full     = (count == CNT_W'(MAX_ORDERS));
  assign depth    = count;
  assign head_oid = slots[0].oid;
  assign head_qty = slots[0].qty;

  always_comb begin
    for (int s = 0; s < MAX_ORDERS; s++) begin
      slot_qty[s] = slots[s].valid ? slots[s].qty : '0;
      slot_oid[s] = slots[s].valid ? slots[s].oid : '0;
    end
  end

  always_comb begin
    total_qty = '0;
    for (int t = 0; t < MAX_ORDERS; t++) begin
      if (slots[t].valid) begin
        total_qty = total_qty + slots[t].qty;
      end
    end
  end

  always_comb begin
    for (int i = 0; i < MAX_ORDERS; i++) begin
      slots_n[i] = slots[i];
      pack_slot[i] = '0;
    end
    count_n   = count;
    rsp_ok_c  = 1'b0;
    rsp_qty_c = '0;
    rsp_oid_c = cmd_oid;

    if (do_cmd) begin
      unique case (cmd_op)
        OP_ADD: begin
          if (!full && cmd_qty != '0) begin
            slots_n[count[IDX_W-1:0]].valid = 1'b1;
            slots_n[count[IDX_W-1:0]].oid   = cmd_oid;
            slots_n[count[IDX_W-1:0]].qty   = cmd_qty;
            count_n                         = count + 1'b1;
            rsp_ok_c                        = 1'b1;
            rsp_qty_c                       = cmd_qty;
            rsp_oid_c                       = cmd_oid;
          end
        end
        OP_MATCH: begin
          if (alloc_en) begin
            automatic logic [QTY_W-1:0] taken_c = '0;
            automatic logic saw = 1'b0;
            automatic int w = 0;
            for (int i = 0; i < MAX_ORDERS; i++) pack_slot[i] = '0;
            for (int i = 0; i < MAX_ORDERS; i++) begin
              if (slots[i].valid && alloc_qty[i] != '0) begin
                automatic logic [QTY_W-1:0] part;
                part = (slots[i].qty > alloc_qty[i]) ? alloc_qty[i] : slots[i].qty;
                slots_n[i].qty = slots[i].qty - part;
                if (slots_n[i].qty == '0) slots_n[i].valid = 1'b0;
                taken_c = taken_c + part;
                if (!saw) begin
                  saw       = 1'b1;
                  rsp_oid_c = slots[i].oid;
                end
              end
            end
            for (int i = 0; i < MAX_ORDERS; i++) begin
              if (slots_n[i].valid && slots_n[i].qty != '0) begin
                pack_slot[w] = slots_n[i];
                w            = w + 1;
              end
            end
            for (int i = 0; i < MAX_ORDERS; i++) slots_n[i] = pack_slot[i];
            count_n = CNT_W'(w);
            if (taken_c != '0) begin
              rsp_ok_c  = 1'b1;
              rsp_qty_c = taken_c;
            end
          end else if (!empty && cmd_qty != '0) begin
            rsp_ok_c  = 1'b1;
            rsp_oid_c = slots[0].oid;
            if (slots[0].qty > cmd_qty) begin
              slots_n[0].qty = slots[0].qty - cmd_qty;
              rsp_qty_c      = cmd_qty;
            end else begin
              rsp_qty_c = slots[0].qty;
              for (int i = 0; i < MAX_ORDERS - 1; i++) begin
                slots_n[i] = slots[i + 1];
              end
              slots_n[MAX_ORDERS - 1] = '0;
              count_n = count - 1'b1;
            end
          end
        end
        OP_CANCEL: begin
          automatic logic found = 1'b0;
          automatic int found_idx = 0;
          for (int i = 0; i < MAX_ORDERS; i++) begin
            if (!found && slots[i].valid && slots[i].oid == cmd_oid) begin
              found     = 1'b1;
              found_idx = i;
            end
          end
          if (found) begin
            rsp_ok_c  = 1'b1;
            rsp_qty_c = slots[found_idx].qty;
            rsp_oid_c = cmd_oid;
            for (int i = 0; i < MAX_ORDERS; i++) begin
              if (i < found_idx) begin
                slots_n[i] = slots[i];
              end else if (i < MAX_ORDERS - 1) begin
                slots_n[i] = slots[i + 1];
              end else begin
                slots_n[i] = '0;
              end
            end
            count_n = count - 1'b1;
          end
        end
        OP_NOP: begin
        end
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int r = 0; r < MAX_ORDERS; r++) begin
        slots[r] <= '0;
      end
      count     <= '0;
      rsp_valid <= 1'b0;
      rsp_ok    <= 1'b0;
      rsp_oid   <= '0;
      rsp_qty   <= '0;
    end else begin
      for (int r = 0; r < MAX_ORDERS; r++) begin
        slots[r] <= slots_n[r];
      end
      count     <= count_n;
      rsp_valid <= do_cmd;
      if (do_cmd) begin
        rsp_ok  <= rsp_ok_c;
        rsp_oid <= rsp_oid_c;
        rsp_qty <= rsp_qty_c;
      end
    end
  end

endmodule

`default_nettype wire
