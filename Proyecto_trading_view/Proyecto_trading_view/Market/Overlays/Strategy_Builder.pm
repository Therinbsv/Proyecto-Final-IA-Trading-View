package Market::Overlays::Strategy_Builder;

# =============================================================================
# Market::Overlays::Strategy_Builder
# Visualizacion del Strategy Builder (seccion 6 del spec).
#
# render_trendlines — Lee los macro pivotes de SMC_Structures y dibuja:
#   Tramo LOW -> HIGH : linea diagonal discontinua VERDE  (tendencia alcista)
#   Tramo HIGH -> LOW : linea diagonal discontinua ROJA   (tendencia bajista)
#
# La linea se dibuja entre los pivotes confirmados, recortada a la ventana
# visible. El ultimo tramo (sin confirmar) se extiende hasta la vela actual
# como una linea muy tenue para indicar la direccion en curso.
#
# render_fib_retracement — Fibonacci Retracement por clic, anclado al
# ZigZag Ex (get_zigzag_a). Ver comentario detallado mas abajo, junto a
# la funcion.
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
# render_trendlines — LINEAS DE TENDENCIA ALCISTA / BAJISTA
# Recibe el indicador SMC ($smc) porque los macro pivotes ya estan calculados
# ahi. No duplica calculo.
# =============================================================================
sub render_trendlines {
    my ( $self, $canvas, $smc, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('sb_tl_all');
    return unless $smc && $scale;

    my $limit  = defined $replay_limit ? $replay_limit : $end;
    my $pivots = $smc->get_macro_pivots();

    # Solo pivotes que ya ocurrieron (causal)
    my @vis = grep { $_->{index} <= $limit } @$pivots;
    return unless @vis >= 2;

    my $bull_color = $self->{theme}{tl_bull} // '#00E676';   # verde brillante
    my $bear_color = $self->{theme}{tl_bear} // '#FF5252';   # rojo claro

    # =========================================================================
    # PASO 1: Dibujar todos los tramos CONFIRMADOS entre pivotes consecutivos
    # =========================================================================
    for my $i ( 0 .. $#vis - 1 ) {
        my $p1 = $vis[$i];
        my $p2 = $vis[ $i + 1 ];

        # Omitir si el tramo completo cae fuera de la ventana visible
        next if $p2->{index} < $start;
        next if $p1->{index} > $end;

        # Sentido: LOW->HIGH = alcista (verde), HIGH->LOW = bajista (rojo)
        my $going_up = ( $p2->{type} eq 'high' );
        my $color    = $going_up ? $bull_color : $bear_color;

        my ( $i1, $pr1 ) = ( $p1->{index}, $p1->{price} );
        my ( $i2, $pr2 ) = ( $p2->{index}, $p2->{price} );

        # Pendiente en precio/barra
        my $slope = ( $i1 != $i2 ) ? ( $pr2 - $pr1 ) / ( $i2 - $i1 ) : 0;

        # Recortar a la ventana visible (clipping lineal)
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
            -dash  => [ 7, 5 ],
            -tags  => [ 'sb_tl_all', 'sb_tl_segment' ],
        );
    }

    # =========================================================================
    # PASO 2: Tramo EN CURSO (desde el ultimo pivote hasta la vela actual)
    # Se dibuja muy tenue para indicar la direccion sin confundir con un
    # tramo confirmado.
    # =========================================================================
    if ( @vis >= 1 ) {
        my $last_pivot = $vis[-1];
        my $lp_idx     = $last_pivot->{index};
        my $lp_price   = $last_pivot->{price};

        # El tipo del ultimo pivote dice hacia donde VA el tramo en curso:
        # si el ultimo confirmado fue un HIGH, ahora se espera un LOW (bajista)
        # si el ultimo confirmado fue un LOW, ahora se espera un HIGH (alcista)
        my $going_up = ( $last_pivot->{type} eq 'low' );
        my $color    = $going_up ? $bull_color : $bear_color;

        # Precio del extremo de referencia en "limit" (usamos open de esa vela)
        # para proyectar la linea hasta donde estamos ahora.
        my $draw_from = $lp_idx < $start ? $start : $lp_idx;
        my $draw_to   = $limit  > $end   ? $end   : $limit;
        return unless $draw_from <= $draw_to;

        my $x1 = $scale->index_to_center_x($draw_from);
        my $x2 = $scale->index_to_center_x($draw_to);
        my $y1 = $scale->value_to_y($lp_price);
        my $y2 = $y1;   # linea horizontal tenue — el precio actual se desconoce
                        # (el verdadero endpoint se confirmara cuando el pivot
                        # opuesto se detecte en el indicador)

        # Linea muy tenue (alpha visual via color oscurecido)
        my $faint = $self->_fade_color( $color, 0.35 );
        $canvas->createLine(
            $x1, $y1, $x2, $y2,
            -fill  => $faint,
            -width => 1,
            -dash  => [ 3, 5 ],
            -tags  => [ 'sb_tl_all', 'sb_tl_pending' ],
        );
    }
    return;
}

