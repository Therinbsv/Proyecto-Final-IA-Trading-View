# =============================================================================
# market.pl
# =============================================================================

use strict;
use warnings;
use lib '.';
use utf8;    
use Tk;
use Time::Moment;

use Market::MarketData;
use Market::IndicatorManager;
use Market::Indicators::ATR;
use Market::Indicators::SMC_Structures;
use Market::Indicators::Liquidity;
use Market::Indicators::Strategy_Builder;
use Market::Panels::Scales;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;
use Market::Overlays::SMC_Structures;
use Market::Overlays::Liquidity;
use Market::Overlays::Strategy_Builder;
use Market::ChartEngine;


# =============================================================================
# VENTANA
# =============================================================================
my $mw = MainWindow->new;
$mw->title('Trading Chart');
$mw->resizable(1, 1);
$mw->configure(-background => '#0c0e10');

eval { $mw->state('zoomed') };
eval { $mw->attributes('-zoomed', 1) };
$mw->update;

my $WIN_W = $mw->screenwidth;
my $WIN_H = $mw->screenheight;

if ($mw->width < $WIN_W * 0.9) {
    $mw->geometry("${WIN_W}x${WIN_H}+0+0");
    $mw->update;
}

$WIN_W = $mw->width  if $mw->width  > 100;
$WIN_H = $mw->height if $mw->height > 100;

# =============================================================================
# DIMENSIONES
# =============================================================================
my $PRICE_SCALE_W = 90;
my $TF_BAR_H      = 28;
my $ATR_H_MIN     = 60;
my $ATR_H_MAX     = 400;
my $ATR_H         = 140;
my $CANVAS_W      = $WIN_W;

# =============================================================================
# LAYOUT
# =============================================================================
my $tf_frame = $mw->Frame(-background => '#1c1f2b', -height => $TF_BAR_H)
    ->pack(-fill => 'x', -side => 'bottom');

# --- BLOQUE PESTAÑAS (NUEVO, reemplaza al viejo "ajuste automatico") ---
# A pedido del usuario: en vez de una sola barra larga con TODOS los
# botones (que igual se desbordaba en pantallas chicas, o necesitaba el
# sistema de reflow/varias filas), ahora hay una fila de PESTAÑAS fija
# arriba de todo ("Estructura", "Liquidez", "ZigZag", "Volumen"), y debajo
# aparece SOLO la fila de botones de la pestaña activa -- las demas quedan
# ocultas (packForget) hasta que se las elija. La pestaña activa se pinta
# resaltada (fondo azul), igual criterio visual que ya usa el resto del
# proyecto para "encendido/apagado".
#
# $tab_frames{$nombre} es el Frame donde se crean los botones de esa
# categoria (mas abajo, junto a cada boton real). Los botones NO se crean
# aca, solo los frames contenedores -- eso permite mantener cada boton
# definido junto a su callback correspondiente, como ya estaba organizado.
my $tabbar_frame = $mw->Frame(-background => '#14161f', -height => $TF_BAR_H)
    ->pack(-fill => 'x', -side => 'top');

my $tabs_content_frame = $mw->Frame(-background => '#1c1f2b', -height => $TF_BAR_H)
    ->pack(-fill => 'x', -side => 'top');

my @tab_order = ( 'Estructura', 'Liquidez', 'ZigZag', 'Volumen' );
my %tab_frames;
for my $name (@tab_order) {
    $tab_frames{$name} = $tabs_content_frame->Frame(-background => '#1c1f2b');
}

my %tab_buttons;
my $active_tab = $tab_order[0];

my $switch_tab;
$switch_tab = sub {
    my ($name) = @_;
    return unless exists $tab_frames{$name};
    $active_tab = $name;
    for my $t (@tab_order) {
        if ( $t eq $name ) {
            $tab_frames{$t}->pack( -fill => 'x', -side => 'top', -anchor => 'w' );
            $tab_buttons{$t}->configure( -background => '#2962ff', -foreground => '#ffffff' ) if $tab_buttons{$t};
        } else {
            $tab_frames{$t}->packForget;
            $tab_buttons{$t}->configure( -background => '#14161f', -foreground => '#787b86' ) if $tab_buttons{$t};
        }
    }
};

for my $name (@tab_order) {
    $tab_buttons{$name} = $tabbar_frame->Button(
        -text             => $name,
        -background       => '#14161f',
        -foreground       => '#787b86',
        -activebackground => '#2f3139',
        -activeforeground => '#ffffff',
        -relief           => 'flat',
        -bd               => 0,
        -font             => 'TkDefaultFont 9 bold',
        -padx             => 14,
        -pady             => 5,
        -command          => sub { $switch_tab->($name); },
    )->pack( -side => 'left' );
}

$switch_tab->($active_tab);   # pestaña inicial visible (frames aun vacios, se llenan mas abajo)

my $canvas_price = $mw->Canvas(
    -background         => '#131722',
    -bd                 => 0,
    -highlightthickness => 0,
)->pack(-fill => 'both', -expand => 1, -side => 'top');

