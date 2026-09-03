package Market::Indicators::Liquidity;

# =============================================================================
# Market::Indicators::Liquidity
# Motor de deteccion de Swing Points -> EQH/EQL -> niveles de liquidez (BSL/SSL)
# con maquina de estados real:
#
#   ACTIVE --(mecha rompe el nivel, cierre NO rompe)--> SWEPT
#   ACTIVE --(cierre rompe el nivel directamente)-----> RUN
#   SWEPT  --(cierre regresa en contra del nivel)------> GRAB   (manipulacion confirmada)
#   SWEPT  --(cierre termina rompiendo el nivel)-------> RUN    (sweep + continuacion real)
#   SWEPT  --(pasan reclaim_window velas sin definirse)-> GRAB   (timeout, grab debil)
#
# GRAB y RUN son estados terminales (resolved).
#
# NOTA DE RENDIMIENTO: _levels conserva TODO el historico (para render y
# consulta), pero la maquina de estados solo necesita revisar en cada vela
# los niveles que aun NO llegaron a un estado terminal. _pending_levels
# mantiene esa lista reducida (referencias a los mismos hashes de _levels,
# no copias) para que el costo por vela sea proporcional a los niveles
# abiertos en ese momento y no al historico completo. Sin este cambio,
# con varios meses de velas de 1m, _update_state_machine termina barriendo
# miles de niveles resueltos en cada vela -> crecimiento cuadratico.
#
# [FIX RENDIMIENTO — NUEVO] _levels NO tenia ningun tope, a diferencia de
# Order Blocks (tope 5 por sesgo) o FVG (tope 6 combinado) -- en varios
# meses de velas de 1 minuto podia acumular miles de niveles. El problema
# no es solo memoria: Market::Overlays::Liquidity::render() recorre TODO
# ese array EN CADA RENDER (cada scroll, zoom, o movimiento de mouse que
# dispare un redibujado) -- con miles de niveles acumulados, eso pesa en
# cada frame, no solo al cambiar de temporalidad. Se agrega un tope
# (level_history_cap, default 300) al array de RENDER (_levels), evictando
# el nivel mas viejo cada vez que se supera -- mismo patron ya usado por
# Order Blocks/FVG. find_recent_level_near (usado para la confluencia de
# liquidez en BOS/CHoCH) sigue funcionando igual: busca desde el final
# hacia atras y corta en el primer match, asi que perder niveles MUY
# viejos del extremo mas antiguo no cambia ningun resultado visible en la
# practica.
# =============================================================================

use strict;
use warnings;

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        swing_length   => $args{swing_length}   // 3,     # k (spec recomienda k=3)
        atr_length     => $args{atr_length}     // 14,
        eq_threshold   => $args{eq_threshold}   // 0.10,  # tolerancia EQH/EQL (x ATR)
        reclaim_window => $args{reclaim_window} // 3,      # velas para confirmar Grab/Run tras un Sweep

        # [FIX RENDIMIENTO — NUEVO] tope del array de niveles (_levels).
        level_history_cap => $args{level_history_cap} // 300,

        _swing_highs => [],   # historial: {index, price}
        _swing_lows  => [],
        _levels      => [],   # niveles de liquidez con su maquina de estados (topeado, ver arriba)
        _pending_levels => [], # BLOQUE PERF: solo niveles activos/swept (no terminales)
        _last_leg    => 0,

        _atr_tr_sum     => 0,
        _atr_last_close => undef,
        _atr_last_value => undef,
        _atr_count      => 0,
        _atr_current    => undef,
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_swing_highs} = [];
    $self->{_swing_lows}  = [];
    $self->{_levels}      = [];
    $self->{_pending_levels} = [];
    $self->{_last_leg}    = 0;
    $self->{_atr_tr_sum}     = 0;
    $self->{_atr_last_close} = undef;
    $self->{_atr_last_value} = undef;
    $self->{_atr_count}      = 0;
    $self->{_atr_current}    = undef;
    return;
}

sub get_values { return []; }
sub get_levels { my ($self) = @_; return $self->{_levels}; }