# =============================================================================
# render_fib_retracement — Fibonacci Retracement por clic.
#
# Puerto del comportamiento del Fibonacci Retracement NATIVO de TradingView
# (no un Pine, es una herramienta de dibujo propia de la plataforma), atado
# al ZigZag Ex (get_zigzag_a de este mismo indicador). No recalcula nada del
# ZigZag; solo LEE dos entradas consecutivas de get_zigzag_a() -- la que el
# usuario ancló ($anchor_pos, ver ChartEngine::set_fib_anchor_pos) y la
# siguiente en la secuencia -- y dibuja:
#
#   1) Las 7 lineas de nivel estandar (0%, 23.6%, 38.2%, 50%, 61.8%, 78.6%,
#      100%), con la convencion Fibonacci habitual: 0% en el precio MAS
#      ALTO de los dos puntos, 100% en el MAS BAJO -- sin importar cual de
#      los dos haya sido el "ancla" elegida por el usuario ni cual sea
#      cronologicamente el primero o el segundo.
#
#      [FIX ANCHO] Estas lineas cruzan TODO el ancho visible del grafico
#      (de $start a $end), no solo el rango entre los dos puntos anclados
#      -- asi es como se ve en TradingView (las lineas de color atraviesan
#      la pantalla completa, incluso a la izquierda del punto 1). Antes se
#      recortaban al rango [anchor,second], por lo que solo se veian
#      "dentro del triangulo" en vez de cruzar de punta a punta.
#
#   2) La linea diagonal ("trend line") que conecta ambos puntos -- esta SI
#      queda acotada exactamente entre los dos puntos (mas su extension,
#      ver 3), igual que la referencia.
#   3) Su proyeccion punteada, extendida con la MISMA pendiente hasta el
#      borde derecho de la ventana visible (igual que el "Extend Line" del
#      Fibonacci nativo de TradingView).
#
# [FIX COLOR] La linea de tendencia (2/3) usaba el mismo azul que el
# ZigZag Ex (zz_a_color, tambien #2962ff por defecto). Como es habitual
# tener ambos overlays prendidos a la vez (el usuario suele activar
# ZigZag Ex primero para ubicar visualmente el pivote antes de clickear en
# Fibonacci), las dos lineas azules se confundian entre si y el ZigZag Ex
# (que dibuja SU PROPIO camino completo, incluyendo tramos antes y despues
# de los dos puntos elegidos para el Fibonacci) parecia una sola linea
# "desviandose" de forma incorrecta. Se cambia a un magenta bien distinto
# para que la linea de tendencia del Fibonacci se distinga siempre, este o
# no encendido el ZigZag Ex.
#
# [SEGUNDO PUNTO] Si la pierna elegida por el usuario YA tiene un pivote
# siguiente confirmado en get_zigzag_a() (indice $anchor_pos+1 existe),
# se usa tal cual. Si el ancla es el ULTIMO pivote confirmado (la pierna
# sigue formandose), se usa el precio de CIERRE de la vela causal mas
# reciente ($now_index) como segundo punto "en vivo" -- este metodo no
# guarda nada: como se llama de nuevo en CADA render con los datos
# frescos, el segundo punto (confirmado o en vivo) y hasta el propio
# ancla (si el ZigZag Ex lo corrige en el lugar, ver _confirm_zigzag con
# $force) se recalculan solos, sin intervencion del ChartEngine.
# =============================================================================
sub render_fib_retracement {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit,
         $anchor_pos, $market_data, $now_index ) = @_;

    $canvas->delete('smc_fib_all');
    return unless $sb && $scale && defined $anchor_pos;

    my $pivots = $sb->get_zigzag_a;
    return unless $pivots && @$pivots && $anchor_pos <= $#$pivots;

    my $anchor = $pivots->[$anchor_pos];
    return unless $anchor;
    # El ancla no debe ser causalmente "futura" (por si el Replay retrocedio
    # despues de haber elegido un pivote mas adelante en el tiempo real).
    return if $anchor->{index} > $replay_limit;

    my $second;
    if ( $anchor_pos < $#$pivots ) {
        # Ya existe el pivote SIGUIENTE confirmado en la secuencia. Como
        # _confirm_zigzag solo muta el ULTIMO elemento del array, este
        # pivote deja de moverse en cuanto aparece uno mas despues de el
        # -- mientras siga siendo el ultimo, puede seguir corrigiendose
        # (ver _confirm_zigzag con $force), y como este metodo lee
        # get_zigzag_a() de nuevo en cada render, ese ajuste se refleja
        # solo, sin necesidad de "congelar" nada aqui.
        $second = $pivots->[ $anchor_pos + 1 ];
        return if $second->{index} > $replay_limit;   # causal (respeta Replay)
    } else {
        # El ancla es el ULTIMO pivote confirmado -- todavia no hay una
        # pierna siguiente. Se usa el precio de CIERRE de la vela causal
        # mas reciente como segundo punto "en vivo": se recalcula solo en
        # cada render (nueva vela => nuevo precio) hasta que el ZigZag Ex
        # confirme un pivote real, momento en el que el proximo render ya
        # entra por la rama de arriba.
        return unless $market_data && defined $now_index;
        my $live_c = $market_data->get_candle($now_index);
        return unless $live_c;
        $second = {
            index => $now_index,
            price => $live_c->{close},
            type  => ( $anchor->{type} eq 'low' ? 'high' : 'low' ),
        };
    }
    return if $second->{index} == $anchor->{index} && $second->{price} == $anchor->{price};

    # Convencion estandar de Fibonacci Retracement: 0% en el precio ALTO,
    # 100% en el precio BAJO -- sin importar cual de los dos puntos fue
    # elegido primero por el usuario (igual comportamiento que el
    # Fibonacci nativo de TradingView al dibujar un retroceso).
    my ( $top, $bottom );
    if ( $anchor->{price} >= $second->{price} ) {
        ( $top, $bottom ) = ( $anchor->{price}, $second->{price} );
    } else {
        ( $top, $bottom ) = ( $second->{price}, $anchor->{price} );
    }
    return if $top <= $bottom;

    my @levels = ( 0, 0.236, 0.382, 0.5, 0.618, 0.786, 1 );
    my %level_colors = (
        0     => '#787b86',
        0.236 => '#f23645',
        0.382 => '#ff9800',
        0.5   => '#4caf50',
        0.618 => '#089981',
        0.786 => '#00bcd4',
        1     => '#787b86',
    );

    # [FIX ANCHO] Las lineas de nivel cruzan TODO el ancho visible (de
    # $start a $end), no solo el rango entre los dos puntos anclados --
    # ver comentario grande arriba de esta funcion.
    my $x_left  = $scale->index_to_center_x($start);
    my $x_right = $scale->index_to_center_x($end);

    # --- 1) Niveles horizontales (0%..100%), con precio en la etiqueta,
    # igual que el Fibonacci nativo de TradingView. ---
    for my $pct (@levels) {
        my $price = $top - $pct * ( $top - $bottom );
        my $y     = $scale->value_to_y($price);
        my $color = $level_colors{$pct} // '#787b86';
        my $is_edge = ( $pct == 0 || $pct == 1 );

        $canvas->createLine(
            $x_left, $y, $x_right, $y,
            -fill  => $color,
            -width => 1,
            -dash  => $is_edge ? [ 2, 2 ] : [ 2, 3 ],
            -tags  => [ 'smc_fib_all', 'smc_fib' ],
        );
        $canvas->createText(
            $x_right - 4, $y - 7,
            -text   => sprintf( '%.1f%% (%.2f)', $pct * 100, $price ),
            -fill   => $color,
            -font   => 'Helvetica 7',
            -anchor => 'e',
            -tags   => [ 'smc_fib_all', 'smc_fib' ],
        );
    }

    # --- 2) Linea diagonal conectando el ancla con el segundo punto
    # ("trend line" del Fibonacci nativo) -- esta SI queda acotada
    # exactamente entre los dos puntos (mas su extension punteada, ver
    # abajo), a diferencia de las lineas de nivel de arriba. ---
    my $line_color = $self->{theme}{fib_trend} // '#e91e63';

    my $anchor_draw_idx = $anchor->{index} < $start ? $start : $anchor->{index};
    my $second_draw_idx = $second->{index} > $end   ? $end   : $second->{index};

    if ( $anchor_draw_idx <= $second_draw_idx ) {
        my $slope = ( $second->{index} != $anchor->{index} )
            ? ( $second->{price} - $anchor->{price} ) / ( $second->{index} - $anchor->{index} )
            : 0;
        my $ax = $scale->index_to_center_x($anchor_draw_idx);
        my $ay = $scale->value_to_y( $anchor->{price} + $slope * ( $anchor_draw_idx - $anchor->{index} ) );
        my $bx = $scale->index_to_center_x($second_draw_idx);
        my $by = $scale->value_to_y( $anchor->{price} + $slope * ( $second_draw_idx - $anchor->{index} ) );

        $canvas->createLine(
            $ax, $ay, $bx, $by,
            -fill  => $line_color,
            -width => 2,
            -tags  => [ 'smc_fib_all', 'smc_fib_trend' ],
        );

        # --- 3) Proyeccion punteada: misma pendiente, extendida desde el
        # segundo punto hasta el borde derecho visible (igual que
        # "Extend Line" del Fibonacci nativo de TradingView). ---
        if ( $second->{index} < $end && $second->{index} != $anchor->{index} ) {
            my $ext_price = $second->{price} + $slope * ( $end - $second->{index} );
            my $ex = $scale->index_to_center_x($end);
            my $ey = $scale->value_to_y($ext_price);

            $canvas->createLine(
                $bx, $by, $ex, $ey,
                -fill  => $line_color,
                -width => 1,
                -dash  => [ 3, 3 ],
                -tags  => [ 'smc_fib_all', 'smc_fib_trend_ext' ],
            );
        }
    }

    return;
}

# =============================================================================
# render_supertrend
# =============================================================================
sub render_supertrend {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('sb_st_all');
    return unless $sb && $scale;

    my $limit  = defined $replay_limit ? $replay_limit : $end;
    my $data   = $sb->get_supertrend;
    my $bull_c = $self->{theme}{st_bull} // '#14D990';
    my $bear_c = $self->{theme}{st_bear} // '#F24968';

    my ( $px, $py, $pc );
    for my $idx ( $start .. ( $limit < $end ? $limit : $end ) ) {
        my $d = $data->[$idx];
        next unless $d && defined $d->{line};
        my $color = $d->{trend} == 1 ? $bull_c : $bear_c;
        my $x = $scale->index_to_center_x($idx);
        my $y = $scale->value_to_y( $d->{line} );
        if ( defined $px ) {
            $canvas->createLine( $px, $py, $x, $y,
                -fill => $pc, -width => 2,
                -tags => [ 'sb_st_all', 'sb_supertrend' ] );
        }
        ( $px, $py, $pc ) = ( $x, $y, $color );
    }
    return;
}

# =============================================================================
# render_halftrend
# =============================================================================
sub render_halftrend {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('sb_ht_all');
    return unless $sb && $scale;

    my $limit  = defined $replay_limit ? $replay_limit : $end;
    my $data   = $sb->get_halftrend;
    my $bull_c = $self->{theme}{ht_bull} // '#14D990';
    my $bear_c = $self->{theme}{ht_bear} // '#F24968';

    my ( $px, $py, $pt );
    for my $idx ( $start .. ( $limit < $end ? $limit : $end ) ) {
        my $d = $data->[$idx];
        next unless $d && defined $d->{signal_price};
        my $color = $d->{trend} == 0 ? $bull_c : $bear_c;
        my $x = $scale->index_to_center_x($idx);
        my $y = $scale->value_to_y( $d->{signal_price} );
        if ( defined $px ) {
            $canvas->createLine( $px, $py, $x, $y,
                -fill => $color, -width => 2,
                -tags => [ 'sb_ht_all', 'sb_halftrend' ] );
        }
        if ( defined $pt && $pt != $d->{trend} ) {
            $canvas->createText( $x, $y + ( $d->{trend} == 0 ? 12 : -12 ),
                -text => ( $d->{trend} == 0 ? '▲' : '▼' ),
                -fill => $color, -font => 'Helvetica 10 bold', -anchor => 'center',
                -tags => [ 'sb_ht_all', 'sb_ht_arrow' ] );
        }
        ( $px, $py, $pt ) = ( $x, $y, $d->{trend} );
    }
    return;
}

