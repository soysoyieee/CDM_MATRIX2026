/*
 * Copyright (c) 2024-2025 James Ross
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_glyph_mode(
	input  wire [7:0] ui_in,    // Dedicated inputs
	output wire [7:0] uo_out,   // Dedicated outputs
	input  wire [7:0] uio_in,   // IOs: Input path
	output wire [7:0] uio_out,  // IOs: Output path
	output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
	input  wire       ena,      // always 1 when the design is powered, so you can ignore it
	input  wire       clk,      // clock
	input  wire       rst_n     // reset_n - low to reset
);

	// VGA signals
	wire hsync, vsync, display_on;
	wire [10:0] hpos;
	wire [9:0] vpos;

	// TinyVGA PMOD
	assign uo_out = {hsync, RGB[0], RGB[2], RGB[4], vsync, RGB[1], RGB[3], RGB[5]};

	// Unused outputs assigned to 0.
	assign uio_out = 0;
	assign uio_oe  = 0;

	wire [7:0] xb = hpos[10:3];
	wire [6:0] x_mix = {xb[7] ^ xb[3], xb[1], xb[4], xb[1], xb[6], xb[0], xb[2]};
	wire [2:0] g_x = hpos[2:0];
	wire [5:0] yb;
	wire [3:0] _unused;
	assign {_unused, yb} = vpos / 10'd12;
	wire [5:0] g_unused;
	wire [3:0] g_y;
	assign {g_unused, g_y} = vpos - {yb, 3'b000} - {1'b0, yb, 2'b00};
	wire hl;

	// Suppress unused signals warning
	wire _unused_ok = &{ena, ui_in[5:3], uio_in};

	reg [9:0] frame;
	reg rst_drop;

	// VGA output
	hvsync_generator hvsync_gen(
		.clk(clk),
		.reset(~rst_n),
		.mode(ui_in[7:6]),
		.hsync(hsync),
		.vsync(vsync),
		.display_on(display_on),
		.hpos(hpos),
		.vpos(vpos)
	);

	// glyphs
	glyphs_rom glyphs(
		.c(glyph_index),
		.y(g_y),
		.x(g_x),
		.pixel(hl)
	);

	// palette
	// ui_in[1:0] picks a palette as before (0=green,1=red,2=blue,3=pride).
	// ui_in[2] turns on alternating pink/green: each column of falling
	// glyphs is entirely pink or entirely green, chosen by column parity.
	wire alt_pink_green = ui_in[2];
	wire [2:0] pid = alt_pink_green ? (xb[0] ? 3'd4 : 3'd0) : {1'b0, ui_in[1:0]};
	wire [5:0] color;
	palette_rom palettes(
		.cid(y),
		.pid(pid),
		.color(color)
	);

	// there are 39 glyphs
	//wire [5:0] glyph_index = {xb[2] ^ yb[0], xb[0] ^ yb[1], xb[1] ^ yb[2], xb[4] ^ yb[3], xb[3] ^ yb[4]} // [0,31]
	//	+ {1'b0, xb[5] ^ yb[5], xb[6] ^ yb[0], xb[0] ^ yb[1], xb[1] ^ yb[2]} // [0,15]
	//	+ {1'b0, x[6:3]} // [0,15]
	//	+ {1'b0, t & frame[7], t & frame[6], t & frame[5], t & frame[4] & s}; // [0,15]

	//wire [5:0] glyph_index = (yb + xb) % 6'd19;
	//wire [5:0] glyph_index = (yb + xb) % 6'd30;
	//wire [5:0] glyph_index = (yb + xb) % 6'd39;

	// "COLEGIO DE MUNTINLUPA" tiled diagonally across the screen (32-char
	// message, padded with trailing spaces so the index just wraps with a
	// cheap 5-bit truncation instead of a mod-39 divide).
	function [5:0] msg_char;
		input [4:0] idx;
		begin
			case (idx)
				5'd0:  msg_char = 6'd2;  // C
				5'd1:  msg_char = 6'd14; // O
				5'd2:  msg_char = 6'd11; // L
				5'd3:  msg_char = 6'd4;  // E
				5'd4:  msg_char = 6'd6;  // G
				5'd5:  msg_char = 6'd8;  // I
				5'd6:  msg_char = 6'd14; // O
				5'd7:  msg_char = 6'd26; // (space)
				5'd8:  msg_char = 6'd3;  // D
				5'd9:  msg_char = 6'd4;  // E
				5'd10: msg_char = 6'd26; // (space)
				5'd11: msg_char = 6'd12; // M
				5'd12: msg_char = 6'd20; // U
				5'd13: msg_char = 6'd13; // N
				5'd14: msg_char = 6'd19; // T
				5'd15: msg_char = 6'd8;  // I
				5'd16: msg_char = 6'd13; // N
				5'd17: msg_char = 6'd11; // L
				5'd18: msg_char = 6'd20; // U
				5'd19: msg_char = 6'd15; // P
				5'd20: msg_char = 6'd0;  // A
				default: msg_char = 6'd26; // padding (space)
			endcase
		end
	endfunction

	wire [5:0] glyph_index = msg_char((yb + xb) & 5'h1F);
	
	wire [1:0] a = xb[1:0];
	wire [3:0] b = xb[5:2];
	wire [2:0] d = xb[3:2] + 2'd3;

	wire t = &{xb[0] ^ yb[2] ^ frame[7], xb[1] ^ yb[1] ^ frame[8], xb[2] ^ yb[3] ^ frame[9], xb[3] ^ yb[0]}; // toggle glyph

	// column features
	wire s = ^xb[6:0]; // speed of rain
	wire n = xb[1] ^ xb[3] ^ xb[5]; // lit on or off

	wire [6:0] v = (s ? frame[8:2] : frame[9:3]) - yb - x_mix;
	wire [3:0] c = {1'b0, a} + d;
	wire [6:0] e = {3'b000, b} << c;
	wire [6:0] f = v & e;
	wire [6:0] x = v >> a;
	wire [2:0] y = ~x[2:0];
	wire [9:0] drop = {1'b0, yb, 3'd0} >> s;
	wire drop_bit = ({3'd0, x_mix} + drop > frame) & ~rst_drop;
	wire [5:0] glyph_color = {6{drop_bit}} ^ color;

	wire [5:0] z = (&(~v[2:0]) & &(y)) ? 6'd63 : glyph_color;

	wire [5:0] RGB = (display_on & hl & ~(|f | n | drop_bit)) ? z : 6'd0;

	always @(posedge vsync, negedge rst_n) begin
		if (~rst_n) begin
			rst_drop <= 0;
			frame <= 0;
		end else begin
			if (&frame) begin
				rst_drop <= 1;
			end
			frame <= frame + 1;
		end
	end

endmodule

