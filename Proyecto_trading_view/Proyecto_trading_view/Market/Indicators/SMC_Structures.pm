package Market::Indicators::SMC_Structures;

use strict;
use warnings;

use constant {
    LEG_BEARISH => 0,
    LEG_BULLISH => 1,
    BULLISH     =>  1,
    BEARISH     => -1,
};

my %TF_MIN = (
    '1m' => 1, '5m' => 5, '15m' => 15,
    '1h' => 60, '2h' => 120, '4h' => 240,
    'D'  => 1440, 'W' => 10080,
);

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        length      => $args{length}      // 5,
        swing_length => $args{swing_length} // 50,
        eq_length    => $args{eq_length}    // 3,
        eq_threshold => $args{eq_threshold} // 0.1,
        macro_prd   => $args{macro_prd}   // 2,
        ref_tf_min  => $args{ref_tf_min}  // 30,
        long_length => $args{long_length} // 150,
        fvg_atr_len => $args{fvg_atr_len} // 55,
        fvg_max_count => $args{fvg_max_count} // 25,

        fvg_history => $args{fvg_history} // 5,

        ob_atr_len  => $args{ob_atr_len}  // 200,

        values        => [],
        _structures   => [],
        _equal_levels => [],
        _fvgs         => [],
        _fvgs_classic => [],
        _pending_fvgs         => [],
        _pending_fvgs_classic => [],
        _macro_pivots => [],
        _long_pivots  => [],
        _order_blocks => [],

        _internal_order_blocks => [],

        _pv_max_dq => { micro => [], swing => [] },
        _pv_min_dq => { micro => [], swing => [] },

        _pivot_high_level   => undef,
        _pivot_high_index   => undef,
        _pivot_high_crossed => 0,
        _pivot_low_level    => undef,
        _pivot_low_index    => undef,
        _pivot_low_crossed  => 0,
        _trend_bias         => 0,
        _last_leg           => LEG_BEARISH,

        _swing_pivot_high_level   => undef,
        _swing_pivot_high_index   => undef,
        _swing_pivot_high_crossed => 0,
        _swing_pivot_low_level    => undef,
        _swing_pivot_low_index    => undef,
        _swing_pivot_low_crossed  => 0,
        _swing_trend_bias         => 0,
        _swing_last_leg           => LEG_BEARISH,
        _swing_pivots             => [],

        _eq_high_level => undef,
        _eq_high_index => undef,
        _eq_low_level  => undef,
        _eq_low_index  => undef,
        _eq_last_leg   => LEG_BEARISH,

        _macro_pivot_high_level => undef,
        _macro_pivot_high_index => undef,
        _macro_pivot_low_level  => undef,
        _macro_pivot_low_index  => undef,
        _macro_last_leg         => LEG_BEARISH,
        _macro_label_ref_high   => undef,
        _macro_label_ref_low    => undef,

        _macro_last_bucket    => undef,
        _macro_newbar_indices => [],

        _long_pivot_high_level => undef,
        _long_pivot_high_index => undef,
        _long_pivot_low_level  => undef,
        _long_pivot_low_index  => undef,
        _long_last_leg         => LEG_BEARISH,

        _trailing_top          => undef,
        _trailing_bottom       => undef,
        _trailing_top_index    => undef,
        _trailing_bottom_index => undef,

        _atr_tr_sum     => 0,
        _atr_last_close => undef,
        _atr_last_value => undef,
        _atr_count      => 0,
        _atr_current    => undef,

        _ob_atr_tr_sum     => 0,
        _ob_atr_last_close => undef,
        _ob_atr_last_value => undef,
        _ob_atr_count      => 0,
        _ob_atr_current    => undef,

        _liquidity => undef,

        _channels    => [],
        _atr_sum_all => 0,
        _atr_cnt_all => 0,
    };
    bless $self, $class;
    return $self;
}

sub set_liquidity_engine {
    my ( $self, $liq ) = @_;
    $self->{_liquidity} = $liq;
    return;
}

