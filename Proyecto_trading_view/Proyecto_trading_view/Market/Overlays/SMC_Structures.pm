package Market::Overlays::SMC_Structures;

# =============================================================================
# Market::Overlays::SMC_Structures
# Metodos publicos INDEPENDIENTES (cada uno con su propio namespace de
# tags Tk) para que ChartEngine pueda activarlos/desactivarlos sin que se
# estorben entre si ni con otros overlays (Liquidity, etc):
#   - render_fibonacci:        Fibonacci click-to-anchor (ZigZag Ex)
#   - render_bos / render_choch:   BOS/CHoCH externos (estructura mayor)
#   - render_ibos / render_ichoch: I-BOS/I-CHOCH internos (estructura menor)
#   - render_eq:               EQH/EQL (Equal Highs/Lows)
#   - render_structure_labels: etiquetas HH/HL/LH/LL sueltas (sin zigzag)
#   - render_fvgs:             Fair Value Gaps (estilo TradingFinder/LuxAlgo)
#   - render_swings:           zigzag (macro)
#   - render_order_blocks:     Order Blocks swing + internos (mismo boton)
#   - render_channel:          Canal/Tendline (NUEVO, grupo 11)
# =============================================================================

use strict;
use warnings;

sub new {
    my ( $class, %args ) = @_;
    my $self = { %args };
    $self->{theme} = {} unless defined $self->{theme};
    bless $self, $class;
    return $self;
}

# =============================================================================
# render_fibonacci
# =============================================================================
sub render_fibonacci {
    my ( $self, $canvas, $scale, $start, $end, $replay_limit, $point1, $point2, $width_index ) = @_;

    $canvas->delete('smc_fib_all');
    return unless $scale && $point1 && $point2;

    my $limit = defined $replay_limit ? $replay_limit : $end;

    $self->_render_fibonacci( $canvas, $scale, $start, $end, $limit, $point1, $point2, $width_index );

    return;
}

sub render_bos {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_bos_all');
    return unless $smc && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;
    $self->_render_structure_events( $canvas, $smc, $scale, $start, $end, $limit, 'BOS', 'smc_bos_all' );
    return;
}

sub render_choch {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_choch_all');
    return unless $smc && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;
    $self->_render_structure_events( $canvas, $smc, $scale, $start, $end, $limit, 'CHOCH', 'smc_choch_all' );
    return;
}

sub render_ibos {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_ibos_all');
    return unless $smc && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;
    $self->_render_structure_events( $canvas, $smc, $scale, $start, $end, $limit, 'I-BOS', 'smc_ibos_all' );
    return;
}

sub render_ichoch {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_ichoch_all');
    return unless $smc && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;
    $self->_render_structure_events( $canvas, $smc, $scale, $start, $end, $limit, 'I-CHOCH', 'smc_ichoch_all' );
    return;
}

sub render_eq {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_eq_all');
    return unless $smc && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;
    my $bull_color = $self->{theme}{smc_bull} // '#089981';
    my $bear_color = $self->{theme}{smc_bear} // '#f23645';

    for my $e ( @{ $smc->get_equal_levels } ) {
        next if $e->{idx2} > $limit;
        next if $e->{idx2} < $start || $e->{idx1} > $end;

        my $is_high = ( $e->{type} eq 'high' );
        my $color   = $is_high ? $bear_color : $bull_color;
        my $tag     = $is_high ? 'EQH' : 'EQL';

        my $from_idx = $e->{idx1} < $start ? $start : $e->{idx1};
        my $x1 = $scale->index_to_center_x($from_idx);
        my $x2 = $scale->index_to_center_x( $e->{idx2} );
        my $y1 = $scale->value_to_y( $e->{price1} );
        my $y2 = $scale->value_to_y( $e->{price2} );

        $canvas->createLine(
            $x1, $y1, $x2, $y2,
            -fill => $color, -dash => [ 2, 3 ], -width => 1,
            -tags => [ 'smc_eq_all', 'smc_eq' ],
        );

        my $mid_x = int( ( $x1 + $x2 ) / 2 );
        my $mid_y = ( $y1 + $y2 ) / 2 + ( $is_high ? -10 : 10 );
        $canvas->createText(
            $mid_x, $mid_y,
            -text => $tag, -fill => $color, -font => 'Helvetica 8 bold',
            -anchor => 'center', -tags => [ 'smc_eq_all', 'smc_eq' ],
        );
    }
    return;
}

