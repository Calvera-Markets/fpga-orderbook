`default_nettype none

// Oldest-first take. take0 is the head's fill in the same cycle the
// quantities are presented. The registered fills are the bench view.
module walker_fifo (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        start,
  input  wire [31:0] take_qty,
  input  wire [31:0] oid0,
  input  wire [31:0] qty0,
  input  wire [31:0] oid1,
  input  wire [31:0] qty1,
  output logic       done,
  output logic [31:0] fill0,
  output logic [31:0] fill1,
  output logic [31:0] maker0,
  output logic [31:0] maker1,
  output wire  [31:0] take0
);

  wire [31:0] head = (take_qty < qty0) ? take_qty : qty0;
  wire [31:0] rest = take_qty - qty0;
  wire [31:0] next = (take_qty > qty0) ? ((rest < qty1) ? rest : qty1) : 32'd0;

  assign take0 = head;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      done   <= 1'b0;
      fill0  <= '0;
      fill1  <= '0;
      maker0 <= '0;
      maker1 <= '0;
    end else if (start) begin
      done   <= 1'b1;
      fill0  <= head;
      fill1  <= next;
      maker0 <= oid0;
      maker1 <= oid1;
    end else begin
      done <= 1'b0;
    end
  end

endmodule

`default_nettype wire
