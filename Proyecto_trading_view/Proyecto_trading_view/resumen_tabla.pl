#!/usr/bin/env perl
# =============================================================================
# resumen_tabla.pl — Tabla-resumen estadistico de features_train.csv, para
# mostrar en la presentacion ("la tabla con la desviacion y todo eso").
#
# Uso:
#   perl resumen_tabla.pl features_train.csv
#
# Genera resumen_estadistico.csv con: columna, cantidad de valores, media,
# desviacion estandar, minimo, maximo -- una fila por cada columna de la
# tabla de features (sin contar metadata event_*/rastro*). Tambien imprime
# en pantalla las columnas de conteo de fantasmas (targets) por separado,
# que es la metrica de "cuantos fantasmas" que pedia el profe.
# =============================================================================
use strict;
use warnings;

my ($CSV) = @ARGV;
die "Uso: perl resumen_tabla.pl <features_train.csv>\n" unless $CSV;

open my $fh, '<', $CSV or die "No se pudo abrir '$CSV': $!\n";
my $header = <$fh>; chomp $header;
my @cols = split /,/, $header;

my @rows;
while (<$fh>) {
    chomp;
    push @rows, [ split /,/, $_, -1 ];
}
close $fh;
my $n = scalar @rows;
printf "Leidas %d filas, %d columnas de %s\n\n", $n, scalar(@cols), $CSV;

# --- resumen por columna (todas menos event_*) ---
open my $out, '>', 'resumen_estadistico.csv' or die $!;
print $out "columna,cantidad,media,desvio_estandar,minimo,maximo\n";

my @target_cols;
for my $i ( 0 .. $#cols ) {
    my $c = $cols[$i];
    next if $c =~ /^event_/;

    my @vals = map { ( $_->[$i] // 0 ) + 0 } @rows;
    my $cnt  = scalar @vals;
    my $sum  = 0; $sum += $_ for @vals;
    my $mean = $sum / $cnt;
    my $sq   = 0; $sq += ( $_ - $mean )**2 for @vals;
    my $std  = $cnt > 1 ? sqrt( $sq / ( $cnt - 1 ) ) : 0;
    my ( $min, $max ) = ( $vals[0], $vals[0] );
    for (@vals) { $min = $_ if $_ < $min; $max = $_ if $_ > $max; }

    printf $out "%s,%d,%.4f,%.4f,%.4f,%.4f\n", $c, $cnt, $mean, $std, $min, $max;
    push @target_cols, [ $c, $mean, $std, $min, $max ] if $c =~ /^rastro/;
}
close $out;
print "Escrito: resumen_estadistico.csv (media/desvio/min/max de cada columna)\n\n";

# --- metricas de "cuantos fantasmas" (lo mas pedido para mostrar) ---
print "=== CONTEO DE FANTASMAS (para la presentacion) ===\n";
printf "  Total de eventos/muestras en la tabla: %d\n\n", $n;
for my $t (@target_cols) {
    my ( $c, $mean, $std, $min, $max ) = @$t;
    printf "  %-16s  promedio=%.2f  desvio=%.2f  min=%.0f  max=%.0f\n", $c, $mean, $std, $min, $max;
}

# --- covarianza (pedida por el profe) entre ATR(1m) y Volumen(1m) ---
my ( $atr_i, $vol_i );
for my $i ( 0 .. $#cols ) {
    $atr_i = $i if $cols[$i] eq 'atr_1m';
    $vol_i = $i if $cols[$i] eq 'volume_1m';
}
if ( defined $atr_i && defined $vol_i ) {
    my @atr = map { ( $_->[$atr_i] // 0 ) + 0 } @rows;
    my @vol = map { ( $_->[$vol_i] // 0 ) + 0 } @rows;
    my ( $sa, $sv ) = ( 0, 0 );
    $sa += $_ for @atr; $sv += $_ for @vol;
    my ( $ma, $mv ) = ( $sa / $n, $sv / $n );
    my $cov = 0;
    $cov += ( $atr[$_] - $ma ) * ( $vol[$_] - $mv ) for ( 0 .. $n - 1 );
    $cov /= ( $n - 1 );
    printf "\n=== COVARIANZA (ATR 1m vs Volumen 1m) ===\n";
    printf "  cov(ATR,Volumen) = %.4f\n", $cov;
    print "  (positivo = cuando el ATR sube, el volumen tiende a subir tambien;\n";
    print "   negativo = tienden a moverse en sentido contrario)\n";
}