sub reset {
    my ($self) = @_;
    $self->{values}        = [];
    $self->{_structures}   = [];
    $self->{_equal_levels} = [];
    $self->{_fvgs}         = [];
    $self->{_fvgs_classic} = [];
    $self->{_pending_fvgs}         = [];
    $self->{_pending_fvgs_classic} = [];
    $self->{_macro_pivots} = [];
    $self->{_long_pivots}  = [];
    $self->{_order_blocks} = [];
    $self->{_internal_order_blocks} = [];

    $self->{_pv_max_dq} = { micro => [], swing => [] };
    $self->{_pv_min_dq} = { micro => [], swing => [] };

    $self->{_pivot_high_level}   = undef;
    $self->{_pivot_high_index}   = undef;
    $self->{_pivot_high_crossed} = 0;
    $self->{_pivot_low_level}    = undef;
    $self->{_pivot_low_index}    = undef;
    $self->{_pivot_low_crossed}  = 0;
    $self->{_trend_bias}         = 0;
    $self->{_last_leg}           = LEG_BEARISH;

    $self->{_swing_pivot_high_level}   = undef;
    $self->{_swing_pivot_high_index}   = undef;
    $self->{_swing_pivot_high_crossed} = 0;
    $self->{_swing_pivot_low_level}    = undef;
    $self->{_swing_pivot_low_index}    = undef;
    $self->{_swing_pivot_low_crossed}  = 0;
    $self->{_swing_trend_bias}         = 0;
    $self->{_swing_last_leg}           = LEG_BEARISH;
    $self->{_swing_pivots}             = [];

    $self->{_eq_high_level} = undef;
    $self->{_eq_high_index} = undef;
    $self->{_eq_low_level}  = undef;
    $self->{_eq_low_index}  = undef;
    $self->{_eq_last_leg}   = LEG_BEARISH;

    $self->{_macro_pivot_high_level} = undef;
    $self->{_macro_pivot_high_index} = undef;
    $self->{_macro_pivot_low_level}  = undef;
    $self->{_macro_pivot_low_index}  = undef;
    $self->{_macro_last_leg}         = LEG_BEARISH;
    $self->{_macro_label_ref_high}   = undef;
    $self->{_macro_label_ref_low}    = undef;
    $self->{_macro_last_bucket}      = undef;
    $self->{_macro_newbar_indices}   = [];

    $self->{_long_pivot_high_level} = undef;
    $self->{_long_pivot_high_index} = undef;
    $self->{_long_pivot_low_level}  = undef;
    $self->{_long_pivot_low_index}  = undef;
    $self->{_long_last_leg}         = LEG_BEARISH;

    $self->{_trailing_top}          = undef;
    $self->{_trailing_bottom}       = undef;
    $self->{_trailing_top_index}    = undef;
    $self->{_trailing_bottom_index} = undef;

    $self->{_atr_tr_sum}     = 0;
    $self->{_atr_last_close} = undef;
    $self->{_atr_last_value} = undef;
    $self->{_atr_count}      = 0;
    $self->{_atr_current}    = undef;

    $self->{_ob_atr_tr_sum}     = 0;
    $self->{_ob_atr_last_close} = undef;
    $self->{_ob_atr_last_value} = undef;
    $self->{_ob_atr_count}      = 0;
    $self->{_ob_atr_current}    = undef;

    $self->{_channels}    = [];
    $self->{_atr_sum_all} = 0;
    $self->{_atr_cnt_all} = 0;
    return;
}

sub get_values         { my ($self) = @_; return $self->{values};        }
sub get_structures     { my ($self) = @_; return $self->{_structures};   }
sub get_equal_levels   { my ($self) = @_; return $self->{_equal_levels}; }
sub get_fvgs           { my ($self) = @_; return $self->{_fvgs};         }
sub get_fvgs_classic   { my ($self) = @_; return $self->{_fvgs_classic}; }
sub get_macro_pivots   { my ($self) = @_; return $self->{_macro_pivots}; }
sub get_swing_pivots   { my ($self) = @_; return $self->{_swing_pivots}; }
sub get_long_pivots    { my ($self) = @_; return $self->{_long_pivots};  }
sub get_order_blocks   { my ($self) = @_; return $self->{_order_blocks}; }

sub get_internal_order_blocks { my ($self) = @_; return $self->{_internal_order_blocks}; }

sub get_channels { my ($self) = @_; return $self->{_channels}; }

sub get_trailing_extremes {
    my ($self) = @_;
    return undef unless defined $self->{_trailing_top} && defined $self->{_trailing_bottom};
    return {
        top          => $self->{_trailing_top},
        top_index    => $self->{_trailing_top_index},
        bottom       => $self->{_trailing_bottom},
        bottom_index => $self->{_trailing_bottom_index},
        trend_bias   => $self->{_trend_bias},
    };
}

sub get_fib_range {
    my ($self) = @_;
    return undef unless defined $self->{_trailing_top} && defined $self->{_trailing_bottom};
    my $from = ( $self->{_trailing_top_index} < $self->{_trailing_bottom_index} )
        ? $self->{_trailing_top_index} : $self->{_trailing_bottom_index};
    return { top => $self->{_trailing_top}, bottom => $self->{_trailing_bottom}, from => $from };
}

sub update_at_index {
    my ( $self, $market_data, $i ) = @_;
    push @{ $self->{values} }, undef;

    $self->_update_internal_atr(  $market_data, $i );
    $self->_update_ob_atr(        $market_data, $i );
    $self->_detect_fvg(           $market_data, $i );
    $self->_mitigate_fvg(         $market_data, $i );
    $self->_detect_fvg_classic(   $market_data, $i );
    $self->_mitigate_fvg_classic( $market_data, $i );

    $self->_update_trailing_extremes( $market_data, $i );

    $self->_update_pivots( $market_data, $i, $self->{swing_length}, 'swing' );
    $self->_update_pivots( $market_data, $i, $self->{length}, 'micro' );
    $self->_update_eq_pivots( $market_data, $i );

    $self->_check_structure_break(       $market_data, $i );
    $self->_check_swing_structure_break( $market_data, $i );
    $self->_mitigate_order_blocks( $market_data, $i );

    my $k_macro = $self->_calc_macro_k( $market_data, $i );
    $self->_update_pivots( $market_data, $i, $k_macro, 'macro' );

    $self->_update_pivots( $market_data, $i, $self->{long_length}, 'long' );

    return;
}

sub recompute_macro_pivots_only {
    my ( $self, $market_data ) = @_;
    return unless $market_data;

    $self->{_macro_pivots}           = [];
    $self->{_macro_pivot_high_level} = undef;
    $self->{_macro_pivot_high_index} = undef;
    $self->{_macro_pivot_low_level}  = undef;
    $self->{_macro_pivot_low_index}  = undef;
    $self->{_macro_last_leg}         = LEG_BEARISH;
    $self->{_macro_label_ref_high}   = undef;
    $self->{_macro_label_ref_low}    = undef;
    $self->{_macro_last_bucket}      = undef;
    $self->{_macro_newbar_indices}   = [];

    my $last_idx = $market_data->last_index;
    return if $last_idx < 0;

    for my $i ( 0 .. $last_idx ) {
        my $k = $self->_calc_macro_k( $market_data, $i );
        $self->_update_pivots( $market_data, $i, $k, 'macro' );
    }
    return;
}

