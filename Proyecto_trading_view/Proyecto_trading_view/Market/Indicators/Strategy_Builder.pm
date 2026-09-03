package Market::Indicators::Strategy_Builder;

use strict;
use warnings;

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        st_period => $args{st_period} // 10,
        st_mult   => $args{st_mult}   // 3.0,
        ht_amplitude => $args{ht_amplitude} // 2,
        ht_period    => $args{ht_period}    // 2,
        rf_period => $args{rf_period} // 14,
        rf_mult   => $args{rf_mult}   // 1.5,
        sd_swing_length => $args{sd_swing_length} // 10,
        sd_history_keep => $args{sd_history_keep} // 20,
        sd_box_width    => $args{sd_box_width}    // 2.5,
        sd_atr_period   => $args{sd_atr_period}   // 50,

        _supertrend   => [],
        _halftrend    => [],
        _range_filter => [],
        _supply_zones => [],
        _demand_zones => [],

        _sd_atr_trs        => [],
        _sd_atr_seeded     => 0,
        _sd_atr_last_value => undef,
        _sd_atr_last_close => undef,

        a_length => $args{a_length} // 150,
        b_period => $args{b_period} // 2,

        _zigzag_a    => [],
        _a_last_leg  => undef,
        _a_prev_high => undef,
        _a_prev_low  => undef,

        _a_bar_index_high => undef,
        _a_price_high     => undef,
        _a_bar_index_low  => undef,
        _a_price_low      => undef,
        _a_is_bullish     => undef,

        _a_roll_max_dq => [],
        _a_roll_min_dq => [],
        _a_roll_max    => undef,
        _a_roll_min    => undef,

        _zigzag_b    => [],
        _b_last_leg  => undef,
        _b_prev_high => undef,
        _b_prev_low  => undef,

        ghost_length => $args{ghost_length} // 50,

        _ghost_pivots => [],
        _ghost_max         => undef,
        _ghost_max_index   => undef,
        _ghost_min         => undef,
        _ghost_min_index   => undef,
        _ghost_follow_max       => undef,
        _ghost_follow_max_index => undef,
        _ghost_follow_min       => undef,
        _ghost_follow_min_index => undef,
        _ghost_os  => undef,
        _ghost_px1 => undef,
        _ghost_py1 => undef,
        _ghost_forming_since => undef,
        _ghost_forming_index => undef,
        _ghost_forming_price => undef,
        _ghost_roll_max_dq => [],
        _ghost_roll_min_dq => [],

        # =====================================================================
        # BLOQUE "GHOST" (REEMPLAZADO) — "Pivot Points High Low & Missed
        # Reversal Levels [LuxAlgo]". Puerto EXTRAIDO de otro proyecto a
        # pedido explicito del usuario, para reemplazar el algoritmo que
        # alimenta el boton "Ghost" (antes basado en "Dynamic Swing
        # Anchored VWAP by Josafa" -- ver bloque _ghost_* arriba, que se
        # deja intacto y sin usar, por si se necesita a futuro).
        # =====================================================================
        pph_length => $args{pph_length} // 50,
        _pph_highs => [],
        _pph_lows  => [],
        _pph_last  => -1,
        _pph_max => undef,             _pph_min => undef,
        _pph_max_x1 => undef,          _pph_min_x1 => undef,
        _pph_follow_max => undef,      _pph_follow_min => undef,
        _pph_follow_max_x1 => undef,   _pph_follow_min_x1 => undef,
        _pph_os  => undef,
        _pph_py1 => undef,             _pph_px1 => undef,
        _pph_seeded_run => 0,
        _pph_labels       => [],
        _pph_zigzag       => [],
        _pph_ghost_levels => [],

        # =====================================================================
        # BLOQUE VWAP AUTO-ANCLADO AL PENULTIMO PIVOTE (NUEVO) — punto 4 del
        # enunciado del profesor. Al revisar "Ghosts_in_swings.txt" (el
        # codigo fuente Pine publicado como referencia), se confirmo que
        # NO es un indicador aparte: es la MISMA "Dynamic Swing Anchored
        # VWAP by Josafa" de la que ya extrajimos el Ghost -- el VWAP ahi
        # se ancla en "px1/py1", que es EXACTAMENTE el ultimo pivote
        # CONFIRMADO (lo que el profesor llama "penultimo pivot": penultimo
        # respecto al fantasma actual, que seria "el ultimo"). Ese dato ya
        # lo tenemos: es _pph_px1/_pph_py1 (ver bloque PPH arriba).
        #
        # A diferencia del Pine (que solo recalcula esto "if barstate.
        # islast", es decir, una vez en vivo), aca se calcula de forma
        # CAUSAL en cada vela (igual criterio que el resto de este
        # proyecto), para que funcione correctamente con Replay y para que
        # el extractor de caracteristicas pueda leer el valor en CUALQUIER
        # punto del historico, no solo en la ultima vela.
        #
        # _pph_vwap_series[$indice] guarda {vwap,band1_hi,band1_lo,
        # band2_hi,band2_lo} para cada vela desde que se ancla en
        # _pph_px1. Se reconstruye desde cero SOLO cuando el ancla cambia
        # (nuevo pivote confirmado -- evento poco frecuente); mientras el
        # ancla no cambia, se actualiza de forma incremental (O(1) por
        # vela), mismo criterio de rendimiento que el resto del proyecto.
        # =====================================================================
        _pph_vwap_anchor => undef,
        _pph_vwap_cumvol => 0,
        _pph_vwap_mean   => 0,
        _pph_vwap_m2     => 0,
        _pph_vwap_series => [],

        _atr_tr_sum     => 0,
        _atr_last_close => undef,
        _atr_last_value => undef,
        _atr_count      => 0,

        _st_upper      => undef,
        _st_lower      => undef,
        _st_trend      => 1,
        _st_prev_close => undef,

        _ht_trend     => 0,
        _ht_next      => 0,
        _ht_max_low   => undef,
        _ht_min_high  => undef,
        _ht_up        => undef,
        _ht_down      => undef,
        _ht_prev_high => undef,
        _ht_prev_low  => undef,

        _rf_ema   => undef,
        _rf_trend => 0,

        vwap_band1_mult => $args{vwap_band1_mult} // 1,
        vwap_band2_mult => $args{vwap_band2_mult} // 2,

        _vwap         => [],
        _vwap_anchor_year  => undef,
        _vwap_anchor_month => undef,
        _vwap_anchor_index => undef,
        _vwap_anchor_ts    => undef,

        avp_rows       => $args{avp_rows}       // 1000,
        avp_value_area => $args{avp_value_area} // 0.70,

        _avp              => undef,
        _avp_anchor_year  => undef,
        _avp_anchor_month => undef,
        _avp_anchor_day   => undef,
        _avp_anchor_ts    => undef,

        values => [],
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_supertrend}   = [];
    $self->{_halftrend}    = [];
    $self->{_range_filter} = [];
    $self->{_supply_zones} = [];
    $self->{_demand_zones} = [];
    $self->{_sd_atr_trs}        = [];
    $self->{_sd_atr_seeded}     = 0;
    $self->{_sd_atr_last_value} = undef;
    $self->{_sd_atr_last_close} = undef;
    $self->{_atr_tr_sum}     = 0;
    $self->{_atr_last_close} = undef;
    $self->{_atr_last_value} = undef;
    $self->{_atr_count}      = 0;
    $self->{_st_upper}       = undef;
    $self->{_st_lower}       = undef;
    $self->{_st_trend}       = 1;
    $self->{_st_prev_close}  = undef;
    $self->{_ht_trend}       = 0;
    $self->{_ht_next}        = 0;
    $self->{_ht_max_low}     = undef;
    $self->{_ht_min_high}    = undef;
    $self->{_ht_up}          = undef;
    $self->{_ht_down}        = undef;
    $self->{_ht_prev_high}   = undef;
    $self->{_ht_prev_low}    = undef;
    $self->{_rf_ema}         = undef;
    $self->{_rf_trend}       = 0;
    $self->{_zigzag_a}    = [];
    $self->{_a_last_leg}  = undef;
    $self->{_a_prev_high} = undef;
    $self->{_a_prev_low}  = undef;
    $self->{_a_bar_index_high} = undef;
    $self->{_a_price_high}     = undef;
    $self->{_a_bar_index_low}  = undef;
    $self->{_a_price_low}      = undef;
    $self->{_a_is_bullish}     = undef;
    $self->{_a_roll_max_dq} = [];
    $self->{_a_roll_min_dq} = [];
    $self->{_a_roll_max}    = undef;
    $self->{_a_roll_min}    = undef;
    $self->{_zigzag_b}    = [];
    $self->{_b_last_leg}  = undef;
    $self->{_b_prev_high} = undef;
    $self->{_b_prev_low}  = undef;
    $self->{_ghost_pivots} = [];
    $self->{_ghost_max}         = undef;
    $self->{_ghost_max_index}   = undef;
    $self->{_ghost_min}         = undef;
    $self->{_ghost_min_index}   = undef;
    $self->{_ghost_follow_max}       = undef;
    $self->{_ghost_follow_max_index} = undef;
    $self->{_ghost_follow_min}       = undef;
    $self->{_ghost_follow_min_index} = undef;
    $self->{_ghost_os}  = undef;
    $self->{_ghost_px1} = undef;
    $self->{_ghost_py1} = undef;
    $self->{_ghost_forming_since} = undef;
    $self->{_ghost_forming_index} = undef;
    $self->{_ghost_forming_price} = undef;
    $self->{_ghost_roll_max_dq} = [];
    $self->{_ghost_roll_min_dq} = [];

    $self->{_pph_highs} = [];
    $self->{_pph_lows}  = [];
    $self->{_pph_last}  = -1;
    $self->{_pph_max} = undef;             $self->{_pph_min} = undef;
    $self->{_pph_max_x1} = undef;          $self->{_pph_min_x1} = undef;
    $self->{_pph_follow_max} = undef;      $self->{_pph_follow_min} = undef;
    $self->{_pph_follow_max_x1} = undef;   $self->{_pph_follow_min_x1} = undef;
    $self->{_pph_os}  = undef;
    $self->{_pph_py1} = undef;             $self->{_pph_px1} = undef;
    $self->{_pph_seeded_run} = 0;
    $self->{_pph_labels}       = [];
    $self->{_pph_zigzag}       = [];
    $self->{_pph_ghost_levels} = [];

    # BLOQUE VWAP AUTO-ANCLADO (NUEVO): reset del estado.
    $self->{_pph_vwap_anchor} = undef;
    $self->{_pph_vwap_cumvol} = 0;
    $self->{_pph_vwap_mean}   = 0;
    $self->{_pph_vwap_m2}     = 0;
    $self->{_pph_vwap_series} = [];

    $self->{_vwap}         = [];
    $self->{_vwap_anchor_year}  = undef;
    $self->{_vwap_anchor_month} = undef;
    $self->{_vwap_anchor_index} = undef;
    $self->{_vwap_anchor_ts}    = undef;
    $self->{_avp}              = undef;
    $self->{_avp_anchor_year}  = undef;
    $self->{_avp_anchor_month} = undef;
    $self->{_avp_anchor_day}   = undef;
    $self->{_avp_anchor_ts}    = undef;
    $self->{values}          = [];
    return;
}