sub render_structure_labels {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_ms_labels_all');
    return unless $smc && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;

    my $pivots  = $smc->get_macro_pivots;
    my @visible = grep { $_->{index} <= $limit && $_->{index} >= $start && $_->{index} <= $end } @$pivots;

    my $bull_color = $self->{theme}{smc_bull} // '#089981';
    my $bear_color = $self->{theme}{smc_bear} // '#f23645';

    for my $p (@visible) {
        my $is_high = ( $p->{type} eq 'high' );
        my $color   = $is_high ? $bear_color : $bull_color;

        my $x     = $scale->index_to_center_x( $p->{index} );
        my $y     = $scale->value_to_y( $p->{price} );
        my $y_off = $is_high ? -10 : 10;

        $canvas->createText( $x, $y + $y_off, -text => $p->{label}, -fill => $color,
            -font => 'Helvetica 8 bold', -anchor => 'center',
            -tags => [ 'smc_ms_labels_all', 'smc_ms_label' ] );
    }
    return;
}

sub render_fvgs {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_fvg_all');
    return unless $smc && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;

    $self->_render_fvgs( $canvas, $smc, $scale, $start, $end, $limit );

    $canvas->lower('smc_fvg_all', 'candle');
    return;
}

sub render_order_blocks {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_ob_all');
    return unless $smc && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;

    my $bull_color = $self->{theme}{ob_bull} // '#3179f5';
    my $bear_color = $self->{theme}{ob_bear} // '#b22833';
    my $fill_alpha = $self->{theme}{ob_alpha} // 0.35;

    my $int_bull_color = $self->{theme}{ob_internal_bull} // '#3179f5';
    my $int_bear_color = $self->{theme}{ob_internal_bear} // '#f77c80';

    $self->_draw_order_block_set(
        $canvas, $scale, $start, $end, $limit, $fill_alpha,
        $smc->get_order_blocks, $bull_color, $bear_color, 'Order Block',
    );

    if ( $smc->can('get_internal_order_blocks') ) {
        $self->_draw_order_block_set(
            $canvas, $scale, $start, $end, $limit, $fill_alpha,
            $smc->get_internal_order_blocks, $int_bull_color, $int_bear_color, 'Internal Order Block',
        );
    }

    $canvas->lower('smc_ob_all', 'candle');

    return;
}

sub _draw_order_block_set {
    my ( $self, $canvas, $scale, $start, $end, $limit, $fill_alpha,
         $obs, $bull_color, $bear_color, $label_base ) = @_;

    for my $ob (@$obs) {
        next if $ob->{start_index} > $limit;
        next if $ob->{start_index} > $end;

        next if $ob->{mitigated} && $ob->{mitigated_index} <= $limit;

        my $color = $ob->{bias} eq 'bullish' ? $bull_color : $bear_color;
        my $fill  = $self->_blend_with_bg( $color, $fill_alpha );

        my $left_idx  = $ob->{start_index} < $start ? $start : $ob->{start_index};
        my $right_idx = $limit > $end ? $end : $limit;
        next if $right_idx < $left_idx;

        my $x1 = $scale->index_to_center_x($left_idx);
        my $x2 = $scale->index_to_center_x($right_idx);
        my $y1 = $scale->value_to_y( $ob->{top} );
        my $y2 = $scale->value_to_y( $ob->{bottom} );

        $canvas->createRectangle(
            $x1, $y1, $x2, $y2,
            -fill => $fill, -outline => $fill,
            -tags => [ 'smc_ob_all', 'smc_ob' ],
        );

        my $label_x = $x1 + 4;
        my $label_y = ( $y1 + $y2 ) / 2;
        $canvas->createText(
            $label_x, $label_y,
            -text   => ( $ob->{bias} eq 'bullish' ? "Bullish $label_base" : "Bearish $label_base" ),
            -fill   => '#ffffff',
            -font   => 'Helvetica 7 bold',
            -anchor => 'w',
            -tags   => [ 'smc_ob_all', 'smc_ob_label' ],
        );
    }
    return;
}