sub _update_trailing_extremes {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return unless $c;

    if ( defined $self->{_trailing_top} && $c->{high} > $self->{_trailing_top} ) {
        $self->{_trailing_top}       = $c->{high};
        $self->{_trailing_top_index} = $i;
    }
    if ( defined $self->{_trailing_bottom} && $c->{low} < $self->{_trailing_bottom} ) {
        $self->{_trailing_bottom}       = $c->{low};
        $self->{_trailing_bottom_index} = $i;
    }
    return;
}

sub _macro_htf_bucket {
    my ( $self, $ts, $ref_min ) = @_;
    my $interval_sec = $ref_min * 60;
    my $anchor_sec   = ( $ref_min >= 60 ) ? 3600 : 0;
    my $shifted      = $ts - $anchor_sec;
    return int( $shifted / $interval_sec ) * $interval_sec + $anchor_sec;
}

sub _calc_macro_k {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return 2 unless $c;

    my $ref_min = $self->{ref_tf_min};
    my $bucket  = $self->_macro_htf_bucket( $c->{ts}, $ref_min );

    if ( !defined $self->{_macro_last_bucket} || $bucket != $self->{_macro_last_bucket} ) {
        unshift @{ $self->{_macro_newbar_indices} }, $i;
        my $keep = $self->{macro_prd} + 2;
        splice @{ $self->{_macro_newbar_indices} }, $keep
            if @{ $self->{_macro_newbar_indices} } > $keep;
    }
    $self->{_macro_last_bucket} = $bucket;

    my $prd = $self->{macro_prd};
    my $bi  = $self->{_macro_newbar_indices}[ $prd - 1 ];

    my $k = defined $bi ? ( $i - $bi + 1 ) : 1;
    $k = 2   if $k < 2;
    $k = 500 if $k > 500;
    return $k;
}

sub set_ref_tf_min {
    my ( $self, $minutes ) = @_;
    return unless defined $minutes && $minutes > 0;
    $self->{ref_tf_min} = $minutes;
    return;
}

sub get_ref_tf_min { my ($self) = @_; return $self->{ref_tf_min}; }

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

