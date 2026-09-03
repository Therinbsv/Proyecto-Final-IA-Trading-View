#!/usr/bin/env perl
# =============================================================================
# extract_features.pl — FASE 2: Extractor de caracteristicas
#
# Uso:
#   perl extract_features.pl <entrada.csv> <salida.csv>
#
#   perl extract_features.pl Data/2026_Abril-Junio.csv features_train.csv
#   perl extract_features.pl Data/2026_07_24.csv       features_test.csv
#
# Corre por separado sobre cada CSV (no mezcla train/test) -- coincide con
# como pide el enunciado: "Cargar el modelo entrenado para el testeo" usa
# una tabla DISTINTA a la de entrenamiento.
#
# =============================================================================
# DEFINICION OPERATIVA DE "APARICION" Y "RASTRO" (necesaria para programar
# esto, ya que el indicador de Ghost/PPH no guarda un conteo -- solo guarda
# los pivotes reales y "fantasma" retroactivos cuando SE CONFIRMA un pivote
# real, ver Market::Indicators::Strategy_Builder::_pph_on_pivot_high/low).
#
# Lo que SI existe en vivo, vela a vela, es get_pph_values()->{provisional}:
# el extremo mas favorable (mayor high / menor low) marcado desde el ultimo
# pivote CONFIRMADO (_pph_px1/_pph_py1) hasta la vela actual. Esto es
# EXACTAMENTE el "fantasma que se desplaza dejando un rastro" que describe
# el enunciado: cada vez que ese extremo se mueve (index o precio cambia
# respecto a la vela anterior), el fantasma "dejo un rastro" ahi.
#
#   RASTRO     = la vela en la que get_pph_values()->{provisional} cambio
#                de valor respecto a la vela anterior (el fantasma se movio).
#   APARICION  = el PRIMER rastro despues de que cambio el ancla
#                (get_pph_vwap_anchor(), que es _pph_px1 -- el ultimo pivote
#                YA confirmado). O sea: el fantasma "nace" apenas se
#                confirma un pivote nuevo, y cada extension posterior de
#                ese mismo fantasma (antes de que el PROXIMO pivote se
#                confirme) es una REUBICACION.
#
# El enunciado pide una muestra nueva "a cada nueva reubicacion" -- no solo
# en la aparicion -- asi que ESTE script abre una muestra (fila) nueva en
# CADA rastro (aparicion o reubicacion por igual), no solo en la aparicion.
# Cada muestra cuenta, para SI MISMA, los rastros que ocurran DESPUES de
# ella dentro de sus propias ventanas de 3/5/10/15 minutos -- lo cual
# tambien incluye reubicaciones de ESE MISMO fantasma que sigan ocurriendo,
# ademas de fantasmas nuevos que aparezcan mientras tanto.
# =============================================================================

use strict;
use warnings;
use utf8;
use lib '.';
use Time::Moment;

use Market::MarketData;
use Market::Indicators::ATR;
use Market::Indicators::SMC_Structures;
use Market::Indicators::Liquidity;
use Market::Indicators::Strategy_Builder;

# =============================================================================
# CONFIG — AJUSTAR ANTES DE CORRER
# =============================================================================
# TODO(usuario): confirmar el tamaño de 1 pip para tu instrumento (NQ). Si
# tu profe/proyecto ya define "1 pip = 1 punto" o "= 0.25" (un tick), poné
# ese valor aca. Mientras tanto uso 1 punto = 1 "pip" (conversion neutra,
# NO cambia el ORDEN relativo de las distancias, solo la escala) para que
# el pipeline corra completo hoy -- se puede recalcular sin re-extraer nada
# mas que multiplicar la columna por un factor, si al final confirman otro
# valor.
use constant PIP_SIZE => 1.0;

# Ventanas de conteo de rastros (minutos)
my @WINDOWS_MIN = ( 3, 5, 10, 15 );

