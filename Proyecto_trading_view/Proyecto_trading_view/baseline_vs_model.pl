#!/usr/bin/env perl
# =============================================================================
# baseline_vs_model.pl — Tabla "ANTES vs DESPUES" para la presentacion.
#
# ANTES = prediccion mas simple posible: "siempre digo el promedio historico"
#         (sin ningun modelo, sin features, solo la media de train).
# DESPUES = tu modelo LSTM ya entrenado (usa el MAE/RMSE que ya calculaste
#           con train_predict_lstm.pl test).
#
# Uso:
#   perl baseline_vs_model.pl features_train.csv features_test.csv
#
# Los numeros de "DESPUES" hay que pegarlos a mano (son los que ya te
# imprimio train_predict_lstm.pl test) -- ver mas abajo, la variable
# %LSTM_RESULTS, para no tener que cargar AI::MXNet de nuevo aca.
# =============================================================================
use strict;
use warnings;

my @WINDOWS = ( 3, 5, 10, 15 );

# --- Pegá acá los resultados que ya te imprimió "train_predict_lstm.pl test"
# (Precision/Recall los dejamos para otra tabla, esta es de MAE/RMSE) ---
my %LSTM_MAE  = ( 3 => 2.142, 5 => 2.806, 10 => 0.926, 15 => 1.337 );
my %LSTM_RMSE = ( 3 => 2.820, 5 => 3.657, 10 => 1.249, 15 => 1.794 );
my %LSTM_F1   = ( 3 => 0.694, 5 => 0.746, 10 => 0.550, 15 => 0.622 );

my ( $TRAIN_CSV, $TEST_CSV ) = @ARGV;
die "Uso: perl baseline_vs_model.pl <features_train.csv> <features_test.csv>\n"
    unless $TRAIN_CSV && $TEST_CSV;

sub read_col {
    my ( $path, $colname ) = @_;
    open my $fh, '<', $path or die "No se pudo abrir '$path': $!\n";
    my $header = <$fh>; chomp $header;
    my @cols = split /,/, $header;
    my $idx;
    for my $i ( 0 .. $#cols ) { $idx = $i if $cols[$i] eq $colname; }
    die "No encontre la columna '$colname' en $path\n" unless defined $idx;
    my @vals;
    while (<$fh>) {
        chomp;
        my @v = split /,/, $_, -1;
        push @vals, ( $v[$idx] // 0 ) + 0;
    }
    close $fh;
    return \@vals;
}

print "=" x 78, "\n";
print "TABLA: PREDICCION INGENUA (promedio) vs MODELO LSTM\n";
print "=" x 78, "\n\n";

printf "%-14s %10s %12s %12s %12s %10s\n",
    'Ventana', 'Promedio', 'MAE base', 'MAE LSTM', 'Mejora %', 'F1 LSTM';
print "-" x 78, "\n";

my %baseline_mean;
for my $w (@WINDOWS) {
    my $train_vals = read_col( $TRAIN_CSV, "rastros_${w}m" );
    my $test_vals  = read_col( $TEST_CSV,  "rastros_${w}m" );

    # ANTES: "siempre predigo el promedio de train" -- prediccion constante
    my $sum = 0; $sum += $_ for @$train_vals;
    my $mean = $sum / scalar(@$train_vals);
    $baseline_mean{$w} = $mean;

    my ( $sum_ae, $sum_se ) = ( 0, 0 );
    for my $actual (@$test_vals) {
        my $err = $actual - $mean;
        $sum_ae += abs($err);
        $sum_se += $err * $err;
    }
    my $n = scalar @$test_vals;
    my $mae_base  = $sum_ae / $n;
    my $rmse_base = sqrt( $sum_se / $n );

    my $mae_lstm = $LSTM_MAE{$w};
    my $mejora   = 100 * ( $mae_base - $mae_lstm ) / $mae_base;

    printf "rastros_%-6s %10.2f %12.3f %12.3f %11.1f%% %10.3f\n",
        "${w}m", $mean, $mae_base, $mae_lstm, $mejora, $LSTM_F1{$w};
}

print "\n";
print "=" x 78, "\n";
print "Lectura para la diapo:\n";
print "  'Promedio' = cuantos rastros deja el fantasma EN PROMEDIO en esa ventana\n";
print "  'MAE base' = que tan mal predice si uno SIEMPRE dice ese promedio\n";
print "               (sin usar ningun modelo -- la comparacion mas justa posible)\n";
print "  'MAE LSTM' = que tan mal predice nuestro modelo entrenado\n";
print "  'Mejora %' = cuanto mejor es el LSTM contra simplemente adivinar el promedio\n";
print "=" x 78, "\n";