my $sep_frame = $mw->Frame(
    -background => '#282a2e',
    -height     => 2,
    -cursor     => 'sb_v_double_arrow',
)->pack(-fill => 'x', -side => 'top');

my $canvas_atr = $mw->Canvas(
    -height             => $ATR_H,
    -background         => '#131722',
    -bd                 => 0,
    -highlightthickness => 0,
)->pack(-fill => 'x', -side => 'top');

# =============================================================================
# DATOS — BLOQUE MULTI-CSV
# Carga TODOS los archivos .csv que existan en la carpeta de datos (uno por
# mes, o parciales como 2026_06_29.csv), ordenados cronologicamente por
# nombre. Permite añadir mas meses en el futuro sin tocar el codigo.
# =============================================================================
print "Cargando datos...\n";
my $market = Market::MarketData->new;

my @data_dir_candidates = ('Data', 'data', '../Data', '../data', '.');
my $data_dir;
for my $d (@data_dir_candidates) {
    next unless -d $d;
    opendir( my $dh, $d ) or next;
    my @found = grep { /^\d{4}_\d{2}(_\d{2})?\.csv$/i } readdir($dh);
    closedir($dh);
    if (@found) { $data_dir = $d; last; }
}
die "No se encontraron archivos .csv (formato YYYY_MM.csv) en Data/ o data/\n"
    unless $data_dir;

opendir( my $dh, $data_dir ) or die "No se pudo abrir '$data_dir': $!\n";
my @csv_files = sort grep { /^\d{4}_\d{2}(_\d{2})?\.csv$/i } readdir($dh);
closedir($dh);

my $count = 0;
for my $fname (@csv_files) {
    my $path = "$data_dir/$fname";
    print "  Leyendo $path...\n";

    open my $fh, '<', $path or die "Error abriendo CSV '$path': $!\n";
    <$fh>;    # descarta cabecera
    while (<$fh>) {
        chomp;
        my ($time_str, $open, $high, $low, $close, $volume) = split /,/;
        next unless defined $close && $close ne '';
        my $tm;
        eval { $tm = Time::Moment->from_string($time_str) };
        next if $@;
        $market->add_candle({
            time   => $time_str,
            ts     => $tm->epoch,
            open   => $open  + 0,
            high   => $high  + 0,
            low    => $low   + 0,
            close  => $close + 0,
            volume => $volume + 0,
        });
        $count++;
    }
    close $fh;
}

printf "Cargadas %d velas de 1m (desde %d archivo%s: %s)\n",
    $count, scalar(@csv_files), ( @csv_files == 1 ? '' : 's' ), join( ', ', @csv_files );

$market->build_timeframes;
printf "5m: %d  |  15m: %d\n",
    scalar @{ $market->get_data->{'5m'} },
    scalar @{ $market->get_data->{'15m'} };


# =============================================================================
# INDICADORES
# =============================================================================
my $ind_manager = Market::IndicatorManager->new;
$ind_manager->register('atr', Market::Indicators::ATR->new(14));
$ind_manager->register('liq', Market::Indicators::Liquidity->new(swing_length => 3));
$ind_manager->register('smc', Market::Indicators::SMC_Structures->new(
    int_sens     => 3,
    ext_sens     => 25,
    macro_prd    => 2,      # periodo ZZMTF (sensibilidad del zigzag interno)
    ref_tf_min   => 30,     # TF de referencia: 30 minutos
    fvg_atr_len  => 55,
    fvg_max_count => 15,    # cuantos FVG se conservan por sesgo (alcista/bajista). Sube este numero si los quieres ver mas atras en el historico, bajalo si se ven muy amontonados.
));

# --- BLOQUE ZIGZAG (independiente de 'smc'): dos calculos de zigzag
# adaptados de indicadores reales de TradingView (ChartPrime y ZZMTF),
# aislados del indicador SMC para no interferir con BOS/CHoCH/FVG/etc. ---
$ind_manager->register('zigzags', Market::Indicators::Strategy_Builder->new(
    
    a_length => 150,   # ChartPrime "ZigZag Volume Profile": ventana movil
    b_period => 2,      # ZZMTF "ZigZag Multi Time Frame": periodo simetrico
));

# --- BLOQUE LIQUIDEZ: conectar SMC con el motor de liquidez ANTES de calcular ---
$ind_manager->get_indicator('smc')->set_liquidity_engine( $ind_manager->get_indicator('liq') );
# --- FIN BLOQUE LIQUIDEZ ---

print "Calculando ATR(14), liquidez y estructuras SMC...\n";
$ind_manager->rebuild_all($market);
printf "ATR listo: %d valores\n", scalar @{ $ind_manager->get('atr') };
printf "Liquidez lista: %d niveles BSL, %d niveles SSL\n",
    scalar @{ $ind_manager->get_indicator('liq')->get_bsl_zones },
    scalar @{ $ind_manager->get_indicator('liq')->get_ssl_zones };
