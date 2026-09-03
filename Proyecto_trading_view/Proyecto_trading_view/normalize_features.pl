#!/usr/bin/env perl
# =============================================================================
# normalize_features.pl — FASE 4: Normalizacion / Estandarizacion
#
# Uso:
#   perl normalize_features.pl features_train.csv features_test.csv
#
# Calcula media y desvio estandar de CADA columna numerica de features
# (NO de las columnas event_*/rastro*, esas se dejan intactas) USANDO SOLO
# features_train.csv, guarda esos parametros en norm_params.json, y aplica
# EXACTAMENTE esos mismos parametros a ambos archivos (nunca recalcula con
# julio) -- tal como pide el enunciado.
#
# Genera: features_train_norm.csv, features_test_norm.csv, norm_params.json
# =============================================================================
use strict;
use warnings;

my ( $TRAIN_CSV, $TEST_CSV ) = @ARGV;
die "Uso: perl normalize_features.pl <features_train.csv> <features_test.csv>\n"
    unless $TRAIN_CSV && $TEST_CSV;

sub read_csv {
    my ($path) = @_;
    open my $fh, '<', $path or die "No se pudo abrir '$path': $!\n";
    my $header = <$fh>;
    chomp $header;
    my @cols = split /,/, $header;
    my @rows;
    while (<$fh>) {
        chomp;
        my @vals = split /,/, $_, -1;
        my %row;
        @row{@cols} = @vals;
        push @rows, \%row;
    }
    close $fh;
    return ( \@cols, \@rows );
}

sub write_csv {
    my ( $path, $cols, $rows ) = @_;
    open my $fh, '>', $path or die "No se pudo escribir '$path': $!\n";
    print $fh join( ',', @$cols ), "\n";
    for my $row (@$rows) {
        print $fh join( ',', map { defined $row->{$_} ? $row->{$_} : '' } @$cols ), "\n";
    }
    close $fh;
}

# Columnas que NUNCA se normalizan: metadata (event_*) y targets (rastro*).
sub is_feature_col {
    my ($c) = @_;
    return 0 if $c =~ /^event_/;
    return 0 if $c =~ /^rastro/;
    return 1;
}

print "Leyendo $TRAIN_CSV...\n";
my ( $cols, $train_rows ) = read_csv($TRAIN_CSV);
my @feat_cols = grep { is_feature_col($_) } @$cols;

print "Calculando media/desvio (SOLO train, " . scalar(@$train_rows) . " filas, " . scalar(@feat_cols) . " columnas)...\n";
my %mean;
my %std;
for my $c (@feat_cols) {
    my @vals = map { $_->{$c} + 0 } @$train_rows;
    my $n    = scalar @vals;
    next unless $n;
    my $sum  = 0; $sum += $_ for @vals;
    my $mu   = $sum / $n;
    my $sq   = 0; $sq += ( $_ - $mu )**2 for @vals;
    my $sd   = $n > 1 ? sqrt( $sq / ( $n - 1 ) ) : 1;
    $sd = 1e-8 if $sd == 0;   # evita division por cero en columnas constantes (ej. flags todos en 0)
    $mean{$c} = $mu;
    $std{$c}  = $sd;
}

# Guardar parametros (formato simple, una linea por columna: nombre,media,desvio)
open my $pf, '>', 'norm_params.json' or die $!;
print $pf "{\n";
my @lines;
for my $c (@feat_cols) {
    push @lines, sprintf( qq(  "%s": {"mean": %.10g, "std": %.10g}), $c, $mean{$c}, $std{$c} );
}
print $pf join( ",\n", @lines ), "\n}\n";
close $pf;
print "Parametros guardados en norm_params.json\n";

sub apply_norm {
    my ($rows) = @_;
    for my $row (@$rows) {
        for my $c (@feat_cols) {
            next unless exists $mean{$c};
            my $v = $row->{$c};
            $v = 0 unless defined $v && $v ne '';
            $row->{$c} = ( $v - $mean{$c} ) / $std{$c};
        }
    }
}

apply_norm($train_rows);
write_csv( 'features_train_norm.csv', $cols, $train_rows );
printf "Escrito features_train_norm.csv (%d filas)\n", scalar(@$train_rows);

print "Leyendo $TEST_CSV...\n";
my ( $cols_test, $test_rows ) = read_csv($TEST_CSV);
apply_norm($test_rows);
write_csv( 'features_test_norm.csv', $cols_test, $test_rows );
printf "Escrito features_test_norm.csv (%d filas)\n", scalar(@$test_rows);

print "Listo.\n";
