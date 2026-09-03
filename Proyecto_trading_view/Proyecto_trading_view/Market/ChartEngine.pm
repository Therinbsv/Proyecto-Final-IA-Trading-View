package Market::ChartEngine;

use strict;
use warnings;
use POSIX qw(floor);
use Market::Panels::Scales;

use constant {
    MIN_BARS       => 2,
    MAX_BARS       => 800,
    DEFAULT_BARS   => 120,
    PRICE_SCALE_W  => 90,
    TIME_AXIS_H    => 24,
    DRAG_THRESHOLD => 3,
    Y_ZOOM_MIN     => 0.10,
    Y_ZOOM_MAX     => 3.00,
};

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        %args,

        visible_bars => DEFAULT_BARS,
        offset       => 0,

        zoom_y_auto   => 1,
        y_range_price => undef,

        zoom_y_auto_atr => 1,
        y_range_atr     => undef,

        _render_pending    => 0,
        _crosshair_pending => 0,

        _drag_start_x => undef,
        _drag_start_y => undef,
        _drag_offset  => undef,
        _drag_moved   => 0,
        _drag_panel   => undef,

        _drag_y_start     => undef,
        _drag_y_start_atr => undef,

        _mouse_x        => -1,
        _mouse_y        => -1,
        _mouse_y_atr    => -1,
        _mouse_in_price => 0,
        _mouse_in_atr   => 0,

        _scale_price => undef,
        _scale_atr   => undef,

        _price_cross => undef,
        _atr_cross   => undef,

        _ctrl_pressed    => 0,
        _zoom_anchor_idx => undef,
        _zoom_anchor_px  => undef,

        _free_mode_price => 0,
        _free_mode_atr   => 0,

        # Callbacks para sincronizar botones de toolbar con estado interno
        _cb_mode_price => undef,
        _cb_mode_atr   => undef,

        # Drag en regleta Y
        _scale_drag_panel   => undef,
        _scale_drag_start_y => undef,

        # Flag para ignorar <Configure> durante resize manual del separador
        _resizing_panels => 0,
        # Replay mode
        replay_active       => 0,
        replay_limit_index  => undef,
        # --- BLOQUE REPLAY: estado extendido para Play/Pause/Step/FF/Exit ---
        _awaiting_replay_cut  => 0,
        _cb_replay_cut_state  => undef,
        replay_playing      => 0,
        replay_timer_id     => undef,
        replay_fast         => 0,
        replay_speed_normal => 1000,   # ms entre velas en modo normal
        replay_speed_fast   => 150,    # ms entre velas en modo rápido
        # =====================================================================
        # BLOQUE VISIBILIDAD: todos los overlays arrancan APAGADOS (0) para
        # que la carga inicial sea rapida (antes arrancaban todos prendidos
        # y el primer render tenia que dibujar TODO de una vez). El calculo
        # de cada indicador (rebuild_all) sigue corriendo igual al iniciar;
        # solo se pospone el DIBUJO hasta que el usuario prenda cada boton
        # de la toolbar. Los botones en market.pl reflejan este estado
        # inicial (texto "OFF" / color apagado) para no desincronizar la UI.
        # =====================================================================
        _smc_visible    => 0,
        _cb_smc_visible => undef,

        # =====================================================================
        # BLOQUE FIBONACCI CLICK-TO-ANCHOR (REEMPLAZA el comportamiento
        # anterior). Antes, "Fibonacci: ON" dibujaba automaticamente un
        # retroceso basado en el swing high/low mas reciente (get_fib_range
        # del indicador SMC), sin que el usuario eligiera nada. Ahora
        # funciona como la herramienta real "Fib Retracement" de
        # TradingView, pero con el segundo punto AUTOMATICO: el usuario
        # elige (con un clic) un pivote del ZigZag Ex como ancla (punto 1,
        # 100%), y el programa detecta solo el pivote ADYACENTE de ese
        # mismo ZigZag Ex (el siguiente en la secuencia, o el anterior si
        # el ancla es el ultimo pivote) como punto 0 -- sin necesidad de un
        # segundo clic. Mismo mecanismo de "modo elegir" que VWAP/AVP
        # (begin_vwap_anchor_selection/begin_avp_anchor_selection), pero el
        # snapping es a PIVOTES DEL ZIGZAG EX, no a cualquier vela.
        # =====================================================================
        _awaiting_fib_anchor => 0,
        _fib_point1          => undef,   # {index,price} -- el pivote elegido por el usuario (ancla, nivel "1" / 100%)
        _fib_point2          => undef,   # {index,price} -- el pivote adyacente detectado automaticamente (nivel "0")
        _fib_width_index     => undef,   # indice del pivote del MISMO tipo que el ancla (LL->LL o HH->HH), define hasta donde llegan las lineas horizontales
        _cb_fib_anchor_state => undef,

        _bos_visible    => 0,
        _cb_bos_visible => undef,

        _choch_visible    => 0,
        _cb_choch_visible => undef,

        _ibos_visible    => 0,
        _cb_ibos_visible => undef,

        _ichoch_visible    => 0,
        _cb_ichoch_visible => undef,

        # --- BLOQUE ZIGZAG: reemplaza al antiguo "Estructura (Etiquetas
        # HH/HL/LH/LL)" (render_structure_labels), retirado por duplicar
        # visualmente las etiquetas del zigzag existente. Estos dos son
        # los zigzag nuevos (ChartPrime / ZZMTF), independientes entre si
        # y del zigzag de SMC_Structures (render_swings, sin tocar). ---
        _zz_a_visible    => 0,
        _cb_zz_a_visible => undef,

        _zz_b_visible    => 0,
        _cb_zz_b_visible => undef,

        # --- VWAP anclado con bandas de desviacion estandar ---
        _vwap_visible    => 0,
        _cb_vwap_visible => undef,
        # --- BLOQUE ANCLA POR CLIC (VWAP) — reemplaza al viejo desplegable
        # de meses. Al presionar el boton "VWAP" estando apagado, entra en
        # modo "elige una vela" (igual mecanismo que "Inicio Replay"): el
        # cursor cambia a cruz, aparece una linea que sigue al mouse con
        # snapping a la vela mas cercana, y el proximo clic en el grafico
        # fija el ancla ahi mismo y prende el VWAP. ---
        _awaiting_vwap_anchor => 0,
        _vwap_anchor_ts       => undef,   # timestamp de la vela anclada (para reubicar tras cambio de TF)
        _cb_vwap_anchor_state => undef,   # callback: se llama con (1) al entrar en modo seleccion, (0) al salir

        # --- AVP (Perfil de Volumen Anclado) ---
        _avp_visible    => 0,
        _cb_avp_visible => undef,
        # --- BLOQUE ANCLA POR CLIC (AVP) — mismo mecanismo que el VWAP arriba. ---
        _awaiting_avp_anchor => 0,
        _avp_anchor_ts       => undef,
        _cb_avp_anchor_state => undef,

        # --- BLOQUE RESOLUCION ZIGZAG INTERNO (desplegable "ZigZag In:
        # resolucion", igual concepto que "ZigZag Resolution" del ZZMTF de
        # referencia). Cambiar la resolucion dispara un recalculo COMPLETO
        # del indicador SMC (no solo los pivotes macro), ya que ese
        # indicador entrelaza todo en un unico update_at_index. ---
        _zigzag_in_ref_min => 30,   # debe calzar con el "ref_tf_min" inicial pasado en market.pl
        _cb_zigzag_in_res  => undef,

        _fvg_visible    => 0,
        _cb_fvg_visible => undef,

        _eq_visible    => 0,
        _cb_eq_visible => undef,

        _swing_visible    => 0,
        _cb_swing_visible => undef,

        _liq_visible    => 0,
        _cb_liq_visible => undef,

        _ob_visible    => 0,
        _cb_ob_visible => undef,

        # [NOTA UNIFICACION] _trail_visible / toggle_trail_visibility /
        # set_trail_visibility_callback se mantienen sin uso activo desde
        # market.pl (el boton separado de "Strong/Weak H-L" se elimino a
        # pedido del usuario), pero se dejan aqui intactos por si algo mas
        # los necesita en el futuro. El render de Strong/Weak H-L
        # (render_trailing, mas abajo en render()) ahora se dispara con
        # _ob_visible directamente, NO con _trail_visible -- asi Order
        # Blocks y Strong/Weak H-L quedan unidos en un solo interruptor.
        _trail_visible    => 0,
        _cb_trail_visible => undef,

        # --- BLOQUE SUPPLY/DEMAND ZONES (NUEVO): puerto fiel de "DIY Custom
        # Strategy Builder [ZP] - v1". El calculo vive en
        # Market::Indicators::Strategy_Builder (_update_supply_demand);
        # este flag SOLO controla si render_supply_demand se invoca o no.
        # Arranca apagado, igual que el resto. ---
        _sd_visible    => 0,
        _cb_sd_visible => undef,

        # --- BLOQUE GHOST VWAP (NUEVO): puerto de "Dynamic Swing Anchored
        # VWAP by Josafa". El calculo vive en
        # Market::Indicators::Strategy_Builder (_update_ghost_swing /
        # _update_ghost_vwap_value); este flag SOLO controla si
        # render_ghost_vwap se invoca o no. Arranca apagado. ---
        _ghost_visible    => 0,
        _cb_ghost_visible => undef,

        # --- VWAP auto-anclado al penultimo pivote (NUEVO, punto 4 del
        # enunciado) — mismo patron que Ghost: solo controla visibilidad,
        # el calculo corre siempre en Strategy_Builder (get_pph_vwap_series). ---
        _pph_vwap_visible    => 0,
        _cb_pph_vwap_visible => undef,

        # --- BLOQUE CANAL/TENDLINE (NUEVO, grupo 11 del enunciado) ---
        _channel_visible    => 0,
        _cb_channel_visible => undef,
    };
    bless $self, $class;
    $self->bind_events;
    return $self;
}

# -----------------------------------------------------------------------------
# set_mode_callbacks
# Registra funciones que se llaman cuando cambia el modo precio/ATR.
# Permite sincronizar los botones de la toolbar con el estado interno.
# $cb_price y $cb_atr reciben (1) si quedó en manual, (0) si quedó en auto.
# -----------------------------------------------------------------------------
sub set_mode_callbacks {
    my ( $self, $cb_price, $cb_atr ) = @_;
    $self->{_cb_mode_price} = $cb_price;
    $self->{_cb_mode_atr}   = $cb_atr;
}

# -----------------------------------------------------------------------------
# _notify_mode_price / _notify_mode_atr  (privados)
# Disparan el callback si está registrado.
# -----------------------------------------------------------------------------
sub _notify_mode_price {
    my ( $self, $is_free ) = @_;
    $self->{_cb_mode_price}->($is_free) if $self->{_cb_mode_price};
}

sub _notify_mode_atr {
    my ( $self, $is_free ) = @_;
    $self->{_cb_mode_atr}->($is_free) if $self->{_cb_mode_atr};
}

# -----------------------------------------------------------------------------
# resize_panels — llamado desde market.pl al arrastrar el separador ATR
# -----------------------------------------------------------------------------
sub resize_panels {
    my ( $self, $new_w, $new_ph, $new_ah ) = @_;
    return if $new_w <= 1 || $new_ph <= 1 || $new_ah <= 1;

    $self->{_resizing_panels} = 1;
    $self->{canvas_w}         = $new_w;
    $self->{canvas_price_h}   = $new_ph;
    $self->{canvas_atr_h}     = $new_ah;

    $self->{canvas_price}->configure(
        -scrollregion => [ 0, 0, $new_w, $new_ph ] );
    $self->{canvas_atr}->configure(
        -scrollregion => [ 0, 0, $new_w, $new_ah ] );

    $self->request_render;
    $self->{canvas_price}->after( 50, sub { $self->{_resizing_panels} = 0 } );
}

# -----------------------------------------------------------------------------
# toggle_free_mode_price / toggle_free_mode_atr
# -----------------------------------------------------------------------------
sub toggle_free_mode_price {
    my ($self) = @_;
    $self->{_free_mode_price} = $self->{_free_mode_price} ? 0 : 1;

    if ( $self->{_free_mode_price} ) {
        if ( !$self->{y_range_price} && $self->{_scale_price} ) {
            my ( $s, $e ) = $self->compute_window;
            my ( $mn, $mx ) = $self->{price_panel}
                ->get_y_range( $self->{market}->get_slice( $s, $e ) );
            $self->{y_range_price} = [ $mn, $mx ];
        }
        $self->{zoom_y_auto} = 0;
    } else {
        $self->{zoom_y_auto}   = 1;
        $self->{y_range_price} = undef;
        $self->request_render;
    }
    $self->_notify_mode_price( $self->{_free_mode_price} );
    return $self->{_free_mode_price};
}

sub toggle_free_mode_atr {
    my ($self) = @_;
    $self->{_free_mode_atr} = $self->{_free_mode_atr} ? 0 : 1;

    if ( $self->{_free_mode_atr} ) {
        if ( !$self->{y_range_atr} && $self->{_scale_atr} ) {
            my ( $s, $e ) = $self->compute_window;
            my ( $mn, $mx ) = $self->{atr_panel}->get_y_range(
                $self->{indicators}->slice_array( 'atr', $s, $e ) );
            $self->{y_range_atr} = [ $mn, $mx ];
        }
        $self->{zoom_y_auto_atr} = 0;
    } else {
        $self->{zoom_y_auto_atr} = 1;
        $self->{y_range_atr}     = undef;
        $self->request_render;
    }
    $self->_notify_mode_atr( $self->{_free_mode_atr} );
    return $self->{_free_mode_atr};
}

# -----------------------------------------------------------------------------
# compute_window
# -----------------------------------------------------------------------------
sub compute_window {
    my ($self) = @_;
    my $total = $self->{market}->size;

    # --- BLOQUE REPLAY: limitar el total efectivo al puntero de Replay ---
    # Todo lo que dependa de compute_window (render, auto-zoom Y, ATR slice,
    # crosshair info) queda automáticamente protegido de mostrar velas futuras.
    if ( $self->{replay_active} && defined $self->{replay_limit_index} ) {
        my $replay_total = $self->{replay_limit_index} + 1;
        $total = $replay_total if $replay_total < $total;
    }
    # --- FIN BLOQUE REPLAY ---

    return ( 0, 0 ) unless $total > 0;

    my $bars         = $self->{visible_bars};
    my $edge_visible = 2;
    my $min_offset   = -( $bars - $edge_visible );
    my $max_offset   = $total - $edge_visible;

    $self->{offset} = $min_offset if $self->{offset} < $min_offset;
    $self->{offset} = $max_offset if $self->{offset} > $max_offset;

    my $end = $self->{offset} + $bars - 1;

    # --- BLOQUE REPLAY: nunca devolver un end más allá del total efectivo ---
    $end = $total - 1 if $end > $total - 1;
    # --- FIN BLOQUE REPLAY ---

    return ( $self->{offset}, $end );
}