printf "SMC listo: %d estructuras, %d FVGs, %d pivotes macro\n",
    scalar @{ $ind_manager->get_indicator('smc')->get_structures },
    scalar @{ $ind_manager->get_indicator('smc')->get_fvgs },
    scalar @{ $ind_manager->get_indicator('smc')->get_macro_pivots };

# =============================================================================
# PANELES Y MOTOR
# =============================================================================
my $price_panel = Market::Panels::PricePanel->new(
    canvas        => $canvas_price,
    price_scale_w => $PRICE_SCALE_W,
);
my $atr_panel = Market::Panels::ATRPanel->new(
    canvas        => $canvas_atr,
    price_scale_w => $PRICE_SCALE_W,
);



my $smc_overlay = Market::Overlays::SMC_Structures->new( theme => { panel_bg => '#131722' } );
my $liq_overlay = Market::Overlays::Liquidity->new(      theme => { panel_bg => '#131722' } );
my $strategy_overlay = Market::Overlays::Strategy_Builder->new( theme => { panel_bg => '#131722' } );

my $engine = Market::ChartEngine->new(
    market         => $market,
    indicators     => $ind_manager,
    canvas_price   => $canvas_price,
    canvas_atr     => $canvas_atr,
    price_panel    => $price_panel,
    atr_panel      => $atr_panel,
    smc_overlay    => $smc_overlay,  
    liquidity_overlay  => $liq_overlay,
    strategy_overlay   => $strategy_overlay,
    canvas_w       => $CANVAS_W,
    canvas_price_h => 0,
    canvas_atr_h   => $ATR_H,
);

# =============================================================================
# TOOLBAR — se crea ANTES de registrar callbacks para que los botones existan
# =============================================================================
my %bs = (
    -background       => '#1c1f2b',
    -foreground       => '#d1d4dc',
    -activebackground => '#2f3139',
    -activeforeground => '#ffffff',
    -relief           => 'flat',
    -bd               => 0,
    -font             => 'TkDefaultFont 9',
    -padx             => 5,
    -pady             => 3,
);

# -----------------------------------------------------------------------------
# %bs_top — mismo estilo que %bs, pero con ANCHO FIJO (en caracteres), para
# que todos los botones dentro de cada pestaña tengan el mismo tamaño.
# -----------------------------------------------------------------------------
my $TOP_BTN_WIDTH = 22;
my %bs_top = ( %bs, -width => $TOP_BTN_WIDTH );

$tf_frame->Label(%bs, -text => 'Zoom')
    ->pack(-side => 'left', -padx => 6, -pady => 2);

$tf_frame->Button(%bs, -text => '+',
    -command => sub { $engine->_horizontal_zoom(-1, 0) })
    ->pack(-side => 'left', -padx => 1, -pady => 2);
$tf_frame->Button(%bs, -text => '-',
    -command => sub { $engine->_horizontal_zoom(1, 0) })
    ->pack(-side => 'left', -padx => 1, -pady => 2);

# --- Inicio / Actual — navegacion rapida al principio o al final de las
# velas cargadas. Solo mueven el scroll horizontal (offset); no cambian el
# zoom ni interactuan con el bloque Replay mas alla de respetar su limite
# (si Replay esta activo, "Actual" lleva hasta el punto de Replay, no mas
# alla). ---
$tf_frame->Button(%bs, -text => 'Inicio',
    -command => sub { $engine->goto_start; })
    ->pack(-side => 'left', -padx => 1, -pady => 2);
$tf_frame->Button(%bs, -text => 'Actual',
    -command => sub { $engine->goto_current; })
    ->pack(-side => 'left', -padx => 1, -pady => 2);

$tf_frame->Frame(-background => '#282a2e', -width => 1, -height => 16)
    ->pack(-side => 'left', -pady => 5, -padx => 6);

# --- Boton modo precio ---
my $mode_btn;
$mode_btn = $tf_frame->Button(%bs,
    -text       => 'Modo Automático',
    -foreground => '#26a69a',
    -font       => 'TkDefaultFont 9 bold',
    -command    => sub {
        my $is_free = $engine->toggle_free_mode_price;
        # El callback se encarga de actualizar el boton
    },
)->pack(-side => 'left', -padx => 4, -pady => 2);

# --- Boton modo ATR ---
my $mode_btn_atr;
$mode_btn_atr = $tf_frame->Button(%bs,
    -text       => 'Modo Automático',
    -foreground => '#26a69a',
    -font       => 'TkDefaultFont 9 bold',
    -command    => sub {
        my $is_free = $engine->toggle_free_mode_atr;
        # El callback se encarga de actualizar el boton
    },
)->pack(-side => 'left', -padx => 4, -pady => 2);

$tf_frame->Frame(-background => '#282a2e', -width => 1, -height => 16)
    ->pack(-side => 'left', -pady => 5, -padx => 6);

