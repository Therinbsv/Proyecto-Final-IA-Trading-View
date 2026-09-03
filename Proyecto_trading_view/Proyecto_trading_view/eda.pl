#!/usr/bin/env perl
# =============================================================================
# eda.pl — FASE 3: Analisis Exploratorio (Pearson + PCA)
#
# Uso:
#   perl eda.pl features_train.csv
#
# Reusa AI::MXNet::nd->corrcoef, igual que tu notebook
# Pearson_Correlation_Coefficients-PCC.pl. Imprime, para cada columna de
# feature, con cual OTRA columna tiene mayor correlacion (ayuda a detectar
# niveles redundantes -- ej. si "ob_dist_pips_1m" y "fvg_dist_pips_1m"
# salen ~1.0 correlacionados, estan midiendo basicamente lo mismo).
#
# Tambien corre PCA (via nd->linalg o SVD manual si tu AI::MXNet no trae
# helper de PCA -- se implementa aca con la matriz de covarianza + eigen,
# mismo criterio que el notebook de PCA) e imprime cuanta VARIANZA
# explica cada componente -- responde directo a "33+ columnas, ¿hace falta
# reducir dimensionalidad?".
# =============================================================================
use strict;
use warnings;
use AI::MXNet qw(mx nd);

my ($CSV) = @ARGV;
die "Uso: perl eda.pl <features_train.csv>\n" unless $CSV;

sub read_features {
    my ($path) = @_;
    open my $fh, '<', $path or die "No se pudo abrir '$path': $!\n";
    my $header = <$fh>; chomp $header;
    my @cols = split /,/, $header;
    my @feat_idx;
    for my $i ( 0 .. $#cols ) {
        next if $cols[$i] =~ /^event_/;
        next if $cols[$i] =~ /^rastro/;
        push @feat_idx, $i;
    }
    my @X;
    while (<$fh>) {
        chomp;
        my @v = split /,/, $_, -1;
        push @X, [ map { ( $v[$_] // 0 ) + 0 } @feat_idx ];
    }
    close $fh;
    return ( [ @cols[@feat_idx] ], \@X );
}

print "Leyendo $CSV...\n";
my ( $names, $X ) = read_features($CSV);
my $n = scalar @$X;
my $p = scalar @$names;
printf "  %d filas, %d columnas de features\n", $n, $p;
die "Muy pocas filas para un analisis util.\n" if $n < 10;

my $Xnd = nd->array($X);

# =============================================================================
# PEARSON — matriz de correlacion completa (misma llamada que tu notebook PCC)
# =============================================================================
print "\n=== PEARSON: pares de columnas MAS correlacionadas (|r| >= 0.9) ===\n";
my $corr = nd->corrcoef( $Xnd->T );
my @corr_pdl = @{ $corr->aspdl->unpdl };

my @flagged;
for my $i ( 0 .. $p - 1 ) {
    for my $j ( $i + 1 .. $p - 1 ) {
        my $r = $corr_pdl[$i][$j];
        push @flagged, [ $names->[$i], $names->[$j], $r ] if abs($r) >= 0.9;
    }
}
if (@flagged) {
    for my $f ( sort { abs( $b->[2] ) <=> abs( $a->[2] ) } @flagged ) {
        printf "  %-28s <-> %-28s  r=%.3f\n", @$f;
    }
    print "  (estos pares miden casi lo mismo -- candidatos a sacar uno de los dos si\n";
    print "   el modelo entrenado tarda mucho o el profe pregunta por que hay tantas columnas)\n";
} else {
    print "  Ningun par con |r|>=0.9 -- las columnas aportan informacion distinta entre si.\n";
}

# =============================================================================
# PCA — via matriz de covarianza + autovalores (mismo concepto que tu
# notebook de PCA: estandarizar, covarianza, eigen-descomposicion, ordenar
# por varianza explicada).
# =============================================================================
print "\n=== PCA: varianza explicada por componente ===\n";

# Estandarizar (media 0, desvio 1) por columna
my $mean = nd->mean( $Xnd, axis => 0 );
my $std  = nd->sqrt( nd->mean( ( $Xnd - $mean ) ** 2, axis => 0 ) + 1e-8 );
my $Xs   = ( $Xnd - $mean ) / $std;

# Matriz de covarianza (p x p) y sus autovalores
my $cov = nd->dot( $Xs->T, $Xs ) / ( $n - 1 );

my $pca_ok = eval {
    my ( $eigvals, $eigvecs ) = mx->nd->linalg->syevd($cov);
    my @vals = reverse @{ $eigvals->aspdl->unpdl };   # de mayor a menor
    my $total = 0; $total += $_ for @vals;

    my $acc = 0;
    for my $k ( 0 .. ( $p < 10 ? $p - 1 : 9 ) ) {   # muestra hasta 10 componentes
        my $var_pct = 100 * $vals[$k] / $total;
        $acc += $var_pct;
        printf "  PC%-2d  varianza=%.1f%%   acumulada=%.1f%%\n", $k + 1, $var_pct, $acc;
    }
    print "\n  (si con pocas componentes ya acumulas >90%, confirma que muchas de tus\n";
    print "   33+ columnas son redundantes -- util para justificarle al profe por que\n";
    print "   el modelo funciona bien con esa cantidad de features)\n";
    1;
};

if ( !$pca_ok ) {
    print "  [AVISO] Tu version de AI::MXNet no trae linalg->syevd (metodo de PCA\n";
    print "  usado aca). Esto NO bloquea nada del resto del pipeline -- el analisis\n";
    print "  de Pearson de arriba ya te da lo importante (que columnas son\n";
    print "  redundantes). Si necesitas el numero exacto de varianza explicada para\n";
    print "  la presentacion, avisame y lo calculo con otro metodo (potencia\n";
    print "  iterativa, sin depender de syevd).\n";
    print "  Error tecnico: $@\n" if $@;
}