# Accesores de compatibilidad (filtran por tipo, utiles para stats/print)
sub get_bsl_zones { my ($self) = @_; return [ grep { $_->{type} eq 'BSL' } @{ $self->{_levels} } ]; }
sub get_ssl_zones { my ($self) = @_; return [ grep { $_->{type} eq 'SSL' } @{ $self->{_levels} } ]; }

# -----------------------------------------------------------------------------
# find_recent_level_near — usado por SMC_Structures.pm para la "integracion
# nativa con vectores de liquidez": busca un nivel de liquidez cercano a un
# precio dado, conocido hasta el indice $before_index (causal).
# -----------------------------------------------------------------------------
sub find_recent_level_near {
    my ( $self, $price, $tolerance, $before_index ) = @_;
    for my $lvl ( reverse @{ $self->{_levels} } ) {
        next if $lvl->{start_index} > $before_index;
        return $lvl if abs( $lvl->{price} - $price ) <= $tolerance;
    }
    return undef;
}

# -----------------------------------------------------------------------------
# update_at_index — 100% causal
# -----------------------------------------------------------------------------
sub update_at_index {
    my ( $self, $market_data, $i ) = @_;
    $self->_update_atr( $market_data, $i );
    $self->_detect_swing_and_eq( $market_data, $i );
    $self->_update_state_machine( $market_data, $i );
    return;
}