# =============================================================================
# BOTONES DE VISIBILIDAD DE OVERLAYS SMC — organizados por PESTAÑA
# (Estructura / Liquidez / ZigZag / Volumen). Cada boton se crea dentro
# del Frame de su categoria ($tab_frames{...}) en vez de una barra unica;
# la pestaña activa decide cual fila de botones se ve.
# =============================================================================

# --- ZigZag In (pestaña "ZigZag") ---
my $swing_btn;
$swing_btn = $tab_frames{'ZigZag'}->Button(%bs_top, -text => 'ZigZag In: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_swing_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_swing_visibility_callback(sub {
    my ($v) = @_;
    $swing_btn->configure(-text => $v ? 'ZigZag In: ON' : 'ZigZag In: OFF', -foreground => $v ? '#2962ff' : '#787b86');
});

# --- Desplegable "ZigZag In: resolucion" — igual concepto que "ZigZag
# Resolution" del ZZMTF de referencia. Cambiar la resolucion dispara un
# recalculo completo del indicador SMC (ver ChartEngine::
# set_zigzag_in_resolution). El valor por defecto (30 min) debe calzar con
# el ref_tf_min pasado mas abajo al crear el indicador 'smc'.
#
# [CAMBIO — BOTONES EN LINEA] Antes esto era un desplegable (boton +
# Tk::Menu con hover). A pedido del usuario, ahora son 12 botones fijos
# en fila (como los de temporalidad de velas de mas abajo) -- entran
# comodos en el ancho de la pestaña "ZigZag" y funcionan como un grupo
# "radio": el que esta activo queda resaltado en azul, el resto apagados.
# ---
my @zigzag_in_resolutions = (
    [ 1,  '1m'  ], [ 2,  '2m'  ], [ 3,  '3m'  ],
    [ 5,  '5m'  ], [ 10, '10m' ], [ 15, '15m' ],
    [ 30, '30m' ], [ 45, '45m' ],
    [ 60, '1h'  ], [ 120, '2h' ], [ 180, '3h' ], [ 240, '4h' ],
);

my %zigzag_res_buttons;
my $active_zigzag_res = 30;   # debe calzar con ref_tf_min al crear el indicador 'smc'

my $highlight_zigzag_res;
$highlight_zigzag_res = sub {
    my ($mins) = @_;
    $active_zigzag_res = $mins;
    for my $r (@zigzag_in_resolutions) {
        my $m = $r->[0];
        next unless $zigzag_res_buttons{$m};
        if ( $m == $mins ) {
            $zigzag_res_buttons{$m}->configure( -background => '#2962ff', -foreground => '#ffffff' );
        } else {
            $zigzag_res_buttons{$m}->configure( -background => '#1c1f2b', -foreground => '#787b86' );
        }
    }
};

for my $r (@zigzag_in_resolutions) {
    my ( $mins, $label ) = @$r;
    $zigzag_res_buttons{$mins} = $tab_frames{'ZigZag'}->Button(
        -text             => $label,
        -background       => ( $mins == $active_zigzag_res ? '#2962ff' : '#1c1f2b' ),
        -foreground       => ( $mins == $active_zigzag_res ? '#ffffff' : '#787b86' ),
        -activebackground => '#2f3139',
        -activeforeground => '#ffffff',
        -relief           => 'flat',
        -bd               => 0,
        -font             => 'TkDefaultFont 9 bold',
        -padx             => 8,
        -pady             => 4,
        -command          => sub {
            $highlight_zigzag_res->($mins);
            $engine->set_zigzag_in_resolution($mins);
        },
    )->pack( -side => 'left', -padx => 1, -pady => 4 );
}

# --- ZigZag Ex (ChartPrime) (pestaña "ZigZag") ---
my $zz_a_btn;
$zz_a_btn = $tab_frames{'ZigZag'}->Button(%bs_top, -text => 'ZigZag Ex: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_zz_a_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_zz_a_visibility_callback(sub {
    my ($v) = @_;
    $zz_a_btn->configure(-text => $v ? 'ZigZag Ex: ON' : 'ZigZag Ex: OFF', -foreground => $v ? '#2962ff' : '#787b86');
});

# [QUITADO a pedido del usuario] Boton "MTF Levels" -- se elimino de la
# barra de herramientas. El metodo toggle_zz_b_visibility/
# set_zz_b_visibility_callback siguen existiendo en ChartEngine.pm sin
# uso (no rompe nada dejarlos), por si se necesitan a futuro.

# Callback: si la resolucion cambia por otra via (no por click directo en
# estos botones), sincroniza igual cual queda resaltado.
$engine->set_zigzag_in_resolution_callback(sub {
    my ($mins) = @_;
    $highlight_zigzag_res->($mins);
});

