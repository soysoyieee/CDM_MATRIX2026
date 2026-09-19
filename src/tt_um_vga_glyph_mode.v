/*
 * Copyright (c) 2024-2025 James Ross
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_vga_glyph_mode(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire ena,
    input  wire clk,
    input  wire rst_n
);

    wire hsync, vsync, display_on;
    wire [10:0] hpos;
    wire [9:0] vpos;
    wire [5:0] RGB;

    // Keep the original TinyVGA output connections.
    assign uo_out = {
        hsync, RGB[0], RGB[2], RGB[4],
        vsync, RGB[1], RGB[3], RGB[5]
    };

    assign uio_out = 8'd0;
    assign uio_oe = 8'd0;

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

    // Animation phases.
    localparam [1:0] BUILD = 2'd0;
    localparam [1:0] HOLD  = 2'd1;
    localparam [1:0] DROP  = 2'd2;
    localparam [1:0] GAP   = 2'd3;

    reg [1:0] phase;
    reg [7:0] phase_frame;
    reg [5:0] color_frame;
    reg [2:0] auto_color;

    // Once per frame, after the 640 x 480 artwork area.
    wire frame_tick =
        (hpos == 11'd0 && vpos == 10'd480);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= BUILD;
            phase_frame <= 8'd0;
            color_frame <= 6'd0;
            auto_color <= 3'd0;
        end else if (frame_tick) begin

            // Advance automatic color every 60 frames.
            if (color_frame == 6'd59) begin
                color_frame <= 6'd0;
                auto_color <= (auto_color == 3'd6)
                            ? 3'd0 : auto_color + 3'd1;
            end else begin
                color_frame <= color_frame + 6'd1;
            end

            case (phase)
                BUILD: begin
                    if (phase_frame == 8'd95) begin
                        phase <= HOLD;
                        phase_frame <= 8'd0;
                    end else begin
                        phase_frame <= phase_frame + 8'd1;
                    end
                end

                HOLD: begin
                    // 180 frames is approximately 3 seconds.
                    if (phase_frame == 8'd179) begin
                        phase <= DROP;
                        phase_frame <= 8'd0;
                    end else begin
                        phase_frame <= phase_frame + 8'd1;
                    end
                end

                DROP: begin
                    if (phase_frame == 8'd95) begin
                        phase <= GAP;
                        phase_frame <= 8'd0;
                    end else begin
                        phase_frame <= phase_frame + 8'd1;
                    end
                end

                default: begin
                    // Brief empty screen before repeating.
                    if (phase_frame == 8'd29) begin
                        phase <= BUILD;
                        phase_frame <= 8'd0;
                    end else begin
                        phase_frame <= phase_frame + 8'd1;
                    end
                end
            endcase
        end
    end

    // Different columns fall at different times.
    wire [7:0] xb = hpos[10:3];

    wire [4:0] delay_code = {
        xb[0], xb[2], xb[4], xb[1], xb[3]
    };

    wire [10:0] delay_px =
        {4'b0000, delay_code, 2'b00};

    wire [10:0] travel = {phase_frame, 3'b000};
    wire [10:0] start_height = 11'd512 + delay_px;

    wire [10:0] lift = (travel < start_height)
                    ? start_height - travel : 11'd0;

    wire [10:0] fall = (travel > delay_px)
                    ? travel - delay_px : 11'd0;

    reg [10:0] source_y;
    reg source_valid;

    always @(*) begin
        source_y = {1'b0, vpos};
        source_valid = 1'b1;

        case (phase)
            BUILD: begin
                source_y = {1'b0, vpos} + lift;
            end

            HOLD: begin
                source_y = {1'b0, vpos};
            end

            DROP: begin
                source_y = {1'b0, vpos} - fall;
                source_valid = ({1'b0, vpos} >= fall);
            end

            default: begin
                source_valid = 1'b0;
            end
        endcase
    end

    // Original 8 x 12 font, following the moving columns.
    wire [10:0] glyph_row = source_y / 11'd12;

    wire [10:0] glyph_line =
        source_y - (glyph_row << 3) - (glyph_row << 2);

    wire [5:0] yb = glyph_row[5:0];
    wire [3:0] g_y = glyph_line[3:0];

    // "CDM BOOTCAMP 2026 " including a trailing space.
    function [5:0] msg_char;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  msg_char = 6'd2;  // C
                5'd1:  msg_char = 6'd3;  // D
                5'd2:  msg_char = 6'd12; // M
                5'd3:  msg_char = 6'd26; // space
                5'd4:  msg_char = 6'd1;  // B
                5'd5:  msg_char = 6'd14; // O
                5'd6:  msg_char = 6'd14; // O
                5'd7:  msg_char = 6'd19; // T
                5'd8:  msg_char = 6'd2;  // C
                5'd9:  msg_char = 6'd0;  // A
                5'd10: msg_char = 6'd12; // M
                5'd11: msg_char = 6'd15; // P
                5'd12: msg_char = 6'd26; // space
                5'd13: msg_char = 6'd28; // 2
                5'd14: msg_char = 6'd36; // 0
                5'd15: msg_char = 6'd28; // 2
                5'd16: msg_char = 6'd32; // 6
                5'd17: msg_char = 6'd26; // space
                default: msg_char = 6'd26;
            endcase
        end
    endfunction

    // Repeat the phrase across the 80 visible columns.
    wire [7:0] text_col =
        (xb >= 8'd72) ? xb - 8'd72 :
        (xb >= 8'd54) ? xb - 8'd54 :
        (xb >= 8'd36) ? xb - 8'd36 :
        (xb >= 8'd18) ? xb - 8'd18 : xb;

    wire [5:0] glyph_index = msg_char(text_col[4:0]);
    wire hl;

    glyphs_rom glyphs(
        .c(glyph_index),
        .y(g_y),
        .x(hpos[2:0]),
        .pixel(hl)
    );

    // Left-facing coupe silhouette.
    reg body;

    always @(*) begin
        body = 1'b0;

        case (yb)
            6'd12:
                body = (xb >= 8'd34 && xb <= 8'd49);
            6'd13:
                body = (xb >= 8'd32 && xb <= 8'd52);
            6'd14:
                body = (xb >= 8'd30 && xb <= 8'd55);
            6'd15:
                body = (xb >= 8'd28 && xb <= 8'd58);
            6'd16:
                body = (xb >= 8'd26 && xb <= 8'd62);
            6'd17:
                body = (xb >= 8'd10 && xb <= 8'd72);
            6'd18:
                body = (xb >= 8'd5 && xb <= 8'd74);
            6'd19, 6'd20, 6'd21:
                body = (xb >= 8'd3 && xb <= 8'd75);
            6'd22:
                body = (xb >= 8'd4 && xb <= 8'd74);
            6'd23:
                body = (xb >= 8'd6 && xb <= 8'd73);
            6'd24:
                body = (xb >= 8'd9 && xb <= 8'd70);
            default:
                body = 1'b0;
        endcase
    end

    wire windows =
        (yb >= 6'd14 && yb <= 6'd16) &&
        ((xb >= 8'd33 && xb <= 8'd46) ||
         (xb >= 8'd49 && xb <= 8'd54));

    wire arches =
        (yb >= 6'd21 && yb <= 6'd24) &&
        ((xb >= 8'd11 && xb <= 8'd23) ||
         (xb >= 8'd53 && xb <= 8'd65));

    wire door_seam =
        (xb == 8'd48 && yb >= 6'd17 && yb <= 6'd24);

    reg wheels;

    always @(*) begin
        wheels = 1'b0;

        case (yb)
            6'd22, 6'd28:
                wheels =
                    (xb >= 8'd14 && xb <= 8'd20) ||
                    (xb >= 8'd56 && xb <= 8'd62);

            6'd23, 6'd27:
                wheels =
                    (xb >= 8'd12 && xb <= 8'd22) ||
                    (xb >= 8'd54 && xb <= 8'd64);

            6'd24, 6'd25, 6'd26:
                wheels =
                    (xb >= 8'd11 && xb <= 8'd23) ||
                    (xb >= 8'd53 && xb <= 8'd65);

            default:
                wheels = 1'b0;
        endcase
    end

    wire wheel_holes =
        (yb == 6'd24 || yb == 6'd26) &&
        ((xb >= 8'd15 && xb <= 8'd19) ||
         (xb >= 8'd57 && xb <= 8'd61));

    wire car =
        (body && !windows && !arches && !door_seam) ||
        (wheels && !wheel_holes);

    // ui_in[2:0]: seven colors or automatic cycling.
   wire [2:0] selected = auto_color;

    reg [5:0] color;

    always @(*) begin
        case (selected)
            3'd0: color = 6'b110011; // magenta
            3'd1: color = 6'b110000; // red
            3'd2: color = 6'b000011; // blue
            3'd3: color = 6'b001100; // green
            3'd4: color = 6'b001111; // cyan
            3'd5: color = 6'b111100; // yellow
            3'd6: color = 6'b111111; // white
            default: color = 6'b110011;
        endcase
    end

    assign RGB =
        (display_on && hpos < 11'd640 &&
         source_valid && source_y < 11'd480 &&
         car && hl) ? color : 6'd0;

    wire _unused_ok = &{
        1'b0, ena, ui_in[5:0], uio_in,
        glyph_row[10:6], glyph_line[10:4]
    };

endmodule