sub get_values       { return []; }
sub get_supertrend   { my ($self) = @_; return $self->{_supertrend};   }
sub get_halftrend    { my ($self) = @_; return $self->{_halftrend};    }
sub get_range_filter { my ($self) = @_; return $self->{_range_filter}; }
sub get_supply_zones { my ($self) = @_; return $self->{_supply_zones}; }
sub get_demand_zones { my ($self) = @_; return $self->{_demand_zones}; }
sub get_vwap         { my ($self) = @_; return $self->{_vwap};         }
sub get_avp          { my ($self) = @_; return $self->{_avp};          }
sub get_zigzag_a { my ($self) = @_; return $self->{_zigzag_a}; }
sub get_zigzag_b { my ($self) = @_; return $self->{_zigzag_b}; }

sub get_zigzag_a_pending { return undef; }

sub get_ghost_pivots { my ($self) = @_; return $self->{_ghost_pivots}; }

sub get_ghost_pending {
    my ($self) = @_;
    return undef unless @{ $self->{_ghost_pivots} };
    return undef unless defined $self->{_ghost_forming_index};
    my $last = $self->{_ghost_pivots}[-1];
    return {
        from_index => $last->{index}, from_price => $last->{price},
        to_index   => $self->{_ghost_forming_index}, to_price => $self->{_ghost_forming_price},
    };
}

# get_pph_values — BLOQUE "GHOST" (REEMPLAZADO). Punto de entrada unico
# que usa el overlay para dibujar el nuevo Ghost (Pivot Points HL & Missed
# Reversal Levels).
# get_pph_vwap_series / get_pph_vwap_anchor — BLOQUE VWAP AUTO-ANCLADO
# (NUEVO, punto 4 del enunciado). El overlay y el extractor de
# caracteristicas leen de aca: get_pph_vwap_series()->[$indice] da
# {vwap,band1_hi,band1_lo,band2_hi,band2_lo} en ese punto del historico
# (undef si todavia no hay ancla o no hay volumen acumulado ahi).
sub get_pph_vwap_series { my ($self) = @_; return $self->{_pph_vwap_series}; }
sub get_pph_vwap_anchor { my ($self) = @_; return $self->{_pph_vwap_anchor}; }

sub get_pph_values {
    my ($self) = @_;
    return {
        labels       => $self->{_pph_labels},
        zigzag       => $self->{_pph_zigzag},
        ghost_levels => $self->_pph_ghost_levels_chained,
        provisional  => $self->_pph_provisional,
        last_index   => $self->{_pph_last},
    };
}

sub update_at_index {
    my ( $self, $market_data, $i ) = @_;
    push @{ $self->{values} }, undef;

    my $c = $market_data->get_candle($i);
    return unless $c;

    my $atr = $self->_update_atr($c);
    $self->_update_supertrend( $c, $atr );
    $self->_update_halftrend(  $market_data, $c, $atr, $i );
    $self->_update_range_filter( $c, $atr );
    $self->_update_supply_demand( $market_data, $c, $i );
    $self->_update_zigzag_a( $market_data, $i );
    $self->_update_zigzag_b( $market_data, $i );
    $self->_update_ghost( $market_data, $i );

    # BLOQUE "GHOST" (REEMPLAZADO): el boton "Ghost" del overlay ahora lee
    # de get_pph_values (ver render_ghost/render_ghost_pph en el overlay),
    # asi que este calculo tiene que correr siempre, igual que el resto.
    $self->_update_pph( $market_data, $i );

    return;
}