# Parametros de los indicadores — DEBEN calzar con los que usa market.pl,
# para que "Order Block"/"FVG"/"BOS"/etc signifiquen lo mismo que ya viste
# en pantalla.
my %SMC_ARGS = (
    int_sens      => 3,
    ext_sens      => 25,
    macro_prd     => 2,
    ref_tf_min    => 30,
    fvg_atr_len   => 55,
    fvg_max_count => 15,
);
my %SB_ARGS = ( a_length => 150, b_period => 2 );

# =============================================================================
# ARGUMENTOS
# =============================================================================
my ( $INPUT_CSV, $OUTPUT_CSV ) = @ARGV;
die "Uso: perl extract_features.pl <entrada.csv> <salida.csv>\n"
    unless $INPUT_CSV && $OUTPUT_CSV;

# =============================================================================
# CARGA DEL CSV 1m — mismo formato/parseo que market.pl
# =============================================================================
sub load_1m_csv {
    my ($path) = @_;
    open my $fh, '<', $path or die "No se pudo abrir '$path': $!\n";
    my @out;
    <$fh>;    # descarta cabecera
    while (<$fh>) {
        chomp;
        my ( $time_str, $open, $high, $low, $close, $volume ) = split /,/;
        next unless defined $close && $close ne '';
        my $tm;
        eval { $tm = Time::Moment->from_string($time_str) };
        next if $@;
        push @out, {
            time   => $time_str,
            ts     => $tm->epoch,
            open   => $open  + 0,
            high   => $high  + 0,
            low    => $low   + 0,
            close  => $close + 0,
            volume => $volume + 0,
        };
    }
    close $fh;
    return \@out;
}

print "Cargando $INPUT_CSV...\n";
my $candles_1m = load_1m_csv($INPUT_CSV);
my $N = scalar @$candles_1m;
printf "  %d velas de 1m cargadas\n", $N;
die "No hay datos, nada que extraer.\n" if $N == 0;

