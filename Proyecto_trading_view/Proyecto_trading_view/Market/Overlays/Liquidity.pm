package Market::Overlays::Liquidity;

# =============================================================================
# Market::Overlays::Liquidity
# Dibuja los niveles de liquidez (BSL/SSL) reflejando su estado actual
# (active/swept/grab/run). La visibilidad de cada estado se recalcula segun
# $replay_limit en cada render — por eso "evoluciona con el Replay": al
# retroceder/avanzar, un nivel puede volver a verse "active" en vez de
# "resuelto" si el evento de resolucion ocurrio despues del puntero actual.
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

sub render {
    my ( $self, $canvas, $liq, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('liq_all');
    return unless $liq && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;

    for my $lvl ( @{ $liq->get_levels } ) {
        next if $lvl->{start_index} > $limit;
        next if $lvl->{start_index} > $end;

        # --- Estado "tal como se veria" en el puntero actual de Replay ---
        my $status      = $lvl->{status};
        my $right_index = $limit;

        if ( $status =~ /^(grab|run)$/ && $lvl->{resolved_index} > $limit ) {
            $status = ( defined $lvl->{sweep_index} && $lvl->{sweep_index} <= $limit )
                ? 'swept' : 'active';
        }
        if ( $status eq 'swept' && defined $lvl->{sweep_index} && $lvl->{sweep_index} > $limit ) {
            $status = 'active';
        }
        if ( $status =~ /^(grab|run)$/ && $lvl->{resolved_index} <= $limit ) {
            $right_index = $lvl->{resolved_index};
        }

        next if $right_index < $start;

        my ( $color, $dash, $width, $suffix ) = $self->_style_for_status( $lvl->{type}, $status );

        my $left_idx  = $lvl->{start_index} < $start ? $start : $lvl->{start_index};
        my $right_idx = $right_index > $end ? $end : $right_index;

        my $x1 = $scale->index_to_center_x($left_idx);
        my $x2 = $scale->index_to_center_x($right_idx);
        my $y  = $scale->value_to_y( $lvl->{price} );

        $canvas->createLine(
            $x1, $y, $x2, $y,
            -fill  => $color,
            -width => $width,
            -dash  => $dash,
            -tags  => [ 'liq_all', 'liq_level' ],
        );
        $canvas->createText(
            $x2 - 4, $y - 7,
            -text   => $lvl->{type} . $suffix,
            -fill   => $color,
            -font   => 'Helvetica 7 bold',
            -anchor => 'e',
            -tags   => [ 'liq_all', 'liq_label' ],
        );
    }
    return;
}

# -----------------------------------------------------------------------------
# _style_for_status — color/estilo segun el estado de la maquina de estados.
# active=gris punteado | swept=naranja | grab=verde (manipulacion confirmada,
# señal de reversion) | run=color base solido (continuacion real)
# -----------------------------------------------------------------------------
sub _style_for_status {
    my ( $self, $type, $status ) = @_;
    my $base = ( $type eq 'BSL' )
        ? ( $self->{theme}{liq_bsl} // '#fa451c' )
        : ( $self->{theme}{liq_ssl} // '#1ce4fa' );

    return ( $base,      [ 2, 2 ], 1, '' )         if $status eq 'active';
    return ( '#ffb74d',  [ 4, 2 ], 2, ' (swept)' ) if $status eq 'swept';
    return ( '#26a69a',  undef,    2, ' (grab)'  ) if $status eq 'grab';
    return ( $base,      undef,    2, ' (run)'   ) if $status eq 'run';
    return ( $base,      [ 2, 2 ], 1, '' );
}

1;