sub _update_pivots {
    my ( $self, $market_data, $i, $k, $mode ) = @_;

    if ( $mode eq 'macro' ) {
        $self->_update_macro_pivot_live( $market_data, $i, $k );
        return;
    }

    if ( $mode eq 'micro' or $mode eq 'swing' ) {
        my $c = $market_data->get_candle($i);
        return unless $c;

        my $wmax = $self->_roll_push_max( $self->{_pv_max_dq}{$mode}, $i, $c->{high}, $k );
        my $wmin = $self->_roll_push_min( $self->{_pv_min_dq}{$mode}, $i, $c->{low},  $k );

        return if $i < $k;

        my $cand_idx  = $i - $k;
        my $candidate = $market_data->get_candle($cand_idx);
        return unless $candidate;

        my $new_leg_high = ( $candidate->{high} > ( $wmax // 0 ) );
        my $new_leg_low  = ( $candidate->{low}  < ( $wmin // 9e99 ) );

        my $leg_key = ( $mode eq 'swing' ) ? '_swing_last_leg' : '_last_leg';
        my $leg     = $self->{$leg_key};
        if    ($new_leg_high) { $leg = LEG_BEARISH; }
        elsif ($new_leg_low)  { $leg = LEG_BULLISH; }

        if ( $leg != $self->{$leg_key} ) {
            if ( $leg == LEG_BULLISH ) {
                $self->_confirm_pivot_low(  $market_data, $cand_idx, $mode );
            } else {
                $self->_confirm_pivot_high( $market_data, $cand_idx, $mode );
            }
        }
        $self->{$leg_key} = $leg;

    } else {
        return if $i < 2 * $k;

        my $cand_idx  = $i - $k;
        my $candidate = $market_data->get_candle($cand_idx);
        return unless $candidate;

        my $is_ph     = 1;
        my $is_pl     = 1;
        my $win_start = $cand_idx - $k;
        $win_start    = 0 if $win_start < 0;

        for my $j ( $win_start .. $cand_idx + $k ) {
            next if $j == $cand_idx;
            my $c = $market_data->get_candle($j);
            next unless $c;
            $is_ph = 0 if $c->{high} >= $candidate->{high};
            $is_pl = 0 if $c->{low}  <= $candidate->{low};
        }

        my $leg_key = '_long_last_leg';
        my $leg     = $self->{$leg_key};

        if    ($is_ph) { $leg = LEG_BEARISH; }
        elsif ($is_pl) { $leg = LEG_BULLISH; }

        if ( $leg != $self->{$leg_key} ) {
            if ( $leg == LEG_BULLISH ) {
                $self->_confirm_pivot_low(  $market_data, $cand_idx, $mode );
            } else {
                $self->_confirm_pivot_high( $market_data, $cand_idx, $mode );
            }
        }
        $self->{$leg_key} = $leg;
    }
    return;
}

sub _update_macro_pivot_live {
    my ( $self, $market_data, $i, $k ) = @_;
    return if $i < $k - 1;

    my $c = $market_data->get_candle($i);
    return unless $c;

    my ( $wmax, $wmin );
    for my $j ( ( $i - $k + 1 ) .. $i ) {
        my $cc = $market_data->get_candle($j);
        next unless $cc;
        $wmax = $cc->{high} if !defined $wmax || $cc->{high} > $wmax;
        $wmin = $cc->{low}  if !defined $wmin || $cc->{low}  < $wmin;
    }
    return unless defined $wmax && defined $wmin;

    my $is_high = ( $c->{high} >= $wmax );
    my $is_low  = ( $c->{low}  <= $wmin );

    return unless ( $is_high xor $is_low );

    my $prev_dir = $self->{_macro_last_leg} || 0;
    my $new_dir  = $is_high ? 1 : -1;
    my $dirchanged = ( $new_dir != $prev_dir );

    if ($dirchanged) {
        if ( $new_dir == 1 ) {
            $self->_confirm_pivot_high( $market_data, $i, 'macro' );
        } else {
            $self->_confirm_pivot_low(  $market_data, $i, 'macro' );
        }
    } else {
        if ( $new_dir == 1 ) {
            $self->_update_macro_pivot_high_inplace( $i, $c->{high} );
        } else {
            $self->_update_macro_pivot_low_inplace(  $i, $c->{low} );
        }
    }
    $self->{_macro_last_leg} = $new_dir;
    return;
}

sub _confirm_pivot_low {
    my ( $self, $market_data, $idx, $mode ) = @_;
    my $c = $market_data->get_candle($idx);
    return unless $c;

    if ( $mode eq 'micro' ) {
        my $last_level = $self->{_pivot_low_level};

        $self->{_pivot_low_level}   = $c->{low};
        $self->{_pivot_low_index}   = $idx;
        $self->{_pivot_low_crossed} = 0;

        $self->{values}[$idx] = {
            type  => ( !defined $last_level || $c->{low} >= $last_level ) ? 'HL' : 'LL',
            price => $c->{low},
        };

    } elsif ( $mode eq 'swing' ) {
        my $last_level = $self->{_swing_pivot_low_level};

        $self->{_swing_pivot_low_level}   = $c->{low};
        $self->{_swing_pivot_low_index}   = $idx;
        $self->{_swing_pivot_low_crossed} = 0;

        $self->{_trailing_bottom}       = $c->{low};
        $self->{_trailing_bottom_index} = $idx;

        my $label = ( !defined $last_level || $c->{low} >= $last_level ) ? 'HL' : 'LL';
        push @{ $self->{_swing_pivots} }, {
            type => 'low', index => $idx, price => $c->{low}, label => $label,
        };

        $self->_try_detect_channel( $market_data, 'low' );

    } elsif ( $mode eq 'macro' ) {
        my $last_level = $self->{_macro_pivot_low_level};
        $self->{_macro_pivot_low_level} = $c->{low};
        $self->{_macro_pivot_low_index} = $idx;
        $self->{_macro_label_ref_low}   = $last_level;

        my $label = ( !defined $last_level || $c->{low} >= $last_level ) ? 'HL' : 'LL';
        push @{ $self->{_macro_pivots} }, {
            type  => 'low', index => $idx, price => $c->{low}, label => $label,
        };

    } else {
        my $last_level = $self->{_long_pivot_low_level};
        $self->{_long_pivot_low_level} = $c->{low};
        $self->{_long_pivot_low_index} = $idx;

        my $label = ( !defined $last_level || $c->{low} >= $last_level ) ? 'HL' : 'LL';
        push @{ $self->{_long_pivots} }, {
            type  => 'low', index => $idx, price => $c->{low}, label => $label,
        };
    }
    return;
}

sub _confirm_pivot_high {
    my ( $self, $market_data, $idx, $mode ) = @_;
    my $c = $market_data->get_candle($idx);
    return unless $c;

    if ( $mode eq 'micro' ) {
        my $last_level = $self->{_pivot_high_level};

        $self->{_pivot_high_level}   = $c->{high};
        $self->{_pivot_high_index}   = $idx;
        $self->{_pivot_high_crossed} = 0;

        $self->{values}[$idx] = {
            type  => ( !defined $last_level || $c->{high} <= $last_level ) ? 'LH' : 'HH',
            price => $c->{high},
        };

    } elsif ( $mode eq 'swing' ) {
        my $last_level = $self->{_swing_pivot_high_level};

        $self->{_swing_pivot_high_level}   = $c->{high};
        $self->{_swing_pivot_high_index}   = $idx;
        $self->{_swing_pivot_high_crossed} = 0;

        $self->{_trailing_top}       = $c->{high};
        $self->{_trailing_top_index} = $idx;

        my $label = ( !defined $last_level || $c->{high} <= $last_level ) ? 'LH' : 'HH';
        push @{ $self->{_swing_pivots} }, {
            type => 'high', index => $idx, price => $c->{high}, label => $label,
        };

        $self->_try_detect_channel( $market_data, 'high' );

    } elsif ( $mode eq 'macro' ) {
        my $last_level = $self->{_macro_pivot_high_level};
        $self->{_macro_pivot_high_level} = $c->{high};
        $self->{_macro_pivot_high_index} = $idx;
        $self->{_macro_label_ref_high}   = $last_level;

        my $label = ( !defined $last_level || $c->{high} <= $last_level ) ? 'LH' : 'HH';
        push @{ $self->{_macro_pivots} }, {
            type  => 'high', index => $idx, price => $c->{high}, label => $label,
        };

    } else {
        my $last_level = $self->{_long_pivot_high_level};
        $self->{_long_pivot_high_level} = $c->{high};
        $self->{_long_pivot_high_index} = $idx;

        my $label = ( !defined $last_level || $c->{high} <= $last_level ) ? 'LH' : 'HH';
        push @{ $self->{_long_pivots} }, {
            type  => 'high', index => $idx, price => $c->{high}, label => $label,
        };
    }
    return;
}

sub _update_macro_pivot_high_inplace {
    my ( $self, $idx, $price ) = @_;
    return unless defined $self->{_macro_pivot_high_level};
    return unless $price > $self->{_macro_pivot_high_level};

    $self->{_macro_pivot_high_level} = $price;
    $self->{_macro_pivot_high_index} = $idx;

    my $pivots = $self->{_macro_pivots};
    if ( @$pivots && $pivots->[-1]{type} eq 'high' ) {
        $pivots->[-1]{price} = $price;
        $pivots->[-1]{index} = $idx;

        my $ref = $self->{_macro_label_ref_high};
        $pivots->[-1]{label} = ( !defined $ref || $price <= $ref ) ? 'LH' : 'HH';
    }
    return;
}

sub _update_macro_pivot_low_inplace {
    my ( $self, $idx, $price ) = @_;
    return unless defined $self->{_macro_pivot_low_level};
    return unless $price < $self->{_macro_pivot_low_level};

    $self->{_macro_pivot_low_level} = $price;
    $self->{_macro_pivot_low_index} = $idx;

    my $pivots = $self->{_macro_pivots};
    if ( @$pivots && $pivots->[-1]{type} eq 'low' ) {
        $pivots->[-1]{price} = $price;
        $pivots->[-1]{index} = $idx;

        my $ref = $self->{_macro_label_ref_low};
        $pivots->[-1]{label} = ( !defined $ref || $price >= $ref ) ? 'HL' : 'LL';
    }
    return;
}

sub _try_detect_channel {
    my ( $self, $market_data, $type ) = @_;
    my @same = grep { $_->{type} eq $type } @{ $self->{_swing_pivots} };
    return if @same < 3;
    my ( $p1, $p2, $p3 ) = @same[ -3, -2, -1 ];

    my $c1 = $market_data->get_candle( $p1->{index} );
    my $c3 = $market_data->get_candle( $p3->{index} );
    return unless $c1 && $c3;

    my $span_min = ( $c3->{ts} - $c1->{ts} ) / 60;
    return if $span_min < 120;

    my $atr = $self->{_atr_current} // 0;
    return if $atr <= 0;
    $self->{_atr_sum_all} += $atr;
    $self->{_atr_cnt_all}++;
    my $atr_avg = $self->{_atr_sum_all} / $self->{_atr_cnt_all};
    return if $atr > $atr_avg;

    return if $p1->{index} == $p3->{index};
    my $slope = ( $p3->{price} - $p1->{price} ) / ( $p3->{index} - $p1->{index} );
    my $pred2 = $p1->{price} + $slope * ( $p2->{index} - $p1->{index} );
    my $tol   = $atr * 0.5;
    return if abs( $p2->{price} - $pred2 ) > $tol;

    my $other  = ( $type eq 'low' ) ? 'high' : 'low';
    my $offset = 0;
    for my $q ( @{ $self->{_swing_pivots} } ) {
        next unless $q->{type} eq $other;
        next if $q->{index} < $p1->{index} || $q->{index} > $p3->{index};
        my $line_y = $p1->{price} + $slope * ( $q->{index} - $p1->{index} );
        my $d = ( $type eq 'low' ) ? ( $q->{price} - $line_y ) : ( $line_y - $q->{price} );
        $offset = $d if $d > $offset;
    }
    return if $offset <= 0;

    push @{ $self->{_channels} }, {
        bull        => ( $type eq 'low' ) ? 1 : 0,
        i1          => $p1->{index}, p1 => $p1->{price},
        i3          => $p3->{index}, p3 => $p3->{price},
        slope       => $slope, offset => $offset,
        start_index => $p1->{index},
    };
    shift @{ $self->{_channels} } if @{ $self->{_channels} } > 5;
    return;
}

sub channel_lines_at {
    my ( $self, $ch, $idx ) = @_;
    my $base = $ch->{p1} + $ch->{slope} * ( $idx - $ch->{i1} );
    my $opp  = $ch->{bull} ? $base + $ch->{offset} : $base - $ch->{offset};
    my $med  = ( $base + $opp ) / 2;
    return ( $base, $opp, $med );
}

sub _check_structure_break {
    my ( $self, $market_data, $i ) = @_;
    return if $i < 1;

    my $close      = $market_data->get_candle($i)->{close};
    my $prev_close = $market_data->get_candle( $i - 1 )->{close};

    if ( defined $self->{_pivot_high_level} && !$self->{_pivot_high_crossed} ) {
        my $level = $self->{_pivot_high_level};
        if ( $prev_close <= $level && $close > $level ) {
            my $tag = ( $self->{_trend_bias} == BEARISH ) ? 'I-CHOCH' : 'I-BOS';
            $self->{_pivot_high_crossed} = 1;
            $self->{_trend_bias}         = BULLISH;
            push @{ $self->{_structures} }, {
                type        => $tag,
                direction   => 'bullish',
                level       => $level,
                from_index  => $self->{_pivot_high_index},
                event_index => $i,
                liquidity   => $self->_check_liquidity_confluence( $market_data, $i, $level ),
            };
            $self->_create_order_block( $market_data, $self->{_pivot_high_index}, $i, 'bullish', 1 );
        }
    }

    if ( defined $self->{_pivot_low_level} && !$self->{_pivot_low_crossed} ) {
        my $level = $self->{_pivot_low_level};
        if ( $prev_close >= $level && $close < $level ) {
            my $tag = ( $self->{_trend_bias} == BULLISH ) ? 'I-CHOCH' : 'I-BOS';
            $self->{_pivot_low_crossed} = 1;
            $self->{_trend_bias}        = BEARISH;
            push @{ $self->{_structures} }, {
                type        => $tag,
                direction   => 'bearish',
                level       => $level,
                from_index  => $self->{_pivot_low_index},
                event_index => $i,
                liquidity   => $self->_check_liquidity_confluence( $market_data, $i, $level ),
            };
            $self->_create_order_block( $market_data, $self->{_pivot_low_index}, $i, 'bearish', 1 );
        }
    }
    return;
}

sub _check_swing_structure_break {
    my ( $self, $market_data, $i ) = @_;
    return if $i < 1;

    my $close      = $market_data->get_candle($i)->{close};
    my $prev_close = $market_data->get_candle( $i - 1 )->{close};

    if ( defined $self->{_swing_pivot_high_level} && !$self->{_swing_pivot_high_crossed} ) {
        my $level = $self->{_swing_pivot_high_level};
        if ( $prev_close <= $level && $close > $level ) {
            my $tag = ( $self->{_swing_trend_bias} == BEARISH ) ? 'CHOCH' : 'BOS';
            $self->{_swing_pivot_high_crossed} = 1;
            $self->{_swing_trend_bias}         = BULLISH;
            push @{ $self->{_structures} }, {
                type        => $tag,
                direction   => 'bullish',
                level       => $level,
                from_index  => $self->{_swing_pivot_high_index},
                event_index => $i,
                liquidity   => $self->_check_liquidity_confluence( $market_data, $i, $level ),
            };
            $self->_create_order_block( $market_data, $self->{_swing_pivot_high_index}, $i, 'bullish' );
        }
    }

    if ( defined $self->{_swing_pivot_low_level} && !$self->{_swing_pivot_low_crossed} ) {
        my $level = $self->{_swing_pivot_low_level};
        if ( $prev_close >= $level && $close < $level ) {
            my $tag = ( $self->{_swing_trend_bias} == BULLISH ) ? 'CHOCH' : 'BOS';
            $self->{_swing_pivot_low_crossed} = 1;
            $self->{_swing_trend_bias}        = BEARISH;
            push @{ $self->{_structures} }, {
                type        => $tag,
                direction   => 'bearish',
                level       => $level,
                from_index  => $self->{_swing_pivot_low_index},
                event_index => $i,
                liquidity   => $self->_check_liquidity_confluence( $market_data, $i, $level ),
            };
            $self->_create_order_block( $market_data, $self->{_swing_pivot_low_index}, $i, 'bearish' );
        }
    }
    return;
}

sub _check_liquidity_confluence {
    my ( $self, $market_data, $i, $level ) = @_;
    return undef unless $self->{_liquidity};
    my $atr = $self->{_atr_current};
    return undef unless defined $atr && $atr > 0;
    my $lvl = $self->{_liquidity}->find_recent_level_near( $level, $atr * 0.15, $i );
    return undef unless $lvl;
    return $lvl->{state};
}

sub _update_eq_pivots {
    my ( $self, $market_data, $i ) = @_;
    my $k = $self->{eq_length};
    return if $i < $k;

    my ( $wmax, $wmin );
    for my $j ( ( $i - $k + 1 ) .. $i ) {
        my $c = $market_data->get_candle($j);
        next unless $c;
        $wmax = $c->{high} if !defined $wmax || $c->{high} > $wmax;
        $wmin = $c->{low}  if !defined $wmin || $c->{low}  < $wmin;
    }
    my $cand_idx  = $i - $k;
    my $candidate = $market_data->get_candle($cand_idx);
    return unless $candidate;

    my $new_leg_high = ( $candidate->{high} > ( $wmax // 0 ) );
    my $new_leg_low  = ( $candidate->{low}  < ( $wmin // 9e99 ) );

    my $leg = $self->{_eq_last_leg};
    if    ($new_leg_high) { $leg = LEG_BEARISH; }
    elsif ($new_leg_low)  { $leg = LEG_BULLISH; }

    if ( $leg != $self->{_eq_last_leg} ) {
        my $atr    = $self->{_atr_current} // 0;
        my $thresh = $self->{eq_threshold} * $atr;

        if ( $leg == LEG_BULLISH ) {
            if ( defined $self->{_eq_low_level} && $atr > 0
                 && abs( $candidate->{low} - $self->{_eq_low_level} ) < $thresh )
            {
                push @{ $self->{_equal_levels} }, {
                    type => 'low', idx1 => $self->{_eq_low_index}, price1 => $self->{_eq_low_level},
                    idx2 => $cand_idx, price2 => $candidate->{low},
                };
                shift @{ $self->{_equal_levels} } if @{ $self->{_equal_levels} } > 200;
            }
            $self->{_eq_low_level} = $candidate->{low};
            $self->{_eq_low_index} = $cand_idx;
        } else {
            if ( defined $self->{_eq_high_level} && $atr > 0
                 && abs( $candidate->{high} - $self->{_eq_high_level} ) < $thresh )
            {
                push @{ $self->{_equal_levels} }, {
                    type => 'high', idx1 => $self->{_eq_high_index}, price1 => $self->{_eq_high_level},
                    idx2 => $cand_idx, price2 => $candidate->{high},
                };
                shift @{ $self->{_equal_levels} } if @{ $self->{_equal_levels} } > 200;
            }
            $self->{_eq_high_level} = $candidate->{high};
            $self->{_eq_high_index} = $cand_idx;
        }
    }
    $self->{_eq_last_leg} = $leg;
    return;
}

sub _update_internal_atr {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return unless $c;

    my $period = $self->{fvg_atr_len};
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
    if ( $self->{_atr_count} < $period ) {
        $self->{_atr_tr_sum} += $tr;
        $self->{_atr_current} = $self->{_atr_tr_sum} / $self->{_atr_count};
    } elsif ( $self->{_atr_count} == $period ) {
        $self->{_atr_tr_sum}    += $tr;
        $self->{_atr_current}    = $self->{_atr_tr_sum} / $period;
        $self->{_atr_last_value} = $self->{_atr_current};
    } else {
        $self->{_atr_current}    = ( $self->{_atr_last_value} * ( $period - 1 ) + $tr ) / $period;
        $self->{_atr_last_value} = $self->{_atr_current};
    }
    $self->{_atr_last_close} = $c->{close};
    return;
}

sub _update_ob_atr {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return unless $c;

    my $period = $self->{ob_atr_len};
    my $tr;
    if ( defined $self->{_ob_atr_last_close} ) {
        my $pc  = $self->{_ob_atr_last_close};
        my $hl  = $c->{high} - $c->{low};
        my $hpc = abs( $c->{high} - $pc );
        my $lpc = abs( $c->{low}  - $pc );
        $tr = $hl; $tr = $hpc if $hpc > $tr; $tr = $lpc if $lpc > $tr;
    } else {
        $tr = $c->{high} - $c->{low};
    }

    $self->{_ob_atr_count}++;
    if ( $self->{_ob_atr_count} < $period ) {
        $self->{_ob_atr_tr_sum} += $tr;
        $self->{_ob_atr_current} = $self->{_ob_atr_tr_sum} / $self->{_ob_atr_count};
    } elsif ( $self->{_ob_atr_count} == $period ) {
        $self->{_ob_atr_tr_sum}    += $tr;
        $self->{_ob_atr_current}    = $self->{_ob_atr_tr_sum} / $period;
        $self->{_ob_atr_last_value} = $self->{_ob_atr_current};
    } else {
        $self->{_ob_atr_current}    = ( $self->{_ob_atr_last_value} * ( $period - 1 ) + $tr ) / $period;
        $self->{_ob_atr_last_value} = $self->{_ob_atr_current};
    }
    $self->{_ob_atr_last_close} = $c->{close};
    return;
}

sub _detect_fvg {
    my ( $self, $market_data, $i ) = @_;
    return if $i < 3;

    my $c1 = $market_data->get_candle( $i - 1 );
    my $c2 = $market_data->get_candle( $i - 2 );
    my $c3 = $market_data->get_candle( $i - 3 );
    return unless $c1 && $c2 && $c3;

    if ( $c3->{high} < $c1->{low} ) {
        my $fvg = {
            bias          => 'bullish',
            top           => $c1->{low},
            bottom        => $c3->{high},
            start_index   => $i - 2,
            partial_index => undef,
            full_index    => undef,
            evicted_index => undef,
        };
        push @{ $self->{_fvgs} }, $fvg;
        push @{ $self->{_pending_fvgs} }, $fvg;
        $self->_cap_fvg_history($i);
    }

    if ( $c3->{low} > $c1->{high} ) {
        my $fvg = {
            bias          => 'bearish',
            top           => $c3->{low},
            bottom        => $c1->{high},
            start_index   => $i - 2,
            partial_index => undef,
            full_index    => undef,
            evicted_index => undef,
        };
        push @{ $self->{_fvgs} }, $fvg;
        push @{ $self->{_pending_fvgs} }, $fvg;
        $self->_cap_fvg_history($i);
    }
    return;
}

sub _cap_fvg_history {
    my ( $self, $i ) = @_;
    my $cap = $self->{fvg_history} + 1;
    if ( @{ $self->{_pending_fvgs} } > $cap ) {
        my $oldest = shift @{ $self->{_pending_fvgs} };
        $oldest->{evicted_index} = $i;
    }
    return;
}

sub _cap_fvg_list {
    my ( $self, $arr, $pending_arr, $bias, $cap ) = @_;
    $cap //= $self->{fvg_max_count};
    my @same = grep { $_->{bias} eq $bias } @$arr;
    return if @same <= $cap;

    my $oldest = $same[0];
    @$arr = grep { $_ != $oldest } @$arr;
    if ($pending_arr) {
        my @still = grep { $_ != $oldest } @$pending_arr;
        @$pending_arr = @still;
    }
    return;
}

sub _mitigate_fvg {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return unless $c;

    my @still_pending;
    for my $fvg ( @{ $self->{_pending_fvgs} } ) {
        if ( $fvg->{bias} eq 'bullish' ) {
            if ( $c->{low} <= $fvg->{bottom} ) {
                $fvg->{full_index} = $i;
            }
            elsif ( $c->{low} < $fvg->{top} && !defined $fvg->{partial_index} ) {
                $fvg->{partial_index} = $i;
            }
        } else {
            if ( $c->{high} >= $fvg->{top} ) {
                $fvg->{full_index} = $i;
            }
            elsif ( $c->{high} > $fvg->{bottom} && !defined $fvg->{partial_index} ) {
                $fvg->{partial_index} = $i;
            }
        }
        push @still_pending, $fvg unless defined $fvg->{full_index};
    }
    $self->{_pending_fvgs} = \@still_pending;
    return;
}

sub _detect_fvg_classic {
    my ( $self, $market_data, $i ) = @_;
    return if $i < 2;

    my $c0 = $market_data->get_candle($i);
    my $c1 = $market_data->get_candle( $i - 1 );
    my $c2 = $market_data->get_candle( $i - 2 );
    return unless $c0 && $c1 && $c2;

    my $s0 = $c0->{close} > $c0->{open} ? 1 : ( $c0->{close} < $c0->{open} ? -1 : 0 );
    my $s1 = $c1->{close} > $c1->{open} ? 1 : ( $c1->{close} < $c1->{open} ? -1 : 0 );
    my $s2 = $c2->{close} > $c2->{open} ? 1 : ( $c2->{close} < $c2->{open} ? -1 : 0 );
    my $sum = $s0 + $s1 + $s2;

    if ( $sum == 3 && $c0->{low} > $c2->{high} ) {
        my $fvg = {
            bias            => 'bullish',
            top             => $c0->{low},
            bottom          => $c2->{high},
            start_index     => $i - 2,
            mitigated       => 0,
            mitigated_index => undef,
        };
        push @{ $self->{_fvgs_classic} }, $fvg;
        push @{ $self->{_pending_fvgs_classic} }, $fvg;
        $self->_cap_fvg_list( $self->{_fvgs_classic}, $self->{_pending_fvgs_classic}, 'bullish' );
    }

    if ( $sum == -3 && $c2->{low} > $c0->{high} ) {
        my $fvg = {
            bias            => 'bearish',
            top             => $c2->{low},
            bottom          => $c0->{high},
            start_index     => $i - 2,
            mitigated       => 0,
            mitigated_index => undef,
        };
        push @{ $self->{_fvgs_classic} }, $fvg;
        push @{ $self->{_pending_fvgs_classic} }, $fvg;
        $self->_cap_fvg_list( $self->{_fvgs_classic}, $self->{_pending_fvgs_classic}, 'bearish' );
    }
    return;
}

sub _mitigate_fvg_classic {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return unless $c;

    my @still_pending;
    for my $fvg ( @{ $self->{_pending_fvgs_classic} } ) {
        if ( $i <= $fvg->{start_index} + 2 ) {
            push @still_pending, $fvg;
            next;
        }

        if ( $fvg->{bias} eq 'bullish' ) {
            if ( $c->{close} < $fvg->{bottom} ) {
                $fvg->{mitigated} = 1; $fvg->{mitigated_index} = $i;
            }
            elsif ( $c->{low} < $fvg->{top} && $c->{low} > $fvg->{bottom} ) {
                $fvg->{top} = $c->{low} if $c->{low} < $fvg->{top};
            }
        } else {
            if ( $c->{close} > $fvg->{top} ) {
                $fvg->{mitigated} = 1; $fvg->{mitigated_index} = $i;
            }
            elsif ( $c->{high} > $fvg->{bottom} && $c->{high} < $fvg->{top} ) {
                $fvg->{bottom} = $c->{high} if $c->{high} > $fvg->{bottom};
            }
        }

        push @still_pending, $fvg unless $fvg->{mitigated};
    }
    $self->{_pending_fvgs_classic} = \@still_pending;
    return;
}

sub _create_order_block {
    my ( $self, $market_data, $from_idx, $to_idx, $direction, $internal ) = @_;
    return unless defined $from_idx;
    my $atr = $self->{_ob_atr_current};
    return unless defined $atr && $atr > 0;

    my ( $best_idx, $best_val );
    for my $j ( $from_idx .. $to_idx ) {
        my $c = $market_data->get_candle($j);
        next unless $c;
        my $high_vol = ( $c->{high} - $c->{low} ) >= ( 2 * $atr );
        if ( $direction eq 'bullish' ) {
            my $parsed_low = $high_vol ? $c->{high} : $c->{low};
            if ( !defined $best_val || $parsed_low < $best_val ) {
                $best_val = $parsed_low; $best_idx = $j;
            }
        } else {
            my $parsed_high = $high_vol ? $c->{low} : $c->{high};
            if ( !defined $best_val || $parsed_high > $best_val ) {
                $best_val = $parsed_high; $best_idx = $j;
            }
        }
    }
    return unless defined $best_idx;

    my $ob_candle = $market_data->get_candle($best_idx);
    return unless $ob_candle;

    my $target = $internal ? $self->{_internal_order_blocks} : $self->{_order_blocks};

    push @$target, {
        bias            => $direction,
        top             => $ob_candle->{high},
        bottom          => $ob_candle->{low},
        start_index     => $best_idx,
        mitigated       => 0,
        mitigated_index => undef,
    };

    my @same = grep { $_->{bias} eq $direction } @$target;
    if ( @same > 5 ) {
        my $oldest = $same[0];
        @$target = grep { $_ != $oldest } @$target;
    }
    return;
}

sub _mitigate_order_blocks {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return unless $c;
    for my $ob ( @{ $self->{_order_blocks} }, @{ $self->{_internal_order_blocks} } ) {
        next if $ob->{mitigated};
        if ( $ob->{bias} eq 'bullish' && $c->{low} < $ob->{bottom} ) {
            $ob->{mitigated} = 1; $ob->{mitigated_index} = $i;
        }
        elsif ( $ob->{bias} eq 'bearish' && $c->{high} > $ob->{top} ) {
            $ob->{mitigated} = 1; $ob->{mitigated_index} = $i;
        }
    }
    return;
}

1;