# =============================================================================
# render_range_filter
# =============================================================================
sub render_range_filter {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('sb_rf_all');
    return unless $sb && $scale;

    my $limit  = defined $replay_limit ? $replay_limit : $end;
    my $data   = $sb->get_range_filter;
    my $bull_c = $self->{theme}{rf_bull} // '#2196F3';
    my $bear_c = $self->{theme}{rf_bear} // '#FF5722';
    my $band_c = $self->{theme}{rf_band} // '#546E7A';

    my ( $px, $phi, $plo, $pmid );
    for my $idx ( $start .. ( $limit < $end ? $limit : $end ) ) {
        my $d = $data->[$idx];
        next unless $d;
        my $color = $d->{trend} == 1 ? $bull_c : $bear_c;
        my $x    = $scale->index_to_center_x($idx);
        my $ymid = $scale->value_to_y( $d->{filtered} );
        my $yhi  = $scale->value_to_y( $d->{hi_band}  );
        my $ylo  = $scale->value_to_y( $d->{lo_band}  );
        if ( defined $px ) {
            $canvas->createLine( $px, $phi, $x, $yhi,
                -fill => $band_c, -width => 1, -dash => [2,2],
                -tags => [ 'sb_rf_all', 'sb_rf_band' ] );
            $canvas->createLine( $px, $plo, $x, $ylo,
                -fill => $band_c, -width => 1, -dash => [2,2],
                -tags => [ 'sb_rf_all', 'sb_rf_band' ] );
            $canvas->createLine( $px, $pmid, $x, $ymid,
                -fill => $color, -width => 2,
                -tags => [ 'sb_rf_all', 'sb_rf_mid' ] );
        }
        ( $px, $phi, $plo, $pmid ) = ( $x, $yhi, $ylo, $ymid );
    }
    return;
}

# =============================================================================
# render_vwap — VWAP anclado con bandas de desviacion estandar.
# Dibuja 5 lineas (igual que la referencia): la linea del VWAP en el medio
# (precio "justo") y dos pares de bandas de desviacion:
#   Banda 1 (multiplicador 1): zona verde RELLENA — el rango "normal".
#   Banda 2 (multiplicador 2): solo lineas (sin relleno) — arriba = "muy
#     caro", abajo = "muy barato".
# Los valores ya vienen calculados por
# Market::Indicators::Strategy_Builder::_update_vwap; este metodo solo
# dibuja, no recalcula nada.
# =============================================================================
sub render_vwap {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('vwap_all');
    return unless $sb && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;
    my $data  = $sb->get_vwap;
    return unless $data;

    my $line_color  = $self->{theme}{vwap_line}  // '#2962ff';   # azul: precio "justo"
    # FIX: '#26a69a' es EXACTAMENTE el color de las velas alcistas
    # (PricePanel::COLOR_BULL) -> se confundia la banda con las velas. Ahora
    # usa un verde distinto (mas vivido/lima, sin el tinte turquesa de las
    # velas) para que la zona se distinga claramente del precio.
    my $band1_color = $self->{theme}{vwap_band1} // '#4CD964';   # verde lima: 1a desviacion
    my $band2_color = $self->{theme}{vwap_band2} // '#8d6e63';   # cafe/oliva: 2a desviacion
    # FIX (tapaba al AVP por completo): un color "pre-mezclado" con el
    # fondo (blend) sigue siendo pintura 100% OPACA en Tk::Canvas -- por
    # mas palido que se vea, tapa cualquier cosa detras (velas, AVP, etc)
    # sin importar el orden de capas. La unica forma de dejar ver GENUINA-
    # MENTE lo que hay detras en Tk es un patron de stipple (trama
    # punteada: solo pinta una fraccion de los pixeles, dejando el resto
    # intactos). Se usa el color base (sin blend) + stipple en vez del
    # color pre-mezclado.
    my $fill_color  = $band1_color;

    my ( @vwap_xy, @b1hi_xy, @b1lo_xy, @b2hi_xy, @b2lo_xy );

    for my $idx ( $start .. ( $limit < $end ? $limit : $end ) ) {
        my $d = $data->[$idx];
        next unless $d;
        my $x = $scale->index_to_center_x($idx);
        push @vwap_xy, [ $x, $scale->value_to_y( $d->{vwap} ) ];
        push @b1hi_xy, [ $x, $scale->value_to_y( $d->{band1_hi} ) ];
        push @b1lo_xy, [ $x, $scale->value_to_y( $d->{band1_lo} ) ];
        push @b2hi_xy, [ $x, $scale->value_to_y( $d->{band2_hi} ) ];
        push @b2lo_xy, [ $x, $scale->value_to_y( $d->{band2_lo} ) ];
    }
    return unless @vwap_xy >= 2;

    # --- Zona verde: relleno entre banda1_hi y banda1_lo (un solo poligono:
    # ida por la banda de arriba, vuelta por la de abajo) ---
    if ( @b1hi_xy >= 2 ) {
        my @poly = ( ( map { @$_ } @b1hi_xy ), ( map { @$_ } reverse @b1lo_xy ) );
        $canvas->createPolygon(
            @poly,
            -fill    => $fill_color,
            -stipple => 'gray25',
            -outline => '',
            -tags    => [ 'vwap_all', 'vwap_zone' ],
        );
        # FIX (tapaba las velas): el color de relleno es una simulacion de
        # transparencia (mezclado con el color de fondo del panel, ya que
        # Tk::Canvas no soporta alpha real) — si se queda ENCIMA de las
        # velas las tapa por completo en vez de dejarlas ver a traves.
        # Empujar el poligono detras de la capa 'candle' (mismo patron ya
        # usado por render_order_blocks/render_supply_demand) para que las
        # velas queden visibles sobre el verde, igual que en la referencia.
        eval { $canvas->lower( 'vwap_zone', 'candle' ) };
    }

    # --- Lineas (banda 2 primero, para que quede debajo visualmente de la
    # linea principal del VWAP) ---
    for my $set ( [ \@b2hi_xy, $band2_color, 1, 'vwap_band2' ],
                  [ \@b2lo_xy, $band2_color, 1, 'vwap_band2' ],
                  [ \@b1hi_xy, $band1_color, 1, 'vwap_band1' ],
                  [ \@b1lo_xy, $band1_color, 1, 'vwap_band1' ] )
    {
        my ( $pts, $color, $width, $tag ) = @$set;
        next unless @$pts >= 2;
        $canvas->createLine( ( map { @$_ } @$pts ),
            -fill => $color, -width => $width, -tags => [ 'vwap_all', $tag ] );
    }

    $canvas->createLine( ( map { @$_ } @vwap_xy ),
        -fill => $line_color, -width => 2, -tags => [ 'vwap_all', 'vwap_line' ] );

    return;
}

# =============================================================================
# render_supply_demand — SOLO DIBUJA. Las zonas (top/bottom/left_index/
# broken/broken_index) ya vienen calculadas por
# Market::Indicators::Strategy_Builder::_update_supply_demand (puerto fiel
# de "DIY Custom Strategy Builder [ZP] - v1"); este metodo no recalcula ni
# reinterpreta nada, solo consume get_supply_zones()/get_demand_zones().
#
# Cada zona se dibuja como un RECTANGULO horizontal celeste (cyan) con
# transparencia simulada (blend contra el fondo del panel + z-order debajo
# de las velas, mismo truco que el resto de overlays de este proyecto ya
# que Tk::Canvas no soporta alpha real), con la etiqueta SUPPLY/DEMAND
# centrada. Se extiende hacia la derecha mientras la zona siga activa
# (broken=0); si fue invalidada (BOS), deja de extenderse en el bar donde
# ocurrio la ruptura. Respeta el modo replay igual que el resto de overlays
# (una zona rota DESPUES del limite de replay se muestra como si aun
# estuviera activa en ese punto del tiempo).
# =============================================================================
sub render_supply_demand {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('sb_sd_all');
    return unless $sb && $scale;

    my $limit      = defined $replay_limit ? $replay_limit : $end;
    my $zone_color = $self->{theme}{sd_zone} // '#00E5FF';   # celeste/cyan
    my $fill       = $self->_blend_with_bg( $zone_color, 0.28 );

    for my $zone ( @{ $sb->get_supply_zones }, @{ $sb->get_demand_zones } ) {
        next if $zone->{left_index} > $limit;
        next if $zone->{left_index} > $end;

        my $right_index = ( $zone->{broken} && defined $zone->{broken_index} && $zone->{broken_index} <= $limit )
            ? $zone->{broken_index}
            : $limit;
        next if $right_index < $start;

        my $li = $zone->{left_index} < $start ? $start : $zone->{left_index};
        my $ri = $right_index > $end ? $end : $right_index;

        my $x1 = $scale->index_to_center_x($li);
        my $x2 = $scale->index_to_center_x($ri);
        my $y1 = $scale->value_to_y( $zone->{top} );
        my $y2 = $scale->value_to_y( $zone->{bottom} );

        $canvas->createRectangle(
            $x1, $y1, $x2, $y2,
            -fill => $fill, -outline => $fill,
            -tags => [ 'sb_sd_all', 'sb_sd_zone' ],
        );

        my $xm = ( $x1 + $x2 ) / 2;
        my $ym = ( $y1 + $y2 ) / 2;
        $canvas->createText(
            $xm, $ym,
            -text   => $zone->{label},
            -fill   => '#ffffff',
            -font   => 'Helvetica 8 bold',
            -anchor => 'center',
            -tags   => [ 'sb_sd_all', 'sb_sd_label' ],
        );
    }

    eval { $canvas->lower( 'sb_sd_all', 'candle' ) };
    return;
}

