`default_nettype none

// One-shot pro-rata over a price queue. Odd lots go to the oldest order.
module walker_prorata
  import exch_pkg::*;
(
  input  wire [QTY_W-1:0] take_qty,
  input  wire [CNT_W-1:0] depth,
  input  wire [QTY_W-1:0] qty [MAX_ORDERS],
  output logic [QTY_W-1:0] fill [MAX_ORDERS],
  output logic [QTY_W-1:0] taken
);

  always_comb begin
    logic [QTY_W-1:0] total;
    logic [QTY_W-1:0] take;
    logic [QTY_W-1:0] raw [MAX_ORDERS];
    logic [QTY_W-1:0] spare;
    logic [QTY_W-1:0] room;
    logic [QTY_W-1:0] give;
    total = '0;
    take  = '0;
    spare = '0;
    taken = '0;
    room  = '0;
    give  = '0;
    for (int i = 0; i < MAX_ORDERS; i++) begin
      fill[i] = '0;
      raw[i]  = '0;
      if (CNT_W'(i) < depth) total = total + qty[i];
    end
    if (total != '0 && take_qty != '0) begin
      take  = (take_qty < total) ? take_qty : total;
      spare = take;
      for (int i = 0; i < MAX_ORDERS; i++) begin
        if (CNT_W'(i) < depth) begin
          raw[i] = QTY_W'(({32'd0, take} * {32'd0, qty[i]}) / {32'd0, total});
          spare  = spare - raw[i];
        end
      end
      for (int i = 0; i < MAX_ORDERS; i++) begin
        if (CNT_W'(i) < depth && spare != '0) begin
          room = qty[i] - raw[i];
          give = (room < spare) ? room : spare;
          raw[i] = raw[i] + give;
          spare  = spare - give;
        end else begin
          room = '0;
          give = '0;
        end
        fill[i] = raw[i];
      end
      taken = take - spare;
    end
  end

endmodule

`default_nettype wire