# --- VWAP anclado (con bandas de desviacion estandar) (pestaña "Volumen").
# YA NO tiene desplegable de meses: al presionar el boton estando
# apagado, entra en modo "elegi una vela" (mismo mecanismo que "Inicio
# Replay") -- el cursor cambia a cruz y aparece una linea punteada ambar
# que sigue al mouse con snapping; el proximo clic en el grafico fija el
# ancla ahi mismo y prende el VWAP. Si ya esta prendido, el boton
# simplemente lo apaga (para elegir otra vela, apagalo y volve a
# presionarlo). ---
my $vwap_btn;
$vwap_btn = $tab_frames{'Volumen'}->Button(%bs_top, -text => 'VWAP: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub {
        if ( $engine->is_vwap_visible ) {
            $engine->toggle_vwap_visibility;
        } else {
            $engine->begin_vwap_anchor_selection;
        }
    })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_vwap_visibility_callback(sub {
    my ($v) = @_;
    $vwap_btn->configure(-text => $v ? 'VWAP: ON' : 'VWAP: OFF', -foreground => $v ? '#2962ff' : '#787b86');
});
$engine->set_vwap_anchor_state_callback(sub {
    my ($awaiting) = @_;
    $vwap_btn->configure(-text => $awaiting ? 'VWAP: elegi una vela...' : 'VWAP: OFF',
        -foreground => $awaiting ? '#f7b500' : '#787b86');
});

# --- AVP (Perfil de Volumen Anclado) (pestaña "Volumen"). Mismo mecanismo
# de "clic para elegir" que el VWAP arriba -- ya NO ancla siempre en el
# indice 0. ---
my $avp_btn;
$avp_btn = $tab_frames{'Volumen'}->Button(%bs_top, -text => 'AVP: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub {
        if ( $engine->is_avp_visible ) {
            $engine->toggle_avp_visibility;
        } else {
            $engine->begin_avp_anchor_selection;
        }
    })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_avp_visibility_callback(sub {
    my ($v) = @_;
    $avp_btn->configure(-text => $v ? 'AVP: ON' : 'AVP: OFF', -foreground => $v ? '#f75990' : '#787b86');
});
$engine->set_avp_anchor_state_callback(sub {
    my ($awaiting) = @_;
    $avp_btn->configure(-text => $awaiting ? 'AVP: elegi una vela...' : 'AVP: OFF',
        -foreground => $awaiting ? '#f7b500' : '#787b86');
});

# --- BoS / CHoCH (externo) (pestaña "Estructura") ---
my $bos_btn;
$bos_btn = $tab_frames{'Estructura'}->Button(%bs_top, -text => 'BOS: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_bos_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_bos_visibility_callback(sub {
    my ($v) = @_;
    $bos_btn->configure(-text => $v ? 'BOS: ON' : 'BOS: OFF', -foreground => $v ? '#089981' : '#787b86');
});

my $choch_btn;
$choch_btn = $tab_frames{'Estructura'}->Button(%bs_top, -text => 'CHoCH: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_choch_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_choch_visibility_callback(sub {
    my ($v) = @_;
    $choch_btn->configure(-text => $v ? 'CHoCH: ON' : 'CHoCH: OFF', -foreground => $v ? '#f23645' : '#787b86');
});

# --- I-BoS / I-CHoCH (internos, estructura menor) (pestaña "Estructura") ---
my $ibos_btn;
$ibos_btn = $tab_frames{'Estructura'}->Button(%bs_top, -text => 'I-BoS: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_ibos_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_ibos_visibility_callback(sub {
    my ($v) = @_;
    $ibos_btn->configure(-text => $v ? 'I-BoS: ON' : 'I-BoS: OFF', -foreground => $v ? '#089981' : '#787b86');
});

my $ichoch_btn;
$ichoch_btn = $tab_frames{'Estructura'}->Button(%bs_top, -text => 'I-CHoCH: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_ichoch_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_ichoch_visibility_callback(sub {
    my ($v) = @_;
    $ichoch_btn->configure(-text => $v ? 'I-CHoCH: ON' : 'I-CHoCH: OFF', -foreground => $v ? '#f23645' : '#787b86');
});
# --- Fibonacci (pestaña "Estructura"): al apretar el boton estando
# apagado, entra en modo "elegi un punto del ZigZag Ex" (mismo mecanismo
# que VWAP/AVP): el cursor cambia a cruz y aparece una linea que se pega
# al pivote mas cercano del ZigZag Ex (necesita tener "ZigZag Ex"
# calculado -- no hace falta tenerlo PRENDIDO, el calculo corre siempre).
# Con un clic sobre ese pivote, se ancla ahi y el programa detecta solo
# el pivote conectado (en diagonal) para completar el retroceso,
# exactamente como la herramienta real de TradingView. Si ya esta
# prendido, el boton simplemente lo apaga (para elegir otro punto,
# apagalo y volve a presionarlo). ---
my $smc_btn;
$smc_btn = $tab_frames{'Estructura'}->Button(%bs_top, -text => 'Fibonacci: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub {
        if ( $engine->is_smc_visible ) {
            $engine->toggle_smc_visibility;
        } else {
            $engine->begin_fib_anchor_selection;
        }
    })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_smc_visibility_callback(sub {
    my ($v) = @_;
    $smc_btn->configure(-text => $v ? 'Fibonacci: ON' : 'Fibonacci: OFF', -foreground => $v ? '#9575cd' : '#787b86');
});
$engine->set_fib_anchor_state_callback(sub {
    my ($awaiting) = @_;
    $smc_btn->configure(-text => $awaiting ? 'Fibonacci: elegi un punto...' : 'Fibonacci: OFF',
        -foreground => $awaiting ? '#f7b500' : '#787b86');
});