# =============================================================================
# render_zigzag_a — "ZigZag Volume Profile [ChartPrime]"
# =============================================================================
sub render_zigzag_a {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('zz_a_all');
    return unless $sb && $scale;

    my $limit = defined $replay_limit ? $replay_limit : $end;
    my $color = $self->{theme}{zz_a_color} // '#2962ff';

    my @pivots = $self->_visible_pivots( $sb->get_zigzag_a, $start, $end, $limit );
    return unless @pivots;

    # FIX (se desliza al hacer scroll + desaparece si falta un punto): antes
    # se recortaba x1 al borde de pantalla pero se dejaba el precio (y1)
    # crudo del pivote, y el bucle dependia de que _visible_pivots ya
    # hubiera descartado los pivotes fuera de $end (ver fix arriba). Ahora
    # se interpola linealmente el precio en el punto exacto de recorte —
    # mismo criterio que en Overlays/SMC_Structures.pm — y el segmento se
    # dibuja aunque solo uno de los dos extremos este en pantalla.
    for my $i ( 0 .. $#pivots - 1 ) {
        my $p1 = $pivots[$i];
        my $p2 = $pivots[ $i + 1 ];

        next if $p2->{index} < $start;
        next if $p1->{index} > $end;

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

        $canvas->createLine( $x1, $y1, $x2, $y2, -fill => $color, -width => 2,
            -tags => [ 'zz_a_all', 'zz_a_line' ] );
    }

    # --- Tramo en formacion (aun sin confirmar): sigue el mismo criterio
    # que set_xy2() del Pine — se extiende MIENTRAS el precio siga marcando
    # nuevos extremos en la direccion esperada, y se queda quieto en cuanto
    # deja de hacerlo, AUNQUE eso signifique no llegar a la vela actual.
    #
    # [CORRECCION 1] En una version anterior esto se extendia de mas, usando
    # el ZigZag B (mucho mas fino) como puente artificial hasta la vela
    # actual — pensando que aplicaba el mismo criterio que el ZigZag Interno.
    # Las capturas de TradingView real (referencia del propio ChartPrime)
    # muestran que el ZigZag Externo NO hace eso: si no hay una reversion
    # genuina confirmada a esta escala, sencillamente no hay linea ahi. Se
    # revierte a dibujar solo el tramo real (get_zigzag_a_pending tal cual),
    # sin ningun puente adicional.
    #
    # [CORRECCION 2] FIX (desaparece al hacer scroll): el guard anterior
    # exigia "$pending->{to_index} <= $limit" para dibujar CUALQUIER parte
    # del tramo — es decir, todo o nada. Como el punto de formacion refleja
    # el estado mas reciente de TODO el dataset (no solo lo visible), en
    # cuanto ese punto quedaba fuera de la ventana visible ($end), la
    # condicion fallaba y el tramo entero desaparecia, aunque una parte de
    # el (desde el pivote confirmado hasta el borde visible) siguiera
    # siendo perfectamente valida para mostrar. Ahora se separan los dos
    # recortes: primero uno CAUSAL (nunca mostrar mas alla de $limit, para
    # no filtrar informacion "futura" durante un replay), y despues uno
    # VISUAL (recortar a [start,end] con interpolacion, igual que el resto
    # de segmentos) — el tramo se dibuja parcialmente en vez de ocultarse
    # por completo.
    if ( $sb->can('get_zigzag_a_pending') ) {
        my $pending = $sb->get_zigzag_a_pending;
        if ( $pending && $pending->{from_index} <= $limit && $pending->{from_index} <= $end ) {
            my ( $i1, $pr1 ) = ( $pending->{from_index}, $pending->{from_price} );
            my ( $i2, $pr2 ) = ( $pending->{to_index},   $pending->{to_price} );
            my $slope = ( $i1 != $i2 ) ? ( $pr2 - $pr1 ) / ( $i2 - $i1 ) : 0;

            # Recorte CAUSAL: nunca ir mas alla de $limit (importante durante
            # replay; fuera de replay $limit == $end y no cambia nada).
            my $causal_i2 = $i2 > $limit ? $limit : $i2;

            # Recorte VISUAL: a la ventana [start,end], con interpolacion.
            my $draw_from = $i1        < $start ? $start : $i1;
            my $draw_to   = $causal_i2 > $end   ? $end   : $causal_i2;
            if ( $draw_from <= $draw_to ) {
                my $dp1 = $pr1 + $slope * ( $draw_from - $i1 );
                my $dp2 = $pr1 + $slope * ( $draw_to   - $i1 );
                my $x1  = $scale->index_to_center_x($draw_from);
                my $x2  = $scale->index_to_center_x($draw_to);
                my $y1  = $scale->value_to_y($dp1);
                my $y2  = $scale->value_to_y($dp2);
                $canvas->createLine( $x1, $y1, $x2, $y2, -fill => $color, -width => 2,
                    -tags => [ 'zz_a_all', 'zz_a_line', 'zz_a_pending' ] );
            }
        }
    }

    for my $p (@pivots) {
        next if $p->{index} < $start || $p->{index} > $end;
        my $x     = $scale->index_to_center_x( $p->{index} );
        my $y     = $scale->value_to_y( $p->{price} );
        my $y_off = ( $p->{type} eq 'high' ) ? -10 : 10;

        $canvas->createText( $x, $y + $y_off, -text => $p->{label}, -fill => $color,
            -font => 'Helvetica 8 bold', -anchor => 'center',
            -tags => [ 'zz_a_all', 'zz_a_label' ] );
    }
    return;
}

# =============================================================================
# render_zigzag_b — "ZigZag Multi Time Frame [ZZMTF]"
# =============================================================================
sub render_zigzag_b {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('zz_b_all');
    return unless $sb && $scale;

    my $limit    = defined $replay_limit ? $replay_limit : $end;
    my $up_color = $self->{theme}{zz_b_up} // '#26a69a';
    my $dn_color = $self->{theme}{zz_b_dn} // '#ef5350';

    my @pivots = $self->_visible_pivots( $sb->get_zigzag_b, $start, $end, $limit );
    return unless @pivots;

    # Misma correccion anti-deslizamiento que render_zigzag_a (interpolar al
    # recortar en vez de dejar el precio crudo del pivote).
    for my $i ( 0 .. $#pivots - 1 ) {
        my $p1 = $pivots[$i];
        my $p2 = $pivots[ $i + 1 ];
        my $color = ( $p1->{type} eq 'low' ) ? $up_color : $dn_color;

        next if $p2->{index} < $start;
        next if $p1->{index} > $end;

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

        $canvas->createLine( $x1, $y1, $x2, $y2, -fill => $color, -width => 2,
            -tags => [ 'zz_b_all', 'zz_b_line' ] );
    }

    for my $p (@pivots) {
        next if $p->{index} < $start || $p->{index} > $end;
        my $color = ( $p->{type} eq 'high' ) ? $dn_color : $up_color;
        my $x     = $scale->index_to_center_x( $p->{index} );
        my $y     = $scale->value_to_y( $p->{price} );
        my $y_off = ( $p->{type} eq 'high' ) ? -10 : 10;

        $canvas->createText( $x, $y + $y_off, -text => $p->{label}, -fill => $color,
            -font => 'Helvetica 8 bold', -anchor => 'center',
            -tags => [ 'zz_b_all', 'zz_b_label' ] );
    }
    return;
}