# =============================================================================
# Market::Simple1m — wrapper minimo tipo Market::MarketData (get_candle/
# size/last_index/get_timeframe), directo sobre el arrayref de velas 1m.
# No dependemos de la API interna de Market::MarketData (build_timeframes,
# etc) para no arriesgar romper algo que no vimos en este chat -- este
# extractor es un script APARTE de la GUI, no toca market.pl para nada.
# =============================================================================
package Market::Simple1m;
sub new { my ( $class, $candles ) = @_; return bless { candles => $candles }, $class; }
sub get_candle  { my ( $self, $i ) = @_; return undef if $i < 0 || $i > $#{ $self->{candles} }; return $self->{candles}[$i]; }
sub size        { my ($self) = @_; return scalar @{ $self->{candles} }; }
sub last_index  { my ($self) = @_; return $#{ $self->{candles} }; }
sub get_timeframe { return '1m'; }
package main;

# =============================================================================
# Market::AggCandles — agrega velas 1m en un timeframe sintetico (10m, 1h),
# con el MISMO criterio de anclaje que usa el resto del proyecto para
# temporalidades >=60min (+1h de ancla) -- ver _macro_htf_bucket en
# SMC_Structures.pm, que replica el mismo anclaje. Ademas guarda, por cada
# indice de la serie 1m, cual es el indice de la vela agregada "activa"
# (la que esta cerrando o en formacion) en ese punto -- eso es lo que deja
# alimentar los indicadores de 10m/1h en el momento CAUSALMENTE correcto
# (nunca antes de que esa vela exista en el tiempo real).
# =============================================================================
package Market::AggCandles;
sub new {
    my ( $class, $candles_1m, $bucket_min ) = @_;
    my $interval_sec = $bucket_min * 60;
    my $anchor_sec   = ( $bucket_min >= 60 ) ? 3600 : 0;

    my @agg;
    my %bucket_to_idx;
    my @map_1m_to_agg;

    for my $c (@$candles_1m) {
        my $bucket_ts = int( ( $c->{ts} - $anchor_sec ) / $interval_sec ) * $interval_sec + $anchor_sec;
        my $idx = $bucket_to_idx{$bucket_ts};
        if ( !defined $idx ) {
            push @agg, {
                ts => $bucket_ts, time => $c->{time},
                open => $c->{open}, high => $c->{high}, low => $c->{low}, close => $c->{close},
                volume => $c->{volume} // 0,
            };
            $idx = $#agg;
            $bucket_to_idx{$bucket_ts} = $idx;
        } else {
            my $b = $agg[$idx];
            $b->{high}  = $c->{high} if $c->{high} > $b->{high};
            $b->{low}   = $c->{low}  if $c->{low}  < $b->{low};
            $b->{close} = $c->{close};
            $b->{volume} += ( $c->{volume} // 0 );
        }
        push @map_1m_to_agg, $idx;
    }
    return bless { candles => \@agg, map_1m => \@map_1m_to_agg }, $class;
}
sub get_candle    { my ( $self, $i ) = @_; return undef if $i < 0 || $i > $#{ $self->{candles} }; return $self->{candles}[$i]; }
sub size          { my ($self) = @_; return scalar @{ $self->{candles} }; }
sub last_index    { my ($self) = @_; return $#{ $self->{candles} }; }
sub get_timeframe { return 'agg'; }
sub agg_index_for_1m { my ( $self, $i ) = @_; return $self->{map_1m}[$i]; }
package main;

print "Agregando temporalidades sinteticas 10m / 1h...\n";
my $agg10 = Market::AggCandles->new( $candles_1m, 10 );
my $agg1h = Market::AggCandles->new( $candles_1m, 60 );
my $md1m  = Market::Simple1m->new($candles_1m);

# =============================================================================
# Indicadores — un juego completo (smc/liq/sb) POR temporalidad, mismos
# parametros que market.pl para que "Order Block"/"FVG"/etc en 10m/1h
# signifiquen lo mismo conceptualmente que en 1m (solo cambia la escala de
# tiempo de las velas que ven).
# =============================================================================
sub make_indicator_set {
    my $smc = Market::Indicators::SMC_Structures->new(%SMC_ARGS);
    my $liq = Market::Indicators::Liquidity->new( swing_length => 3 );
    my $sb  = Market::Indicators::Strategy_Builder->new(%SB_ARGS);
    $smc->set_liquidity_engine($liq) if $smc->can('set_liquidity_engine');
    return { smc => $smc, liq => $liq, sb => $sb };
}

print "Inicializando indicadores (1m / 10m / 1h)...\n";
my $ind1m = make_indicator_set();
my $ind10 = make_indicator_set();
my $ind1h = make_indicator_set();

# =============================================================================
# HELPERS DE DISTANCIA — cada uno devuelve { signed_pips, range_pips } del
# nivel MAS CERCANO a $ref_price entre los ya confirmados/vigentes hasta
# $idx (causal: nunca usa datos que "todavia no pasaron" en esa temporalidad).
#
# CONVENCION DE SIGNO (importante para el modelo -- separa interes de
# compra vs venta, tal como pidio el profe): positivo = el nivel queda POR
# DEBAJO del precio de referencia (soporte, interes de compra). Negativo =
# el nivel queda POR ENCIMA (resistencia, interes de venta).
# =============================================================================
sub to_pips { my ($price_diff) = @_; return $price_diff / PIP_SIZE; }

sub _better {
    my ( $best, $dist ) = @_;
    return 1 unless defined $best;
    return $dist < $best->{_absdist};
}

sub nearest_order_block {
    my ( $smc, $idx, $ref ) = @_;
    my $best;
    for my $ob ( @{ $smc->get_order_blocks }, @{ $smc->get_internal_order_blocks } ) {
        next if $ob->{start_index} > $idx;
        next if $ob->{mitigated} && defined $ob->{mitigated_index} && $ob->{mitigated_index} <= $idx;
        my $mid  = ( $ob->{top} + $ob->{bottom} ) / 2;
        my $dist = abs( $ref - $mid );
        if ( _better( $best, $dist ) ) {
            $best = { _absdist => $dist, signed_pips => to_pips( $ref - $mid ), range_pips => to_pips( $ob->{top} - $ob->{bottom} ) };
        }
    }
    return $best;
}

sub nearest_fvg {
    my ( $smc, $idx, $ref ) = @_;
    my $best;
    for my $fvg ( @{ $smc->get_fvgs } ) {
        next if $fvg->{start_index} > $idx;
        next if defined $fvg->{full_index}    && $fvg->{full_index}    <= $idx;
        next if defined $fvg->{evicted_index} && $fvg->{evicted_index} <= $idx;
        my $mid  = ( $fvg->{top} + $fvg->{bottom} ) / 2;
        my $dist = abs( $ref - $mid );
        if ( _better( $best, $dist ) ) {
            $best = { _absdist => $dist, signed_pips => to_pips( $ref - $mid ), range_pips => to_pips( $fvg->{top} - $fvg->{bottom} ) };
        }
    }
    return $best;
}

sub nearest_structure_level {
    # BOS/CHoCH (incluye I-BOS/I-CHOCH tambien -- son el mismo array).
    my ( $smc, $idx, $ref, $want_types ) = @_;
    my %want = map { $_ => 1 } @$want_types;
    my $best;
    for my $s ( @{ $smc->get_structures } ) {
        next unless $want{ $s->{type} };
        next if $s->{event_index} > $idx;
        my $dist = abs( $ref - $s->{level} );
        if ( _better( $best, $dist ) ) {
            $best = { _absdist => $dist, signed_pips => to_pips( $ref - $s->{level} ), range_pips => 0 };
        }
    }
    return $best;
}

sub nearest_eq {
    my ( $smc, $idx, $ref ) = @_;
    my $best;
    for my $e ( @{ $smc->get_equal_levels } ) {
        next if $e->{idx2} > $idx;
        my $lvl  = ( $e->{price1} + $e->{price2} ) / 2;
        my $dist = abs( $ref - $lvl );
        if ( _better( $best, $dist ) ) {
            $best = { _absdist => $dist, signed_pips => to_pips( $ref - $lvl ), range_pips => to_pips( abs( $e->{price1} - $e->{price2} ) ) };
        }
    }
    return $best;
}

sub nearest_supply_demand {
    my ( $sb, $idx, $ref ) = @_;
    my $best;
    for my $z ( @{ $sb->get_supply_zones }, @{ $sb->get_demand_zones } ) {
        next if $z->{left_index} > $idx;
        next if $z->{broken} && defined $z->{broken_index} && $z->{broken_index} <= $idx;
        my $dist = abs( $ref - $z->{poi} );
        if ( _better( $best, $dist ) ) {
            $best = { _absdist => $dist, signed_pips => to_pips( $ref - $z->{poi} ), range_pips => to_pips( $z->{top} - $z->{bottom} ) };
        }
    }
    return $best;
}

# --- VWAP auto-anclado al penultimo pivote (Ghost/PPH) — punto 4 del enunciado ---
sub vwap_auto_distances {
    my ( $sb, $idx, $ref ) = @_;
    my $series = $sb->get_pph_vwap_series;
    my $d = $series->[$idx];
    return undef unless $d;
    return {
        vwap_pips     => to_pips( $ref - $d->{vwap} ),
        band1_hi_pips => to_pips( $ref - $d->{band1_hi} ),
        band1_lo_pips => to_pips( $ref - $d->{band1_lo} ),
        band2_hi_pips => to_pips( $ref - $d->{band2_hi} ),
        band2_lo_pips => to_pips( $ref - $d->{band2_lo} ),
    };
}

# --- AVP (POC/VAH/VAL) anclado al ULTIMO pivote confirmado del ZigZag Ex —
# punto 5 del enunciado ("anclado al impulso consolidado del zigzag
# externo"). Se recalcula on-demand en cada evento usando el mismo metodo
# recompute_avp_from_index que ya existe (bloque 1.2b de la bitacora,
# implementado directamente aca en el extractor en vez de en la GUI). ---
sub avp_distances {
    my ( $sb, $market_tf, $idx, $ref ) = @_;
    my $pivots = $sb->get_zigzag_a;
    return undef unless $pivots && @$pivots;
    my $anchor_idx;
    for my $p (@$pivots) {
        last if $p->{index} > $idx;
        $anchor_idx = $p->{index};
    }
    return undef unless defined $anchor_idx;
    return undef unless $sb->can('recompute_avp_from_index');

    # OJO RENDIMIENTO: esto recalcula el AVP completo desde el ancla hasta
    # $idx CADA VEZ que se llama (una vez por muestra, no por vela) -- si
    # el extractor corre lento, este es el primer lugar a revisar (podria
    # cachearse mientras el ancla no cambie, mismo patron que el VWAP
    # auto). Se deja simple por ahora para priorizar la entrega de hoy.
    $sb->recompute_avp_from_index( $market_tf, $anchor_idx );
    my $avp = $sb->get_avp;
    return undef unless $avp;
    return {
        poc_pips => to_pips( $ref - $avp->{poc} ),
        vah_pips => to_pips( $ref - $avp->{vah} ),
        val_pips => to_pips( $ref - $avp->{val} ),
    };
}

# =============================================================================
# TODO(usuario) — Grupo 6 (S/R 4h/D/W): mismo patron que Market::AggCandles
# de arriba (agregar 4h/D/W y correr SMC_Structures modo 'swing' sobre esas
# velas), no lo arme todavia por tiempo -- es la pieza mas facil de sumar
# despues, mismo molde que 10m/1h.
#
# TODO(usuario) — Grupo 3 (Fibonacci auto-anclado): pendiente igual que
# dice la bitacora (Fase 1.2c) -- por ahora sentinela+flag.
#
# Grupo 11 (Canal/Tendline): SALTEADO por completo -- el enunciado lo
# marca como opcional ("solo si correctamente implementado").
# =============================================================================
# --- Sweep/Grab/Run (grupo 9) — usa Market::Indicators::Liquidity::
# get_levels() (misma forma de datos que ya usa Market::Overlays::Liquidity
# para dibujar: {start_index, type BSL/SSL, price, status, sweep_index,
# resolved_index}). Solo cuenta niveles que YA tuvieron sweep/grab/run
# confirmado -- "debidamente justificadas con su nivel de liquidez". ---
sub nearest_liquidity {
    my ( $liq, $idx, $ref ) = @_;
    return undef unless $liq->can('get_levels');
    my $best;
    for my $lvl ( @{ $liq->get_levels } ) {
        next if $lvl->{start_index} > $idx;
        next unless $lvl->{status} && $lvl->{status} =~ /^(swept|grab|run)$/;
        my $event_idx = $lvl->{sweep_index} // $lvl->{resolved_index};
        next if defined $event_idx && $event_idx > $idx;
        my $dist = abs( $ref - $lvl->{price} );
        if ( _better( $best, $dist ) ) {
            $best = { _absdist => $dist, signed_pips => to_pips( $ref - $lvl->{price} ), range_pips => 0 };
        }
    }
    return $best;
}

use constant SENTINEL => -999999;

# =============================================================================
# EXTRACCION DE UNA MUESTRA (features), en el indice $idx de la serie 1m.
# =============================================================================
my $vol_ema9 = undef;   # EMA(9) del volumen 1m, se mantiene fuera de esta
                         # funcion (estado que avanza vela a vela, ver loop)

sub extract_sample {
    my ($idx) = @_;
    my $c = $candles_1m->[$idx];
    return undef unless $c;

    my $ref_price = ( $c->{high} + $c->{low} + $c->{close} ) / 3;   # HLC3, misma fuente que el resto del proyecto

    my %f;   # features
    $f{event_index} = $idx;
    $f{event_ts}     = $c->{ts};
    $f{event_time}   = $c->{time};   # metadata -- NO entra al modelo

    # --- columnas extra (1m) ---
    $f{atr_1m}        = $ind1m->{smc}{_atr_current};   # ya calculado por SMC_Structures (mismo ATR interno)
    $f{volume_1m}     = $c->{volume};
    $f{vol_ema9_1m}   = $vol_ema9;

    # --- por temporalidad: 1m / 10m / 1h ---
    my %tf_map = (
        '1m'  => { ind => $ind1m, md => $md1m, idx => $idx },
        '10m' => { ind => $ind10, md => $agg10, idx => $agg10->agg_index_for_1m($idx) },
        '1h'  => { ind => $ind1h, md => $agg1h, idx => $agg1h->agg_index_for_1m($idx) },
    );

    for my $tf ( '1m', '10m', '1h' ) {
        my $t   = $tf_map{$tf};
        my $smc = $t->{ind}{smc};
        my $sb  = $t->{ind}{sb};
        my $i2  = $t->{idx};

        my $ob  = nearest_order_block( $smc, $i2, $ref_price );
        my $fvg = nearest_fvg( $smc, $i2, $ref_price );
        my $bos = nearest_structure_level( $smc, $i2, $ref_price, [ 'BOS', 'CHOCH' ] );
        my $eq  = nearest_eq( $smc, $i2, $ref_price );
        my $sd  = nearest_supply_demand( $sb, $i2, $ref_price );
        my $vw  = vwap_auto_distances( $sb, $i2, $ref_price );
        my $avp = avp_distances( $sb, $t->{md}, $i2, $ref_price );

        # Order Block
        $f{"ob_dist_pips_$tf"}  = $ob  ? $ob->{signed_pips}  : SENTINEL;
        $f{"ob_range_pips_$tf"} = $ob  ? $ob->{range_pips}   : SENTINEL;
        $f{"ob_flag_$tf"}       = $ob  ? 1 : 0;
        # FVG
        $f{"fvg_dist_pips_$tf"}  = $fvg ? $fvg->{signed_pips} : SENTINEL;
        $f{"fvg_range_pips_$tf"} = $fvg ? $fvg->{range_pips}  : SENTINEL;
        $f{"fvg_flag_$tf"}       = $fvg ? 1 : 0;
        # BOS/CHoCH
        $f{"bos_dist_pips_$tf"} = $bos ? $bos->{signed_pips} : SENTINEL;
        $f{"bos_flag_$tf"}      = $bos ? 1 : 0;
        # EQH/EQL
        $f{"eq_dist_pips_$tf"} = $eq ? $eq->{signed_pips} : SENTINEL;
        $f{"eq_flag_$tf"}      = $eq ? 1 : 0;
        # Supply/Demand
        $f{"sd_dist_pips_$tf"}  = $sd ? $sd->{signed_pips} : SENTINEL;
        $f{"sd_range_pips_$tf"} = $sd ? $sd->{range_pips}  : SENTINEL;
        $f{"sd_flag_$tf"}       = $sd ? 1 : 0;
        # VWAP auto (penultimo pivote)
        if ($vw) {
            $f{"vwap_dist_pips_$tf"}     = $vw->{vwap_pips};
            $f{"vwap_band1hi_pips_$tf"}  = $vw->{band1_hi_pips};
            $f{"vwap_band1lo_pips_$tf"}  = $vw->{band1_lo_pips};
            $f{"vwap_band2hi_pips_$tf"}  = $vw->{band2_hi_pips};
            $f{"vwap_band2lo_pips_$tf"}  = $vw->{band2_lo_pips};
            $f{"vwap_flag_$tf"}          = 1;
        } else {
            $f{"vwap_dist_pips_$tf"} = $f{"vwap_band1hi_pips_$tf"} = $f{"vwap_band1lo_pips_$tf"}
                = $f{"vwap_band2hi_pips_$tf"} = $f{"vwap_band2lo_pips_$tf"} = SENTINEL;
            $f{"vwap_flag_$tf"} = 0;
        }
        # AVP (POC/VAH/VAL)
        if ($avp) {
            $f{"avp_poc_pips_$tf"} = $avp->{poc_pips};
            $f{"avp_vah_pips_$tf"} = $avp->{vah_pips};
            $f{"avp_val_pips_$tf"} = $avp->{val_pips};
            $f{"avp_flag_$tf"}     = 1;
        } else {
            $f{"avp_poc_pips_$tf"} = $f{"avp_vah_pips_$tf"} = $f{"avp_val_pips_$tf"} = SENTINEL;
            $f{"avp_flag_$tf"} = 0;
        }
        # Fibonacci — TODO(usuario), sentinela por ahora
        $f{"fib_dist_pips_$tf"} = SENTINEL;
        $f{"fib_flag_$tf"}      = 0;
        # S/R 4h/D/W — TODO(usuario), sentinela por ahora (no depende de $tf realmente)
        $f{"sr_dist_pips_$tf"} = SENTINEL;
        $f{"sr_flag_$tf"}      = 0;
        # Sweep/Grab/Run
        my $sw = nearest_liquidity( $t->{ind}{liq}, $i2, $ref_price );
        $f{"sweep_dist_pips_$tf"} = $sw ? $sw->{signed_pips} : SENTINEL;
        $f{"sweep_flag_$tf"}      = $sw ? 1 : 0;
    }

    return {
        idx       => $idx,
        features  => \%f,
        event_ts  => $c->{ts},
        count     => { map { $_ => 0 } @WINDOWS_MIN },
        closed    => { map { $_ => 0 } @WINDOWS_MIN },
        finalized => 0,
    };
}

sub finalize_row {
    my ($s) = @_;
    my %row = %{ $s->{features} };
    for my $w (@WINDOWS_MIN) {
        $row{"rastros_${w}m"} = $s->{count}{$w};
        $row{"rastro_${w}m_bin"} = ( $s->{count}{$w} > 0 ) ? 1 : 0;   # target de clasificacion (binarizado)
    }
    return \%row;
}

# =============================================================================
# LOOP PRINCIPAL
# =============================================================================
print "Extrayendo (esto puede tardar, corre TODOS los indicadores 1m/10m/1h)...\n";

my $last10_fed = -1;
my $last1h_fed = -1;
my $prev_prov_key = undef;
my $current_anchor = undef;
my @open_samples;
my @rows;

my $total_apariciones = 0;
my $total_rastros     = 0;

for my $i ( 0 .. $N - 1 ) {
    my $c = $candles_1m->[$i];

    # EMA(9) del volumen 1m — se mantiene siempre, la usen o no las muestras
    my $k9 = 2 / ( 9 + 1 );
    $vol_ema9 = defined $vol_ema9 ? ( $c->{volume} * $k9 + $vol_ema9 * ( 1 - $k9 ) ) : $c->{volume};

    # --- alimentar indicadores 1m ---
    $ind1m->{smc}->update_at_index( $md1m, $i );
    $ind1m->{liq}->update_at_index( $md1m, $i ) if $ind1m->{liq}->can('update_at_index');
    $ind1m->{sb}->update_at_index( $md1m, $i );

    # --- alimentar 10m / 1h en cuanto haya barras nuevas disponibles (causal) ---
    my $agg10_now = $agg10->agg_index_for_1m($i);
    while ( $last10_fed < $agg10_now ) {
        $last10_fed++;
        $ind10->{smc}->update_at_index( $agg10, $last10_fed );
        $ind10->{liq}->update_at_index( $agg10, $last10_fed ) if $ind10->{liq}->can('update_at_index');
        $ind10->{sb}->update_at_index( $agg10, $last10_fed );
    }
    my $agg1h_now = $agg1h->agg_index_for_1m($i);
    while ( $last1h_fed < $agg1h_now ) {
        $last1h_fed++;
        $ind1h->{smc}->update_at_index( $agg1h, $last1h_fed );
        $ind1h->{liq}->update_at_index( $agg1h, $last1h_fed ) if $ind1h->{liq}->can('update_at_index');
        $ind1h->{sb}->update_at_index( $agg1h, $last1h_fed );
    }

    # --- detectar movimiento del fantasma (rastro) en 1m ---
    my $pph  = $ind1m->{sb}->get_pph_values;
    my $prov = $pph->{provisional};

    my $moved = 0;
    if ($prov) {
        my $key = "$prov->{index}:$prov->{price}";
        $moved = ( !defined $prev_prov_key || $key ne $prev_prov_key );
        $prev_prov_key = $key;
    }

    if ($moved) {
        $total_rastros++;
        my $anchor_now = $ind1m->{sb}->get_pph_vwap_anchor;
        my $is_new_anchor = ( !defined $current_anchor || ( defined $anchor_now && $anchor_now != $current_anchor ) );
        $current_anchor = $anchor_now if defined $anchor_now;

        # Se abre una muestra nueva en CADA rastro (aparicion o
        # reubicacion), en la vela SIGUIENTE -- ver definicion operativa
        # al inicio del archivo.
        $total_apariciones++ if $is_new_anchor;
        my $event_idx = $i + 1;
        if ( $event_idx < $N ) {
            my $sample = extract_sample($event_idx);
            push @open_samples, $sample if $sample;
        }

        # Este mismo rastro cuenta para todas las muestras YA abiertas
        # cuyo evento haya sido ANTES de esta vela.
        for my $s (@open_samples) {
            next if $i <= $s->{idx};
            my $dt_min = ( $c->{ts} - $s->{event_ts} ) / 60;
            for my $w (@WINDOWS_MIN) {
                next if $s->{closed}{$w};
                $s->{count}{$w}++ if $dt_min <= $w;
            }
        }
    }

    # --- cerrar muestras cuya ventana de 15 min ya se cumplio ---
    my $now_ts = $c->{ts};
    my @still_open;
    for my $s (@open_samples) {
        if ( ( $now_ts - $s->{event_ts} ) / 60 > $WINDOWS_MIN[-1] ) {
            push @rows, finalize_row($s);
        } else {
            push @still_open, $s;
        }
    }
    @open_samples = @still_open;

    printf "  ... %d / %d velas procesadas (%d muestras cerradas)\n", $i + 1, $N, scalar(@rows)
        if ( $i + 1 ) % 20000 == 0;
}

# Cerrar lo que haya quedado abierto al final del archivo (con lo que se
# alcanzo a contar hasta ahi -- ventanas incompletas, pero se guardan
# igual: mejor tener el dato parcial que perder la muestra por completo).
for my $s (@open_samples) {
    push @rows, finalize_row($s);
}

printf "Listo: %d apariciones nuevas, %d rastros totales, %d muestras finales.\n",
    $total_apariciones, $total_rastros, scalar(@rows);

# =============================================================================
# ESCRITURA DEL CSV DE SALIDA
# =============================================================================
die "No se genero ninguna muestra -- revisar los datos de entrada.\n" unless @rows;

my @cols = sort keys %{ $rows[0] };
# Metadata primero, despues features, despues targets (orden mas legible)
my @meta_cols   = grep { /^event_/ } @cols;
my @target_cols = grep { /^rastro/ } @cols;
my @feat_cols   = grep { my $c = $_; !( grep { $_ eq $c } @meta_cols, @target_cols ) } @cols;
@cols = ( @meta_cols, @feat_cols, @target_cols );

open my $out, '>', $OUTPUT_CSV or die "No se pudo escribir '$OUTPUT_CSV': $!\n";
print $out join( ',', @cols ), "\n";
for my $row (@rows) {
    print $out join( ',', map { defined $row->{$_} ? $row->{$_} : '' } @cols ), "\n";
}
close $out;

printf "Escrito: %s (%d columnas, %d filas)\n", $OUTPUT_CSV, scalar(@cols), scalar(@rows);