sub _update_atr {
    my ( $self, $c ) = @_;
    my $period = $self->{st_period};
    my $tr;
    if ( defined $self->{_atr_last_close} ) {
        my $pc  = $self->{_atr_last_close};
        my $hl  = $c->{high} - $c->{low};
        my $hpc = abs( $c->{high} - $pc );
        my $lpc = abs( $c->{low}  - $pc );
        $tr = $hl; $tr = $hpc if $hpc > $tr; $tr = $lpc if $lpc > $tr;
    } else {
        $tr = $c->{high} - $c->{low};
    }
    $self->{_atr_count}++;
    my $atr;
    if ( $self->{_atr_count} < $period ) {
        $self->{_atr_tr_sum} += $tr;
        $atr = $self->{_atr_tr_sum} / $self->{_atr_count};
    } elsif ( $self->{_atr_count} == $period ) {
        $self->{_atr_tr_sum}    += $tr;
        $atr                     = $self->{_atr_tr_sum} / $period;
        $self->{_atr_last_value} = $atr;
    } else {
        $atr = ( $self->{_atr_last_value} * ( $period - 1 ) + $tr ) / $period;
        $self->{_atr_last_value} = $atr;
    }
    $self->{_atr_last_close} = $c->{close};
    return $atr // 0;
}

sub _update_supertrend {
    my ( $self, $c, $atr ) = @_;
    my $hl2  = ( $c->{high} + $c->{low} ) / 2;
    my $mult = $self->{st_mult};
    my $basic_upper = $hl2 + $mult * $atr;
    my $basic_lower = $hl2 - $mult * $atr;
    my $prev_upper = $self->{_st_upper} // $basic_upper;
    my $prev_lower = $self->{_st_lower} // $basic_lower;
    my $prev_close = $self->{_st_prev_close} // $c->{close};
    my $upper = ( $basic_upper < $prev_upper || $prev_close > $prev_upper ) ? $basic_upper : $prev_upper;
    my $lower = ( $basic_lower > $prev_lower || $prev_close < $prev_lower ) ? $basic_lower : $prev_lower;
    my $trend = $self->{_st_trend};
    if    ( $c->{close} > $prev_upper ) { $trend =  1; }
    elsif ( $c->{close} < $prev_lower ) { $trend = -1; }
    $self->{_st_upper}      = $upper;
    $self->{_st_lower}      = $lower;
    $self->{_st_trend}      = $trend;
    $self->{_st_prev_close} = $c->{close};
    push @{ $self->{_supertrend} }, { trend => $trend, line  => ( $trend == 1 ) ? $lower : $upper };
    return;
}