my $fvg_btn;
$fvg_btn = $tab_frames{'Estructura'}->Button(%bs_top, -text => 'FVG: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_fvg_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_fvg_visibility_callback(sub {
    my ($v) = @_;
    $fvg_btn->configure(-text => $v ? 'FVG: ON' : 'FVG: OFF', -foreground => $v ? '#ff7d04' : '#787b86');
});

# --- Canal/Tendline (pestaña "Estructura") — BLOQUE CANAL (NUEVO, grupo
# 11 del enunciado). Solo controla visibilidad; el calculo corre siempre
# en SMC_Structures (_try_detect_channel). Arranca apagado, igual que el
# resto de los botones. ---
my $channel_btn;
$channel_btn = $tab_frames{'Estructura'}->Button(%bs_top, -text => 'Canal: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_channel_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_channel_visibility_callback(sub {
    my ($v) = @_;
    $channel_btn->configure(-text => $v ? 'Canal: ON' : 'Canal: OFF', -foreground => $v ? '#2962ff' : '#787b86');
});

# --- EQH/EQL (Equal Highs / Equal Lows) (pestaña "Estructura") ---
my $eq_btn;
$eq_btn = $tab_frames{'Estructura'}->Button(%bs_top, -text => 'EQH: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_eq_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_eq_visibility_callback(sub {
    my ($v) = @_;
    $eq_btn->configure(-text => $v ? 'EQH: ON' : 'EQH: OFF', -foreground => $v ? '#b2b5be' : '#787b86');
});

# --- Liquidity (pestaña "Liquidez") ---
my $liq_btn;
$liq_btn = $tab_frames{'Liquidez'}->Button(%bs_top, -text => 'Liquidity: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_liquidity_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_liquidity_visibility_callback(sub {
    my ($v) = @_;
    $liq_btn->configure(-text => $v ? 'Liquidity: ON' : 'Liquidity: OFF', -foreground => $v ? '#fa451c' : '#787b86');
});

# -----------------------------------------------------------------------------
# [UNIFICADO] "Order Blocks" ahora controla TAMBIEN Strong/Weak H-L -- un
# solo boton, un solo interruptor. La union real sucede en ChartEngine.pm:
# render_trailing (Strong/Weak H-L) se dibuja bajo la MISMA condicion que
# render_order_blocks (_ob_visible). (pestaña "Liquidez")
# -----------------------------------------------------------------------------
my $ob_btn;
$ob_btn = $tab_frames{'Liquidez'}->Button(%bs_top, -text => 'Order Blocks: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_ob_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_ob_visibility_callback(sub {
    my ($v) = @_;
    $ob_btn->configure(-text => $v ? 'Order Blocks: ON' : 'Order Blocks: OFF', -foreground => $v ? '#1848cc' : '#787b86');
});

# --- Supply / Demand Zones (pestaña "Liquidez") — puerto fiel de "DIY
# Custom Strategy Builder [ZP] - v1" (Pine v6, seccion "Supply/Demand
# POI"). Solo controla visibilidad; el calculo
# (Market::Indicators::Strategy_Builder) corre siempre, arranca apagado
# igual que el resto de los botones. [FIX] Ahora solo se muestran zonas
# que nacieron dentro de la ventana visible actual (ver
# render_supply_demand en el overlay). ---
my $sd_btn;
$sd_btn = $tab_frames{'Liquidez'}->Button(%bs_top, -text => 'Supply/Demand Zones: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_sd_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_sd_visibility_callback(sub {
    my ($v) = @_;
    $sd_btn->configure(-text => $v ? 'Supply/Demand Zones: ON' : 'Supply/Demand Zones: OFF', -foreground => $v ? '#00E5FF' : '#787b86');
});

# --- Ghost VWAP (pestaña "Volumen") — puerto de "Dynamic Swing Anchored
# VWAP by Josafa". Detecta pivotes simetricos (ventana 50 velas por
# defecto) y marca con 👻 los pivotes "saltados" (fantasma); el VWAP se
# reancla solo al ultimo pivote confirmado, sin necesidad de elegir nada
# con un clic. Solo controla visibilidad; el calculo corre siempre. ---
my $ghost_btn;
$ghost_btn = $tab_frames{'Volumen'}->Button(%bs_top, -text => 'Ghost: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_ghost_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_ghost_visibility_callback(sub {
    my ($v) = @_;
    $ghost_btn->configure(-text => $v ? 'Ghost: ON' : 'Ghost: OFF', -foreground => $v ? '#ba68c8' : '#787b86');
});