sub _update_atr {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return unless $c;

    my $period = $self->{atr_length};
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

# -----------------------------------------------------------------------------
# _detect_swing_and_eq — detecta swing points (mismo mecanismo causal que
# SMC_Structures) y, al confirmar uno nuevo, busca un EQH/EQL contra swings
# anteriores dentro de la tolerancia ATR*eq_threshold.
# -----------------------------------------------------------------------------
sub _detect_swing_and_eq {
    my ( $self, $market_data, $i ) = @_;
    my $k = $self->{swing_length};
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

    my $new_leg_high = $candidate->{high} > $wmax;
    my $new_leg_low  = $candidate->{low}  < $wmin;

    my $leg = $self->{_last_leg};
    if    ($new_leg_high) { $leg = 0; }
    elsif ($new_leg_low)  { $leg = 1; }

    if ( $leg != $self->{_last_leg} ) {
        if ( $leg == 1 ) {
            $self->_register_swing( 'low',  $cand_idx, $candidate->{low}  );
        } else {
            $self->_register_swing( 'high', $cand_idx, $candidate->{high} );
        }
    }
    $self->{_last_leg} = $leg;
    return;
}

sub _register_swing {
    my ( $self, $kind, $idx, $price ) = @_;
    my $pool = ( $kind eq 'high' ) ? $self->{_swing_highs} : $self->{_swing_lows};
    push @$pool, { index => $idx, price => $price };

    my $atr = $self->{_atr_current};
    return unless defined $atr && $atr > 0;
    my $margin = $atr * $self->{eq_threshold};
    my $type   = ( $kind eq 'high' ) ? 'BSL' : 'SSL';

    # Comparar contra el swing INMEDIATAMENTE anterior del mismo tipo (EQH/EQL
    # clasico: dos picos/valles consecutivos a precio equivalente)
    return if @$pool < 2;
    my $prev = $pool->[-2];
    return if abs( $prev->{price} - $price ) > $margin;

    $self->_form_or_extend_level( $type, $idx, $price, $margin );
    return;
}

sub _form_or_extend_level {
    my ( $self, $type, $idx, $price, $margin ) = @_;

    for my $lvl ( reverse @{ $self->{_levels} } ) {
        next unless $lvl->{type} eq $type;
        next unless $lvl->{status} eq 'active';
        if ( abs( $lvl->{price} - $price ) <= $margin ) {
            $lvl->{price}      = ( $lvl->{price} + $price ) / 2;
            $lvl->{end_index}  = $idx;
            $lvl->{touches}++;
            return;
        }
        last;   # solo evaluamos el nivel activo mas reciente de este tipo
    }

    my $new_level = {
        type           => $type,                  # 'BSL' | 'SSL'
        price          => $price,
        start_index    => $idx,
        end_index      => $idx,
        touches        => 1,
        status         => 'active',               # active -> swept -> grab|run
        sweep_index    => undef,
        resolved_type  => undef,                  # 'grab' | 'run'
        resolved_index => undef,
    };
    push @{ $self->{_levels} }, $new_level;
    # BLOQUE PERF: mismo hashref en ambas listas -> actualizar el estado en
    # una lo refleja automaticamente en la otra, no hay que sincronizar nada.
    push @{ $self->{_pending_levels} }, $new_level;

    # [FIX RENDIMIENTO — NUEVO] Tope del array de RENDER (_levels): si se
    # supera level_history_cap, se desaloja el nivel MAS VIEJO (FIFO, igual
    # criterio que Order Blocks/FVG). Si ese nivel evacuado todavia estaba
    # en _pending_levels (o sea, aun no habia llegado a un estado
    # terminal), se lo saca de ahi tambien -- no tiene sentido seguir
    # actualizando la maquina de estados de un nivel que ya no se va a
    # dibujar nunca mas.
    if ( @{ $self->{_levels} } > $self->{level_history_cap} ) {
        my $oldest = shift @{ $self->{_levels} };
        $self->{_pending_levels} = [ grep { $_ != $oldest } @{ $self->{_pending_levels} } ];
    }
    return;
}

# -----------------------------------------------------------------------------
# _update_state_machine — avanza el estado de CADA nivel PENDIENTE (no
# terminal) segun la vela actual. BSL se barre/rompe hacia ARRIBA, SSL se
# barre/rompe hacia ABAJO.
#
# BLOQUE PERF: antes se recorria @{ $self->{_levels} } completo (todo el
# historico) en cada vela. Ahora se recorre solo _pending_levels, y los
# niveles que llegan a un estado terminal (grab/run) se sacan de esa lista
# -> el costo por vela queda acotado a los niveles realmente abiertos.
# El array _levels no se toca (sigue completo, ahora topeado, para render/
# consulta).
# -----------------------------------------------------------------------------
sub _update_state_machine {
    my ( $self, $market_data, $i ) = @_;
    my $c = $market_data->get_candle($i);
    return unless $c;

    my @still_pending;

    for my $lvl ( @{ $self->{_pending_levels} } ) {
        my $is_bsl = ( $lvl->{type} eq 'BSL' );
        my $wick_breach  = $is_bsl ? ( $c->{high}  > $lvl->{price} ) : ( $c->{low}   < $lvl->{price} );
        my $close_beyond = $is_bsl ? ( $c->{close} > $lvl->{price} ) : ( $c->{close} < $lvl->{price} );
        my $close_back   = $is_bsl ? ( $c->{close} < $lvl->{price} ) : ( $c->{close} > $lvl->{price} );

        if ( $lvl->{status} eq 'active' ) {
            if ($wick_breach) {
                if ($close_beyond) {
                    $lvl->{status} = 'run'; $lvl->{resolved_type} = 'run'; $lvl->{resolved_index} = $i;
                } else {
                    $lvl->{status} = 'swept'; $lvl->{sweep_index} = $i;
                }
            }
        }
        elsif ( $lvl->{status} eq 'swept' ) {
            my $age = $i - $lvl->{sweep_index};
            if ($close_back) {
                $lvl->{status} = 'grab'; $lvl->{resolved_type} = 'grab'; $lvl->{resolved_index} = $i;
            }
            elsif ($close_beyond) {
                $lvl->{status} = 'run'; $lvl->{resolved_type} = 'run'; $lvl->{resolved_index} = $i;
            }
            elsif ( $age > $self->{reclaim_window} ) {
                # No se definio en la ventana de confirmacion -> grab debil (timeout)
                $lvl->{status} = 'grab'; $lvl->{resolved_type} = 'grab'; $lvl->{resolved_index} = $i;
            }
        }

        push @still_pending, $lvl
            unless $lvl->{status} eq 'grab' || $lvl->{status} eq 'run';
    }

    $self->{_pending_levels} = \@still_pending;
    return;
}

1;