sub _update_halftrend {
    my ( $self, $market_data, $c, $atr, $i ) = @_;
    my $period  = $self->{ht_period};
    my $amp     = $self->{ht_amplitude};
    my $sma_h   = $self->_sma( $market_data, $i, $period, 'high' );
    my $sma_l   = $self->_sma( $market_data, $i, $period, 'low'  );
    my $dev     = $atr / 2 * $amp;
    my $prev_high = $self->{_ht_prev_high} // $c->{high};
    my $prev_low  = $self->{_ht_prev_low}  // $c->{low};

    if ( $self->{_ht_next} == 1 ) {
        my $baseline = $self->{_ht_max_low} // $sma_l;
        my $cand     = $sma_l > $baseline ? $sma_l : $baseline;
        $self->{_ht_max_low} = $cand;
        if ( $sma_h < $self->{_ht_max_low} && $c->{close} < $prev_low ) {
            $self->{_ht_trend} = 1; $self->{_ht_next} = 0;
            $self->{_ht_min_high} = $sma_h;
        }
    } else {
        my $baseline = $self->{_ht_min_high} // $sma_h;
        my $cand     = $sma_h < $baseline ? $sma_h : $baseline;
        $self->{_ht_min_high} = $cand;
        if ( $sma_l > $self->{_ht_min_high} && $c->{close} > $prev_high ) {
            $self->{_ht_trend} = 0; $self->{_ht_next} = 1;
            $self->{_ht_max_low} = $sma_l;
        }
    }
    if    ( $self->{_ht_trend} == 0 ) { $self->{_ht_up}   = $sma_l; }
    else                               { $self->{_ht_down} = $sma_h; }
    my $sp = ( $self->{_ht_trend} == 0 ) ? $self->{_ht_up} : $self->{_ht_down};
    push @{ $self->{_halftrend} }, {
        trend => $self->{_ht_trend}, signal_price => $sp,
        atr_hi => ( $sp // 0 ) + $dev, atr_lo => ( $sp // 0 ) - $dev,
    };
    $self->{_ht_prev_high} = $c->{high};
    $self->{_ht_prev_low}  = $c->{low};
    return;
}

sub _sma {
    my ( $self, $md, $i, $period, $field ) = @_;
    my ( $sum, $cnt ) = ( 0, 0 );
    for my $j ( ( $i - $period + 1 ) .. $i ) {
        next if $j < 0;
        my $cc = $md->get_candle($j);
        next unless $cc;
        $sum += $cc->{$field}; $cnt++;
    }
    return $cnt > 0 ? $sum / $cnt : 0;
}

sub _update_range_filter {
    my ( $self, $c, $atr ) = @_;
    my $k   = 2 / ( $self->{rf_period} + 1 );
    my $src = ( $c->{high} + $c->{low} + $c->{close} * 2 ) / 4;
    my $ema = defined $self->{_rf_ema} ? $self->{_rf_ema} * ( 1 - $k ) + $src * $k : $src;
    $self->{_rf_ema} = $ema;
    my $range = $atr * $self->{rf_mult};
    push @{ $self->{_range_filter} }, {
        filtered => $ema, hi_band => $ema + $range / 2, lo_band => $ema - $range / 2,
        trend => $c->{close} >= $ema ? 1 : -1,
    };
    return;
}

sub _update_supply_demand {
    my ( $self, $market_data, $c, $i ) = @_;
    my $atrpoi = $self->_sd_update_atr50($c);
    my $k = $self->{sd_swing_length};
    my ( $swing_high, $swing_low, $cand_idx ) = $self->_sd_check_pivot( $market_data, $i, $k );
    if ( defined $swing_high ) {
        $self->_sd_create_zone( 'supply', $swing_high, $cand_idx, $i, $atrpoi );
    }
    elsif ( defined $swing_low ) {
        $self->_sd_create_zone( 'demand', $swing_low, $cand_idx, $i, $atrpoi );
    }
    for my $z ( @{ $self->{_supply_zones} } ) {
        next if $z->{broken};
        if ( $c->{close} >= $z->{top} ) { $z->{broken} = 1; $z->{broken_index} = $i; }
    }
    for my $z ( @{ $self->{_demand_zones} } ) {
        next if $z->{broken};
        if ( $c->{close} <= $z->{bottom} ) { $z->{broken} = 1; $z->{broken_index} = $i; }
    }
    return;
}

sub _sd_check_pivot {
    my ( $self, $market_data, $i, $k ) = @_;
    return ( undef, undef, undef ) if $i < 2 * $k;
    my $cand_idx  = $i - $k;
    my $candidate = $market_data->get_candle($cand_idx);
    return ( undef, undef, undef ) unless $candidate;
    my $is_ph = 1;
    my $is_pl = 1;
    for my $j ( $cand_idx - $k .. $cand_idx + $k ) {
        next if $j == $cand_idx;
        my $c = $market_data->get_candle($j);
        next unless $c;
        $is_ph = 0 if $c->{high} >= $candidate->{high};
        $is_pl = 0 if $c->{low}  <= $candidate->{low};
    }
    my $ph = $is_ph ? $candidate->{high} : undef;
    my $pl = $is_pl ? $candidate->{low}  : undef;
    return ( $ph, $pl, $cand_idx );
}

sub _sd_create_zone {
    my ( $self, $kind, $level, $left_index, $i, $atrpoi ) = @_;
    return unless defined $atrpoi && defined $level;
    my $atr_buffer = $atrpoi * ( $self->{sd_box_width} / 10 );
    my ( $top, $bottom );
    if ( $kind eq 'supply' ) { $top = $level; $bottom = $top - $atr_buffer; }
    else { $bottom = $level; $top = $bottom + $atr_buffer; }
    my $poi = ( $top + $bottom ) / 2;
    my $arr = ( $kind eq 'supply' ) ? $self->{_supply_zones} : $self->{_demand_zones};
    return unless $self->_sd_check_overlap( $poi, $arr, $atrpoi );
    pop @$arr if @$arr >= $self->{sd_history_keep};
    unshift @$arr, {
        top => $top, bottom => $bottom, poi => $poi, left_index => $left_index,
        created_index => $i, broken => 0, broken_index => undef, label => uc($kind),
    };
    return;
}

sub _sd_check_overlap {
    my ( $self, $poi, $arr, $atrpoi ) = @_;
    my $atr_threshold = $atrpoi * 2;
    for my $z (@$arr) {
        next if $z->{broken};
        my $upper = $z->{poi} + $atr_threshold;
        my $lower = $z->{poi} - $atr_threshold;
        return 0 if $poi >= $lower && $poi <= $upper;
    }
    return 1;
}

sub _sd_update_atr50 {
    my ( $self, $c ) = @_;
    my $period = $self->{sd_atr_period};
    my ( $high, $low, $close ) = @{$c}{qw(high low close)};
    my $tr;
    if ( defined $self->{_sd_atr_last_close} ) {
        my $pc = $self->{_sd_atr_last_close};
        my $a  = $high - $low;
        my $b  = abs( $high - $pc );
        my $d  = abs( $low  - $pc );
        $tr = $a; $tr = $b if $b > $tr; $tr = $d if $d > $tr;
    } else {
        $tr = $high - $low;
    }
    $self->{_sd_atr_last_close} = $close;
    push @{ $self->{_sd_atr_trs} }, $tr;
    my $count = scalar @{ $self->{_sd_atr_trs} };
    my $atr;
    if ( !$self->{_sd_atr_seeded} ) {
        my $sum = 0;
        $sum += $_ for @{ $self->{_sd_atr_trs} };
        $atr = $sum / $count;
        $self->{_sd_atr_last_value} = $atr;
        $self->{_sd_atr_seeded} = 1 if $count >= $period;
    } else {
        $atr = ( $self->{_sd_atr_last_value} * ( $period - 1 ) + $tr ) / $period;
        $self->{_sd_atr_last_value} = $atr;
    }
    return $atr;
}

sub _rolling_extreme {
    my ( $self, $market_data, $i, $k ) = @_;
    return ( undef, undef ) if $i < 0;
    my $start = $i - $k + 1;
    $start = 0 if $start < 0;
    my ( $hi, $lo );
    for my $j ( $start .. $i ) {
        my $c = $market_data->get_candle($j);
        next unless $c;
        $hi = $c->{high} if !defined $hi || $c->{high} > $hi;
        $lo = $c->{low}  if !defined $lo || $c->{low}  < $lo;
    }
    return ( $hi, $lo );
}

sub _roll_push_max {
    my ( $self, $dq_ref, $idx, $value, $k ) = @_;
    pop   @$dq_ref while @$dq_ref && $dq_ref->[-1][1] <= $value;
    push  @$dq_ref, [ $idx, $value ];
    my $window_left = $idx - $k + 1;
    shift @$dq_ref while @$dq_ref && $dq_ref->[0][0] < $window_left;
    return $dq_ref->[0][1];
}

sub _roll_push_min {
    my ( $self, $dq_ref, $idx, $value, $k ) = @_;
    pop   @$dq_ref while @$dq_ref && $dq_ref->[-1][1] >= $value;
    push  @$dq_ref, [ $idx, $value ];
    my $window_left = $idx - $k + 1;
    shift @$dq_ref while @$dq_ref && $dq_ref->[0][0] < $window_left;
    return $dq_ref->[0][1];
}

sub _update_zigzag_a {
    my ( $self, $market_data, $i ) = @_;

    my $k   = $self->{a_length};
    my $cur = $market_data->get_candle($i);
    return unless $cur;

    my $swing_high_prev = $self->{_a_roll_max};
    my $swing_low_prev  = $self->{_a_roll_min};

    my $swing_high = $self->_roll_push_max( $self->{_a_roll_max_dq}, $i, $cur->{high}, $k );
    my $swing_low  = $self->_roll_push_min( $self->{_a_roll_min_dq}, $i, $cur->{low},  $k );
    $self->{_a_roll_max} = $swing_high;
    $self->{_a_roll_min} = $swing_low;

    return if $i < 1;
    return unless defined $swing_high      && defined $swing_low
               && defined $swing_high_prev && defined $swing_low_prev;

    my $prev = $market_data->get_candle( $i - 1 );
    return unless $prev;

    my $prev_bullish = $self->{_a_is_bullish};

    $self->{_a_is_bullish} = 1 if $cur->{high} == $swing_high;
    $self->{_a_is_bullish} = 0 if $cur->{low}  == $swing_low;

    my $is_bullish = $self->{_a_is_bullish};

    my $high_just_confirmed = 0;
    my $low_just_confirmed  = 0;

    if ( $prev->{high} == $swing_high_prev && $cur->{high} < $swing_high ) {
        $self->{_a_bar_index_high} = $i - 1;
        $self->{_a_price_high}     = $prev->{low};
        $high_just_confirmed = 1;
    }
    if ( $prev->{low} == $swing_low_prev && $cur->{low} > $swing_low ) {
        $self->{_a_bar_index_low} = $i - 1;
        $self->{_a_price_low}     = $prev->{low};
        $low_just_confirmed = 1;
    }

    return unless defined $is_bullish;

    if ( defined $prev_bullish && $is_bullish != $prev_bullish && $is_bullish ) {
        if ( defined $self->{_a_bar_index_low} && defined $self->{_a_price_low} ) {
            $self->_confirm_zigzag( $self->{_zigzag_a}, 'a', 'low',
                $self->{_a_bar_index_low}, $self->{_a_price_low}, 1 );
        }
    }

    if ( $is_bullish && $high_just_confirmed ) {
        $self->_confirm_zigzag( $self->{_zigzag_a}, 'a', 'high',
            $self->{_a_bar_index_high}, $self->{_a_price_high}, 1 );
    }

    if ( defined $prev_bullish && $is_bullish != $prev_bullish && !$is_bullish ) {
        if ( defined $self->{_a_bar_index_high} && defined $self->{_a_price_high} ) {
            $self->_confirm_zigzag( $self->{_zigzag_a}, 'a', 'high',
                $self->{_a_bar_index_high}, $self->{_a_price_high}, 1 );
        }
    }

    if ( !$is_bullish && $low_just_confirmed ) {
        $self->_confirm_zigzag( $self->{_zigzag_a}, 'a', 'low',
            $self->{_a_bar_index_low}, $self->{_a_price_low}, 1 );
    }

    return;
}

sub _update_zigzag_b {
    my ( $self, $market_data, $i ) = @_;
    my $p = $self->{b_period};
    return if $i < 2 * $p;
    my $cand_idx  = $i - $p;
    my $candidate = $market_data->get_candle($cand_idx);
    return unless $candidate;
    my ( $hi, $lo );
    for my $j ( $cand_idx - $p .. $cand_idx + $p ) {
        my $c = $market_data->get_candle($j);
        next unless $c;
        $hi = $c->{high} if !defined $hi || $c->{high} > $hi;
        $lo = $c->{low}  if !defined $lo || $c->{low}  < $lo;
    }
    return unless defined $hi;
    if ( $candidate->{high} == $hi ) {
        $self->_confirm_zigzag( $self->{_zigzag_b}, 'b', 'high', $cand_idx, $candidate->{high} );
    }
    if ( $candidate->{low} == $lo ) {
        $self->_confirm_zigzag( $self->{_zigzag_b}, 'b', 'low', $cand_idx, $candidate->{low} );
    }
    return;
}

sub _update_ghost {
    my ( $self, $market_data, $i ) = @_;
    my $p   = $self->{ghost_length};
    my $win = 2 * $p + 1;

    my $cur = $market_data->get_candle($i);
    return unless $cur;

    my $hi = $self->_roll_push_max( $self->{_ghost_roll_max_dq}, $i, $cur->{high}, $win );
    my $lo = $self->_roll_push_min( $self->{_ghost_roll_min_dq}, $i, $cur->{low},  $win );

    return if $i < 2 * $p;

    my $cand_idx  = $i - $p;
    my $candidate = $market_data->get_candle($cand_idx);
    return unless $candidate;

    return unless defined $hi;
    if ( $candidate->{high} == $hi ) {
        $self->_confirm_zigzag( $self->{_ghost_pivots}, 'ghost', 'high', $cand_idx, $candidate->{high} );
    }
    if ( $candidate->{low} == $lo ) {
        $self->_confirm_zigzag( $self->{_ghost_pivots}, 'ghost', 'low', $cand_idx, $candidate->{low} );
    }

    $self->_update_forming_ghost( $market_data, $i );
    return;
}

sub _update_forming_ghost {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return unless $c;
    my $arr = $self->{_ghost_pivots};
    return unless @$arr;
    my $last       = $arr->[-1];
    my $expect     = ( $last->{type} eq 'high' ) ? 'low' : 'high';
    my $last_index = $last->{index};
    if ( !defined $self->{_ghost_forming_since} || $self->{_ghost_forming_since} != $last_index ) {
        $self->{_ghost_forming_since} = $last_index;
        $self->{_ghost_forming_index} = $last_index;
        $self->{_ghost_forming_price} = $last->{price};
    }
    if ( $expect eq 'high' ) {
        if ( $c->{high} > $self->{_ghost_forming_price} ) {
            $self->{_ghost_forming_price} = $c->{high};
            $self->{_ghost_forming_index} = $i;
        }
    } else {
        if ( $c->{low} < $self->{_ghost_forming_price} ) {
            $self->{_ghost_forming_price} = $c->{low};
            $self->{_ghost_forming_index} = $i;
        }
    }
    return;
}

# =============================================================================
# BLOQUE "GHOST" (REEMPLAZADO) — "Pivot Points High Low & Missed Reversal
# Levels [LuxAlgo]". Puerto EXTRAIDO de otro proyecto Perl/Tk del usuario,
# adaptado a las convenciones de ESTE proyecto (update_at_index causal,
# get_candle devuelve hashref en vez de arrayref).
# =============================================================================
sub _update_pph {
    my ( $self, $market_data, $index ) = @_;
    my $c = $market_data->get_candle($index);
    return unless $c;

    $self->{_pph_highs}[$index] = $c->{high};
    $self->{_pph_lows}[$index]  = $c->{low};
    $self->{_pph_last}          = $index;

    my $len = $self->{pph_length};
    my $Lh  = $index - $len;
    return if $Lh < 0;
    my $hL = $self->{_pph_highs}[$Lh];
    my $lL = $self->{_pph_lows}[$Lh];
    return unless defined $hL && defined $lL;

    unless ( $self->{_pph_seeded_run} ) {
        $self->{_pph_max} = $hL; $self->{_pph_min} = $lL;
        $self->{_pph_follow_max} = $hL; $self->{_pph_follow_min} = $lL;
        $self->{_pph_max_x1} = $Lh; $self->{_pph_min_x1} = $Lh;
        $self->{_pph_follow_max_x1} = $Lh; $self->{_pph_follow_min_x1} = $Lh;
        $self->{_pph_seeded_run} = 1;
    }

    my $max_prev  = $self->{_pph_max};
    my $min_prev  = $self->{_pph_min};
    my $fmax_prev = $self->{_pph_follow_max};
    my $fmin_prev = $self->{_pph_follow_min};

    $self->{_pph_max} = $hL if $hL > $self->{_pph_max};
    $self->{_pph_min} = $lL if $lL < $self->{_pph_min};
    $self->{_pph_follow_max} = $hL if $hL > $self->{_pph_follow_max};
    $self->{_pph_follow_min} = $lL if $lL < $self->{_pph_follow_min};

    if ( $self->{_pph_max} > $max_prev ) { $self->{_pph_max_x1} = $Lh; $self->{_pph_follow_min} = $lL; }
    if ( $self->{_pph_min} < $min_prev ) { $self->{_pph_min_x1} = $Lh; $self->{_pph_follow_max} = $hL; }
    if ( $self->{_pph_follow_min} < $fmin_prev ) { $self->{_pph_follow_min_x1} = $Lh; }
    if ( $self->{_pph_follow_max} > $fmax_prev ) { $self->{_pph_follow_max_x1} = $Lh; }

    my $ph = $self->_pph_is_pivot_high($Lh) ? $hL : undef;
    my $pl = $self->_pph_is_pivot_low($Lh)  ? $lL : undef;

    my $os_prev = $self->{_pph_os};

    $self->_pph_on_pivot_high( $Lh, $ph, $os_prev ) if defined $ph;
    $self->_pph_on_pivot_low(  $Lh, $pl, $os_prev ) if defined $pl;

    # BLOQUE VWAP AUTO-ANCLADO (NUEVO): se actualiza en CADA vela (no solo
    # cuando hay pivote nuevo), usando como ancla el pivote _pph_px1 mas
    # reciente disponible en este punto -- ver _update_pph_vwap.
    $self->_update_pph_vwap( $market_data, $index );

    return;
}

sub _pph_is_pivot_high {
    my ( $self, $p ) = @_;
    my $len = $self->{pph_length};
    return 0 if $p - $len < 0;
    my $hp = $self->{_pph_highs}[$p];
    return 0 unless defined $hp;
    for my $j ( $p - $len .. $p + $len ) {
        next if $j == $p;
        my $hj = $self->{_pph_highs}[$j];
        return 0 unless defined $hj;
        return 0 if $hj >= $hp;
    }
    return 1;
}

sub _pph_is_pivot_low {
    my ( $self, $p ) = @_;
    my $len = $self->{pph_length};
    return 0 if $p - $len < 0;
    my $lp = $self->{_pph_lows}[$p];
    return 0 unless defined $lp;
    for my $j ( $p - $len .. $p + $len ) {
        next if $j == $p;
        my $lj = $self->{_pph_lows}[$j];
        return 0 unless defined $lj;
        return 0 if $lj <= $lp;
    }
    return 1;
}

sub _pph_add_label {
    my ( $self, $index, $price, $glyph, $dir, $color_key, $missed ) = @_;
    return unless defined $index && defined $price;
    push @{ $self->{_pph_labels} }, {
        index => $index, price => $price, glyph => $glyph, dir => $dir,
        color_key => $color_key, missed => $missed ? 1 : 0,
    };
    return;
}

sub _pph_add_zigzag {
    my ( $self, $x1, $y1, $x2, $y2, $color_key, $style ) = @_;
    return unless defined $x1 && defined $y1 && defined $x2 && defined $y2;
    push @{ $self->{_pph_zigzag} }, {
        from_index => $x1, from_price => $y1, to_index => $x2, to_price => $y2,
        color_key => $color_key, style => $style,
    };
    return;
}

sub _pph_add_ghost_level {
    my ( $self, $index, $price, $color_key ) = @_;
    return unless defined $index && defined $price;
    push @{ $self->{_pph_ghost_levels} }, { index => $index, price => $price, color_key => $color_key };
    return;
}

sub _pph_on_pivot_high {
    my ( $self, $Lh, $ph, $os_prev ) = @_;

    if ( defined $os_prev && $os_prev == 1 ) {
        $self->_pph_add_label( $self->{_pph_min_x1}, $self->{_pph_min}, 'ghost', 'up', 'miss_pl', 1 );
        $self->_pph_add_zigzag( $self->{_pph_px1}, $self->{_pph_py1}, $self->{_pph_min_x1}, $self->{_pph_min}, 'miss_ph', 'dashed' );
        $self->{_pph_px1} = $self->{_pph_min_x1}; $self->{_pph_py1} = $self->{_pph_min};
        $self->_pph_add_ghost_level( $self->{_pph_px1}, $self->{_pph_py1}, 'reg_pl' );
    }
    elsif ( defined $self->{_pph_max} && $ph < $self->{_pph_max} ) {
        $self->_pph_add_label( $self->{_pph_max_x1}, $self->{_pph_max}, 'ghost', 'down', 'miss_ph', 1 );
        $self->_pph_add_label( $self->{_pph_follow_min_x1}, $self->{_pph_follow_min}, 'ghost', 'up', 'miss_pl', 1 );
        $self->_pph_add_zigzag( $self->{_pph_px1}, $self->{_pph_py1}, $self->{_pph_max_x1}, $self->{_pph_max}, 'miss_pl', 'dashed' );
        $self->{_pph_px1} = $self->{_pph_max_x1}; $self->{_pph_py1} = $self->{_pph_max};
        $self->_pph_add_ghost_level( $self->{_pph_px1}, $self->{_pph_py1}, 'reg_ph' );
        $self->_pph_add_zigzag( $self->{_pph_px1}, $self->{_pph_py1}, $self->{_pph_follow_min_x1}, $self->{_pph_follow_min}, 'miss_ph', 'dashed' );
        $self->{_pph_px1} = $self->{_pph_follow_min_x1}; $self->{_pph_py1} = $self->{_pph_follow_min};
        $self->_pph_add_ghost_level( $self->{_pph_px1}, $self->{_pph_py1}, 'reg_pl' );
    }

    $self->_pph_add_label( $Lh, $ph, 'reg_high', 'down', 'reg_ph', 0 );
    if ( defined $self->{_pph_px1} ) {
        my $style = ( ( defined $self->{_pph_max} && $ph < $self->{_pph_max} )
                     || ( defined $os_prev && $os_prev == 1 ) ) ? 'dashed' : 'solid';
        $self->_pph_add_zigzag( $self->{_pph_px1}, $self->{_pph_py1}, $Lh, $ph, 'miss_pl', $style );
    }

    $self->{_pph_py1} = $ph; $self->{_pph_px1} = $Lh; $self->{_pph_os} = 1;
    $self->{_pph_max} = $ph; $self->{_pph_min} = $ph;
    return;
}

sub _pph_on_pivot_low {
    my ( $self, $Lh, $pl, $os_prev ) = @_;

    if ( defined $os_prev && $os_prev == 0 ) {
        $self->_pph_add_label( $self->{_pph_max_x1}, $self->{_pph_max}, 'ghost', 'down', 'miss_ph', 1 );
        $self->_pph_add_zigzag( $self->{_pph_px1}, $self->{_pph_py1}, $self->{_pph_max_x1}, $self->{_pph_max}, 'miss_pl', 'dashed' );
        $self->{_pph_px1} = $self->{_pph_max_x1}; $self->{_pph_py1} = $self->{_pph_max};
        $self->_pph_add_ghost_level( $self->{_pph_px1}, $self->{_pph_py1}, 'reg_ph' );
    }
    elsif ( defined $self->{_pph_min} && $pl > $self->{_pph_min} ) {
        $self->_pph_add_label( $self->{_pph_follow_max_x1}, $self->{_pph_follow_max}, 'ghost', 'down', 'miss_ph', 1 );
        $self->_pph_add_label( $self->{_pph_min_x1}, $self->{_pph_min}, 'ghost', 'up', 'miss_pl', 1 );
        $self->_pph_add_zigzag( $self->{_pph_px1}, $self->{_pph_py1}, $self->{_pph_min_x1}, $self->{_pph_min}, 'miss_ph', 'dashed' );
        $self->{_pph_px1} = $self->{_pph_min_x1}; $self->{_pph_py1} = $self->{_pph_min};
        $self->_pph_add_ghost_level( $self->{_pph_px1}, $self->{_pph_py1}, 'reg_pl' );
        $self->_pph_add_zigzag( $self->{_pph_px1}, $self->{_pph_py1}, $self->{_pph_follow_max_x1}, $self->{_pph_follow_max}, 'miss_pl', 'dashed' );
        $self->{_pph_px1} = $self->{_pph_follow_max_x1}; $self->{_pph_py1} = $self->{_pph_follow_max};
        $self->_pph_add_ghost_level( $self->{_pph_px1}, $self->{_pph_py1}, 'reg_ph' );
    }

    $self->_pph_add_label( $Lh, $pl, 'reg_low', 'up', 'reg_pl', 0 );
    if ( defined $self->{_pph_px1} ) {
        my $style = ( ( defined $self->{_pph_min} && $pl > $self->{_pph_min} )
                     || ( defined $os_prev && $os_prev == 0 ) ) ? 'dashed' : 'solid';
        $self->_pph_add_zigzag( $self->{_pph_px1}, $self->{_pph_py1}, $Lh, $pl, 'miss_ph', $style );
    }

    $self->{_pph_py1} = $pl; $self->{_pph_px1} = $Lh; $self->{_pph_os} = 0;
    $self->{_pph_max} = $pl; $self->{_pph_min} = $pl;
    return;
}

# =============================================================================
# _update_pph_vwap / _pph_vwap_accumulate — BLOQUE VWAP AUTO-ANCLADO AL
# PENULTIMO PIVOTE (NUEVO, punto 4 del enunciado). Formula identica a la
# ya usada en el VWAP manual de este archivo (_compute_vwap_core, ver mas
# abajo): media y varianza ponderadas por volumen (algoritmo de Welford),
# fuente HLC3. La UNICA diferencia real es el ancla: en vez de que el
# usuario la elija con un clic, se recalcula sola cada vez que
# _pph_px1 (el ultimo pivote CONFIRMADO del Ghost) cambia.
#
# [RENDIMIENTO] Reconstruir TODO desde el ancla en cada vela seria
# O(n*k) igual que los problemas de rendimiento ya resueltos en otras
# partes de este archivo. En vez de eso: si el ancla es la MISMA que en
# la vela anterior, se hace una actualizacion incremental O(1) (se suma
# solo la vela actual a los acumuladores ya guardados); la reconstruccion
# completa SOLO ocurre las veces que cambia el ancla (un evento poco
# frecuente -- una vez por cada pivote nuevo, no por cada vela).
# =============================================================================
sub _update_pph_vwap {
    my ( $self, $market_data, $index ) = @_;
    my $anchor = $self->{_pph_px1};
    return unless defined $anchor;   # todavia no hay ningun pivote confirmado

    if ( !defined $self->{_pph_vwap_anchor} || $self->{_pph_vwap_anchor} != $anchor ) {
        # Ancla nueva (pivote recien confirmado): reconstruir desde cero,
        # UNA sola vez, desde el ancla hasta la vela actual.
        $self->{_pph_vwap_anchor} = $anchor;
        $self->{_pph_vwap_cumvol} = 0;
        $self->{_pph_vwap_mean}   = 0;
        $self->{_pph_vwap_m2}     = 0;
        for my $j ( $anchor .. $index ) {
            $self->_pph_vwap_accumulate( $market_data, $j );
        }
    } else {
        # Ancla sin cambios: solo sumar la vela actual (incremental).
        $self->_pph_vwap_accumulate( $market_data, $index );
    }
    return;
}

sub _pph_vwap_accumulate {
    my ( $self, $market_data, $j ) = @_;
    my $c = $market_data->get_candle($j);
    return unless $c;

    my $typical = ( $c->{high} + $c->{low} + $c->{close} ) / 3;   # HLC3
    my $vol     = $c->{volume} // 0;
    $vol = 0 if $vol < 0;

    if ( $vol > 0 ) {
        $self->{_pph_vwap_cumvol} += $vol;
        my $delta = $typical - $self->{_pph_vwap_mean};
        $self->{_pph_vwap_mean} += ( $vol / $self->{_pph_vwap_cumvol} ) * $delta;
        my $delta2 = $typical - $self->{_pph_vwap_mean};
        $self->{_pph_vwap_m2} += $vol * $delta * $delta2;
    }

    if ( $self->{_pph_vwap_cumvol} > 0 ) {
        my $variance = $self->{_pph_vwap_m2} / $self->{_pph_vwap_cumvol};
        $variance = 0 if $variance < 0;
        my $stdev = sqrt($variance);
        $self->{_pph_vwap_series}[$j] = {
            vwap     => $self->{_pph_vwap_mean},
            band1_hi => $self->{_pph_vwap_mean} + $stdev,
            band1_lo => $self->{_pph_vwap_mean} - $stdev,
            band2_hi => $self->{_pph_vwap_mean} + 2 * $stdev,
            band2_lo => $self->{_pph_vwap_mean} - 2 * $stdev,
        };
    } else {
        $self->{_pph_vwap_series}[$j] = undef;
    }
    return;
}

sub _pph_provisional {
    my ($self) = @_;
    my $n = $self->{_pph_last};
    return undef unless defined $n && $n >= 0;
    return undef unless defined $self->{_pph_px1} && defined $self->{_pph_os};
    my $from = $self->{_pph_px1};
    return undef if $from > $n;

    my ( $best_x, $best_y );
    my ( $dir, $ghost_key, $line_key );
    if ( $self->{_pph_os} == 1 ) {
        for my $i ( $from .. $n ) {
            my $v = $self->{_pph_lows}[$i];
            next unless defined $v;
            if ( !defined $best_y || $v < $best_y ) { $best_y = $v; $best_x = $i; }
        }
        ( $dir, $ghost_key, $line_key ) = ( 'up', 'miss_pl', 'miss_ph' );
    } else {
        for my $i ( $from .. $n ) {
            my $v = $self->{_pph_highs}[$i];
            next unless defined $v;
            if ( !defined $best_y || $v > $best_y ) { $best_y = $v; $best_x = $i; }
        }
        ( $dir, $ghost_key, $line_key ) = ( 'down', 'miss_ph', 'miss_pl' );
    }
    return undef unless defined $best_x;
    return {
        from_index => $self->{_pph_px1}, from_price => $self->{_pph_py1},
        index      => $best_x,           price      => $best_y,
        dir        => $dir, ghost_key => $ghost_key, line_key => $line_key,
        last_index => $n,
    };
}

sub _pph_ghost_levels_chained {
    my ($self) = @_;
    my @lv = @{ $self->{_pph_ghost_levels} };
    my @out;
    for my $k ( 0 .. $#lv ) {
        my $to = ( $k < $#lv ) ? $lv[ $k + 1 ]{index} : $self->{_pph_last};
        push @out, {
            index => $lv[$k]{index}, price => $lv[$k]{price},
            color_key => $lv[$k]{color_key}, to_index => $to,
        };
    }
    return \@out;
}

use constant DATA_TZ_OFFSET_SEC => 5 * 3600;

sub _vwap_month_bucket {
    my ($ts) = @_;
    my @gmt = gmtime( $ts - DATA_TZ_OFFSET_SEC );
    return ( $gmt[5] + 1900 ) * 12 + $gmt[4];
}

sub recompute_vwap {
    my ( $self, $market_data, $year, $month ) = @_;
    return unless $market_data;

    my $last_idx = $market_data->last_index;
    if ( $last_idx < 0 ) {
        $self->{_vwap} = [];
        return;
    }

    my $anchor_idx = 0;
    if ( defined $year && defined $month ) {
        my $target_bucket = $year * 12 + ( $month - 1 );
        my $found;
        for my $i ( 0 .. $last_idx ) {
            my $c = $market_data->get_candle($i);
            next unless $c;
            if ( _vwap_month_bucket( $c->{ts} ) == $target_bucket ) {
                $found = $i;
                last;
            }
        }
        $anchor_idx = $found if defined $found;
    }

    $self->{_vwap}              = $self->_compute_vwap_core( $market_data, $anchor_idx, $last_idx );
    $self->{_vwap_anchor_year}  = $year;
    $self->{_vwap_anchor_month} = $month;
    return;
}

sub recompute_vwap_from_index {
    my ( $self, $market_data, $anchor_idx ) = @_;
    return unless $market_data;

    my $last_idx = $market_data->last_index;
    if ( $last_idx < 0 ) {
        $self->{_vwap} = [];
        return;
    }

    $anchor_idx = 0                if !defined $anchor_idx || $anchor_idx < 0;
    $anchor_idx = $last_idx        if $anchor_idx > $last_idx;

    $self->{_vwap} = $self->_compute_vwap_core( $market_data, $anchor_idx, $last_idx );

    my $anchor_c = $market_data->get_candle($anchor_idx);
    $self->{_vwap_anchor_ts}    = $anchor_c ? $anchor_c->{ts} : undef;
    $self->{_vwap_anchor_index} = $anchor_idx;
    $self->{_vwap_anchor_year}  = undef;
    $self->{_vwap_anchor_month} = undef;
    return;
}

sub _compute_vwap_core {
    my ( $self, $market_data, $anchor_idx, $last_idx ) = @_;

    my @vwap;
    push @vwap, undef for ( 1 .. $anchor_idx );

    my ( $cum_vol, $mean, $m2 ) = ( 0, 0, 0 );
    my $m1_mult = $self->{vwap_band1_mult};
    my $m2_mult = $self->{vwap_band2_mult};

    for my $i ( $anchor_idx .. $last_idx ) {
        my $c = $market_data->get_candle($i);
        if ( !$c ) {
            push @vwap, undef;
            next;
        }

        my $typical = ( $c->{high} + $c->{low} + $c->{close} ) / 3;
        my $vol     = $c->{volume} // 0;
        $vol = 0 if $vol < 0;

        if ( $vol > 0 ) {
            $cum_vol += $vol;
            my $delta = $typical - $mean;
            $mean += ( $vol / $cum_vol ) * $delta;
            my $delta2 = $typical - $mean;
            $m2 += $vol * $delta * $delta2;
        }

        if ( $cum_vol > 0 ) {
            my $variance = $m2 / $cum_vol;
            $variance = 0 if $variance < 0;
            my $stdev = sqrt($variance);

            push @vwap, {
                vwap     => $mean,
                band1_hi => $mean + $m1_mult * $stdev,
                band1_lo => $mean - $m1_mult * $stdev,
                band2_hi => $mean + $m2_mult * $stdev,
                band2_lo => $mean - $m2_mult * $stdev,
            };
        } else {
            push @vwap, undef;
        }
    }

    return \@vwap;
}

sub get_vwap_anchor {
    my ($self) = @_;
    return ( $self->{_vwap_anchor_year}, $self->{_vwap_anchor_month} );
}

sub get_vwap_anchor_index { my ($self) = @_; return $self->{_vwap_anchor_index}; }
sub get_vwap_anchor_ts    { my ($self) = @_; return $self->{_vwap_anchor_ts};    }

sub _avp_day_bucket {
    my ($ts) = @_;
    my @gmt = gmtime( $ts - DATA_TZ_OFFSET_SEC );
    return sprintf( '%04d-%02d-%02d', $gmt[5] + 1900, $gmt[4] + 1, $gmt[3] );
}

sub recompute_avp {
    my ( $self, $market_data, $year, $month, $day ) = @_;
    return unless $market_data;

    my $last_idx = $market_data->last_index;
    if ( $last_idx < 0 ) {
        $self->{_avp} = undef;
        return;
    }

    my $anchor_idx = 0;
    if ( defined $year && defined $month && defined $day ) {
        my $target = sprintf( '%04d-%02d-%02d', $year, $month, $day );
        my $found;
        for my $i ( 0 .. $last_idx ) {
            my $c = $market_data->get_candle($i);
            next unless $c;
            if ( _avp_day_bucket( $c->{ts} ) eq $target ) {
                $found = $i;
                last;
            }
        }
        $anchor_idx = $found if defined $found;
    }

    $self->{_avp} = $self->_compute_avp_core( $market_data, $anchor_idx, $last_idx );
    if ( $self->{_avp} ) {
        $self->{_avp_anchor_year}  = $year;
        $self->{_avp_anchor_month} = $month;
        $self->{_avp_anchor_day}   = $day;
    }
    return;
}

sub recompute_avp_from_index {
    my ( $self, $market_data, $anchor_idx ) = @_;
    return unless $market_data;

    my $last_idx = $market_data->last_index;
    if ( $last_idx < 0 ) {
        $self->{_avp} = undef;
        return;
    }

    $anchor_idx = 0         if !defined $anchor_idx || $anchor_idx < 0;
    $anchor_idx = $last_idx if $anchor_idx > $last_idx;

    $self->{_avp} = $self->_compute_avp_core( $market_data, $anchor_idx, $last_idx );

    my $anchor_c = $market_data->get_candle($anchor_idx);
    $self->{_avp_anchor_ts} = $anchor_c ? $anchor_c->{ts} : undef;
    $self->{_avp_anchor_year}  = undef;
    $self->{_avp_anchor_month} = undef;
    $self->{_avp_anchor_day}   = undef;
    return;
}

sub _compute_avp_core {
    my ( $self, $market_data, $anchor_idx, $last_idx ) = @_;

    my ( $price_min, $price_max );
    for my $i ( $anchor_idx .. $last_idx ) {
        my $c = $market_data->get_candle($i);
        next unless $c;
        $price_min = $c->{low}  if !defined $price_min || $c->{low}  < $price_min;
        $price_max = $c->{high} if !defined $price_max || $c->{high} > $price_max;
    }
    return undef if !defined $price_min || $price_max <= $price_min;

    my $rows = $self->{avp_rows};
    $rows = 10 if $rows < 10;
    my $bin_size = ( $price_max - $price_min ) / $rows;

    my @bins;
    for my $r ( 0 .. $rows - 1 ) {
        push @bins, {
            price_lo => $price_min + $r * $bin_size,
            price_hi => $price_min + ( $r + 1 ) * $bin_size,
            up_vol   => 0,
            down_vol => 0,
        };
    }

    for my $i ( $anchor_idx .. $last_idx ) {
        my $c = $market_data->get_candle($i);
        next unless $c;
        my $vol = $c->{volume} // 0;
        next if $vol <= 0;

        my $is_up = ( $c->{close} >= $c->{open} );

        my $lo_bin = int( ( $c->{low}  - $price_min ) / $bin_size );
        my $hi_bin = int( ( $c->{high} - $price_min ) / $bin_size );
        $lo_bin = 0          if $lo_bin < 0;
        $lo_bin = $rows - 1  if $lo_bin > $rows - 1;
        $hi_bin = 0          if $hi_bin < 0;
        $hi_bin = $rows - 1  if $hi_bin > $rows - 1;
        ( $lo_bin, $hi_bin ) = ( $hi_bin, $lo_bin ) if $lo_bin > $hi_bin;

        my $span        = $hi_bin - $lo_bin + 1;
        my $vol_per_bin = $vol / $span;

        for my $b ( $lo_bin .. $hi_bin ) {
            if ($is_up) { $bins[$b]{up_vol}   += $vol_per_bin; }
            else        { $bins[$b]{down_vol} += $vol_per_bin; }
        }
    }

    my $poc_idx   = 0;
    my $poc_vol   = -1;
    my $total_vol = 0;
    for my $b ( 0 .. $#bins ) {
        my $v = $bins[$b]{up_vol} + $bins[$b]{down_vol};
        $total_vol += $v;
        if ( $v > $poc_vol ) { $poc_vol = $v; $poc_idx = $b; }
    }

    my $target_vol = $total_vol * $self->{avp_value_area};
    my ( $va_lo, $va_hi ) = ( $poc_idx, $poc_idx );
    my $acc_vol = $bins[$poc_idx]{up_vol} + $bins[$poc_idx]{down_vol};

    while ( $acc_vol < $target_vol && ( $va_lo > 0 || $va_hi < $#bins ) ) {
        my $vol_below = ( $va_lo > 0 )      ? ( $bins[ $va_lo - 1 ]{up_vol} + $bins[ $va_lo - 1 ]{down_vol} ) : -1;
        my $vol_above = ( $va_hi < $#bins ) ? ( $bins[ $va_hi + 1 ]{up_vol} + $bins[ $va_hi + 1 ]{down_vol} ) : -1;

        if ( $vol_above >= $vol_below ) {
            $va_hi++;
            $acc_vol += $vol_above;
        } else {
            $va_lo--;
            $acc_vol += $vol_below;
        }
    }

    return {
        bins         => \@bins,
        poc          => ( $bins[$poc_idx]{price_lo} + $bins[$poc_idx]{price_hi} ) / 2,
        vah          => $bins[$va_hi]{price_hi},
        val          => $bins[$va_lo]{price_lo},
        max_bin_vol  => $poc_vol,
        anchor_index => $anchor_idx,
        end_index    => $last_idx,
    };
}

sub get_avp_anchor {
    my ($self) = @_;
    return ( $self->{_avp_anchor_year}, $self->{_avp_anchor_month}, $self->{_avp_anchor_day} );
}

sub get_avp_anchor_ts { my ($self) = @_; return $self->{_avp_anchor_ts}; }

sub _confirm_zigzag {
    my ( $self, $arr, $prefix, $kind, $idx, $price, $force ) = @_;
    my $leg_key  = "_${prefix}_last_leg";
    my $prev_key = "_${prefix}_prev_${kind}";

    if ( defined $self->{$leg_key} && $self->{$leg_key} eq $kind && @$arr ) {
        my $last = $arr->[-1];
        unless ($force) {
            my $better = ( $kind eq 'high' ) ? ( $price > $last->{price} ) : ( $price < $last->{price} );
            return unless $better;
        }
        $last->{index} = $idx;
        $last->{price} = $price;
        $last->{label} = ( $kind eq 'high' )
            ? ( ( !defined $self->{$prev_key} || $price <= $self->{$prev_key} ) ? 'LH' : 'HH' )
            : ( ( !defined $self->{$prev_key} || $price >= $self->{$prev_key} ) ? 'HL' : 'LL' );
        return;
    }

    my $label = ( $kind eq 'high' )
        ? ( ( !defined $self->{$prev_key} || $price <= $self->{$prev_key} ) ? 'LH' : 'HH' )
        : ( ( !defined $self->{$prev_key} || $price >= $self->{$prev_key} ) ? 'HL' : 'LL' );

    push @$arr, { type => $kind, index => $idx, price => $price, label => $label };
    $self->{$leg_key}  = $kind;
    $self->{$prev_key} = $price;
    return;
}

1;