sub render_trailing {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_trail_all');
    return unless $smc && $scale;

    my $limit  = defined $replay_limit ? $replay_limit : $end;
    my $extr   = $smc->get_trailing_extremes;
    return unless $extr;
    return if $extr->{top_index} > $limit && $extr->{bottom_index} > $limit;

    my $bull_color = $self->{theme}{trail_bull} // '#089981';
    my $bear_color = $self->{theme}{trail_bear} // '#f23645';

    my $top_label    = ( $extr->{trend_bias} == -1 ) ? 'Strong High' : 'Weak High';
    my $bottom_label = ( $extr->{trend_bias} ==  1 ) ? 'Strong Low'  : 'Weak Low';

    if ( $extr->{top_index} <= $limit && $extr->{top_index} >= $start - 200 ) {
        my $x1 = $scale->index_to_center_x( $extr->{top_index} < $start ? $start : $extr->{top_index} );
        my $x2 = $scale->index_to_center_x($end);
        my $y  = $scale->value_to_y( $extr->{top} );
        $canvas->createLine( $x1, $y, $x2, $y, -fill => $bear_color, -width => 1, -dash => [ 5, 3 ],
            -tags => [ 'smc_trail_all', 'smc_trail' ] );
        $canvas->createText( $x2 - 4, $y - 8, -text => $top_label, -fill => $bear_color,
            -font => 'Helvetica 7 bold', -anchor => 'e', -tags => [ 'smc_trail_all', 'smc_trail' ] );
    }

    if ( $extr->{bottom_index} <= $limit && $extr->{bottom_index} >= $start - 200 ) {
        my $x1 = $scale->index_to_center_x( $extr->{bottom_index} < $start ? $start : $extr->{bottom_index} );
        my $x2 = $scale->index_to_center_x($end);
        my $y  = $scale->value_to_y( $extr->{bottom} );
        $canvas->createLine( $x1, $y, $x2, $y, -fill => $bull_color, -width => 1, -dash => [ 5, 3 ],
            -tags => [ 'smc_trail_all', 'smc_trail' ] );
        $canvas->createText( $x2 - 4, $y + 12, -text => $bottom_label, -fill => $bull_color,
            -font => 'Helvetica 7 bold', -anchor => 'e', -tags => [ 'smc_trail_all', 'smc_trail' ] );
    }
    return;
}

sub render_swings {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit, $market_data, $now_index ) = @_;

    $canvas->delete('smc_swing_all');
    return unless $smc && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;
    $self->_render_macro_swings( $canvas, $smc, $scale, $start, $end, $limit, $market_data, $now_index );
    return;
}