sub round {
    my ( $self, $value, $dec ) = @_;
    $dec //= 2;
    return sprintf( "%.${dec}f", $value ) + 0;
}

sub request_render {
    my ($self) = @_;
    return if $self->{_render_pending};
    $self->{_render_pending} = 1;
    $self->{canvas_price}->after( 1, sub {
        $self->{_render_pending} = 0;
        $self->render;
    });
}

sub _request_crosshair_draw {
    my ($self) = @_;
    return if $self->{_crosshair_pending};
    $self->{_crosshair_pending} = 1;
    $self->{canvas_price}->after( 1, sub {
        $self->{_crosshair_pending} = 0;
        $self->_draw_crosshair_all;
    });
}

# -----------------------------------------------------------------------------
# render
# -----------------------------------------------------------------------------
sub render {
    my ($self) = @_;

    return if $self->{market}->size == 0;
    my ( $start, $end ) = $self->compute_window;
    my $total = $self->{market}->size;

    my $canv_w  = $self->{canvas_price}->width;
    my $canv_ph = $self->{canvas_price}->height;
    my $canv_ah = $self->{canvas_atr}->height;
    $canv_w  = $self->{canvas_w}       if $canv_w  <= 1;
    $canv_ph = $self->{canvas_price_h} if $canv_ph <= 1;
    $canv_ah = $self->{canvas_atr_h}   if $canv_ah <= 1;
    $self->{canvas_w}       = $canv_w;
    $self->{canvas_price_h} = $canv_ph;
    $self->{canvas_atr_h}   = $canv_ah;

    my $safe_start = $start < 0     ? 0        : $start;
    my $safe_end   = $end >= $total ? $total-1 : $end;
    $safe_end = $safe_start if $safe_end < $safe_start;

    my $visible_candles = $self->{market}->get_slice( $safe_start, $safe_end );
    my $visible_atr     = $self->{indicators}->slice_array( 'atr', $start, $end );

    my ( $min_p, $max_p );
    if ( $self->{zoom_y_auto} && !$self->{_free_mode_price} ) {
        ( $min_p, $max_p ) = $self->{price_panel}->get_y_range($visible_candles);

        # [MEJORA] Si el VWAP esta activo, expandir el rango automatico
        # para que las 5 lineas completas (no solo las velas) queden
        # dentro de la vista. Sin esto, cuando la banda de desviacion
        # estandar se ensancha mas que el rango de precio de las velas
        # visibles (esperable con un ancla lejana en el tiempo), la banda
        # simplemente se corta fuera de pantalla en vez de que el auto-
        # zoom se aleje para mostrarla completa — no hay forma de "hacer
        # menos zoom" manualmente porque el auto-zoom la vuelve a recortar
        # en cada render. Solo aplica en modo automatico: si el usuario ya
        # fijo un rango manual (Modo Manual / y_range_price), se respeta
        # su eleccion tal cual, sin forzar a incluir el VWAP.
        if ( $self->{_vwap_visible} ) {
            my ( $vmin, $vmax ) = $self->_vwap_y_range( $safe_start, $safe_end );
            if ( defined $vmin && defined $vmax ) {
                $min_p = $vmin if $vmin < $min_p;
                $max_p = $vmax if $vmax > $max_p;
            }
        }

        # [MEJORA] Mismo criterio que el VWAP arriba, para el AVP: como
        # ahora ancla a TODO el historico, su recuadro/histograma abarca
        # el rango de precio COMPLETO alguna vez operado (que puede ser
        # mucho mas alto que el rango de las velas actualmente visibles) —
        # sin esto, el perfil se corta arriba/abajo en vez de que el auto-
        # zoom se aleje para mostrarlo entero.
        if ( $self->{_avp_visible} ) {
            my ( $amin, $amax ) = $self->_avp_y_range();
            if ( defined $amin && defined $amax ) {
                $min_p = $amin if $amin < $min_p;
                $max_p = $amax if $amax > $max_p;
            }
        }
    } elsif ( $self->{y_range_price} ) {
        ( $min_p, $max_p ) = @{ $self->{y_range_price} };
    } else {
        ( $min_p, $max_p ) = $self->{price_panel}->get_y_range($visible_candles);
    }
    my $last_visible = $visible_candles->[-1];

    # Escala de Precio (SIN visual_offset)
    my $scale_price = Market::Panels::Scales->new(
        canvas_w      => $canv_w,
        canvas_h      => $canv_ph,
        price_scale_w => PRICE_SCALE_W,
        visible_bars  => $self->{visible_bars},
        offset        => $start,
        min_val       => $min_p,
        max_val       => $max_p,
        padding_top   => 10,
        padding_bot   => TIME_AXIS_H,
        last_close    => $last_visible ? $last_visible->{close} : undef,
    );
    $self->{price_panel}->set_scale($scale_price);
    $self->{_scale_price} = $scale_price;

    my ( $min_a, $max_a );
    if ( $self->{zoom_y_auto_atr} && !$self->{_free_mode_atr} ) {
        ( $min_a, $max_a ) = $self->{atr_panel}->get_y_range($visible_atr);
    } elsif ( $self->{y_range_atr} ) {
        ( $min_a, $max_a ) = @{ $self->{y_range_atr} };
    } else {
        ( $min_a, $max_a ) = $self->{atr_panel}->get_y_range($visible_atr);
    }
    my $last_atr_val;
    for my $v ( reverse @$visible_atr ) {
        if ( defined $v ) { $last_atr_val = $v; last; }
    }

    # Escala de ATR (SIN visual_offset)
    my $scale_atr = Market::Panels::Scales->new(
        canvas_w      => $canv_w,
        canvas_h      => $canv_ah,
        price_scale_w => PRICE_SCALE_W,
        visible_bars  => $self->{visible_bars},
        offset        => $start,
        min_val       => $min_a,
        max_val       => $max_a,
        padding_top   => 14,
        padding_bot   => 6,
        last_atr_val  => $last_atr_val,
    );
    $self->{atr_panel}->set_scale($scale_atr);
    $self->{_scale_atr} = $scale_atr;

    $self->{canvas_price}->delete('price_bg');
    $self->{canvas_price}->delete('candle');
    $self->{canvas_price}->delete('scale_bg');
    $self->{canvas_price}->delete('scale_border');
    $self->{canvas_price}->delete('scale_grid');
    $self->{canvas_price}->delete('scale_label');
    $self->{canvas_price}->delete('last_price');
    $self->{canvas_price}->delete('time_axis');

    $self->{price_panel}->render( $self->{canvas_price}, $visible_candles, $scale_price );

    # --- BLOQUE SMC: estructuras (micro) + swings (macro), independientes ---
    if ( $self->{smc_overlay} ) {
        my $smc = $self->{indicators}->get_indicator('smc');
        if ($smc) {
            # FIX (lineas desaparecen al retroceder el scroll): antes, fuera
            # de replay, $replay_limit se igualaba a $end (el borde derecho
            # de la ventana VISIBLE) en vez del verdadero ultimo indice del
            # dataset. Como $limit se usa para filtrar que pivotes/segmentos
            # son "causalmente validos" (no solo visibles), esto hacia que
            # CUALQUIER pivote mas alla del borde visible actual quedara
            # excluido -- aunque no fuera dato futuro en absoluto (fuera de
            # replay, TODO el dataset ya es conocido). Al hacer scroll hacia
            # atras (ver velas viejas), el ultimo pivote confirmado -y el
            # tramo que lo conecta con el anterior- caia fuera de ese
            # "limite" artificial y desaparecia por completo, aunque una
            # parte de ese tramo deberia verse (recortado) en la ventana
            # visible. Ahora, fuera de replay, el limite causal es el
            # ultimo indice real de los datos -- sin restriccion ligada al
            # scroll. El recorte a lo que se VE en pantalla lo sigue
            # haciendo cada funcion de render por separado (via $start/$end).
            my $replay_limit = ( $self->{replay_active} && defined $self->{replay_limit_index} )
                ? $self->{replay_limit_index} : $self->{market}->last_index;

            if ( $self->{_smc_visible} && $self->{_fib_point1} && $self->{_fib_point2} ) {
                $self->{smc_overlay}->render_fibonacci(
                    $self->{canvas_price}, $scale_price, $safe_start, $safe_end, $replay_limit,
                    $self->{_fib_point1}, $self->{_fib_point2}, $self->{_fib_width_index} );
            } else {
                $self->{canvas_price}->delete('smc_fib_all');
            }

            if ( $self->{_bos_visible} ) {
                $self->{smc_overlay}->render_bos(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('smc_bos_all');
            }

            if ( $self->{_choch_visible} ) {
                $self->{smc_overlay}->render_choch(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('smc_choch_all');
            }

            if ( $self->{_ibos_visible} ) {
                $self->{smc_overlay}->render_ibos(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('smc_ibos_all');
            }

            if ( $self->{_ichoch_visible} ) {
                $self->{smc_overlay}->render_ichoch(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('smc_ichoch_all');
            }

            if ( $self->{_fvg_visible} ) {
                $self->{smc_overlay}->render_fvgs(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('smc_fvg_all');
            }

            # --- BLOQUE CANAL/TENDLINE (NUEVO, grupo 11) ---
            if ( $self->{_channel_visible} && $self->{smc_overlay}->can('render_channel') ) {
                $self->{smc_overlay}->render_channel(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('smc_channel_all');
            }

            if ( $self->{_eq_visible} ) {
                $self->{smc_overlay}->render_eq(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('smc_eq_all');
            }

            if ( $self->{_swing_visible} ) {
    
                my $now_index = ( $self->{replay_active} && defined $self->{replay_limit_index} )
                    ? $self->{replay_limit_index}
                    : $self->{market}->last_index;


                $self->{smc_overlay}->render_swings(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit, $self->{market}, $now_index );
            } else {
                $self->{canvas_price}->delete('smc_swing_all');
            }

            if ( $self->{_ob_visible} ) {
                $self->{smc_overlay}->render_order_blocks(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('smc_ob_all');
            }

            # [UNIFICADO] Strong/Weak H-L ahora se dibuja bajo LA MISMA
            # condicion que Order Blocks (_ob_visible), no bajo su propio
            # flag (_trail_visible, que ya no se activa desde ningun boton
            # de la toolbar -- ver market.pl). Asi ambos aparecen y
            # desaparecen siempre juntos con un unico interruptor.
            if ( $self->{_ob_visible} ) {
                $self->{smc_overlay}->render_trailing(
                    $self->{canvas_price}, $smc, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('smc_trail_all');
            }
        }
    }
        

    # --- BLOQUE ZIGZAG (nuevo, independiente de SMC): ChartPrime + ZZMTF ---
    if ( $self->{strategy_overlay} ) {
        my $sb = $self->{indicators}->get_indicator('zigzags');
        if ($sb) {
            # Mismo FIX que el bloque SMC: fuera de replay, el limite causal
            # debe ser el ultimo indice real del dataset, no el borde visible.
            my $replay_limit = ( $self->{replay_active} && defined $self->{replay_limit_index} )
                ? $self->{replay_limit_index} : $self->{market}->last_index;
                
            my $smc_ind = $self->{indicators}->get_indicator('smc');
            # [FIX] render_trendlines dibuja las lineas diagonales verde/roja
            # discontinuas a partir de los MISMOS macro pivots de "ZigZag In"
            # (get_macro_pivots), pero antes se llamaba sin condicion alguna:
            # no revisaba _swing_visible ni borraba su tag ('sb_tl_all') al
            # apagar el boton, por eso las lineas seguian apareciendo con
            # "ZigZag In: OFF". Ahora sigue el mismo flag que render_swings.
            if ( $self->{_swing_visible} ) {
                $self->{strategy_overlay}->render_trendlines(
                    $self->{canvas_price}, $smc_ind, $scale_price, $safe_start, $safe_end, $replay_limit
                );
            } else {
                $self->{canvas_price}->delete('sb_tl_all');
            }

            # --- ZigZag A ---
            if ( $self->{_zz_a_visible} ) {
                $self->{strategy_overlay}->render_zigzag_a(
                    $self->{canvas_price}, $sb, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('zz_a_all');
            }

            # --- MTF Levels (antes "ZigZag B" / "ZigZag MTF") ---
            # [CAMBIO] Este boton ya no dibuja el ZigZag B (ese calculo,
            # render_zigzag_b, sigue existiendo en Strategy_Builder.pm por
            # si se necesita a futuro, pero ya no se llama desde aqui). El
            # usuario pidio que el boton muestre/oculte las etiquetas
            # HH/HL/LH/LL de la estructura SWING (las mismas 50 velas que ya
            # usan BOS/CHoCH), igual que "Show Swing Point Labels" del Pine
            # SMC Pro [Neon] de LuxAlgo. El tag de canvas ('zz_b_all') y el
            # flag interno (_zz_b_visible) se mantienen sin cambios para no
            # tener que tocar mas codigo del necesario.
            if ( $self->{_zz_b_visible} ) {
                $self->{smc_overlay}->render_swing_labels(
                    $self->{canvas_price}, $smc_ind, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('zz_b_all');
            }

            # --- VWAP anclado (con bandas de desviacion estandar) ---
            if ( $self->{_vwap_visible} ) {
                $self->{strategy_overlay}->render_vwap(
                    $self->{canvas_price}, $sb, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('vwap_all');
            }

            # --- AVP (Perfil de Volumen Anclado) ---
            if ( $self->{_avp_visible} ) {
                $self->{strategy_overlay}->render_avp(
                    $self->{canvas_price}, $sb, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('avp_all');
            }

            # --- Supply / Demand Zones (NUEVO) ---
            if ( $self->{_sd_visible} ) {
                $self->{strategy_overlay}->render_supply_demand(
                    $self->{canvas_price}, $sb, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('sb_sd_all');
            }

            # --- Ghost (REEMPLAZADO): antes llamaba directo a
            # render_ghost_vwap (el Ghost VWAP viejo) -- por eso el cambio
            # de Ghost nunca se notaba, siempre corria el codigo viejo sin
            # importar que se editara el overlay. Ahora llama a
            # render_ghost_pph (Pivot Points HL & Missed Reversal Levels). ---
            if ( $self->{_ghost_visible} ) {
                $self->{strategy_overlay}->render_ghost_pph(
                    $self->{canvas_price}, $sb, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('ghost_all');
            }

            # --- VWAP auto-anclado al penultimo pivote (NUEVO, punto 4) ---
            if ( $self->{_pph_vwap_visible} ) {
                $self->{strategy_overlay}->render_pph_vwap_auto(
                    $self->{canvas_price}, $sb, $scale_price, $safe_start, $safe_end, $replay_limit );
            } else {
                $self->{canvas_price}->delete('pph_vwap_all');
            }
        }
    }

    # --- BLOQUE LIQUIDITY ---
    if ( $self->{liquidity_overlay} && $self->{_liq_visible} ) {
        my $liq = $self->{indicators}->get_indicator('liq');
        if ($liq) {
            # Mismo FIX que los bloques anteriores.
            my $replay_limit = ( $self->{replay_active} && defined $self->{replay_limit_index} )
                ? $self->{replay_limit_index} : $self->{market}->last_index;
            $self->{liquidity_overlay}->render(
                $self->{canvas_price}, $liq, $scale_price, $safe_start, $safe_end, $replay_limit );
        }
    } elsif ( $self->{liquidity_overlay} ) {
        $self->{canvas_price}->delete('liq_all');
    }
    # --- FIN BLOQUES ---

    # --- BLOQUE SWING STRUCTURE: overlay HH/HL/LH/LL + zigzag ---
    if ( $self->{swing_overlay} && $self->{_swing_visible} ) {
        my $swing = $self->{indicators}->get_indicator('swing');
        if ($swing) {
            # Mismo FIX que los bloques anteriores.
            my $replay_limit = ( $self->{replay_active} && defined $self->{replay_limit_index} )
                ? $self->{replay_limit_index}
                : $self->{market}->last_index;
            $self->{swing_overlay}->render(
                $self->{canvas_price}, $swing, $scale_price, $safe_start, $safe_end, $replay_limit
            );
        }
    }
    # --- FIN BLOQUE SWING STRUCTURE ---

    # =========================================================================
    # BLOQUE Z-ORDER (FIX: overlays se tapaban entre si) — cada overlay que
    # necesita quedar detras de las velas (VWAP, AVP, Supply/Demand, Order
    # Blocks, FVG) hace su PROPIO lower(tag,'candle') dentro de su propia
    # funcion de render. El problema: el orden RELATIVO entre esos overlays
    # (cual queda mas "encima" de los demas, aunque todos esten detras de
    # las velas) dependia de cual se hubiera dibujado mas recientemente, no
    # de un criterio deliberado -- y como ninguno de estos rellenos tiene
    # transparencia real (Tk::Canvas no la soporta, solo un color pre-
    # mezclado con el fondo), el que quedaba mas arriba de ese grupo tapaba
    # por completo a los demas. Esto hacia que el FVG (el primero en
    # dibujarse en la secuencia de render) terminara escondido detras del
    # VWAP/AVP (dibujados despues), por ejemplo.
    #
    # Se fija aqui, al final de CADA render, un orden EXPLICITO (de mas al
    # fondo a menos): AVP -> VWAP -> Supply/Demand -> Order Blocks -> FVG.
    # Cada lower() posterior empuja a los anteriores mas hacia el fondo,
    # asi que llamando en este orden el FVG termina siendo el mas visible
    # de este grupo (justo debajo de las velas), y las velas siguen por
    # encima de todo. Solo se llama para los overlays que esten realmente
    # visibles (evita operar sobre tags vacios).
    #
    # [FIX] AVP y VWAP estaban en el orden contrario (VWAP primero, AVP
    # despues): como AVP se lowereaba DESPUES, quedaba encima del VWAP y
    # la franja verde desaparecia por completo cuando ambos estaban
    # activos a la vez. Se invierte: ahora VWAP se lowerea despues de AVP,
    # asi la franja verde queda visible por encima del perfil de volumen.
    # =========================================================================
    eval {
        my $cp = $self->{canvas_price};
        $cp->lower( 'avp_box',        'candle' ) if $self->{_avp_visible};
        $cp->lower( 'avp_bar',        'candle' ) if $self->{_avp_visible};
        $cp->lower( 'vwap_zone',      'candle' ) if $self->{_vwap_visible};
        $cp->lower( 'ghost_vwap_zone','candle' ) if $self->{_ghost_visible};
        $cp->lower( 'sb_sd_all',      'candle' ) if $self->{_sd_visible};
        $cp->lower( 'smc_ob_all',     'candle' ) if $self->{_ob_visible};
        $cp->lower( 'smc_fvg_all',    'candle' ) if $self->{_fvg_visible};
    };

    $self->{price_panel}->render_last_visible_price( $self->{canvas_price} );
    
    my $anchors = $self->compute_intraday_labels( $start, $end );
    $self->{price_panel}->draw_time_axis( $self->{canvas_price}, $anchors );
    $self->{price_panel}->_init_crosshair_objects;

    $self->{canvas_atr}->delete('atr_all');
    $self->{canvas_atr}->delete('scale_bg');
    $self->{canvas_atr}->delete('scale_border');
    $self->{canvas_atr}->delete('scale_grid');
    $self->{canvas_atr}->delete('scale_label');

    $self->{atr_panel}->render( $self->{canvas_atr}, $visible_atr, $scale_atr );
    $self->{atr_panel}->render_last_visible_value( $self->{canvas_atr} );
    $self->{atr_panel}->_init_crosshair;

    $self->_draw_crosshair_all;
}

# -----------------------------------------------------------------------------
# bind_events
# -----------------------------------------------------------------------------
sub bind_events {
    my ($self) = @_;

    my $cp = $self->{canvas_price};
    my $ca = $self->{canvas_atr};

    $cp->configure( -takefocus => 1 );
    $ca->configure( -takefocus => 1 );

    my $toplevel = $cp->toplevel;

    # =========================================================================
    # hit_test: 'price'|'price_scale'|'atr'|'atr_scale'|undef
    # =========================================================================
    my $hit_test = sub {
        my ( $abs_x, $abs_y ) = @_;

        my $cpx = $cp->rootx; my $cpy = $cp->rooty;
        my $cpw = $cp->width; my $cph = $cp->height;
        if (   $abs_x >= $cpx && $abs_x < $cpx + $cpw
            && $abs_y >= $cpy && $abs_y < $cpy + $cph )
        {
            my $lx = $abs_x - $cpx;
            my $ly = $abs_y - $cpy;
            return ( $lx >= $cpw - PRICE_SCALE_W )
                ? ( 'price_scale', $lx, $ly )
                : ( 'price',       $lx, $ly );
        }

        my $cax = $ca->rootx; my $cay = $ca->rooty;
        my $caw = $ca->width; my $cah = $ca->height;
        if (   $abs_x >= $cax && $abs_x < $cax + $caw
            && $abs_y >= $cay && $abs_y < $cay + $cah )
        {
            my $lx = $abs_x - $cax;
            my $ly = $abs_y - $cay;
            return ( $lx >= $caw - PRICE_SCALE_W )
                ? ( 'atr_scale', $lx, $ly )
                : ( 'atr',       $lx, $ly );
        }

        return ( undef, 0, 0 );
    };

    # =========================================================================
    # CTRL press/release
    # =========================================================================
    for my $key (qw(Control_L Control_R)) {
        $toplevel->bind( "<KeyPress-$key>", sub {
            return if $self->{_ctrl_pressed};
            $self->{_ctrl_pressed} = 1;
            return unless $self->{_scale_price} && $self->{_mouse_x} >= 0;
            my $idx = $self->{_scale_price}->x_to_index( $self->{_mouse_x} );
            $self->{_zoom_anchor_idx} = $idx;
            $self->{_zoom_anchor_px}  = $self->{_mouse_x};
        });
        $toplevel->bind( "<KeyRelease-$key>", sub {
            $self->{_ctrl_pressed}    = 0;
            $self->{_zoom_anchor_idx} = undef;
            $self->{_zoom_anchor_px}  = undef;
        });
    }

    # =========================================================================
    # FOCUSOUT / FocusOut a nivel toplevel:
    # Si el usuario hace Alt+Tab o cambia de ventana mientras CTRL esta
    # presionado, el KeyRelease nunca llega y el crosshair queda congelado.
    # Reseteamos _ctrl_pressed al perder el foco para evitar ese bloqueo.
    # =========================================================================
    $toplevel->bind( '<FocusOut>', sub {
        if ( $self->{_ctrl_pressed} ) {
            $self->{_ctrl_pressed}    = 0;
            $self->{_zoom_anchor_idx} = undef;
            $self->{_zoom_anchor_px}  = undef;
        }
        # Tambien forzamos un redibujado del crosshair para que no quede
        # el _crosshair_pending atascado en 1 por una llamada after huerfana.
        $self->{_crosshair_pending} = 0;
    });

    # =========================================================================
    # RUEDA
    # =========================================================================
    $toplevel->bind( '<Button-4>', sub {
        my $state = $_[0]->XEvent->s;
        my $ctrl  = ( $state & 4 ) ? 1 : 0;
        my $shift = ( $state & 1 ) ? 1 : 0;

        if ($shift) {
            $self->_vertical_zoom_price(0.9) if $self->{_mouse_in_price};
            $self->_vertical_zoom_atr(0.9)   if $self->{_mouse_in_atr};
        } else {
            if ( $ctrl && !defined $self->{_zoom_anchor_idx}
                && $self->{_scale_price} && $self->{_mouse_x} >= 0 )
            {
                my $idx = $self->{_scale_price}->x_to_index( $self->{_mouse_x} );
                $self->{_ctrl_pressed}    = 1;
                $self->{_zoom_anchor_idx} = $idx;
                $self->{_zoom_anchor_px}  = $self->{_mouse_x};
            }
            $self->_horizontal_zoom( -1, $ctrl );
        }
        Tk->break;
    });

    $toplevel->bind( '<Button-5>', sub {
        my $state = $_[0]->XEvent->s;
        my $ctrl  = ( $state & 4 ) ? 1 : 0;
        my $shift = ( $state & 1 ) ? 1 : 0;

        if ($shift) {
            $self->_vertical_zoom_price(1.1) if $self->{_mouse_in_price};
            $self->_vertical_zoom_atr(1.1)   if $self->{_mouse_in_atr};
        } else {
            if ( $ctrl && !defined $self->{_zoom_anchor_idx}
                && $self->{_scale_price} && $self->{_mouse_x} >= 0 )
            {
                my $idx = $self->{_scale_price}->x_to_index( $self->{_mouse_x} );
                $self->{_ctrl_pressed}    = 1;
                $self->{_zoom_anchor_idx} = $idx;
                $self->{_zoom_anchor_px}  = $self->{_mouse_x};
            }
            $self->_horizontal_zoom( 1, $ctrl );
        }
        Tk->break;
    });

    # =========================================================================
    # MOTION
    # En modo manual NO congelamos el mouse — el crosshair sigue al cursor.
    # En modo CTRL el anchor de zoom se congela pero el crosshair se sigue
    # moviendo (igual que TradingView).
    # =========================================================================
    $toplevel->bind( '<Motion>', sub {
        my $ev = $_[0]->XEvent;
        my ( $panel, $lx, $ly ) = $hit_test->( $ev->X, $ev->Y );

        if ( $self->{_awaiting_replay_cut} ) {
            if ( defined $panel && $panel eq 'price' && $self->{_scale_price} ) {
                my $idx    = $self->{_scale_price}->x_to_index($lx);
                my $snap_x = $self->{_scale_price}->index_to_center_x($idx);
                $self->_draw_replay_cut_line($snap_x);
            }
            return;
        }

        # --- BLOQUE FIBONACCI (click-to-anchor): a diferencia de VWAP/AVP,
        # NO se pega a cualquier vela -- se pega al PIVOTE mas cercano del
        # ZigZag Ex, para que el usuario siempre ancle sobre un punto real
        # de la estructura. ---
        if ( $self->{_awaiting_fib_anchor} ) {
            if ( defined $panel && $panel eq 'price' && $self->{_scale_price} ) {
                my $idx = $self->{_scale_price}->x_to_index($lx);
                my ( $pivot_pos, $pivots ) = $self->_find_nearest_zigzag_pivot($idx);
                if ( defined $pivot_pos ) {
                    my $snap_x = $self->{_scale_price}->index_to_center_x( $pivots->[$pivot_pos]{index} );
                    $self->_draw_anchor_pick_line($snap_x);
                }
            }
            return;
        }

        # --- BLOQUE ANCLA POR CLIC (VWAP/AVP): mismo snapping que el
        # corte de Replay, pero con su propio color/tag para no
        # confundirse visualmente con la linea de Replay. ---
        if ( $self->{_awaiting_vwap_anchor} || $self->{_awaiting_avp_anchor} ) {
            if ( defined $panel && $panel eq 'price' && $self->{_scale_price} ) {
                my $idx    = $self->{_scale_price}->x_to_index($lx);
                my $snap_x = $self->{_scale_price}->index_to_center_x($idx);
                $self->_draw_anchor_pick_line($snap_x);
            }
            return;
        }

        unless ( defined $panel ) {
            if ( $self->{_mouse_in_price} || $self->{_mouse_in_atr} ) {
                $self->{_mouse_in_price} = 0;
                $self->{_mouse_in_atr}   = 0;
                $self->{price_panel}->hide_crosshair;
                $self->{atr_panel}->hide_crosshair;
            }
            return;
        }

        if ( $panel eq 'price' ) {
            $self->{_mouse_in_price} = 1;
            $self->{_mouse_in_atr}   = 0;
            $self->{_mouse_x}        = $lx;
            $self->{_mouse_y}        = $ly;
        } elsif ( $panel eq 'atr' || $panel eq 'atr_scale' ) {
            $self->{_mouse_in_atr}   = 1;
            $self->{_mouse_in_price} = 0;
            $self->{_mouse_x}        = $lx;
            $self->{_mouse_y_atr}    = $ly;
        }
        $self->_request_crosshair_draw;
    });

    # =========================================================================
    # BUTTONPRESS-1
    # =========================================================================
    $toplevel->bind( '<ButtonPress-1>', sub {
        my $ev = $_[0]->XEvent;
        my ( $panel, $lx, $ly ) = $hit_test->( $ev->X, $ev->Y );
        return unless defined $panel;

        if ( $self->{_awaiting_replay_cut} ) {
            if ( $panel eq 'price' && $self->{_scale_price} ) {
                my $idx = $self->{_scale_price}->x_to_index($lx);
                $self->iniciar_modo_replay($idx);
            }
            return;
        }

        # --- BLOQUE FIBONACCI (click-to-anchor) ---
        if ( $self->{_awaiting_fib_anchor} ) {
            if ( $panel eq 'price' && $self->{_scale_price} ) {
                my $idx = $self->{_scale_price}->x_to_index($lx);
                $self->_cancel_fib_anchor_selection;
                $self->set_fib_anchor_index($idx);
            } else {
                $self->_cancel_fib_anchor_selection;
            }
            return;
        }

        # --- BLOQUE ANCLA POR CLIC (VWAP/AVP) ---
        if ( $self->{_awaiting_vwap_anchor} ) {
            if ( $panel eq 'price' && $self->{_scale_price} ) {
                my $idx = $self->{_scale_price}->x_to_index($lx);
                $self->_cancel_vwap_anchor_selection;
                $self->set_vwap_anchor_index($idx);
            } else {
                $self->_cancel_vwap_anchor_selection;
            }
            return;
        }
        if ( $self->{_awaiting_avp_anchor} ) {
            if ( $panel eq 'price' && $self->{_scale_price} ) {
                my $idx = $self->{_scale_price}->x_to_index($lx);
                $self->_cancel_avp_anchor_selection;
                $self->set_avp_anchor_index($idx);
            } else {
                $self->_cancel_avp_anchor_selection;
            }
            return;
        }

        # --- Drag en regleta Y de precios: activa modo manual precio ---
        if ( $panel eq 'price_scale' ) {
            unless ( $self->{y_range_price} ) {
                my ( $s, $e ) = $self->compute_window;
                my ( $mn, $mx ) = $self->{price_panel}
                    ->get_y_range( $self->{market}->get_slice( $s, $e ) );
                $self->{y_range_price} = [ $mn, $mx ];
            }
            $self->{zoom_y_auto}        = 0;
            $self->{_scale_drag_panel}  = 'price';
            $self->{_scale_drag_start_y} = $ly;
            # Activar modo manual si no estaba ya activo
            if ( !$self->{_free_mode_price} ) {
                $self->{_free_mode_price} = 1;
                $self->_notify_mode_price(1);
            }
            return;
        }

        # --- Drag en regleta Y del ATR: activa modo manual ATR ---
        if ( $panel eq 'atr_scale' ) {
            unless ( $self->{y_range_atr} ) {
                my ( $s, $e ) = $self->compute_window;
                my ( $mn, $mx ) = $self->{atr_panel}->get_y_range(
                    $self->{indicators}->slice_array( 'atr', $s, $e ) );
                $self->{y_range_atr} = [ $mn, $mx ];
            }
            $self->{zoom_y_auto_atr}     = 0;
            $self->{_scale_drag_panel}   = 'atr';
            $self->{_scale_drag_start_y} = $ly;
            # Activar modo manual si no estaba ya activo
            if ( !$self->{_free_mode_atr} ) {
                $self->{_free_mode_atr} = 1;
                $self->_notify_mode_atr(1);
            }
            return;
        }

        # --- Drag normal en el plot ---
        $self->{_mouse_in_price} = ( $panel eq 'price' ) ? 1 : 0;
        $self->{_mouse_in_atr}   = ( $panel eq 'atr'   ) ? 1 : 0;
        $self->{_drag_start_x}   = $lx;
        $self->{_drag_start_y}   = $ly;
        $self->{_drag_offset}    = $self->{offset};
        $self->{_drag_moved}     = 0;
        $self->{_drag_panel}     = $panel;

        if ( $self->{_free_mode_price} && $panel eq 'price'
            && !$self->{y_range_price} && $self->{_scale_price} )
        {
            my ( $s, $e ) = $self->compute_window;
            my ( $mn, $mx ) = $self->{price_panel}
                ->get_y_range( $self->{market}->get_slice( $s, $e ) );
            $self->{y_range_price} = [ $mn, $mx ];
            $self->{zoom_y_auto}   = 0;
        }

        if ( $self->{_free_mode_atr} && $panel eq 'atr'
            && !$self->{y_range_atr} && $self->{_scale_atr} )
        {
            my ( $s, $e ) = $self->compute_window;
            my ( $mn, $mx ) = $self->{atr_panel}->get_y_range(
                $self->{indicators}->slice_array( 'atr', $s, $e ) );
            $self->{y_range_atr}     = [ $mn, $mx ];
            $self->{zoom_y_auto_atr} = 0;
        }
    });

    # =========================================================================
    # B1-MOTION
    # =========================================================================
    $toplevel->bind( '<B1-Motion>', sub {
        my $ev = $_[0]->XEvent;

        # --- Drag activo en regleta Y ---
        if ( defined $self->{_scale_drag_panel} ) {
            my $drag_panel = $self->{_scale_drag_panel};
            my $cv  = ( $drag_panel eq 'price' ) ? $cp : $ca;
            my $ly  = $ev->Y - $cv->rooty;
            my $dy  = $ly - ( $self->{_scale_drag_start_y} // $ly );
            $self->{_scale_drag_start_y} = $ly;

            my $factor = 1.0 + $dy * 0.01;
            $factor = 0.02 if $factor < 0.02;
            $factor = 10.0 if $factor > 10.0;

            if ( $drag_panel eq 'price' && $self->{y_range_price} ) {
                my ( $mn, $mx ) = @{ $self->{y_range_price} };
                my $mid  = ( $mn + $mx ) / 2;
                my $half = ( $mx - $mn ) / 2 * $factor;
                my ( $new_mn, $new_mx ) =
                    $self->_clamp_price_range( $mid - $half, $mid + $half );
                $self->{y_range_price} = [ $new_mn, $new_mx ];
                $self->request_render;
            }
            elsif ( $drag_panel eq 'atr' && $self->{y_range_atr} ) {
                my ( $mn, $mx ) = @{ $self->{y_range_atr} };
                my $mid  = ( $mn + $mx ) / 2;
                my $half = ( $mx - $mn ) / 2 * $factor;
                my ( $new_mn, $new_mx ) =
                    $self->_clamp_atr_range( $mid - $half, $mid + $half );
                $self->{y_range_atr} = [ $new_mn, $new_mx ];
                $self->request_render;
            }
            return;
        }

        # --- Drag normal en el plot ---
        return unless $self->{_mouse_in_price} || $self->{_mouse_in_atr};

        my ( $panel, $lx, $ly ) = $hit_test->( $ev->X, $ev->Y );
        if ( !defined $panel ) {
            my $cv = ( $self->{_drag_panel} || 'price' ) eq 'price' ? $cp : $ca;
            $lx = $ev->X - $cv->rootx;
            $ly = $ev->Y - $cv->rooty;
        }

        my $dx = $lx - ( $self->{_drag_start_x} // $lx );
        my $dy = $ly - ( $self->{_drag_start_y} // $ly );

        $self->{_drag_moved} = 1
            if abs($dx) > DRAG_THRESHOLD || abs($dy) > DRAG_THRESHOLD;
        return unless $self->{_drag_moved};

        my $scale = $self->{_scale_price} // $self->{_scale_atr};
        if ( $scale && $self->{visible_bars} > 0 ) {
            my $bar_w = $scale->_plot_w / $self->{visible_bars};
            if ( $bar_w > 0 ) {
                $self->{offset} =
                    ( $self->{_drag_offset} // 0 ) - int( $dx / $bar_w );
            }
        }

        if ( $self->{_free_mode_price} && $self->{_mouse_in_price}
            && $self->{y_range_price} && abs($dy) > 0 )
        {
            my ( $mn, $mx ) = @{ $self->{y_range_price} };
            my $plot_h = $self->{canvas_price_h} - 10 - TIME_AXIS_H;
            if ( $plot_h > 0 ) {
                my $delta = $dy / $plot_h * ( $mx - $mn );
                $self->{y_range_price} = [ $mn + $delta, $mx + $delta ];
            }
        }

        if ( $self->{_free_mode_atr} && $self->{_mouse_in_atr}
            && $self->{y_range_atr} && abs($dy) > 0 )
        {
            my ( $mn, $mx ) = @{ $self->{y_range_atr} };
            my $plot_h = $self->{canvas_atr_h} - 14 - 6;
            if ( $plot_h > 0 ) {
                my $delta = $dy / $plot_h * ( $mx - $mn );
                $self->{y_range_atr} = [ $mn + $delta, $mx + $delta ];
            }
        }

        $self->{_drag_start_y} = $ly;
        $self->{_mouse_x}      = $lx;
        $self->request_render;
    });

    # =========================================================================
    # BUTTONRELEASE-1
    # =========================================================================
    $toplevel->bind( '<ButtonRelease-1>', sub {
        if ( defined $self->{_scale_drag_panel} ) {
            $self->{_scale_drag_panel}   = undef;
            $self->{_scale_drag_start_y} = undef;
            return;
        }

        my $ev = $_[0]->XEvent;
        my ( $panel, $lx, $ly ) = $hit_test->( $ev->X, $ev->Y );
        return unless defined $panel;
        return if $panel eq 'price_scale' || $panel eq 'atr_scale';

        my $dx = $lx - ( $self->{_drag_start_x} // $lx );
        my $dy = $ly - ( $self->{_drag_start_y} // $ly );

        return if $self->{_free_mode_price} && $panel eq 'price';
        return if $self->{_free_mode_atr}   && $panel eq 'atr';
        return if abs($dx) > DRAG_THRESHOLD || abs($dy) > DRAG_THRESHOLD;

    });

    # =========================================================================
    # DOBLE CLICK IZQUIERDO
    # Regleta Y -> restaurar autozoom + volver a modo Auto
    # Plot      -> borrar marca persistente
    # =========================================================================
    $toplevel->bind( '<Double-Button-1>', sub {
        my $ev = $_[0]->XEvent;
        my ($panel) = $hit_test->( $ev->X, $ev->Y );
        return unless defined $panel;

        if ( $panel eq 'price_scale' ) {
            $self->{zoom_y_auto}      = 1;
            $self->{y_range_price}    = undef;
            $self->{_free_mode_price} = 0;
            $self->_notify_mode_price(0);
            $self->request_render;
            return;
        }
        if ( $panel eq 'atr_scale' ) {
            $self->{zoom_y_auto_atr} = 1;
            $self->{y_range_atr}     = undef;
            $self->{_free_mode_atr}  = 0;
            $self->_notify_mode_atr(0);
            $self->request_render;
            return;
        }
        if ( $panel eq 'price' ) {
            $self->{_price_cross} = undef;
            $self->{canvas_price}->delete('price_cross');
        } elsif ( $panel eq 'atr' ) {
            $self->{_atr_cross} = undef;
            $self->{canvas_atr}->delete('atr_cross');
        }
    });

    # =========================================================================
    # ESC: borra AMBAS marcas persistentes
    # =========================================================================
    $toplevel->bind( '<Escape>', sub {
        $self->{_price_cross} = undef;
        $self->{_atr_cross}   = undef;
        $self->{canvas_price}->delete('price_cross');
        $self->{canvas_atr}->delete('atr_cross');
    });

    # =========================================================================
    # DRAG DERECHO: zoom/pan vertical en el plot
    # =========================================================================
    $toplevel->bind( '<ButtonPress-3>', sub {
        my $ev = $_[0]->XEvent;
        my ( $panel, $lx, $ly ) = $hit_test->( $ev->X, $ev->Y );
        return unless defined $panel;
        return if $panel eq 'price_scale' || $panel eq 'atr_scale';

        if ( $panel eq 'price' ) {
            $self->{_drag_y_start} = $ly;
            unless ( $self->{y_range_price} ) {
                my ( $s, $e ) = $self->compute_window;
                my ( $mn, $mx ) = $self->{price_panel}
                    ->get_y_range( $self->{market}->get_slice( $s, $e ) );
                $self->{y_range_price} = [ $mn, $mx ];
            }
            $self->{zoom_y_auto} = 0;
        } else {
            $self->{_drag_y_start_atr} = $ly;
            unless ( $self->{y_range_atr} ) {
                my ( $s, $e ) = $self->compute_window;
                my ( $mn, $mx ) = $self->{atr_panel}->get_y_range(
                    $self->{indicators}->slice_array( 'atr', $s, $e ) );
                $self->{y_range_atr} = [ $mn, $mx ];
            }
            $self->{zoom_y_auto_atr} = 0;
        }
    });

    $toplevel->bind( '<B3-Motion>', sub {
        my $ev = $_[0]->XEvent;
        my ( $panel, $lx, $ly ) = $hit_test->( $ev->X, $ev->Y );

        if ( !defined $panel || $panel eq 'price_scale' || $panel eq 'atr_scale' ) {
            my $cv = ( $self->{_drag_panel} || 'price' ) eq 'price' ? $cp : $ca;
            $ly    = $ev->Y - $cv->rooty;
            $panel = $self->{_drag_panel} || 'price';
        }

        if ( $panel eq 'price' ) {
            my $dy = $ly - ( $self->{_drag_y_start} // $ly );
            $self->{_drag_y_start} = $ly;
            $self->_vertical_drag($dy);
        } else {
            my $dy = $ly - ( $self->{_drag_y_start_atr} // $ly );
            $self->{_drag_y_start_atr} = $ly;
            $self->_vertical_drag_atr($dy);
        }
    });

    $toplevel->bind( '<Double-Button-3>', sub {
        my $ev = $_[0]->XEvent;
        my ($panel) = $hit_test->( $ev->X, $ev->Y );
        return unless defined $panel;
        if ( $panel eq 'price' || $panel eq 'price_scale' ) {
            $self->{zoom_y_auto}   = 1;
            $self->{y_range_price} = undef;
        } else {
            $self->{zoom_y_auto_atr} = 1;
            $self->{y_range_atr}     = undef;
        }
        $self->request_render;
    });

    # =========================================================================
    # RESIZE — ignorar si estamos en resize manual del separador
    # =========================================================================
    $toplevel->bind( '<Configure>', sub {
        return if $self->{_resizing_panels};

        my $new_w  = $self->{canvas_price}->width;
        my $new_h  = $self->{canvas_price}->height;
        my $new_ah = $self->{canvas_atr}->height;

        return if $new_w  <= 1 || $new_h <= 1;
        return if $new_w  == $self->{canvas_w}
               && $new_h  == $self->{canvas_price_h}
               && $new_ah == $self->{canvas_atr_h};

        $self->{canvas_w}       = $new_w;
        $self->{canvas_price_h} = $new_h;
        $self->{canvas_atr_h}   = $new_ah;
        $self->{canvas_price}->configure(
            -scrollregion => [ 0, 0, $new_w, $new_h ] );
        $self->{canvas_atr}->configure(
            -scrollregion => [ 0, 0, $new_w, $new_ah ] );
        $self->request_render;
    });
}

# -----------------------------------------------------------------------------
# _horizontal_zoom
# FIX: Agregada validacion para romper el bucle infinito cuando el redondeo
# de enteros atasca el factor de escala al llegar a MIN_BARS o al alejar.
# -----------------------------------------------------------------------------
sub _horizontal_zoom {
    my ( $self, $dir, $use_anchor ) = @_;
    my $old = $self->{visible_bars};
    
    my $new;
    if ( $dir > 0 ) {
        $new = int( $old * 1.15 );
        $new++ if $new == $old; # Fuerza el salto si el redondeo lo estanca
    } else {
        $new = int( $old / 1.15 );
        $new-- if $new == $old; # Fuerza el salto si el redondeo lo estanca
    }

    $new = MIN_BARS if $new < MIN_BARS;
    $new = MAX_BARS if $new > MAX_BARS;
    return if $new == $old;

    if ( $use_anchor && defined $self->{_zoom_anchor_idx} && $self->{_scale_price} ) {
        my $anchor_idx = $self->{_zoom_anchor_idx};
        my $anchor_px  = $self->{_zoom_anchor_px};
        my $bar_w_new  = $self->{_scale_price}->_plot_w / $new;
        $self->{visible_bars} = $new;
        $self->{offset} = $anchor_idx - int( $anchor_px / $bar_w_new );
    } else {
        my $anchor = $self->{offset} + $old - 1;
        $self->{visible_bars} = $new;
        $self->{offset}       = $anchor - ( $new - 1 );
    }

    $self->request_render;
}

# -----------------------------------------------------------------------------
# _clamp_price_range
# -----------------------------------------------------------------------------
sub _clamp_price_range {
    my ( $self, $new_mn, $new_mx ) = @_;
    my $range = $new_mx - $new_mn;
    return ( $new_mn, $new_mx ) if $range <= 0;

    my ( $s, $e ) = $self->compute_window;
    my $vis = $self->{market}->get_slice( $s, $e );
    return ( $new_mn, $new_mx ) unless $vis && @$vis;

    my $data_max = $vis->[0]{high};
    my $data_min = $vis->[0]{low};
    for my $c (@$vis) {
        $data_max = $c->{high} if $c->{high} > $data_max;
        $data_min = $c->{low}  if $c->{low}  < $data_min;
    }
    my $data_range = $data_max - $data_min;
    $data_range = 1 if $data_range < 1;
    my $margin = $data_range * 0.10;

    my $max_range = $data_range * Y_ZOOM_MAX;
    if ( $range > $max_range ) {
        my $center = ( $new_mn + $new_mx ) / 2;
        $range  = $max_range;
        $new_mn = $center - $range / 2;
        $new_mx = $center + $range / 2;
    }

    my $min_range = $data_range * Y_ZOOM_MIN;
    if ( $range < $min_range ) {
        my $center = ( $new_mn + $new_mx ) / 2;
        $range  = $min_range;
        $new_mn = $center - $range / 2;
        $new_mx = $center + $range / 2;
    }

    if ( $new_mx < $data_min + $margin ) {
        $new_mx = $data_min + $margin;
        $new_mn = $new_mx - $range;
    }
    if ( $new_mn > $data_max - $margin ) {
        $new_mn = $data_max - $margin;
        $new_mx = $new_mn + $range;
    }

    return ( $new_mn, $new_mx );
}

# -----------------------------------------------------------------------------
# _clamp_atr_range
# -----------------------------------------------------------------------------
sub _clamp_atr_range {
    my ( $self, $new_mn, $new_mx ) = @_;
    my $range = $new_mx - $new_mn;
    return ( $new_mn, $new_mx ) if $range <= 0;

    my ( $s, $e ) = $self->compute_window;
    my $vis_atr = $self->{indicators}->slice_array( 'atr', $s, $e );
    my @valid   = grep { defined $_ } @$vis_atr;
    return ( $new_mn, $new_mx ) unless @valid;

    my $data_max   = $valid[0];
    for my $v (@valid) { $data_max = $v if $v > $data_max; }
    my $data_range = $data_max < 0.1 ? 0.1 : $data_max;
    my $margin     = $data_range * 0.5;

    my $max_range = $data_range * Y_ZOOM_MAX;
    if ( $range > $max_range ) {
        my $center = ( $new_mn + $new_mx ) / 2;
        $range  = $max_range;
        $new_mn = $center - $range / 2;
        $new_mx = $center + $range / 2;
    }

    my $min_range = $data_range * Y_ZOOM_MIN;
    if ( $range < $min_range ) {
        my $center = ( $new_mn + $new_mx ) / 2;
        $range  = $min_range;
        $new_mn = $center - $range / 2;
        $new_mx = $center + $range / 2;
    }

    if ( $new_mn < 0 ) {
        $new_mx -= $new_mn;
        $new_mn = 0;
    }

    if ( $new_mx > $data_max + $margin && $range >= $max_range ) {
        $new_mx = $data_max + $margin;
        $new_mn = $new_mx - $range;
        $new_mn = 0 if $new_mn < 0;
    }
    return ( $new_mn, $new_mx );
}

sub _format_time_for_axis {
    my ($iso) = @_;
    return '' unless defined $iso;
    if ( $iso =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/ ) {
        return sprintf( '%s/%s %s:%s', $3, $2, $4, $5 );
    }
    return $iso;
}

sub _vertical_drag {
    my ( $self, $dy ) = @_;
    return unless $self->{y_range_price};
    my ( $mn, $mx ) = @{ $self->{y_range_price} };
    my $plot_h = $self->{canvas_price_h} - 10 - TIME_AXIS_H;
    return if $plot_h <= 0;
    my $factor = 1.0 - ( $dy / $plot_h );
    $factor = 0.05 if $factor < 0.05;
    $factor = 5.0  if $factor > 5.0;
    my $mid  = ( $mn + $mx ) / 2;
    my $half = ( $mx - $mn ) / 2 * $factor;
    my ( $new_mn, $new_mx ) = $self->_clamp_price_range( $mid - $half, $mid + $half );
    $self->{y_range_price} = [ $new_mn, $new_mx ];
    $self->request_render;
}

sub _vertical_drag_atr {
    my ( $self, $dy ) = @_;
    return unless $self->{y_range_atr};
    my ( $mn, $mx ) = @{ $self->{y_range_atr} };
    my $plot_h = $self->{canvas_atr_h};
    return if $plot_h <= 0;
    my $factor = 1.0 - ( $dy / $plot_h );
    $factor = 0.05 if $factor < 0.05;
    $factor = 5.0  if $factor > 5.0;
    my $mid  = ( $mn + $mx ) / 2;
    my $half = ( $mx - $mn ) / 2 * $factor;
    my ( $new_mn, $new_mx ) = $self->_clamp_atr_range( $mid - $half, $mid + $half );
    $self->{y_range_atr} = [ $new_mn, $new_mx ];
    $self->request_render;
}

sub _vertical_zoom_price {
    my ( $self, $factor ) = @_;
    $self->{zoom_y_auto} = 0;
    my ( $mn, $mx );
    if ( $self->{y_range_price} ) {
        ( $mn, $mx ) = @{ $self->{y_range_price} };
    } else {
        my ( $s, $e ) = $self->compute_window;
        ( $mn, $mx ) = $self->{price_panel}->get_y_range(
            $self->{market}->get_slice($s,$e) );
    }
    my $mid  = ( $mn + $mx ) / 2;
    my $half = ( $mx - $mn ) / 2 * $factor;
    my ( $new_mn, $new_mx ) = $self->_clamp_price_range( $mid - $half, $mid + $half );
    $self->{y_range_price} = [ $new_mn, $new_mx ];
    $self->request_render;
}

sub _vertical_zoom_atr {
    my ( $self, $factor ) = @_;
    $self->{zoom_y_auto_atr} = 0;
    my ( $mn, $mx );
    if ( $self->{y_range_atr} ) {
        ( $mn, $mx ) = @{ $self->{y_range_atr} };
    } else {
        my ( $s, $e ) = $self->compute_window;
        ( $mn, $mx ) = $self->{atr_panel}->get_y_range(
            $self->{indicators}->slice_array( 'atr', $s, $e ) );
    }
    my $mid  = ( $mn + $mx ) / 2;
    my $half = ( $mx - $mn ) / 2 * $factor;
    my ( $new_mn, $new_mx ) = $self->_clamp_atr_range( $mid - $half, $mid + $half );
    $self->{y_range_atr} = [ $new_mn, $new_mx ];
    $self->request_render;
}

# -----------------------------------------------------------------------------
# _draw_crosshair_all
# -----------------------------------------------------------------------------
sub _draw_crosshair_all {
    my ($self) = @_;

    my $x;
    if ( $self->{_ctrl_pressed} && defined $self->{_zoom_anchor_px} ) {
        $x = $self->{_zoom_anchor_px};
    } else {
        $x = $self->{_mouse_x};
    }

    my $y     = $self->{_mouse_y};
    my $y_atr = $self->{_mouse_y_atr};
    return if !defined $x || $x < 0;

my $candle_info;
    if ( $self->{_scale_price} ) {
        my $idx = $self->{_scale_price}->x_to_index($x);
        # --- BLOQUE REPLAY: nunca exponer info de una vela posterior al corte ---
        $idx = $self->_replay_visible_index($idx) if defined $idx;
        $candle_info = defined $idx ? $self->{market}->get_candle($idx) : undef;
        # --- FIN BLOQUE REPLAY ---
    }

    if ( $self->{_scale_price} && $self->{price_panel}{_cross_ready} ) {
        if ( $self->{_mouse_in_price} || $self->{_ctrl_pressed} ) {
            my $snap_idx = $self->{_scale_price}->x_to_index($x);
            my $snap_x   = ( $self->{_free_mode_price} || $self->{_ctrl_pressed} )
                ? $x
                : $self->{_scale_price}->index_to_center_x($snap_idx);
            $self->{price_panel}->draw_crosshair( $snap_x, $y, $candle_info );
        } elsif ( $self->{_mouse_in_atr} ) {
            my $snap_idx = $self->{_scale_price}->x_to_index($x);
            my $snap_x   = $self->{_scale_price}->index_to_center_x($snap_idx);
            $self->{price_panel}->show_vline_only($snap_x);
            
            if ($candle_info) {
                $self->{price_panel}->show_ohlcv_info($candle_info);
                $self->{price_panel}->draw_time_label($snap_x, $candle_info);
            }
        } else {
            $self->{price_panel}->hide_crosshair;
        }
    }

    if ( $self->{_scale_atr} && $self->{atr_panel}{_cross_ready} ) {
        if ( $self->{_mouse_in_atr} ) {
            my $snap_idx = $self->{_scale_atr}->x_to_index($x);
            my $snap_x   = $self->{_scale_atr}->index_to_center_x($snap_idx);
            $self->{atr_panel}->draw_crosshair( $snap_x, $y_atr );
        } elsif ( $self->{_mouse_in_price} || $self->{_ctrl_pressed} ) {
            my $snap_idx = $self->{_scale_atr}->x_to_index($x);
            my $snap_x   = $self->{_free_mode_atr}
                ? $x
                : $self->{_scale_atr}->index_to_center_x($snap_idx);
            $self->{atr_panel}->show_vline_only($snap_x);
        } else {
            $self->{atr_panel}->hide_crosshair;
        }
    }
}

sub set_timeframe {
    my ( $self, $tf ) = @_;
    $self->replay_exit if $self->{replay_active};
    
    $self->{market}->set_timeframe($tf);

    $self->{indicators}->reset_all;
    $self->{indicators}->rebuild_all( $self->{market} );

    # BLOQUE VWAP/AVP: reaplicar el ancla actual (por TIMESTAMP, no por
    # indice de vela -- los indices de una temporalidad NO equivalen a los
    # de otra, ej. el indice 500 en 1m no es la misma vela que el indice
    # 500 en 5m) tras el cambio de temporalidad. rebuild_all ya NO calcula
    # VWAP/AVP (se calculan aparte, bajo demanda) -- sin esto, quedarian
    # con los indices de la temporalidad VIEJA, desalineados con las velas
    # nuevas.
    my $sb = $self->{indicators}->get_indicator('zigzags');
    if ($sb) {
        if ( defined $self->{_vwap_anchor_ts} && $sb->can('recompute_vwap_from_index') ) {
            my $idx = $self->_find_index_for_ts( $self->{market}, $self->{_vwap_anchor_ts} );
            $sb->recompute_vwap_from_index( $self->{market}, $idx ) if defined $idx;
        }
        if ( defined $self->{_avp_anchor_ts} && $sb->can('recompute_avp_from_index') ) {
            my $idx = $self->_find_index_for_ts( $self->{market}, $self->{_avp_anchor_ts} );
            $sb->recompute_avp_from_index( $self->{market}, $idx ) if defined $idx;
        }
    }

    # BLOQUE FIBONACCI: el ancla se basa en pivotes del ZigZag Ex, que se
    # recalculan DESDE CERO en la temporalidad nueva (indices distintos,
    # sin relacion con los de la TF anterior). A diferencia de VWAP/AVP
    # (que se reubican por timestamp), aca simplemente se apaga y se
    # limpia -- el usuario vuelve a elegir el ancla si la quiere en la
    # nueva temporalidad.
    if ( $self->{_fib_point1} ) {
        $self->{_fib_point1}      = undef;
        $self->{_fib_point2}      = undef;
        $self->{_fib_width_index} = undef;
        $self->{_smc_visible}     = 0;
        $self->{_cb_smc_visible}->(0) if $self->{_cb_smc_visible};
    }

    $self->{_free_mode_price} = 0;
    $self->{_free_mode_atr}   = 0;
    $self->{zoom_y_auto}      = 1;
    $self->{y_range_price}    = undef;
    $self->{zoom_y_auto_atr}  = 1;
    $self->{y_range_atr}      = undef;

    $self->reset_view;
    $self->request_render;
}

# -----------------------------------------------------------------------------
# set_vwap_anchor_month — BLOQUE ANCLA VWAP (desplegable "Ancla VWAP").
# Recalcula el VWAP anclado desde el 1ro del mes elegido, SIN reiniciarse
# despues (acumula de corrido hasta la ultima vela cargada). Guarda el
# ancla elegida para poder reaplicarla si el usuario cambia de temporalidad
# (ver set_timeframe).
# -----------------------------------------------------------------------------
sub set_vwap_anchor_month {
    my ( $self, $year, $month ) = @_;
    $self->{_vwap_anchor_year}  = $year;
    $self->{_vwap_anchor_month} = $month;

    my $sb = $self->{indicators}->get_indicator('zigzags');
    if ( $sb && $sb->can('recompute_vwap') ) {
        $sb->recompute_vwap( $self->{market}, $year, $month );
    }

    $self->{_cb_vwap_anchor}->( $year, $month ) if $self->{_cb_vwap_anchor};
    $self->request_render;
    return;
}

sub set_vwap_anchor_callback { my ( $self, $cb ) = @_; $self->{_cb_vwap_anchor} = $cb; }

# -----------------------------------------------------------------------------
# set_avp_anchor_day — recalcula el AVP. [AJUSTE] Ya NO hay desplegable de
# dia: el AVP siempre ancla a TODO el historico cargado -- se llama con
# (undef,undef,undef), lo que recompute_avp interpreta como "indice 0". Se
# deja el parametro por si en el futuro se necesita anclar a un dia
# especifico de nuevo, pero market.pl ya no lo usa asi.
# -----------------------------------------------------------------------------
sub set_avp_anchor_day {
    my ( $self, $year, $month, $day ) = @_;
    $self->{_avp_anchor_year}  = $year;
    $self->{_avp_anchor_month} = $month;
    $self->{_avp_anchor_day}   = $day;
    $self->{_avp_initialized}  = 1;   # ya se llamo al menos una vez -> reaplicar tras cambios de TF

    my $sb = $self->{indicators}->get_indicator('zigzags');
    if ( $sb && $sb->can('recompute_avp') ) {
        $sb->recompute_avp( $self->{market}, $year, $month, $day );
    }

    $self->{_cb_avp_anchor}->( $year, $month, $day ) if $self->{_cb_avp_anchor};
    $self->request_render;
    return;
}

sub set_avp_anchor_callback { my ( $self, $cb ) = @_; $self->{_cb_avp_anchor} = $cb; }

# =============================================================================
# BLOQUE ANCLA POR CLIC — VWAP y AVP
# Reemplaza a los viejos desplegables ("Ancla VWAP: mes", "Ancla AVP: dia").
# Mismo mecanismo que "Inicio Replay" (begin_replay_selection /
# iniciar_modo_replay): al presionar el boton estando apagado, se activa
# el modo "elige una vela" -- cursor de cruz + linea que sigue al mouse con
# snapping -- y el proximo clic en el grafico fija el ancla ahi mismo.
# =============================================================================

sub begin_vwap_anchor_selection {
    my ($self) = @_;
    $self->{_awaiting_vwap_anchor} = 1;
    $self->{_awaiting_avp_anchor}  = 0;   # solo un modo de seleccion a la vez
    $self->{canvas_price}->configure( -cursor => 'crosshair' );
    $self->{_cb_vwap_anchor_state}->(1) if $self->{_cb_vwap_anchor_state};
    return;
}

sub begin_avp_anchor_selection {
    my ($self) = @_;
    $self->{_awaiting_avp_anchor}  = 1;
    $self->{_awaiting_vwap_anchor} = 0;
    $self->{canvas_price}->configure( -cursor => 'crosshair' );
    $self->{_cb_avp_anchor_state}->(1) if $self->{_cb_avp_anchor_state};
    return;
}

sub _cancel_vwap_anchor_selection {
    my ($self) = @_;
    $self->{_awaiting_vwap_anchor} = 0;
    $self->{canvas_price}->configure( -cursor => '' );
    $self->{canvas_price}->delete('anchor_pick_line');
    $self->{_cb_vwap_anchor_state}->(0) if $self->{_cb_vwap_anchor_state};
    return;
}

sub _cancel_avp_anchor_selection {
    my ($self) = @_;
    $self->{_awaiting_avp_anchor} = 0;
    $self->{canvas_price}->configure( -cursor => '' );
    $self->{canvas_price}->delete('anchor_pick_line');
    $self->{_cb_avp_anchor_state}->(0) if $self->{_cb_avp_anchor_state};
    return;
}

# -----------------------------------------------------------------------------
# set_vwap_anchor_index / set_avp_anchor_index — se llaman cuando el
# usuario hace clic durante el modo seleccion (ver bind_events). Guardan el
# TIMESTAMP de la vela elegida (no solo el indice) para poder reubicar el
# ancla si despues cambia de temporalidad (ver set_timeframe / callers de
# _find_index_for_ts), recalculan, prenden el overlay y piden un render.
# -----------------------------------------------------------------------------
sub set_vwap_anchor_index {
    my ( $self, $idx ) = @_;
    return unless defined $idx;

    my $sb = $self->{indicators}->get_indicator('zigzags');
    if ( $sb && $sb->can('recompute_vwap_from_index') ) {
        $sb->recompute_vwap_from_index( $self->{market}, $idx );
        my $c = $self->{market}->get_candle($idx);
        $self->{_vwap_anchor_ts} = $c ? $c->{ts} : undef;
    }

    $self->{_vwap_visible} = 1;
    $self->{_cb_vwap_visible}->(1) if $self->{_cb_vwap_visible};
    $self->request_render;
    return;
}

sub set_avp_anchor_index {
    my ( $self, $idx ) = @_;
    return unless defined $idx;

    my $sb = $self->{indicators}->get_indicator('zigzags');
    if ( $sb && $sb->can('recompute_avp_from_index') ) {
        $sb->recompute_avp_from_index( $self->{market}, $idx );
        my $c = $self->{market}->get_candle($idx);
        $self->{_avp_anchor_ts} = $c ? $c->{ts} : undef;
    }

    $self->{_avp_visible} = 1;
    $self->{_cb_avp_visible}->(1) if $self->{_cb_avp_visible};
    $self->request_render;
    return;
}

sub set_vwap_anchor_state_callback { my ( $self, $cb ) = @_; $self->{_cb_vwap_anchor_state} = $cb; }
sub set_avp_anchor_state_callback  { my ( $self, $cb ) = @_; $self->{_cb_avp_anchor_state}  = $cb; }

# =============================================================================
# BLOQUE FIBONACCI CLICK-TO-ANCHOR (NUEVO, reemplaza el comportamiento
# automatico anterior basado en get_fib_range del indicador SMC).
#
# Funciona como la herramienta "Fib Retracement" real de TradingView, pero
# con el 2do punto AUTOMATICO: el usuario elige un pivote del ZigZag Ex
# (get_zigzag_a del indicador 'zigzags') con un clic -- ese es el ancla,
# nivel "1" (100%) -- y el programa detecta el pivote ADYACENTE de esa
# misma secuencia (el siguiente cronologicamente; si el ancla es el ULTIMO
# pivote confirmado, usa el anterior) como el punto "0" (0%), sin
# necesidad de un segundo clic. Formula verificada contra capturas reales
# de TradingView: price(nivel) = price_0 + nivel*(price_1 - price_0), con
# price_0 = punto AUTO-DETECTADO y price_1 = punto ANCLA (el que el
# usuario elige).
# =============================================================================

sub begin_fib_anchor_selection {
    my ($self) = @_;
    $self->{_awaiting_fib_anchor}  = 1;
    $self->{_awaiting_vwap_anchor} = 0;   # solo un modo de seleccion a la vez
    $self->{_awaiting_avp_anchor}  = 0;
    $self->{canvas_price}->configure( -cursor => 'crosshair' );
    $self->{_cb_fib_anchor_state}->(1) if $self->{_cb_fib_anchor_state};
    return;
}

sub _cancel_fib_anchor_selection {
    my ($self) = @_;
    $self->{_awaiting_fib_anchor} = 0;
    $self->{canvas_price}->configure( -cursor => '' );
    $self->{canvas_price}->delete('anchor_pick_line');
    $self->{_cb_fib_anchor_state}->(0) if $self->{_cb_fib_anchor_state};
    return;
}

sub set_fib_anchor_state_callback { my ( $self, $cb ) = @_; $self->{_cb_fib_anchor_state} = $cb; }

sub is_smc_visible { my ($self) = @_; return $self->{_smc_visible} ? 1 : 0; }

# -----------------------------------------------------------------------------
# _find_nearest_zigzag_pivot — busca, dentro de los pivotes YA CONFIRMADOS
# del ZigZag Ex (get_zigzag_a), el mas cercano al indice de vela indicado
# (por distancia de INDICE, no de pixeles -- el llamador ya convierte
# pixeles a indice antes de invocar esto). Devuelve (posicion_en_el_array,
# arrayref_completo) para que el llamador pueda facilmente ubicar el
# pivote ADYACENTE (posicion+1 o posicion-1) sin tener que buscar de
# nuevo. Devuelve (undef, undef) si el ZigZag Ex no tiene ningun pivote
# confirmado todavia.
# -----------------------------------------------------------------------------
sub _find_nearest_zigzag_pivot {
    my ( $self, $target_idx ) = @_;
    my $sb = $self->{indicators}->get_indicator('zigzags');
    return ( undef, undef ) unless $sb && $sb->can('get_zigzag_a');

    my $pivots = $sb->get_zigzag_a;
    return ( undef, undef ) unless $pivots && @$pivots;

    my ( $best, $best_dist );
    for my $j ( 0 .. $#$pivots ) {
        my $dist = abs( $pivots->[$j]{index} - $target_idx );
        if ( !defined $best_dist || $dist < $best_dist ) {
            $best_dist = $dist;
            $best      = $j;
        }
    }
    return ( undef, undef ) unless defined $best;
    return ( $best, $pivots );
}

# -----------------------------------------------------------------------------
# set_fib_anchor_index — se llama cuando el usuario hace clic durante el
# modo seleccion (ver bind_events). Ancla el Fibonacci en el pivote del
# ZigZag Ex mas cercano al indice de vela clickeado, y detecta
# automaticamente el punto opuesto (el pivote ADYACENTE en la secuencia):
# preferentemente el SIGUIENTE (cronologicamente posterior, igual que en
# el ejemplo del usuario: ancla en un LOW, se conecta al HIGH que viene
# despues); si el ancla es el ULTIMO pivote confirmado (no hay "siguiente"
# todavia), usa el ANTERIOR en su lugar para que siempre haya con que
# completar el retroceso.
#
# [NUEVO] BLOQUE ANCHO — a pedido explicito del usuario: "el tamaño de la
# linea debe ir de LL a LL, o de HH a HH, dependiendo de cual sera el
# punto de anclaje". Es decir, el ANCHO (hasta donde se dibujan las
# lineas horizontales) NO es "hasta ahora" ni "toda la pantalla" -- es
# hasta el SIGUIENTE pivote del MISMO TIPO que el ancla, saltando el
# pivote intermedio (que es $target, el que ya define los niveles 0/1).
# Ejemplo: ancla en un LL -> $target es el HH siguiente -> el ancho llega
# hasta el PROXIMO LL despues de ese HH (dos pivotes mas alla del ancla).
# Si ese tercer pivote todavia no existe, el overlay usa "ahora" (limite
# de replay) como respaldo -- ver _render_fibonacci.
# -----------------------------------------------------------------------------
sub set_fib_anchor_index {
    my ( $self, $click_idx ) = @_;
    return unless defined $click_idx;

    my ( $pivot_pos, $pivots ) = $self->_find_nearest_zigzag_pivot($click_idx);
    return unless defined $pivot_pos;

    my $anchor = $pivots->[$pivot_pos];

    my $target_pos;
    if ( $pivot_pos < $#$pivots ) {
        $target_pos = $pivot_pos + 1;   # preferido: el siguiente en la secuencia
    } elsif ( $pivot_pos > 0 ) {
        $target_pos = $pivot_pos - 1;   # fallback: el ancla es el ultimo pivote confirmado
    }
    return unless defined $target_pos;

    my $target = $pivots->[$target_pos];

    # Tercer punto: mismo tipo que el ancla, un paso mas alla de $target
    # en la MISMA direccion (si $target esta a +1 del ancla, el tercero
    # esta a +2; si $target esta a -1, el tercero esta a -2).
    my $step      = $target_pos - $pivot_pos;
    my $third_pos = $target_pos + $step;

    my $width_index;
    if ( $third_pos >= 0 && $third_pos <= $#$pivots ) {
        $width_index = $pivots->[$third_pos]{index};
    }

    $self->{_fib_point1}      = { index => $anchor->{index}, price => $anchor->{price} };
    $self->{_fib_point2}      = { index => $target->{index}, price => $target->{price} };
    $self->{_fib_width_index} = $width_index;

    $self->{_smc_visible} = 1;
    $self->{_cb_smc_visible}->(1) if $self->{_cb_smc_visible};
    $self->request_render;
    return;
}

# -----------------------------------------------------------------------------
# _find_index_for_ts — busca el indice de la PRIMERA vela cuyo timestamp
# sea >= $target_ts en la temporalidad ACTUALMENTE activa de $market_data.
# Se usa para reubicar el ancla de VWAP/AVP tras un cambio de temporalidad
# (los indices de una temporalidad no son equivalentes a los de otra).
# Si $target_ts es posterior a toda la data cargada, devuelve el ultimo
# indice disponible (mejor aproximacion posible).
# -----------------------------------------------------------------------------
sub _find_index_for_ts {
    my ( $self, $market_data, $target_ts ) = @_;
    return undef unless defined $target_ts;
    my $last_idx = $market_data->last_index;
    return undef if $last_idx < 0;
    for my $i ( 0 .. $last_idx ) {
        my $c = $market_data->get_candle($i);
        next unless $c;
        return $i if $c->{ts} >= $target_ts;
    }
    return $last_idx;
}

# =============================================================================
# BLOQUE RESOLUCION ZIGZAG INTERNO — desplegable "ZigZag In: resolucion"
# (igual concepto que "ZigZag Resolution" del ZZMTF de referencia). Cambia
# el parametro ref_tf_min del indicador SMC y dispara un recalculo COMPLETO
# de ESE indicador (no de todos) -- SMC_Structures entrelaza BOS/CHOCH/FVG/
# EQH-EQL/Order Blocks/pivotes macro en un unico update_at_index, asi que
# no hay forma de recalcular solo los pivotes macro sin rehacer el resto.
# =============================================================================
sub set_zigzag_in_resolution {
    my ( $self, $minutes ) = @_;
    return unless defined $minutes && $minutes > 0;

    $self->{_zigzag_in_ref_min} = $minutes;

    my $smc = $self->{indicators}->get_indicator('smc');
    if ( $smc && $smc->can('set_ref_tf_min') ) {
        $smc->set_ref_tf_min($minutes);
        $smc->reset;
        for my $i ( 0 .. $self->{market}->size - 1 ) {
            $smc->update_at_index( $self->{market}, $i );
        }
    }

    $self->{_cb_zigzag_in_res}->($minutes) if $self->{_cb_zigzag_in_res};
    $self->request_render;
    return;
}

sub set_zigzag_in_resolution_callback { my ( $self, $cb ) = @_; $self->{_cb_zigzag_in_res} = $cb; }

# -----------------------------------------------------------------------------
# iniciar_modo_replay
# Activa el modo replay y guarda el índice límite seleccionado.
# -----------------------------------------------------------------------------
sub iniciar_modo_replay {
    my ( $self, $index ) = @_;

    $self->_cancel_replay_selection;

    # --- BLOQUE REPLAY: estado limpio (permite refijar el corte en caliente,
    # igual que TradingView, sin dejar un Play o Fast-Forward "fantasma") ---
    $self->replay_pause;
    $self->{replay_fast} = 0;
    # --- FIN BLOQUE REPLAY ---

    $self->{replay_limit_index} = $index;
    $self->{replay_active}      = 1;

    $self->request_render;
}

# -----------------------------------------------------------------------------
# set_replay_cut_callback — BLOQUE REPLAY
# Permite que market.pl sincronice el color del botón "Inicio Replay".
# -----------------------------------------------------------------------------
sub set_replay_cut_callback {
    my ( $self, $cb ) = @_;
    $self->{_cb_replay_cut_state} = $cb;
}

sub _notify_replay_cut_state {
    my ( $self, $is_active ) = @_;
    $self->{_cb_replay_cut_state}->($is_active) if $self->{_cb_replay_cut_state};
}

# -----------------------------------------------------------------------------
# begin_replay_selection — BLOQUE REPLAY
# Activador: NO modifica el gráfico, solo pone la interfaz "atenta" al
# próximo clic, habilitando la línea de corte con snapping.
# -----------------------------------------------------------------------------
sub begin_replay_selection {
    my ($self) = @_;
    $self->{_awaiting_replay_cut} = 1;
    $self->{canvas_price}->configure( -cursor => 'crosshair' );
    $self->_notify_replay_cut_state(1);
}

sub _cancel_replay_selection {
    my ($self) = @_;
    $self->{_awaiting_replay_cut} = 0;
    $self->{canvas_price}->configure( -cursor => '' );
    $self->{canvas_price}->delete('replay_cut_line');
    $self->_notify_replay_cut_state(0);
}

sub _draw_replay_cut_line {
    my ( $self, $snap_x ) = @_;
    $self->{canvas_price}->delete('replay_cut_line');
    return unless defined $snap_x;
    my $h = $self->{canvas_price}->height;
    $self->{canvas_price}->createLine(
        $snap_x, 0, $snap_x, $h,
        -fill  => '#2962ff',
        -width => 2,
        -tags  => 'replay_cut_line',
    );
    $self->{canvas_price}->raise('replay_cut_line');
}

# -----------------------------------------------------------------------------
# _draw_anchor_pick_line — BLOQUE ANCLA POR CLIC (VWAP/AVP). Misma idea que
# _draw_replay_cut_line (linea vertical que sigue al mouse con snapping a
# la vela mas cercana), con su propio color/tag para no confundirse
# visualmente con el corte de Replay.
# -----------------------------------------------------------------------------
sub _draw_anchor_pick_line {
    my ( $self, $snap_x ) = @_;
    $self->{canvas_price}->delete('anchor_pick_line');
    return unless defined $snap_x;
    my $h = $self->{canvas_price}->height;
    $self->{canvas_price}->createLine(
        $snap_x, 0, $snap_x, $h,
        -fill  => '#f7b500',
        -width => 2,
        -dash  => [ 4, 3 ],
        -tags  => 'anchor_pick_line',
    );
    $self->{canvas_price}->raise('anchor_pick_line');
}

# -----------------------------------------------------------------------------
# _replay_visible_index — BLOQUE REPLAY
# Devuelve $idx si es válido dentro del límite de Replay, o undef si cae
# en una vela posterior al punto de corte (vela "futura").
# -----------------------------------------------------------------------------
sub _replay_visible_index {
    my ( $self, $idx ) = @_;
    return $idx unless $self->{replay_active} && defined $self->{replay_limit_index};
    return undef if $idx > $self->{replay_limit_index};
    return $idx;
}

# -----------------------------------------------------------------------------
# replay_play — BLOQUE REPLAY
# Inicia el bucle automático de avance de velas.
# -----------------------------------------------------------------------------
sub replay_play {
    my ($self) = @_;
    return unless $self->{replay_active};
    return if $self->{replay_playing};

    $self->{replay_playing} = 1;
    $self->_replay_schedule_tick;
}

sub _replay_schedule_tick {
    my ($self) = @_;
    return unless $self->{replay_playing};

    my $interval = $self->{replay_fast}
        ? $self->{replay_speed_fast}
        : $self->{replay_speed_normal};

    $self->{replay_timer_id} = $self->{canvas_price}->after( $interval, sub {
        $self->_replay_tick;
    });
}

sub _replay_tick {
    my ($self) = @_;
    return unless $self->{replay_playing};

    my $max_index = $self->{market}->size - 1;
    if ( $self->{replay_limit_index} >= $max_index ) {
        $self->replay_pause;   # no quedan más velas
        return;
    }

    $self->{replay_limit_index}++;
    $self->request_render;
    $self->_replay_schedule_tick;
}

# -----------------------------------------------------------------------------
# replay_pause — BLOQUE REPLAY
# -----------------------------------------------------------------------------
sub replay_pause {
    my ($self) = @_;
    $self->{replay_playing} = 0;
    if ( defined $self->{replay_timer_id} ) {
        eval { $self->{replay_timer_id}->cancel };
        $self->{replay_timer_id} = undef;
    }
}

# -----------------------------------------------------------------------------
# replay_step_forward / replay_step_backward — BLOQUE REPLAY
# -----------------------------------------------------------------------------
sub replay_step_forward {
    my ($self) = @_;
    return unless $self->{replay_active};
    $self->replay_pause;

    my $max_index = $self->{market}->size - 1;
    return if $self->{replay_limit_index} >= $max_index;

    $self->{replay_limit_index}++;
    $self->request_render;
}

sub replay_step_backward {
    my ($self) = @_;
    return unless $self->{replay_active};
    $self->replay_pause;

    return if $self->{replay_limit_index} <= 0;

    $self->{replay_limit_index}--;
    $self->request_render;
}

# -----------------------------------------------------------------------------
# replay_toggle_fast_forward — BLOQUE REPLAY
# No cambia la lógica del Play, solo el intervalo del temporizador.
# -----------------------------------------------------------------------------
sub replay_toggle_fast_forward {
    my ($self) = @_;
    $self->{replay_fast} = $self->{replay_fast} ? 0 : 1;
    return $self->{replay_fast};
}

# -----------------------------------------------------------------------------
# replay_exit — BLOQUE REPLAY
# Destruye la simulación y devuelve el control al gráfico en tiempo real.
# -----------------------------------------------------------------------------
sub replay_exit {
    my ($self) = @_;
    $self->replay_pause;

    $self->{replay_active}      = 0;
    $self->{replay_limit_index} = undef;
    $self->{replay_fast}        = 0;

    $self->request_render;
}

# -----------------------------------------------------------------------------
# toggle_smc_visibility — BLOQUE FIBONACCI (antes "SMC"; ahora que BoS/CHoCH
# tienen su propio boton, este solo controla el Fibonacci automatico).
# -----------------------------------------------------------------------------
sub toggle_smc_visibility {
    my ($self) = @_;
    $self->{_smc_visible} = $self->{_smc_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_fib_all') unless $self->{_smc_visible};
    $self->{_cb_smc_visible}->( $self->{_smc_visible} ) if $self->{_cb_smc_visible};
    $self->request_render;
    return $self->{_smc_visible};
}

# -----------------------------------------------------------------------------
# toggle_bos_visibility / toggle_choch_visibility — BLOQUE ESTRUCTURA EXTERNA
# Independientes entre si: activar/desactivar uno no afecta al otro.
# -----------------------------------------------------------------------------
sub toggle_bos_visibility {
    my ($self) = @_;
    $self->{_bos_visible} = $self->{_bos_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_bos_all') unless $self->{_bos_visible};
    $self->{_cb_bos_visible}->( $self->{_bos_visible} ) if $self->{_cb_bos_visible};
    $self->request_render;
    return $self->{_bos_visible};
}

sub toggle_choch_visibility {
    my ($self) = @_;
    $self->{_choch_visible} = $self->{_choch_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_choch_all') unless $self->{_choch_visible};
    $self->{_cb_choch_visible}->( $self->{_choch_visible} ) if $self->{_cb_choch_visible};
    $self->request_render;
    return $self->{_choch_visible};
}

# -----------------------------------------------------------------------------
# toggle_ibos_visibility / toggle_ichoch_visibility — BLOQUE ESTRUCTURA INTERNA
# Mismo patron que BoS/CHoCH pero para I-BoS/I-CHoCH (sensibilidad menor).
# -----------------------------------------------------------------------------
sub toggle_ibos_visibility {
    my ($self) = @_;
    $self->{_ibos_visible} = $self->{_ibos_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_ibos_all') unless $self->{_ibos_visible};
    $self->{_cb_ibos_visible}->( $self->{_ibos_visible} ) if $self->{_cb_ibos_visible};
    $self->request_render;
    return $self->{_ibos_visible};
}

sub toggle_ichoch_visibility {
    my ($self) = @_;
    $self->{_ichoch_visible} = $self->{_ichoch_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_ichoch_all') unless $self->{_ichoch_visible};
    $self->{_cb_ichoch_visible}->( $self->{_ichoch_visible} ) if $self->{_cb_ichoch_visible};
    $self->request_render;
    return $self->{_ichoch_visible};
}

# -----------------------------------------------------------------------------
# toggle_zz_a_visibility / toggle_zz_b_visibility — BLOQUE ZIGZAG
# Reemplaza a toggle_ms_labels_visibility (retirado). zz_a = "ZigZag Volume
# Profile [ChartPrime]", zz_b = "ZigZag Multi Time Frame [ZZMTF]". Ambos
# independientes entre si y del zigzag existente (Swings/render_swings).
# -----------------------------------------------------------------------------
sub toggle_zz_a_visibility {
    my ($self) = @_;
    $self->{_zz_a_visible} = $self->{_zz_a_visible} ? 0 : 1;
    $self->{canvas_price}->delete('zz_a_all') unless $self->{_zz_a_visible};
    $self->{_cb_zz_a_visible}->( $self->{_zz_a_visible} ) if $self->{_cb_zz_a_visible};
    $self->request_render;
    return $self->{_zz_a_visible};
}

sub toggle_zz_b_visibility {
    my ($self) = @_;
    $self->{_zz_b_visible} = $self->{_zz_b_visible} ? 0 : 1;
    $self->{canvas_price}->delete('zz_b_all') unless $self->{_zz_b_visible};
    $self->{_cb_zz_b_visible}->( $self->{_zz_b_visible} ) if $self->{_cb_zz_b_visible};
    $self->request_render;
    return $self->{_zz_b_visible};
}

sub toggle_vwap_visibility {
    my ($self) = @_;
    $self->{_vwap_visible} = $self->{_vwap_visible} ? 0 : 1;
    $self->{canvas_price}->delete('vwap_all') unless $self->{_vwap_visible};
    $self->{_cb_vwap_visible}->( $self->{_vwap_visible} ) if $self->{_cb_vwap_visible};
    $self->request_render;
    return $self->{_vwap_visible};
}

sub is_vwap_visible { my ($self) = @_; return $self->{_vwap_visible} ? 1 : 0; }

sub toggle_avp_visibility {
    my ($self) = @_;
    $self->{_avp_visible} = $self->{_avp_visible} ? 0 : 1;
    $self->{canvas_price}->delete('avp_all') unless $self->{_avp_visible};
    $self->{_cb_avp_visible}->( $self->{_avp_visible} ) if $self->{_cb_avp_visible};
    $self->request_render;
    return $self->{_avp_visible};
}

sub is_avp_visible { my ($self) = @_; return $self->{_avp_visible} ? 1 : 0; }

# -----------------------------------------------------------------------------
# toggle_fvg_visibility — BLOQUE FVG
# -----------------------------------------------------------------------------
sub toggle_fvg_visibility {
    my ($self) = @_;
    $self->{_fvg_visible} = $self->{_fvg_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_fvg_all') unless $self->{_fvg_visible};
    $self->{_cb_fvg_visible}->( $self->{_fvg_visible} ) if $self->{_cb_fvg_visible};
    $self->request_render;
    return $self->{_fvg_visible};
}

# -----------------------------------------------------------------------------
# toggle_eq_visibility — BLOQUE EQH/EQL (NUEVO)
# -----------------------------------------------------------------------------
sub toggle_eq_visibility {
    my ($self) = @_;
    $self->{_eq_visible} = $self->{_eq_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_eq_all') unless $self->{_eq_visible};
    $self->{_cb_eq_visible}->( $self->{_eq_visible} ) if $self->{_cb_eq_visible};
    $self->request_render;
    return $self->{_eq_visible};
}

sub toggle_swing_visibility {
    my ($self) = @_;
    $self->{_swing_visible} = $self->{_swing_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_swing_all') unless $self->{_swing_visible};
    $self->{_cb_swing_visible}->( $self->{_swing_visible} ) if $self->{_cb_swing_visible};
    $self->request_render;
    return $self->{_swing_visible};
}

sub toggle_liquidity_visibility {
    my ($self) = @_;
    $self->{_liq_visible} = $self->{_liq_visible} ? 0 : 1;
    $self->{canvas_price}->delete('liq_all') unless $self->{_liq_visible};
    $self->{_cb_liq_visible}->( $self->{_liq_visible} ) if $self->{_cb_liq_visible};
    $self->request_render;
    return $self->{_liq_visible};
}

sub toggle_ob_visibility {
    my ($self) = @_;
    $self->{_ob_visible} = $self->{_ob_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_ob_all') unless $self->{_ob_visible};
    # [UNIFICADO] Order Blocks ahora controla TAMBIEN el tag de Strong/Weak
    # H-L ('smc_trail_all'): al apagar Order Blocks, se borra tambien ese
    # tag aca mismo (redundante con el "else" del render() pero necesario
    # para que no quede dibujado un frame extra antes del proximo render).
    $self->{canvas_price}->delete('smc_trail_all') unless $self->{_ob_visible};
    $self->{_cb_ob_visible}->( $self->{_ob_visible} ) if $self->{_cb_ob_visible};
    $self->request_render;
    return $self->{_ob_visible};
}

sub toggle_trail_visibility {
    my ($self) = @_;
    $self->{_trail_visible} = $self->{_trail_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_trail_all') unless $self->{_trail_visible};
    $self->{_cb_trail_visible}->( $self->{_trail_visible} ) if $self->{_cb_trail_visible};
    $self->request_render;
    return $self->{_trail_visible};
}

# -----------------------------------------------------------------------------
# toggle_sd_visibility — BLOQUE SUPPLY/DEMAND ZONES (NUEVO)
# Solo controla visibilidad (render). No toca el calculo ni los datos
# generados por Market::Indicators::Strategy_Builder: al volver a activarlo
# las zonas reaparecen exactamente donde estaban.
# -----------------------------------------------------------------------------
sub toggle_sd_visibility {
    my ($self) = @_;
    $self->{_sd_visible} = $self->{_sd_visible} ? 0 : 1;
    $self->{canvas_price}->delete('sb_sd_all') unless $self->{_sd_visible};
    $self->{_cb_sd_visible}->( $self->{_sd_visible} ) if $self->{_cb_sd_visible};
    $self->request_render;
    return $self->{_sd_visible};
}

# -----------------------------------------------------------------------------
# toggle_ghost_visibility — BLOQUE GHOST VWAP (NUEVO)
# Solo controla visibilidad (render). El calculo (pivotes + VWAP dinamico)
# corre siempre en Market::Indicators::Strategy_Builder.
# -----------------------------------------------------------------------------
sub toggle_ghost_visibility {
    my ($self) = @_;
    $self->{_ghost_visible} = $self->{_ghost_visible} ? 0 : 1;
    $self->{canvas_price}->delete('ghost_all') unless $self->{_ghost_visible};
    $self->{_cb_ghost_visible}->( $self->{_ghost_visible} ) if $self->{_cb_ghost_visible};
    $self->request_render;
    return $self->{_ghost_visible};
}

# -----------------------------------------------------------------------------
# toggle_pph_vwap_visibility — BLOQUE VWAP AUTO-ANCLADO (NUEVO, punto 4 del
# enunciado). Mismo patron que Ghost: solo controla visibilidad.
# -----------------------------------------------------------------------------
sub toggle_pph_vwap_visibility {
    my ($self) = @_;
    $self->{_pph_vwap_visible} = $self->{_pph_vwap_visible} ? 0 : 1;
    $self->{canvas_price}->delete('pph_vwap_all') unless $self->{_pph_vwap_visible};
    $self->{_cb_pph_vwap_visible}->( $self->{_pph_vwap_visible} ) if $self->{_cb_pph_vwap_visible};
    $self->request_render;
    return $self->{_pph_vwap_visible};
}

# -----------------------------------------------------------------------------
# toggle_channel_visibility — BLOQUE CANAL/TENDLINE (NUEVO, grupo 11)
# -----------------------------------------------------------------------------
sub toggle_channel_visibility {
    my ($self) = @_;
    $self->{_channel_visible} = $self->{_channel_visible} ? 0 : 1;
    $self->{canvas_price}->delete('smc_channel_all') unless $self->{_channel_visible};
    $self->{_cb_channel_visible}->( $self->{_channel_visible} ) if $self->{_cb_channel_visible};
    $self->request_render;
    return $self->{_channel_visible};
}

sub set_ob_visibility_callback    { my ( $self, $cb ) = @_; $self->{_cb_ob_visible}    = $cb; }
sub set_trail_visibility_callback { my ( $self, $cb ) = @_; $self->{_cb_trail_visible} = $cb; }
sub set_sd_visibility_callback    { my ( $self, $cb ) = @_; $self->{_cb_sd_visible}    = $cb; }
sub set_ghost_visibility_callback { my ( $self, $cb ) = @_; $self->{_cb_ghost_visible} = $cb; }
sub set_pph_vwap_visibility_callback { my ( $self, $cb ) = @_; $self->{_cb_pph_vwap_visible} = $cb; }
sub set_channel_visibility_callback  { my ( $self, $cb ) = @_; $self->{_cb_channel_visible}  = $cb; }

sub set_smc_visibility_callback       { my ( $self, $cb ) = @_; $self->{_cb_smc_visible}   = $cb; }
sub set_bos_visibility_callback       { my ( $self, $cb ) = @_; $self->{_cb_bos_visible}   = $cb; }
sub set_choch_visibility_callback     { my ( $self, $cb ) = @_; $self->{_cb_choch_visible} = $cb; }
sub set_ibos_visibility_callback      { my ( $self, $cb ) = @_; $self->{_cb_ibos_visible}   = $cb; }
sub set_ichoch_visibility_callback    { my ( $self, $cb ) = @_; $self->{_cb_ichoch_visible} = $cb; }
sub set_zz_a_visibility_callback       { my ( $self, $cb ) = @_; $self->{_cb_zz_a_visible} = $cb; }
sub set_zz_b_visibility_callback       { my ( $self, $cb ) = @_; $self->{_cb_zz_b_visible} = $cb; }
sub set_vwap_visibility_callback       { my ( $self, $cb ) = @_; $self->{_cb_vwap_visible} = $cb; }
sub set_avp_visibility_callback        { my ( $self, $cb ) = @_; $self->{_cb_avp_visible}  = $cb; }
sub set_fvg_visibility_callback       { my ( $self, $cb ) = @_; $self->{_cb_fvg_visible}   = $cb; }
sub set_eq_visibility_callback        { my ( $self, $cb ) = @_; $self->{_cb_eq_visible}    = $cb; }
sub set_swing_visibility_callback     { my ( $self, $cb ) = @_; $self->{_cb_swing_visible} = $cb; }
sub set_liquidity_visibility_callback { my ( $self, $cb ) = @_; $self->{_cb_liq_visible}    = $cb; }

# -----------------------------------------------------------------------------
# force_all_overlays_off — BLOQUE ARRANQUE LIMPIO
# Garantiza que, sin importar el orden de inicializacion, TODOS los overlays
# de la barra superior (smc_toolbar) empiecen apagados: pone en 0 cada flag
# de visibilidad y borra cualquier tag que pudiera haber quedado dibujado en
# el canvas. Se llama UNA sola vez, antes del primer render (ver market.pl).
#
# No toca el calculo de los indicadores (rebuild_all sigue corriendo igual
# al iniciar); solo asegura que nada se DIBUJE hasta que el usuario presione
# el boton correspondiente. Si en el futuro se agrega un overlay nuevo,
# basta con sumar su flag y su tag a las listas de abajo.
# -----------------------------------------------------------------------------
sub force_all_overlays_off {
    my ($self) = @_;

    for my $flag (qw(
        _smc_visible    _bos_visible   _choch_visible _ibos_visible
        _ichoch_visible _zz_a_visible  _zz_b_visible  _fvg_visible
        _eq_visible     _swing_visible _liq_visible   _ob_visible
        _trail_visible  _sd_visible    _vwap_visible  _avp_visible
        _ghost_visible  _pph_vwap_visible _channel_visible
    )) {
        $self->{$flag} = 0;
    }

    # BLOQUE FIBONACCI: limpiar el ancla tambien, para que no quede una
    # seleccion vieja "fantasma" si el usuario la habia elegido antes de
    # recargar.
    $self->{_fib_point1} = undef;
    $self->{_fib_point2} = undef;
    $self->{_fib_width_index} = undef;
    $self->{_awaiting_fib_anchor} = 0;

    if ( $self->{canvas_price} ) {
        for my $tag (qw(
            smc_fib_all smc_bos_all smc_choch_all smc_ibos_all smc_ichoch_all
            smc_fvg_all smc_eq_all  smc_swing_all smc_ob_all   smc_trail_all
            sb_tl_all   zz_a_all    zz_b_all       sb_sd_all   liq_all
            vwap_all    avp_all     ghost_all   pph_vwap_all  smc_channel_all
        )) {
            $self->{canvas_price}->delete($tag);
        }
    }

    return;
}

# -----------------------------------------------------------------------------
# _vwap_y_range — min/max de las bandas EXTERNAS del VWAP (banda 2, la mas
# ancha) dentro de [start,end]. Se usa para que el auto-zoom vertical
# incluya el VWAP completo, no solo las velas (ver bloque en render()).
# -----------------------------------------------------------------------------
sub _vwap_y_range {
    my ( $self, $start, $end ) = @_;
    my $sb = $self->{indicators}->get_indicator('zigzags');
    return ( undef, undef ) unless $sb && $sb->can('get_vwap');

    my $data = $sb->get_vwap;
    return ( undef, undef ) unless $data;

    my ( $mn, $mx );
    for my $idx ( $start .. $end ) {
        my $d = $data->[$idx];
        next unless $d;
        $mn = $d->{band2_lo} if !defined $mn || $d->{band2_lo} < $mn;
        $mx = $d->{band2_hi} if !defined $mx || $d->{band2_hi} > $mx;
    }
    return ( $mn, $mx );
}

# -----------------------------------------------------------------------------
# _avp_y_range — rango de precio del AVP (min de la franja mas baja, max de
# la mas alta). A diferencia de _vwap_y_range, no depende de [start,end]:
# el perfil es un rango de precio FIJO (calculado una sola vez al anclar),
# el mismo sin importar hacia donde se haya hecho scroll.
# -----------------------------------------------------------------------------
sub _avp_y_range {
    my ($self) = @_;
    my $sb = $self->{indicators}->get_indicator('zigzags');
    return ( undef, undef ) unless $sb && $sb->can('get_avp');

    my $avp = $sb->get_avp;
    return ( undef, undef ) unless $avp && @{ $avp->{bins} };

    my $bins = $avp->{bins};
    return ( $bins->[0]{price_lo}, $bins->[-1]{price_hi} );
}

sub reset_view {
    my ($self) = @_;
    $self->{visible_bars}     = DEFAULT_BARS;
    $self->{zoom_y_auto}      = 1;
    $self->{y_range_price}    = undef;
    $self->{zoom_y_auto_atr}  = 1;
    $self->{y_range_atr}      = undef;
    $self->{_scale_price}     = undef;
    $self->{_scale_atr}       = undef;
    $self->{_price_cross}     = undef;
    $self->{_atr_cross}       = undef;
    $self->{_ctrl_pressed}    = 0;
    $self->{_zoom_anchor_idx} = undef;
    $self->{_zoom_anchor_px}  = undef;

    my $total = $self->{market}->size;
    $self->{offset} = $total - DEFAULT_BARS;
    $self->{offset} = 0 if $self->{offset} < 0;
}

# -----------------------------------------------------------------------------
# goto_start / goto_current — BLOQUE NAVEGACION RAPIDA (botones "Inicio" y
# "Actual", junto al Zoom). Solo mueven el scroll horizontal (offset); NO
# tocan el nivel de zoom (visible_bars) ni nada del bloque Replay. El
# recorte a limites validos (incluido el limite de Replay si esta activo)
# ya lo hace compute_window en cada render, igual que con cualquier otro
# scroll manual — no hace falta duplicar esa logica aqui.
# -----------------------------------------------------------------------------
sub goto_start {
    my ($self) = @_;
    $self->{offset} = 0;
    $self->request_render;
    return;
}

sub goto_current {
    my ($self) = @_;
    my $total = $self->{market}->size;
    if ( $self->{replay_active} && defined $self->{replay_limit_index} ) {
        my $replay_total = $self->{replay_limit_index} + 1;
        $total = $replay_total if $replay_total < $total;
    }
    my $off = $total - $self->{visible_bars};
    $off = 0 if $off < 0;
    $self->{offset} = $off;
    $self->request_render;
    return;
}

sub compute_intraday_labels {
    my ( $self, $start, $end ) = @_;

    my $visible = $end - $start + 1;
    return [] if $visible <= 0;

    my %tf_min   = (
        '1m'  => 1,
        '5m'  => 5,
        '15m' => 15,
        '1h'  => 60,
        '2h'  => 120,
        '4h'  => 240,
        'D'   => 1440,
        'W'   => 10080,
    );
    my $tf       = $self->{market}->get_timeframe;
    my $bar_min  = $tf_min{$tf} // 1;

    my @nice     = ( 1, 2, 5, 10, 15, 20, 30, 60, 120, 240, 360, 720, 1440, 10080 );
    my $step_min = $nice[-1];
    for my $s (@nice) {
        next if $s < $bar_min;
        if ( $visible / ( $s / $bar_min ) <= 12 ) { $step_min = $s; last; }
    }

    my $min_gap = int( $step_min / $bar_min / 2 );
    $min_gap = 1 if $min_gap < 1;

    my @DAY_ABBR        = qw(Sun Mon Tue Wed Thu Fri Sat);
    my @result;
    my $last_placed_idx = -999999;
    my $last_slot       = -1;
    my $last_day        = -1;
    my $first_bar       = 1;

    for my $i ( $start .. $end ) {
        my $c = $self->{market}->get_candle($i);
        next unless $c;
        next unless defined $c->{time}
            && $c->{time} =~ /\d{4}-\d{2}-(\d{2})T(\d{2}):(\d{2})/;

        my ( $mday, $hour, $min ) = ( $1+0, $2+0, $3+0 );
        my $cur_slot = int( ( $hour * 60 + $min ) / $step_min );

        if ($first_bar) {
            push @result, {
                index => $i,
                label => sprintf('%d:%02d', $hour, $min),
                ts    => $c->{ts}
            };
            $last_placed_idx = $i;
            $last_day        = $mday;
            $last_slot       = $cur_slot;
            $first_bar       = 0;
            next;
        }

        my $day_change  = ( $mday != $last_day );
        my $slot_change = ( $cur_slot != $last_slot );
        $last_day  = $mday;
        $last_slot = $cur_slot;

        next unless $day_change || $slot_change;
        next if $i - $last_placed_idx < $min_gap;

        my $label;
        if ($day_change) {
            my $wday = ( gmtime( $c->{ts} ) )[6];
            $label = $DAY_ABBR[$wday] . ' ' . $mday;
        } else {
            $label = sprintf( '%d:%02d',
                int( $cur_slot * $step_min / 60 ),
                ( $cur_slot * $step_min ) % 60 );
        }

        push @result, { index => $i, label => $label, ts => $c->{ts} };
        $last_placed_idx = $i;
    }

    return \@result;
}

sub get_all_timestamps {
    my ($self) = @_;
    my ( $start, $end ) = $self->compute_window;
    my $slice = $self->{market}->get_slice( $start, $end );
    return [ map { $_->{ts} } @$slice ];
}

1;