# --- VWAP Auto (pestaña "Volumen") — BLOQUE VWAP AUTO-ANCLADO AL
# PENULTIMO PIVOTE (NUEVO, punto 4 del enunciado del profesor). Es el
# MISMO indicador Pine que el Ghost ("Dynamic Swing Anchored VWAP by
# Josafa", ver Ghosts_in_swings.txt) -- ahi el VWAP se ancla en el ultimo
# pivote CONFIRMADO (el "penultimo pivot" respecto al fantasma actual).
# Boton independiente para poder mostrarlo/ocultarlo sin afectar al
# Ghost. Solo controla visibilidad; el calculo corre siempre. ---
my $pph_vwap_btn;
$pph_vwap_btn = $tab_frames{'Volumen'}->Button(%bs_top, -text => 'VWAP Auto: OFF', -foreground => '#787b86', -font => 'TkDefaultFont 9 bold',
    -command => sub { $engine->toggle_pph_vwap_visibility; })->pack(-side => 'left', -padx => 4, -pady => 4);
$engine->set_pph_vwap_visibility_callback(sub {
    my ($v) = @_;
    $pph_vwap_btn->configure(-text => $v ? 'VWAP Auto: ON' : 'VWAP Auto: OFF', -foreground => $v ? '#ba68c8' : '#787b86');
});

# [QUITADO] El viejo "BLOQUE REFLOW" (ajuste automatico de una barra
# unica larga) ya no hace falta -- con las pestañas, cada categoria tiene
# solo 3 a 7 botones en una fila simple, que entra comodo con un ->pack
# normal sin necesitar logica de wrap. Si en el futuro una pestaña
# especifica llegara a desbordar en pantallas muy chicas, se puede
# reintroducir el mismo mecanismo de reflow (ver el git history de este
# archivo) pero aplicado solo a ese $tab_frames{...} puntual.


# =============================================================================
# CALLBACKS DE MODO — sincronizan botones con estado interno del engine
# Cualquier cambio de modo (boton, regleta, dbl-clic) actualiza el boton.
# =============================================================================
$engine->set_mode_callbacks(
    sub {   # callback precio
        my ($is_free) = @_;
        $mode_btn->configure(
            -text       => $is_free ? 'Modo Manual' : 'Modo Automático',
            -foreground => $is_free ? '#ef5350'  : '#26a69a',
        );
    },
    sub {   # callback ATR
        my ($is_free) = @_;
        $mode_btn_atr->configure(
            -text       => $is_free ? 'Modo Manual' : 'Modo Automático',
            -foreground => $is_free ? '#ef5350'    : '#26a69a',
        );
    },
);


# =============================================================================
# TEMPORALIDADES — [CAMBIO — BOTONES EN LINEA] Antes era un desplegable
# (Button + Menu.post, con el fix WSL/X11 de coordenadas). A pedido del
# usuario, ahora son 8 botones fijos en fila, mismo criterio "radio" que
# la resolucion del ZigZag In: el activo queda resaltado en azul.
# =============================================================================
my $active_tf = '1m';
my %tf_buttons;

my $highlight_tf;
$highlight_tf = sub {
    my ($tf) = @_;
    $active_tf = $tf;
    for my $t ( '1m', '5m', '15m', '1h', '2h', '4h', 'D', 'W' ) {
        next unless $tf_buttons{$t};
        if ( $t eq $tf ) {
            $tf_buttons{$t}->configure( -background => '#2962ff', -foreground => '#ffffff' );
        } else {
            $tf_buttons{$t}->configure( -background => '#1c1f2b', -foreground => '#d1d4dc' );
        }
    }
};

for my $tf ( '1m', '5m', '15m', '1h', '2h', '4h', 'D', 'W' ) {
    $tf_buttons{$tf} = $tf_frame->Button(
        -text             => $tf,
        -background       => ( $tf eq $active_tf ? '#2962ff' : '#1c1f2b' ),
        -foreground       => ( $tf eq $active_tf ? '#ffffff' : '#d1d4dc' ),
        -activebackground => '#2f3139',
        -activeforeground => '#ffffff',
        -relief           => 'flat',
        -bd               => 0,
        -font             => 'TkDefaultFont 9 bold',
        -padx             => 8,
        -pady             => 3,
        -command          => sub {
            $highlight_tf->($tf);
            $engine->set_timeframe($tf);
            $mode_btn->configure(    -text => 'Modo Automático', -foreground => '#26a69a' );
            $mode_btn_atr->configure(-text => 'Modo Automático', -foreground => '#26a69a' );
        },
    )->pack( -side => 'left', -padx => 1, -pady => 2 );
}


# Botón Inicio Replay: activa modo selección de corte (retícula magnética)