# =============================================================================
# render_channel — BLOQUE CANAL/TENDLINE (NUEVO, grupo 11 del enunciado).
# Dibuja, para cada canal detectado por el indicador (get_channels): 2
# lineas SOLIDAS (la base -- por donde pasan los 3 pivotes del mismo tipo
# -- y la pared opuesta), 1 linea PUNTEADA (la mediana), y un relleno azul
# transparente entre ambas paredes -- igual estilo que pediste ("canal
# azul transparente").
# =============================================================================
sub render_channel {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('smc_channel_all');
    return unless $smc && $scale;
    return unless $smc->can('get_channels');

    my $limit = defined $replay_limit ? $replay_limit : $end;
    my $line_color = $self->{theme}{channel_line} // '#2962ff';
    my $fill       = $self->_blend_with_bg( $line_color, $self->{theme}{channel_alpha} // 0.15 );

    for my $ch ( @{ $smc->get_channels } ) {
        next if $ch->{i1} > $limit;

        my $li = $ch->{i1} < $start ? $start : $ch->{i1};
        my $box_right = $ch->{i3};
        $box_right = $limit if $box_right > $limit;
        my $ri = $box_right > $end ? $end : $box_right;
        next if $ri < $li;

        my ( $b1, $o1 ) = $smc->channel_lines_at( $ch, $li );
        my ( $b2, $o2 ) = $smc->channel_lines_at( $ch, $ri );

        my $x1 = $scale->index_to_center_x($li);
        my $x2 = $scale->index_to_center_x($ri);

        # Relleno azul transparente entre las dos paredes
        $canvas->createPolygon(
            $x1, $scale->value_to_y($b1), $x2, $scale->value_to_y($b2),
            $x2, $scale->value_to_y($o2), $x1, $scale->value_to_y($o1),
            -fill => $fill, -outline => '',
            -tags => [ 'smc_channel_all', 'smc_channel' ],
        );

        # Pared base (por donde pasan los 3 pivotes)
        $canvas->createLine( $x1, $scale->value_to_y($b1), $x2, $scale->value_to_y($b2),
            -fill => $line_color, -width => 1,
            -tags => [ 'smc_channel_all', 'smc_channel' ] );

        # Pared opuesta
        $canvas->createLine( $x1, $scale->value_to_y($o1), $x2, $scale->value_to_y($o2),
            -fill => $line_color, -width => 1,
            -tags => [ 'smc_channel_all', 'smc_channel' ] );

        # Mediana (punteada)
        my $m1 = ( $b1 + $o1 ) / 2;
        my $m2 = ( $b2 + $o2 ) / 2;
        $canvas->createLine( $x1, $scale->value_to_y($m1), $x2, $scale->value_to_y($m2),
            -fill => '#90a4ff', -width => 1, -dash => [ 4, 3 ],
            -tags => [ 'smc_channel_all', 'smc_channel' ] );
    }

    $canvas->lower( 'smc_channel_all', 'candle' );
    return;
}

sub _render_structure_events {
    my ( $self, $canvas, $smc, $scale, $start, $end, $limit, $want_type, $tag_all ) = @_;

    my $bull_color = $self->{theme}{smc_bull} // '#089981';
    my $bear_color = $self->{theme}{smc_bear} // '#f23645';

    for my $s ( @{ $smc->get_structures } ) {
        next unless $s->{type} eq $want_type;
        next if $s->{event_index} > $limit;
        next if $s->{event_index} < $start || $s->{from_index} > $end;

        my $color = ( $s->{direction} eq 'bullish' ) ? $bull_color : $bear_color;

        my $from_idx = $s->{from_index} < $start ? $start : $s->{from_index};
        my $x1 = $scale->index_to_center_x($from_idx);
        my $x2 = $scale->index_to_center_x( $s->{event_index} );
        my $y  = $scale->value_to_y( $s->{level} );

        $canvas->createLine(
            $x1, $y, $x2, $y,
            -fill  => $color,
            -dash  => ( $s->{type} =~ /CHOCH$/ ) ? [ 4, 3 ] : undef,
            -width => 1,
            -tags  => [ $tag_all, 'smc_structure' ],
        );

        my $label_text = $s->{type};
        $label_text .= ' +LQ' if defined $s->{liquidity};

        my $label_y = ( $s->{direction} eq 'bullish' ) ? $y - 8 : $y + 14;
        $canvas->createText(
            $x2, $label_y,
            -text   => $label_text,
            -fill   => $color,
            -font   => 'Helvetica 8 bold',
            -anchor => 'center',
            -tags   => [ $tag_all, 'smc_structure' ],
        );
    }
    return;
}

sub _render_fvgs {
    my ( $self, $canvas, $smc, $scale, $start, $end, $limit ) = @_;

    my $bull_color = $self->{theme}{smc_fvg_bull}      // '#4caf50';
    my $bear_color = $self->{theme}{smc_fvg_bear}      // '#f23645';
    my $gray_color = $self->{theme}{smc_fvg_mitigated} // '#9e9e9e';
    my $alpha      = $self->{theme}{smc_fvg_alpha}     // 0.5;

    for my $fvg ( @{ $smc->get_fvgs } ) {
        next if $fvg->{start_index} > $limit;
        next if $fvg->{start_index} > $end;

        my $full_happened    = defined $fvg->{full_index}    && $fvg->{full_index}    <= $limit;
        my $evicted_happened = defined $fvg->{evicted_index} && $fvg->{evicted_index} <= $limit;
        next if $full_happened || $evicted_happened;

        my $right_index = $limit > $end ? $end : $limit;
        next if $right_index < $start;

        my $left_idx = $fvg->{start_index} < $start ? $start : $fvg->{start_index};

        my $is_bull = ( $fvg->{bias} eq 'bullish' );
        my $is_gray = defined $fvg->{partial_index} && $fvg->{partial_index} <= $limit;

        my $base_color = $is_gray ? $gray_color : ( $is_bull ? $bull_color : $bear_color );
        my $fill_color = $self->_blend_with_bg( $base_color, $alpha );

        my $x1 = $scale->index_to_center_x($left_idx);
        my $x2 = $scale->index_to_center_x($right_index);
        my $y1 = $scale->value_to_y( $fvg->{top} );
        my $y2 = $scale->value_to_y( $fvg->{bottom} );

        $canvas->createRectangle(
            $x1, $y1, $x2, $y2,
            -fill => $fill_color, -outline => '',
            -tags => [ 'smc_fvg_all', 'smc_fvg_box' ],
        );

        my $label_x = ( $x1 + $x2 ) / 2;
        my $label_y = ( $y1 + $y2 ) / 2;

        $canvas->createText(
            $label_x, $label_y,
            -text   => 'FVG',
            -fill   => '#ffffff',
            -font   => 'Helvetica 7 bold',
            -anchor => 'center',
            -tags   => [ 'smc_fvg_all', 'smc_fvg_label' ],
        );
    }
    return;
}

sub _blend_with_bg {
    my ( $self, $hex_color, $alpha ) = @_;
    my $bg = $self->{theme}{panel_bg} // '#131722';
    my ( $r1, $g1, $b1 ) = map { hex($_) } ( $hex_color =~ /^#(..)(..)(..)$/ );
    my ( $r2, $g2, $b2 ) = map { hex($_) } ( $bg         =~ /^#(..)(..)(..)$/ );
    my $r = int( $r1 * $alpha + $r2 * ( 1 - $alpha ) );
    my $g = int( $g1 * $alpha + $g2 * ( 1 - $alpha ) );
    my $b = int( $b1 * $alpha + $b2 * ( 1 - $alpha ) );
    return sprintf( '#%02x%02x%02x', $r, $g, $b );
}

sub _render_fibonacci {
    my ( $self, $canvas, $scale, $start, $end, $limit, $point1, $point2, $width_index ) = @_;

    return unless $point1 && $point2;

    my $latest_index = $point2->{index} > $point1->{index} ? $point2->{index} : $point1->{index};
    return if $latest_index > $limit;

    my $price_1 = $point1->{price};
    my $price_0 = $point2->{price};

    my @levels = ( 0, 0.236, 0.382, 0.5, 0.618, 0.786, 1, 1.618, 2.618, 3.618, 4.236 );

    my %level_colors = (
        '0'     => $self->{theme}{fib_0}     // '#9598a1',
        '0.236' => $self->{theme}{fib_236}   // '#f23645',
        '0.382' => $self->{theme}{fib_382}   // '#ff9800',
        '0.5'   => $self->{theme}{fib_500}   // '#4caf50',
        '0.618' => $self->{theme}{fib_618}   // '#089981',
        '0.786' => $self->{theme}{fib_786}   // '#00bcd4',
        '1'     => $self->{theme}{fib_1}     // '#9598a1',
        '1.618' => $self->{theme}{fib_1618}  // '#2962ff',
        '2.618' => $self->{theme}{fib_2618}  // '#f23645',
        '3.618' => $self->{theme}{fib_3618}  // '#9c27b0',
        '4.236' => $self->{theme}{fib_4236}  // '#e91e63',
    );

    my $far_index = defined $width_index ? $width_index : $limit;

    my $box_left  = $point1->{index};
    my $box_right = $far_index;
    ( $box_left, $box_right ) = ( $box_right, $box_left ) if $box_left > $box_right;

    my $draw_from = $box_left  < $start ? $start : $box_left;
    my $draw_to   = $box_right > $end   ? $end   : $box_right;
    $draw_to = $limit if $draw_to > $limit;
    return if $draw_to < $draw_from;

    my $x1 = $scale->index_to_center_x($draw_from);
    my $x2 = $scale->index_to_center_x($draw_to);

    for my $pct (@levels) {
        my $price  = $price_0 + $pct * ( $price_1 - $price_0 );
        my $y      = $scale->value_to_y($price);
        my $lcolor = $level_colors{"$pct"} // '#9598a1';
        $canvas->createLine( $x1, $y, $x2, $y, -fill => $lcolor, -dash => [ 2, 3 ],
            -tags => [ 'smc_fib_all', 'smc_fib' ] );
        $canvas->createText( $x2 - 4, $y - 7,
            -text   => sprintf( '%s (%.2f)', _fmt_pct($pct), $price ),
            -fill   => $lcolor, -font => 'Helvetica 7', -anchor => 'e',
            -tags   => [ 'smc_fib_all', 'smc_fib' ] );
    }

    if ( $point1->{index} != $far_index ) {
        my $slope = ( $price_0 - $price_1 ) / ( $far_index - $point1->{index} );

        my $tl_p1 = $price_1 + $slope * ( $draw_from - $point1->{index} );
        my $tl_p2 = $price_1 + $slope * ( $draw_to   - $point1->{index} );

        my $lx1 = $scale->index_to_center_x($draw_from);
        my $ly1 = $scale->value_to_y($tl_p1);
        my $lx2 = $scale->index_to_center_x($draw_to);
        my $ly2 = $scale->value_to_y($tl_p2);

        $canvas->createLine( $lx1, $ly1, $lx2, $ly2,
            -fill => '#b2b5be', -width => 1, -dash => [ 3, 3 ],
            -tags => [ 'smc_fib_all', 'smc_fib_trend' ] );
    }

    for my $p ( $point1, $point2 ) {
        next if $p->{index} < $start || $p->{index} > $end;
        my $px = $scale->index_to_center_x( $p->{index} );
        my $py = $scale->value_to_y( $p->{price} );
        $canvas->createOval( $px - 4, $py - 4, $px + 4, $py + 4,
            -outline => '#9598a1', -width => 2, -fill => '',
            -tags => [ 'smc_fib_all', 'smc_fib_point' ] );
    }

    return;
}

sub _fmt_pct {
    my ($pct) = @_;
    my $s = sprintf( '%.3f', $pct );
    $s =~ s/0+$//;
    $s =~ s/\.$//;
    return $s eq '' ? '0' : $s;
}

sub _render_macro_swings {
    my ( $self, $canvas, $smc, $scale, $start, $end, $limit, $market_data, $now_index ) = @_;

    my $pivots = $smc->get_macro_pivots;
    my @vis    = grep { $_->{index} <= $limit } @$pivots;
    return unless @vis;

    my $first = 0;
    for my $idx ( 0 .. $#vis ) {
        if ( $vis[$idx]{index} >= $start ) {
            $first = $idx > 0 ? $idx - 1 : 0;
            last;
        }
        $first = $idx;
    }
    @vis = @vis[ $first .. $#vis ];

    my $bull_c = '#00C896';
    my $bear_c = '#FF4560';

    for my $i ( 0 .. $#vis - 1 ) {
        my $p1 = $vis[$i];
        my $p2 = $vis[ $i + 1 ];

        next if $p2->{index} > $limit;
        next if $p2->{index} < $start;
        next if $p1->{index} > $end;

        my $going_up = ( $p1->{type} eq 'low' && $p2->{type} eq 'high' );
        my $going_dn = ( $p1->{type} eq 'high' && $p2->{type} eq 'low' );
        next unless $going_up || $going_dn;

        my $color = $going_up ? $bull_c : $bear_c;

        my ( $i1, $pr1 ) = ( $p1->{index}, $p1->{price} );
        my ( $i2, $pr2 ) = ( $p2->{index}, $p2->{price} );
        my $slope = ( $i1 != $i2 ) ? ( $pr2 - $pr1 ) / ( $i2 - $i1 ) : 0;

        my $di1 = $i1 < $start ? $start : $i1;
        my $di2 = $i2 > $end   ? $end   : $i2;

        my $dp1 = $pr1 + $slope * ( $di1 - $i1 );
        my $dp2 = $pr1 + $slope * ( $di2 - $i1 );

        my $x1 = $scale->index_to_center_x($di1);
        my $x2 = $scale->index_to_center_x($di2);
        my $y1 = $scale->value_to_y($dp1);
        my $y2 = $scale->value_to_y($dp2);

        $canvas->createLine(
            $x1, $y1, $x2, $y2,
            -fill  => $color,
            -width => 2,
            -tags  => [ 'smc_swing_all', 'smc_swing_zigzag' ],
        );
    }

    if ( defined $now_index && @vis && $market_data ) {
        my $last_p = $vis[-1];

        if ( $last_p->{index} <= $now_index ) {
            my @chain = ( { index => $last_p->{index}, price => $last_p->{price} } );

            my $micro_values = $smc->can('get_values') ? $smc->get_values : undef;
            if ($micro_values) {
                for my $idx ( $last_p->{index} + 1 .. $now_index ) {
                    last if $idx > $#$micro_values;
                    my $mv = $micro_values->[$idx];
                    next unless $mv && defined $mv->{price};
                    push @chain, { index => $idx, price => $mv->{price} };
                }
            }

            my $cur = $market_data->get_candle($now_index);
            if ( $cur && $chain[-1]{index} != $now_index ) {
                push @chain, { index => $now_index, price => $cur->{close} };
            }

            for my $s ( 0 .. $#chain - 1 ) {
                my $p1 = $chain[$s];
                my $p2 = $chain[ $s + 1 ];
                next if $p2->{index} < $start;
                next if $p1->{index} > $end;

                my $color = ( $p2->{price} >= $p1->{price} ) ? $bull_c : $bear_c;

                my ( $i1, $pr1 ) = ( $p1->{index}, $p1->{price} );
                my ( $i2, $pr2 ) = ( $p2->{index}, $p2->{price} );
                my $slope = ( $i1 != $i2 ) ? ( $pr2 - $pr1 ) / ( $i2 - $i1 ) : 0;

                my $di1 = $i1 < $start ? $start : $i1;
                my $di2 = $i2 > $end   ? $end   : $i2;

                my $dp1 = $pr1 + $slope * ( $di1 - $i1 );
                my $dp2 = $pr1 + $slope * ( $di2 - $i1 );

                my $x1 = $scale->index_to_center_x($di1);
                my $x2 = $scale->index_to_center_x($di2);
                my $y1 = $scale->value_to_y($dp1);
                my $y2 = $scale->value_to_y($dp2);

                $canvas->createLine(
                    $x1, $y1, $x2, $y2,
                    -fill  => $color,
                    -width => 2,
                    -tags  => [ 'smc_swing_all', 'smc_swing_zigzag' ],
                );
            }
        }
    }

    return;
}

sub render_swing_labels {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('zz_b_all');
    return unless $smc && $scale;

    my $limit  = defined $replay_limit ? $replay_limit : $end;
    my $pivots = $smc->get_swing_pivots;
    return unless $pivots && @$pivots;

    my $bull_c = $self->{theme}{swing_lbl_bull} // '#00C896';
    my $bear_c = $self->{theme}{swing_lbl_bear} // '#FF4560';

    for my $p (@$pivots) {
        next if $p->{index} > $limit;
        next if $p->{index} < $start || $p->{index} > $end;

        my $is_high = ( $p->{type} eq 'high' );
        my $is_bull = ( $p->{label} eq 'HH' || $p->{label} eq 'HL' );
        my $box_c   = $is_bull ? $bull_c : $bear_c;

        my $x     = $scale->index_to_center_x( $p->{index} );
        my $y     = $scale->value_to_y( $p->{price} );
        my $y_off = $is_high ? -12 : 12;
        my $cy    = $y + $y_off;

        $canvas->createRectangle(
            $x - 13, $cy - 7, $x + 13, $cy + 7,
            -fill    => $box_c,
            -outline => $box_c,
            -tags    => [ 'zz_b_all', 'mtf_lvl_label' ],
        );
        $canvas->createText(
            $x, $cy,
            -text   => $p->{label},
            -fill   => '#ffffff',
            -font   => 'Helvetica 7 bold',
            -anchor => 'center',
            -tags   => [ 'zz_b_all', 'mtf_lvl_label' ],
        );
    }
    return;
}

1;