module mitchell_exp2 #(parameter W=12, parameter F=6)(
    input  wire signed [W-1:0] x,
    output reg         [W-1:0] y
);
    localparam INT = W-F;
    wire signed [INT-1:0] e; wire [F-1:0] f;
    assign e = x[W-1:F];
    assign f = x[F-1:0];
    wire [F:0] mant = {1'b1, f};  // 7-bit, value = (64+f)/64

    // wide = mant shifted so its '1' (bit F of mant) is at position W+F of wide
    // = mant << W   (24-bit register)
    // right_shift_amount = W - e  to bring binary point to position F
    reg [2*W-1:0] wide;
    integer rsh;
    always @(*) begin
        wide = {{(W-F-1){1'b0}}, mant, {W{1'b0}}};  // mant << W
        rsh  = W - $signed({{(32-INT){e[INT-1]}},e});
        if (rsh < 0)        y = {W{1'b1}};  // overflow
        else if (rsh >= 2*W) y = {W{1'b0}};  // underflow
        else begin
            wide = wide >> rsh;
            y = (|wide[2*W-1:W]) ? {W{1'b1}} : wide[W-1:0];
        end
    end
endmodule