my $replay_btn;
$replay_btn = $tf_frame->Button(%bs,
    -text       => 'Inicio Replay',
    -background => '#ff7043',
    -foreground => '#ffffff',
    -font       => 'TkDefaultFont 9 bold',
    -command    => sub { $engine->begin_replay_selection; },
)->pack(-side => 'left', -padx => 6, -pady => 2);

# Sincroniza el color del botón con el estado interno del engine
$engine->set_replay_cut_callback(sub {
    my ($is_active) = @_;
    $replay_btn->configure(-background => $is_active ? '#d32f2f' : '#ff7043');
});

# =============================================================================
# BLOQUE REPLAY: Play / Pause / Step / Fast Forward / Exit
# =============================================================================
$tf_frame->Button(%bs,
    -text       => '▶ Play',
    -background => '#26a69a',
    -foreground => '#ffffff',
    -font       => 'TkDefaultFont 9 bold',
    -command    => sub { $engine->replay_play; },
)->pack(-side => 'left', -padx => 2, -pady => 2);

$tf_frame->Button(%bs,
    -text       => '⏸ Pause',
    -background => '#ef5350',
    -foreground => '#ffffff',
    -font       => 'TkDefaultFont 9 bold',
    -command    => sub { $engine->replay_pause; },
)->pack(-side => 'left', -padx => 2, -pady => 2);

$tf_frame->Button(%bs,
    -text    => '⏮ Retroceder',
    -command => sub { $engine->replay_step_backward; },
)->pack(-side => 'left', -padx => 2, -pady => 2);

$tf_frame->Button(%bs,
    -text    => '⏭ Avanzar',
    -command => sub { $engine->replay_step_forward; },
)->pack(-side => 'left', -padx => 2, -pady => 2);

my $replay_ff_btn;
$replay_ff_btn = $tf_frame->Button(%bs,
    -text       => '⏩ Avance Rápido',
    -foreground => '#787b86',
    -command    => sub {
        my $is_fast = $engine->replay_toggle_fast_forward;
        $replay_ff_btn->configure(
            -foreground => $is_fast ? '#2962ff' : '#787b86',
            -text       => $is_fast ? '⏩ Avance Rápido (ON)' : '⏩ Avance Rápido',
        );
    },
)->pack(-side => 'left', -padx => 2, -pady => 2);

$tf_frame->Button(%bs,
    -text       => '⏹ Salir Replay',
    -background => '#ff7043',
    -foreground => '#ffffff',
    -font       => 'TkDefaultFont 9 bold',
    -command    => sub { $engine->replay_exit; },
)->pack(-side => 'left', -padx => 6, -pady => 2);

$tf_frame->Label(%bs,
    -text       => 'Rueda: zoom  |  Ctrl+Rueda: ancla mouse  |  Shift+Rueda: zoom V  |  Drag regleta: zoom V  |  Dbl-regleta: auto  |  Drag sep: resize ATR',
    -foreground => '#787b86',
    -font       => 'TkDefaultFont 7',
    -background => '#1c1f2b',
)->pack(-side => 'left', -padx => 10);

# =============================================================================
# DRAG DEL SEPARADOR ATR
# =============================================================================
{
    my $drag_y_start = undef;
    my $drag_atr_h   = undef;

    $sep_frame->bind('<ButtonPress-1>', sub {
        $drag_y_start = $_[0]->XEvent->Y;
        $drag_atr_h   = $canvas_atr->height;
    });

    $sep_frame->bind('<B1-Motion>', sub {
        return unless defined $drag_y_start;
        my $dy    = $drag_y_start - $_[0]->XEvent->Y;
        my $new_h = $drag_atr_h + $dy;
        $new_h = $ATR_H_MIN if $new_h < $ATR_H_MIN;
        $new_h = $ATR_H_MAX if $new_h > $ATR_H_MAX;

        $canvas_atr->configure(-height => $new_h);
        $engine->resize_panels(
            $canvas_price->width,
            $canvas_price->height - ($new_h - $drag_atr_h),
            $new_h,
        );
    });

    $sep_frame->bind('<ButtonRelease-1>', sub {
        $drag_y_start = undef;
        $drag_atr_h   = undef;
    });

    $sep_frame->bind('<Double-Button-1>', sub {
        $canvas_atr->configure(-height => 140);
        $mw->update;
        $engine->resize_panels(
            $canvas_price->width,
            $canvas_price->height,
            140,
        );
    });
}

# =============================================================================
# PRIMER RENDER
# =============================================================================
# Arranque limpio: apaga (y garantiza apagados) todos los overlays de la
# barra superior antes de pintar nada. Solo el precio y el ATR se muestran
# de entrada; el resto aparece unicamente cuando el usuario prende su boton.
# VWAP y AVP arrancan SIN ancla -- no hay nada que mostrar hasta que el
# usuario elija una vela con un clic (ver botones "VWAP"/"AVP" mas arriba).
$engine->force_all_overlays_off;

$engine->reset_view;

$mw->after(80, sub { $engine->render });
MainLoop;