# -----------------------------------------------------------------------------
# _visible_pivots — Filtra pivots por causalidad (<=$limit) solamente.
# FIX (linea derecha desaparecia): antes tambien filtraba por "<= $end",
# lo que significaba que si el pivote SIGUIENTE todavia no habia entrado en
# pantalla, ese pivote no formaba parte de la lista devuelta -> el segmento
# que lo conecta con el anterior nunca se intentaba dibujar (ni siquiera
# recortado), y la linea parecia "desaparecer" hasta que ambos puntos
# quedaban visibles a la vez. Ahora se devuelven TODOS los pivotes causales
# desde uno antes de $start en adelante; el recorte a la ventana visible
# (con interpolacion) lo hace cada funcion de render, segmento por segmento.
# -----------------------------------------------------------------------------
sub _visible_pivots {
    my ( $self, $pivots, $start, $end, $limit ) = @_;

    my @visible = grep { $_->{index} <= $limit } @$pivots;
    return () unless @visible;

    my $first = 0;
    for my $idx ( 0 .. $#visible ) {
        if ( $visible[$idx]{index} >= $start ) { $first = $idx > 0 ? $idx - 1 : 0; last; }
        $first = $idx;
    }
    return @visible[ $first .. $#visible ];
}

# =============================================================================
# render_avp — "AVP" (Perfil de Volumen Anclado). Dibuja:
#   - Un histograma horizontal: una fila visual por cada franja de precio
#     (o grupo de franjas, ver FIX abajo), creciendo desde el borde DERECHO
#     hacia la izquierda (igual que "Colocacion: Derecha" de la referencia),
#     partida en dos colores (celeste=volumen alcista, rosa=volumen bajista).
#   - 3 lineas negras/moradas horizontales: VAH (arriba), POC (medio), VAL (abajo).
# El perfil se calcula UNA vez (recompute_avp, bajo demanda) y no cambia
# con el scroll -- este metodo solo lo DIBUJA, recortado a la ventana
# visible; no recalcula nada.
#
# FIX (el histograma desaparecia por completo al alejar el zoom): las 1000
# franjas de datos se agrupan en "filas visuales" por pixel entero, sumando
# su volumen, y cada fila visual se dibuja SIEMPRE con minimo 1px de alto
# (nunca se descarta ninguna). Asi el perfil completo nunca desaparece,
# igual que en TradingView: con zoom in se ven muchas filas finas, con
# zoom out se agrupan en menos filas pero el histograma sigue visible.
# =============================================================================
sub render_avp {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('avp_all');
    return unless $sb && $scale;
    return unless $sb->can('get_avp');

    my $avp = $sb->get_avp;
    return unless $avp && @{ $avp->{bins} };

    my $limit      = defined $replay_limit ? $replay_limit : $end;
    my $anchor_idx = $avp->{anchor_index};
    my $end_idx    = $avp->{end_index};

    return if $anchor_idx > $limit;
    return if $anchor_idx > $end || $end_idx < $start;

    my $box_left  = $anchor_idx < $start ? $start : $anchor_idx;
    my $box_right = $end_idx > $end ? $end : $end_idx;
    $box_right    = $limit if $box_right > $limit;
    return if $box_right < $box_left;

    my $x_left  = $scale->index_to_center_x($box_left);
    my $x_right = $scale->index_to_center_x($box_right);

    my $bins = $avp->{bins};

    eval { $canvas->lower( 'avp_box', 'candle' ) };

    my $up_color   = $self->_blend_with_bg( $self->{theme}{avp_up}   // '#7fdbda', $self->{theme}{avp_alpha} // 0.55 );
    my $down_color = $self->_blend_with_bg( $self->{theme}{avp_down} // '#f75990', $self->{theme}{avp_alpha} // 0.55 );
    my $max_width_px = ( $x_right - $x_left ) * ( $self->{theme}{avp_max_width_pct} // 0.30 );

    my @visual_rows;
    my $cur_key;
    my $cur;

    for my $b (@$bins) {
        my $total = $b->{up_vol} + $b->{down_vol};
        next if $total <= 0;

        my $y_hi = $scale->value_to_y( $b->{price_hi} );
        my $y_lo = $scale->value_to_y( $b->{price_lo} );
        my $row_key = int($y_hi);

        if ( defined $cur_key && $cur_key == $row_key ) {
            $cur->{up_vol}   += $b->{up_vol};
            $cur->{down_vol} += $b->{down_vol};
            $cur->{y_lo}      = $y_lo if $y_lo > $cur->{y_lo};
        } else {
            push @visual_rows, $cur if $cur;
            $cur_key = $row_key;
            $cur = {
                y_hi     => $y_hi,
                y_lo     => $y_lo,
                up_vol   => $b->{up_vol},
                down_vol => $b->{down_vol},
            };
        }
    }
    push @visual_rows, $cur if $cur;
    return unless @visual_rows;

    my $max_vol = 1;
    for my $row (@visual_rows) {
        my $t = $row->{up_vol} + $row->{down_vol};
        $max_vol = $t if $t > $max_vol;
    }

    for my $row (@visual_rows) {
        my $total = $row->{up_vol} + $row->{down_vol};
        next if $total <= 0;

        my $row_h = $row->{y_lo} - $row->{y_hi};
        $row_h = 1 if $row_h < 1;

        my $gap = $row_h > 3 ? 1 : 0;
        my $ry1 = $row->{y_hi} + $gap;
        my $ry2 = $row->{y_hi} + $row_h - $gap;
        ( $ry1, $ry2 ) = ( $row->{y_hi}, $row->{y_hi} + $row_h ) if $ry2 <= $ry1;

        my $bar_width  = $max_width_px * ( $total / $max_vol );
        my $up_width   = $bar_width * ( $row->{up_vol}   / $total );
        my $down_width = $bar_width * ( $row->{down_vol} / $total );

        my $x_edge = $x_right;
        if ( $down_width > 0 ) {
            $canvas->createRectangle(
                $x_edge - $down_width, $ry1, $x_edge, $ry2,
                -fill => $down_color, -outline => '',
                -tags => [ 'avp_all', 'avp_bar' ],
            );
            $x_edge -= $down_width;
        }
        if ( $up_width > 0 ) {
            $canvas->createRectangle(
                $x_edge - $up_width, $ry1, $x_edge, $ry2,
                -fill => $up_color, -outline => '',
                -tags => [ 'avp_all', 'avp_bar' ],
            );
        }
    }

    eval { $canvas->lower( 'avp_bar', 'candle' ) };

    my $line_color = $self->{theme}{avp_line} // '#c98bff';
    for my $lvl ( $avp->{vah}, $avp->{poc}, $avp->{val} ) {
        my $y = $scale->value_to_y($lvl);
        $canvas->createLine( $x_left, $y, $x_right, $y,
            -fill => $line_color, -width => 1,
            -tags => [ 'avp_all', 'avp_level' ] );
    }

    return;
}

# --- helpers ---
sub _blend_with_bg {
    my ( $self, $hex, $alpha ) = @_;
    my $bg = $self->{theme}{panel_bg} // '#131722';
    my ( $r1, $g1, $b1 ) = map { hex($_) } ( $hex =~ /^#(..)(..)(..)$/ );
    my ( $r2, $g2, $b2 ) = map { hex($_) } ( $bg  =~ /^#(..)(..)(..)$/ );
    return sprintf( '#%02x%02x%02x',
        int( $r1*$alpha + $r2*(1-$alpha) ),
        int( $g1*$alpha + $g2*(1-$alpha) ),
        int( $b1*$alpha + $b2*(1-$alpha) ) );
}

sub _fade_color {
    my ( $self, $hex, $alpha ) = @_;
    return $self->_blend_with_bg( $hex, $alpha );
}

# =============================================================================
# render_ghost_vwap — puerto de "Dynamic Swing Anchored VWAP by Josafa".
#
# [REESCRITO] Analizado directamente contra el codigo fuente Pine v6 real
# (el usuario lo adjunto). La version anterior le faltaba la pieza mas
# importante del indicador original: el "ghost_level", una linea horizontal
# que se re-ancla en cada pivote (confirmado O fantasma) y se EXTIENDE
# permanentemente hasta la vela actual (en Pine: line.set_x2(ghost_level[1],
# b) se ejecuta EN CADA BARRA). Esa es la linea verde/roja que recorre el
# grafico en la imagen de referencia -- y que antes simplemente no se
# dibujaba (solo existia el marcador puntual 👻 "en vivo", sin ninguna linea
# horizontal). Por eso "desaparecia": nunca habia existido.
#
# Tambien se corrigen los colores para que calcen con el Pine real:
#   - El zigzag confirmado colorea cada tramo segun su ORIGEN (sale de un
#     minimo -> verde/alcista, sale de un maximo -> rojo/bajista), igual
#     que "color=miss_pl_css" al conectar hacia un ph y viceversa en el
#     Pine, y el mismo criterio que ya usa render_zigzag_b en este archivo.
#     Antes se coloreaba segun el DESTINO del tramo (al reves).
#   - Los marcadores fantasma (👻) usan el color de su PROPIO tipo (rojo si
#     es un maximo fantasma, verde si es un minimo fantasma -- miss_ph_css/
#     miss_pl_css del Pine), no un gris generico como antes.
#
# Dibuja, en este orden:
#   1. Trail historico: cada pivote (confirmado o fantasma) extiende su
#      nivel de precio en una linea horizontal hasta el INDICE del
#      siguiente pivote (equivalente a los segmentos ya "congelados" del
#      ghost_level del Pine).
#   2. Trail en vivo: el ULTIMO pivote extiende su nivel hasta el limite
#      causal actual ($limit) -- esta es la linea que NUNCA debe
#      desaparecer, equivalente al ghost_level extendiendose cada barra.
#   3. Zigzag: lineas conectando pivotes consecutivos (solido si ambos son
#      confirmados, punteado si alguno es fantasma), color segun el origen.
#   4. Etiquetas: ▼/▲ para confirmados, 👻 para fantasma, color segun tipo.
#   5. Linea diagonal punteada del ultimo pivote al marcador "en vivo"
#      (equivalente a line.new(px1,py1,x_last,y_last,...,dashed) del Pine).
#   6. Marcador "en vivo" (👻, equivalente a barstate.islast).
#   7. VWAP dinamico anclado al ultimo pivote, con bandas (sin cambios).
#
# Namespace de tags propio ('ghost_all') para prender/apagar sin afectar
# al VWAP normal ni a nada mas.
# =============================================================================
sub render_ghost_vwap {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('ghost_all');
    return unless $sb && $scale;
    return unless $sb->can('get_ghost_pivots');

    my $limit   = defined $replay_limit ? $replay_limit : $end;
    my $pivots  = $sb->get_ghost_pivots;
    return unless $pivots && @$pivots;

    my $reg_high_color = $self->{theme}{ghost_reg_high} // '#ef5350';   # rojo (miss_ph_css/reg_ph_css)
    my $reg_low_color  = $self->{theme}{ghost_reg_low}  // '#26a69a';   # verde (miss_pl_css/reg_pl_css)

    # Color segun el TIPO del propio punto (no segun direccion del tramo).
    # Se usa para los marcadores (confirmados y fantasma) y para el trail.
    my $color_for_type = sub {
        my ($type) = @_;
        return ( $type eq 'high' ) ? $reg_high_color : $reg_low_color;
    };

    my @vis = grep { $_->{index} <= $limit } @$pivots;

    # =========================================================================
    # 1) TRAIL HISTORICO — cada pivote (confirmado o fantasma) extiende su
    # nivel de precio horizontalmente hasta el indice del SIGUIENTE pivote.
    # Equivalente a los segmentos de "ghost_level" ya congelados en el Pine
    # (cada vez que aparece un pivote nuevo, la linea anterior deja de
    # extenderse y se crea una nueva desde el nuevo punto).
    # =========================================================================
    for my $i ( 0 .. $#vis - 1 ) {
        my $p1 = $vis[$i];
        my $p2 = $vis[ $i + 1 ];
        next if $p2->{index} < $start;
        next if $p1->{index} > $end;

        my $li = $p1->{index} < $start ? $start : $p1->{index};
        my $ri = $p2->{index} > $end   ? $end   : $p2->{index};
        next if $ri < $li;

        my $x1 = $scale->index_to_center_x($li);
        my $x2 = $scale->index_to_center_x($ri);
        my $y  = $scale->value_to_y( $p1->{price} );
        my $trail_color = $self->_blend_with_bg( $color_for_type->( $p1->{type} ), 0.5 );

        $canvas->createLine( $x1, $y, $x2, $y,
            -fill => $trail_color, -width => 2,
            -tags => [ 'ghost_all', 'ghost_trail' ] );
    }

    # =========================================================================
    # 2) TRAIL EN VIVO — el ULTIMO pivote extiende su nivel hasta el limite
    # causal actual ($limit, que respeta Replay). ESTA es la linea que debe
    # persistir siempre mientras el indicador este prendido -- nunca debe
    # desaparecer, sin importar el zoom o el scroll.
    # =========================================================================
    if (@vis) {
        my $last_p = $vis[-1];
        if ( $last_p->{index} <= $limit && $last_p->{index} <= $end ) {
            my $li = $last_p->{index} < $start ? $start : $last_p->{index};
            my $ri = $limit > $end ? $end : $limit;
            if ( $ri >= $li ) {
                my $x1 = $scale->index_to_center_x($li);
                my $x2 = $scale->index_to_center_x($ri);
                my $y  = $scale->value_to_y( $last_p->{price} );
                my $trail_color = $self->_blend_with_bg( $color_for_type->( $last_p->{type} ), 0.5 );

                $canvas->createLine( $x1, $y, $x2, $y,
                    -fill => $trail_color, -width => 2,
                    -tags => [ 'ghost_all', 'ghost_trail', 'ghost_trail_live' ] );
            }
        }
    }

    # =========================================================================
    # 3) ZIGZAG — lineas conectando pivotes consecutivos causales. Color
    # segun el ORIGEN del tramo (sale de un LOW -> verde/alcista, sale de un
    # HIGH -> rojo/bajista), igual criterio que el Pine y que
    # render_zigzag_b de este mismo archivo. Punteado si cualquiera de los
    # dos extremos es un pivote fantasma.
    # =========================================================================
    for my $i ( 0 .. $#vis - 1 ) {
        my $p1 = $vis[$i];
        my $p2 = $vis[ $i + 1 ];
        next if $p2->{index} < $start;
        next if $p1->{index} > $end;

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

        my $is_dashed  = ( $p2->{is_ghost} || $p1->{is_ghost} );
        my $line_color = $color_for_type->( $p1->{type} );   # origen del tramo

        $canvas->createLine( $x1, $y1, $x2, $y2,
            -fill => $line_color,
            -width => 1, ( $is_dashed ? ( -dash => [ 3, 3 ] ) : () ),
            -tags => [ 'ghost_all', 'ghost_line' ] );
    }

    # =========================================================================
    # 4) ETIQUETAS — ▼/▲ para confirmados, 👻 para fantasma. Color SIEMPRE
    # segun el tipo del propio punto (un fantasma alto es tan rojo como uno
    # confirmado; ya no hay un gris generico separado).
    # =========================================================================
    for my $p (@vis) {
        next if $p->{index} < $start || $p->{index} > $end;
        my $x       = $scale->index_to_center_x( $p->{index} );
        my $y       = $scale->value_to_y( $p->{price} );
        my $is_high = ( $p->{type} eq 'high' );
        my $y_off   = $is_high ? -10 : 10;
        my $color   = $color_for_type->( $p->{type} );

        if ( $p->{is_ghost} ) {
            $canvas->createText( $x, $y + $y_off, -text => '👻', -fill => $color,
                -font => 'Helvetica 9', -anchor => 'center',
                -tags => [ 'ghost_all', 'ghost_label' ] );
        } else {
            $canvas->createText( $x, $y + $y_off, -text => ( $is_high ? '▼' : '▲' ),
                -fill => $color,
                -font => 'Helvetica 9 bold', -anchor => 'center',
                -tags => [ 'ghost_all', 'ghost_label' ] );
        }
    }

    # =========================================================================
    # 5) LINEA DIAGONAL PUNTEADA hacia el marcador "en vivo" — equivalente a
    # line.new(px1, py1, x_last, y_last, ..., style=line.style_dashed) del
    # Pine: muestra hacia donde se esta formando el proximo pivote.
    # =========================================================================
    if ( @vis && $sb->can('get_ghost_live_marker') ) {
        my $last_p = $vis[-1];
        my $live   = $sb->get_ghost_live_marker;

        if ( $live && $live->{index} >= $last_p->{index} && $live->{index} <= $limit
            && $live->{index} >= $start && $last_p->{index} <= $end )
        {
            my $i1 = $last_p->{index} < $start ? $start : $last_p->{index};
            my $i2 = $live->{index}  > $end    ? $end   : $live->{index};
            if ( $i2 >= $i1 ) {
                my $slope = ( $last_p->{index} != $live->{index} )
                    ? ( $live->{price} - $last_p->{price} ) / ( $live->{index} - $last_p->{index} )
                    : 0;
                my $dp1 = $last_p->{price} + $slope * ( $i1 - $last_p->{index} );
                my $dp2 = $last_p->{price} + $slope * ( $i2 - $last_p->{index} );

                my $x1 = $scale->index_to_center_x($i1);
                my $x2 = $scale->index_to_center_x($i2);
                my $y1 = $scale->value_to_y($dp1);
                my $y2 = $scale->value_to_y($dp2);

                my $color = $color_for_type->( $last_p->{type} );
                $canvas->createLine( $x1, $y1, $x2, $y2,
                    -fill => $color, -width => 1, -dash => [ 3, 3 ],
                    -tags => [ 'ghost_all', 'ghost_pending' ] );
            }
        }
    }

    # =========================================================================
    # 6) MARCADOR "EN VIVO" (equivalente a barstate.islast): 👻 en el
    # extremo mas reciente hacia donde se dirige el proximo pivote.
    # =========================================================================
    if ( $sb->can('get_ghost_live_marker') ) {
        my $live = $sb->get_ghost_live_marker;
        if ( $live && $live->{index} >= $start && $live->{index} <= $end && $live->{index} <= $limit ) {
            my $x     = $scale->index_to_center_x( $live->{index} );
            my $y     = $scale->value_to_y( $live->{price} );
            my $y_off = ( $live->{type} eq 'high' ) ? -10 : 10;
            my $color = $color_for_type->( $live->{type} );
            $canvas->createText( $x, $y + $y_off, -text => '👻', -fill => $color,
                -font => 'Helvetica 10', -anchor => 'center',
                -tags => [ 'ghost_all', 'ghost_live' ] );
        }
    }

    # =========================================================================
    # 7) VWAP dinamico anclado al ultimo pivote (mismo estilo que el VWAP
    # normal) — SIN CAMBIOS respecto a la version anterior.
    # =========================================================================
    my $data = $sb->can('get_ghost_vwap') ? $sb->get_ghost_vwap : undef;
    if ($data) {
        my $line_color  = $self->{theme}{ghost_vwap_line}  // '#ba68c8';
        my $band1_color = $self->{theme}{ghost_vwap_band1} // '#4CD964';
        my $band2_color = $self->{theme}{ghost_vwap_band2} // '#8d6e63';

        my ( @vwap_xy, @b1hi_xy, @b1lo_xy, @b2hi_xy, @b2lo_xy );
        for my $idx ( $start .. ( $limit < $end ? $limit : $end ) ) {
            my $d = $data->[$idx];
            next unless $d;
            my $x = $scale->index_to_center_x($idx);
            push @vwap_xy, [ $x, $scale->value_to_y( $d->{vwap} ) ];
            push @b1hi_xy, [ $x, $scale->value_to_y( $d->{band1_hi} ) ];
            push @b1lo_xy, [ $x, $scale->value_to_y( $d->{band1_lo} ) ];
            push @b2hi_xy, [ $x, $scale->value_to_y( $d->{band2_hi} ) ];
            push @b2lo_xy, [ $x, $scale->value_to_y( $d->{band2_lo} ) ];
        }

        if ( @b1hi_xy >= 2 ) {
            my @poly = ( ( map { @$_ } @b1hi_xy ), ( map { @$_ } reverse @b1lo_xy ) );
            $canvas->createPolygon( @poly, -fill => $band1_color, -stipple => 'gray25',
                -outline => '', -tags => [ 'ghost_all', 'ghost_vwap_zone' ] );
            eval { $canvas->lower( 'ghost_vwap_zone', 'candle' ) };
        }

        for my $set ( [ \@b2hi_xy, $band2_color ], [ \@b2lo_xy, $band2_color ],
                      [ \@b1hi_xy, $band1_color ], [ \@b1lo_xy, $band1_color ] )
        {
            my ( $pts, $color ) = @$set;
            next unless @$pts >= 2;
            $canvas->createLine( ( map { @$_ } @$pts ),
                -fill => $color, -width => 1, -tags => [ 'ghost_all', 'ghost_vwap_band' ] );
        }

        if ( @vwap_xy >= 2 ) {
            $canvas->createLine( ( map { @$_ } @vwap_xy ),
                -fill => $line_color, -width => 2, -tags => [ 'ghost_all', 'ghost_vwap_line' ] );
        }
    }

    return;
}

# =============================================================================
# render_ghost — [REEMPLAZADO] Antes era un alias de render_ghost_vwap
# ("Dynamic Swing Anchored VWAP by Josafa"). A pedido explicito del
# usuario, el boton "Ghost" ahora dibuja OTRO indicador, extraido de otro
# proyecto Perl/Tk del usuario: "Pivot Points High Low & Missed Reversal
# Levels [LuxAlgo]" (ver Market::Indicators::Strategy_Builder::_update_pph
# y get_pph_values). render_ghost_vwap se deja intacta y sin usar (por si
# se necesita a futuro); este metodo ahora reenvia a render_ghost_pph.
# =============================================================================
sub render_ghost {
    my $self = shift;
    return $self->render_ghost_pph(@_);
}

# =============================================================================
# render_ghost_pph — "Pivot Points High Low & Missed Reversal Levels
# [LuxAlgo]". Puerto EXTRAIDO de otro proyecto del usuario
# (Market::Overlays::PivotPointsHL alla), adaptado a las convenciones de
# ESTE overlay (mismo patron canvas->createLine/createText que el resto de
# este archivo, coordenadas absolutas via $scale->index_to_center_x/
# value_to_y en vez de indices "locales"). Usa el mismo namespace de tags
# ('ghost_all') que el viejo render_ghost_vwap, asi el boton "Ghost" y su
# logica de mostrar/ocultar en ChartEngine.pm no necesitan ningun cambio.
#
# Dibuja, en este orden (fondo -> frente):
#   1) Ghost levels: lineas horizontales semitransparentes (stipple) al
#      nivel de cada pivote, cortadas en el siguiente pivote (no se
#      extienden hasta el final del grafico).
#   2) Zigzag entre pivotes: solido = confirmado, punteado = missed.
#   3) Etiquetas ▼ (high, rojo) / ▲ (low, verde) / 👻 (fantasma, en los
#      pivotes "perdidos").
#   4) Fantasma PROVISIONAL (el pivote en formacion de la vela mas
#      reciente): diagonal punteada + horizontal semitransparente hasta
#      "ahora" (respetando Replay) + etiqueta 👻.
#
# Respeta Replay igual que el resto del archivo: nada con indice > $limit
# se dibuja, aunque el indicador (100% causal) ya nunca calcula nada mas
# alla de la vela que se le alimento.
# =============================================================================
# =============================================================================
# render_pph_vwap_auto — BLOQUE VWAP AUTO-ANCLADO AL PENULTIMO PIVOTE
# (NUEVO, punto 4 del enunciado). Dibuja la serie calculada en
# Market::Indicators::Strategy_Builder::get_pph_vwap_series (linea VWAP +
# banda 1 rellena + banda 2 en lineas), EXACTAMENTE el mismo estilo visual
# que render_vwap (el VWAP manual de este archivo) -- la unica diferencia
# es que el ancla la elige el propio indicador (el ultimo pivote
# confirmado del Ghost), no un clic del usuario. Tag propio
# ('pph_vwap_all') para poder mostrarlo/ocultarlo con su propio boton sin
# afectar al Ghost ni al VWAP manual.
# =============================================================================
sub render_pph_vwap_auto {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('pph_vwap_all');
    return unless $sb && $scale;
    return unless $sb->can('get_pph_vwap_series') && $sb->can('get_pph_vwap_anchor');

    my $limit  = defined $replay_limit ? $replay_limit : $end;
    my $anchor = $sb->get_pph_vwap_anchor;
    return unless defined $anchor;
    return if $anchor > $limit;

    my $series = $sb->get_pph_vwap_series;
    return unless $series;

    my $line_color  = $self->{theme}{pph_vwap_line}  // '#ba68c8';
    my $band1_color = $self->{theme}{pph_vwap_band1} // '#4CD964';
    my $band2_color = $self->{theme}{pph_vwap_band2} // '#8d6e63';

    my $draw_from = $anchor < $start ? $start : $anchor;
    my $draw_to   = $limit  > $end   ? $end   : $limit;
    return if $draw_to < $draw_from;

    my ( @vwap_xy, @b1hi_xy, @b1lo_xy, @b2hi_xy, @b2lo_xy );
    for my $idx ( $draw_from .. $draw_to ) {
        my $d = $series->[$idx];
        next unless $d;
        my $x = $scale->index_to_center_x($idx);
        push @vwap_xy, [ $x, $scale->value_to_y( $d->{vwap} ) ];
        push @b1hi_xy, [ $x, $scale->value_to_y( $d->{band1_hi} ) ];
        push @b1lo_xy, [ $x, $scale->value_to_y( $d->{band1_lo} ) ];
        push @b2hi_xy, [ $x, $scale->value_to_y( $d->{band2_hi} ) ];
        push @b2lo_xy, [ $x, $scale->value_to_y( $d->{band2_lo} ) ];
    }
    return unless @vwap_xy >= 2;

    if ( @b1hi_xy >= 2 ) {
        my @poly = ( ( map { @$_ } @b1hi_xy ), ( map { @$_ } reverse @b1lo_xy ) );
        $canvas->createPolygon( @poly,
            -fill => $band1_color, -stipple => 'gray25', -outline => '',
            -tags => [ 'pph_vwap_all', 'pph_vwap_zone' ] );
        eval { $canvas->lower( 'pph_vwap_zone', 'candle' ) };
    }

    for my $set ( [ \@b2hi_xy, $band2_color ], [ \@b2lo_xy, $band2_color ],
                  [ \@b1hi_xy, $band1_color ], [ \@b1lo_xy, $band1_color ] )
    {
        my ( $pts, $color ) = @$set;
        next unless @$pts >= 2;
        $canvas->createLine( ( map { @$_ } @$pts ),
            -fill => $color, -width => 1, -tags => [ 'pph_vwap_all', 'pph_vwap_band' ] );
    }

    $canvas->createLine( ( map { @$_ } @vwap_xy ),
        -fill => $line_color, -width => 2, -tags => [ 'pph_vwap_all', 'pph_vwap_line' ] );

    return;
}

sub render_ghost_pph {
    my ( $self, $canvas, $sb, $scale, $start, $end, $replay_limit ) = @_;

    $canvas->delete('ghost_all');
    return unless $sb && $scale;
    return unless $sb->can('get_pph_values');

    my $limit = defined $replay_limit ? $replay_limit : $end;
    my $vals  = $sb->get_pph_values;
    return unless $vals;

    my $col_ph = $self->{theme}{pph_high} // '#ef5350';   # rojo (reg_ph/miss_ph)
    my $col_pl = $self->{theme}{pph_low}  // '#26a69a';   # verde (reg_pl/miss_pl)

    my $color_for = sub {
        my ($key) = @_;
        return $col_ph if $key eq 'reg_ph' || $key eq 'miss_ph';
        return $col_pl if $key eq 'reg_pl' || $key eq 'miss_pl';
        return '#9598a1';
    };

    # ¿El segmento [a,b] cae dentro de la ventana visible Y es causalmente
    # valido (no cruza mas alla del limite de Replay)?
    my $seg_ok = sub {
        my ( $a, $b ) = @_;
        return 0 if !defined $a || !defined $b;
        return 0 if $a > $limit;
        my ( $lo, $hi ) = $a <= $b ? ( $a, $b ) : ( $b, $a );
        return 0 if $hi < $start;
        return 0 if $lo > $end;
        return 1;
    };

    # 1) Ghost levels (al fondo)
    for my $g ( @{ $vals->{ghost_levels} || [] } ) {
        my $to = $g->{to_index} // $end;
        $to = $limit if $to > $limit;
        next unless $seg_ok->( $g->{index}, $to );
        my $x1 = $scale->index_to_center_x( $g->{index} );
        my $x2 = $scale->index_to_center_x($to);
        my $y  = $scale->value_to_y( $g->{price} );
        $canvas->createLine( $x1, $y, $x2, $y,
            -fill => $color_for->( $g->{color_key} ), -width => 2, -stipple => 'gray50',
            -tags => [ 'ghost_all', 'ghost_trail' ] );
    }

    # 2) Zigzag (solido confirmado / punteado missed-pendiente)
    for my $s ( @{ $vals->{zigzag} || [] } ) {
        next unless defined $s->{from_price} && defined $s->{to_price};
        next unless $seg_ok->( $s->{from_index}, $s->{to_index} );
        my @opts = ( -fill => $color_for->( $s->{color_key} ), -width => 2,
            -tags => [ 'ghost_all', 'ghost_line' ] );
        push @opts, ( -dash => [ 3, 3 ] ) if ( $s->{style} // '' ) eq 'dashed';
        $canvas->createLine(
            $scale->index_to_center_x( $s->{from_index} ), $scale->value_to_y( $s->{from_price} ),
            $scale->index_to_center_x( $s->{to_index} ),   $scale->value_to_y( $s->{to_price} ),
            @opts );
    }

    # 3) Etiquetas de pivotes (▼ / ▲ / 👻)
    for my $lb ( @{ $vals->{labels} || [] } ) {
        next if $lb->{index} > $limit;
        next if $lb->{index} < $start || $lb->{index} > $end;
        $self->_pph_draw_label( $canvas,
            $scale->index_to_center_x( $lb->{index} ), $scale->value_to_y( $lb->{price} ),
            $lb->{glyph}, $lb->{dir}, $color_for->( $lb->{color_key} ) );
    }

    # 4) Fantasma provisional (se mueve vela a vela hasta que un pivote
    # real lo confirma; "n" se recorta al limite de Replay para no
    # extender la horizontal mas alla de "ahora").
    if ( my $p = $vals->{provisional} ) {
        if ( $p->{index} <= $limit && $p->{from_index} <= $limit ) {
            my $line_col  = $color_for->( $p->{line_key}  // $p->{color_key} );
            my $ghost_col = $color_for->( $p->{ghost_key} // $p->{color_key} );
            my $to = $p->{last_index} // $end;
            $to = $limit if $to > $limit;

            if ( $seg_ok->( $p->{from_index}, $p->{index} ) ) {
                $canvas->createLine(
                    $scale->index_to_center_x( $p->{from_index} ), $scale->value_to_y( $p->{from_price} ),
                    $scale->index_to_center_x( $p->{index} ),      $scale->value_to_y( $p->{price} ),
                    -fill => $line_col, -width => 2, -dash => [ 3, 3 ],
                    -tags => [ 'ghost_all', 'ghost_pending' ] );
            }
            if ( $seg_ok->( $p->{index}, $to ) ) {
                $canvas->createLine(
                    $scale->index_to_center_x( $p->{index} ), $scale->value_to_y( $p->{price} ),
                    $scale->index_to_center_x($to),            $scale->value_to_y( $p->{price} ),
                    -fill => $line_col, -width => 2, -stipple => 'gray50',
                    -tags => [ 'ghost_all', 'ghost_trail_live' ] );
            }
            if ( $p->{index} >= $start && $p->{index} <= $end ) {
                $self->_pph_draw_label( $canvas,
                    $scale->index_to_center_x( $p->{index} ), $scale->value_to_y( $p->{price} ),
                    'ghost', $p->{dir}, $ghost_col );
            }
        }
    }

    return;
}

# -----------------------------------------------------------------------------
# _pph_draw_label — dibuja la etiqueta de un pivote CON PRIMITIVAS DE CANVAS
# (lineas/poligonos), NO con texto Unicode.
#
# [FIX] La version anterior usaba "\x{25BC}"/"\x{25B2}"/"\x{1F47B}"
# (triangulos y el emoji 👻) como texto via createText. En este entorno
# Tk/Perl esos caracteres llegan corruptos al canvas (se ven como "â¼",
# "â²" -- bytes UTF-8 mal interpretados) en vez del simbolo real. El
# proyecto de referencia de donde se extrajo este Ghost ya se habia
# topado con este mismo problema ("Fedora35/Tk no renderiza el emoji") y
# lo resuelve dibujando el fantasma y los triangulos con primitivas de
# canvas (poligonos/ovalos) en vez de depender de que la fuente del
# sistema tenga esos glifos -- funciona identico sin importar el entorno.
# Se porta ese mismo dibujo aqui, tal cual se ve en la referencia real.
#
# dir 'down' -> arriba del precio (marca de high); 'up' -> debajo (marca
# de low). Offset 12px, igual que la referencia.
# -----------------------------------------------------------------------------
sub _pph_draw_label {
    my ( $self, $canvas, $x, $y, $glyph, $dir, $color ) = @_;
    my $dy = ( $dir eq 'down' ) ? -12 : 12;
    my $ly = $y + $dy;

    if ( $glyph eq 'ghost' ) {
        $self->_pph_draw_ghost_shape( $canvas, $x, $ly, $color );
        return;
    }

    # Triangulo solido: ▼ (reg_high, apunta hacia abajo) o ▲ (reg_low,
    # apunta hacia arriba), ~5px de radio -- mismo tamaño visual que el
    # texto Unicode que reemplaza.
    my $w = 5;
    my @pts;
    if ( $glyph eq 'reg_high' ) {
        @pts = ( $x - $w, $ly - $w, $x + $w, $ly - $w, $x, $ly + $w );
    } else {
        @pts = ( $x, $ly - $w, $x + $w, $ly + $w, $x - $w, $ly + $w );
    }
    $canvas->createPolygon( @pts,
        -fill => $color, -outline => $color,
        -tags => [ 'ghost_all', 'ghost_label' ] );
    return;
}

# -----------------------------------------------------------------------------
# _pph_draw_ghost_shape — fantasma dibujado con primitivas (cabeza
# redondeada + base ondulada + 2 ojos blancos), ~14px de alto. Puerto
# EXACTO del dibujo del proyecto de referencia -- mismo resultado visual
# que las capturas del usuario (el "pac-man" cian con ojitos).
# -----------------------------------------------------------------------------
sub _pph_draw_ghost_shape {
    my ( $self, $canvas, $cx, $cy, $color ) = @_;
    my $w = 5;    # medio ancho
    my $h = 6;    # medio alto

    my @body = (
        $cx - $w,       $cy + $h,
        $cx - $w,       $cy - $h * 0.3,
        $cx - $w * 0.6, $cy - $h,
        $cx,            $cy - $h * 1.15,
        $cx + $w * 0.6, $cy - $h,
        $cx + $w,       $cy - $h * 0.3,
        $cx + $w,       $cy + $h,
        $cx + $w * 0.5, $cy + $h * 0.5,
        $cx,            $cy + $h,
        $cx - $w * 0.5, $cy + $h * 0.5,
    );
    $canvas->createPolygon( @body,
        -fill => $color, -outline => $color,
        -tags => [ 'ghost_all', 'ghost_label' ] );

    my $er = 1.1;
    for my $ex ( -$w * 0.4, $w * 0.4 ) {
        $canvas->createOval(
            $cx + $ex - $er, $cy - $er - 1,
            $cx + $ex + $er, $cy + $er - 1,
            -fill => '#ffffff', -outline => '#ffffff',
            -tags => [ 'ghost_all', 'ghost_label' ],
        );
    }
    return;
}

1;