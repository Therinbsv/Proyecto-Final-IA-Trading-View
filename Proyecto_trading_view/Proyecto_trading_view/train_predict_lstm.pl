#!/usr/bin/env perl
# =============================================================================
# train_predict_lstm.pl — FASES 5, 6 y 7, con LSTM (reemplaza a la red densa
# de train_predict.pl, a pedido explicito de usar LSTM). Sigue el MISMO
# patron que el script de referencia del profesor
# (09_02_02-Concise_Implementation_of_LSTM.pl): make_sequences(seq_len) +
# mx->gluon->rnn->LSTM + Dense final. Sin capas convolucionales (CNN).
#
# Diferencia clave con el ejemplo del profe: alli cada fila YA es un paso
# de tiempo consecutivo real (audio). Aca, cada fila es un EVENTO (aparicion
# /reubicacion del fantasma) potencialmente separado por minutos u horas.
# La "secuencia" que le damos al LSTM son los ultimos $SEQ_LEN eventos en
# orden cronologico (event_index) -- el LSTM aprende del PATRON de los
# ultimos N eventos del fantasma para predecir el resultado del evento
# actual. Esto es una eleccion de diseño razonable y defendible: es "usar
# LSTM" de verdad (aprovecha la memoria secuencial), no un maquillaje.
#
# Uso:
#   perl train_predict_lstm.pl train features_train_norm.csv
#   perl train_predict_lstm.pl test  features_test_norm.csv
# =============================================================================
use strict;
use warnings;
use AI::MXNet qw(mx nd);

my $SEQ_LEN = 5;   # cuantos eventos previos ve el LSTM para predecir el actual

my @TARGET_WINDOWS = ( 3, 5, 10, 15 );
my @REG_COLS = map { "rastros_${_}m" }    @TARGET_WINDOWS;
my @CLS_COLS = map { "rastro_${_}m_bin" } @TARGET_WINDOWS;

my ( $MODE, $CSV ) = @ARGV;
die "Uso: perl train_predict_lstm.pl train|test <features_norm.csv>\n"
    unless $MODE && $CSV && ( $MODE eq 'train' || $MODE eq 'test' );

# =============================================================================
# Lectura — IGUAL que train_predict.pl (mismas columnas), pero el CSV ya
# viene ORDENADO cronologicamente por event_index (asi lo escribe
# extract_features.pl, en el orden en que ocurrieron los eventos), que es
# justo el orden que necesita make_sequences.
# =============================================================================
sub read_dataset {
    my ($path) = @_;
    open my $fh, '<', $path or die "No se pudo abrir '$path': $!\n";
    my $header = <$fh>;
    chomp $header;
    my @cols = split /,/, $header;

    my ( @feat_idx, @reg_idx, @cls_idx );
    for my $i ( 0 .. $#cols ) {
        my $c = $cols[$i];
        if    ( grep { $_ eq $c } @REG_COLS ) { push @reg_idx, $i; }
        elsif ( grep { $_ eq $c } @CLS_COLS ) { push @cls_idx, $i; }
        elsif ( $c !~ /^event_/ )             { push @feat_idx, $i; }
    }
    my $time_idx = 0;
    for my $i ( 0 .. $#cols ) { $time_idx = $i if $cols[$i] eq 'event_time'; }

    my ( @X, @Yreg, @Ycls, @meta_time );
    while (<$fh>) {
        chomp;
        my @v = split /,/, $_, -1;
        push @X,    [ map { ( $v[$_] // 0 ) + 0 } @feat_idx ];
        push @Yreg, [ map { ( $v[$_] // 0 ) + 0 } @reg_idx ];
        push @Ycls, [ map { ( $v[$_] // 0 ) + 0 } @cls_idx ];
        push @meta_time, $v[$time_idx];
    }
    close $fh;
    return ( \@X, \@Yreg, \@Ycls, \@meta_time );
}

# =============================================================================
# make_sequences — mismo concepto que el script de referencia del profe:
# para cada evento i (con i >= SEQ_LEN-1), arma una ventana de los SEQ_LEN
# eventos [i-SEQ_LEN+1 .. i] como entrada, y el target es el de la ULTIMA
# posicion de esa ventana (el evento actual, i) -- exactamente igual que
# "y_seq = $y->slice([$seq_len-1, $N])" del script de referencia.
# Los primeros SEQ_LEN-1 eventos del dataset no tienen suficiente historia
# previa y se descartan (mismo comportamiento que el script de referencia).
# =============================================================================
sub make_sequences {
    my ( $X, $Y, $seq_len ) = @_;
    my $n = scalar @$X;
    my ( @Xseq, @Yout );
    for my $i ( $seq_len - 1 .. $n - 1 ) {
        my @window = @{$X}[ ( $i - $seq_len + 1 ) .. $i ];
        push @Xseq, \@window;
        push @Yout, $Y->[$i];
    }
    return ( \@Xseq, \@Yout );
}

print "Leyendo $CSV...\n";
my ( $X, $Yreg, $Ycls, $meta_time ) = read_dataset($CSV);
my $n_samples = scalar @$X;
my $n_feats   = scalar @{ $X->[0] // [] };
die "No hay muestras -- revisa el CSV.\n" unless $n_samples;
die "Necesitas al menos $SEQ_LEN muestras (tenes $n_samples) -- baja \$SEQ_LEN o generá más datos.\n"
    if $n_samples < $SEQ_LEN;

printf "  %d eventos, %d features por evento, secuencias de %d eventos\n", $n_samples, $n_feats, $SEQ_LEN;

my ( $Xseq_reg, $Yreg_seq ) = make_sequences( $X, $Yreg, $SEQ_LEN );
my ( $Xseq_cls, $Ycls_seq ) = make_sequences( $X, $Ycls, $SEQ_LEN );
my $n_seq = scalar @$Xseq_reg;
printf "  %d secuencias utilizables (se pierden los primeros %d eventos, sin historia previa)\n",
    $n_seq, $SEQ_LEN - 1;

my $Xnd_reg  = nd->array($Xseq_reg);    # [n_seq, SEQ_LEN, n_feats]
my $Yreg_nd  = nd->array($Yreg_seq);    # [n_seq, 4]
my $Xnd_cls  = nd->array($Xseq_cls);
my $Ycls_nd  = nd->array($Ycls_seq);

# =============================================================================
# Arquitectura LSTM — layout NTC (batch, tiempo, canales/features), igual
# que el script de referencia. Se toma SOLO la salida del ULTIMO paso de
# tiempo (H->slice(':',-1,':')) para predecir el evento actual -- mismo
# criterio que la funcion forward() del script de referencia.
# =============================================================================
package SeqNet {
    use AI::MXNet qw(mx);
    use base ("AI::MXNet::Gluon::Block");
    sub new {
        my ( $class, %args ) = @_;
        my $self = $class->SUPER::new(%args);
        $self->{lstm} = mx->gluon->rnn->LSTM(
            hidden_size => $args{hidden_units}, num_layers => 1,
            layout => 'NTC', input_size => $args{input_size},
        );
        $self->{dense} = mx->gluon->nn->Dense(
            units => $args{units}, in_units => $args{hidden_units},
            flatten => 0,
            ( defined $args{out_activation} ? ( activation => $args{out_activation} ) : () ),
        );
        $self->register_child( $self->{lstm} );
        $self->register_child( $self->{dense} );
        return bless( $self, $class );
    }
    sub forward {
        my ( $self, $X ) = @_;
        my $H = $self->{lstm}->forward($X);
        $H = $H->slice( ':', -1, ':' )->sever;   # solo el ultimo paso de tiempo
        return $self->{dense}->forward($H);
    }
    1;
}

if ( $MODE eq 'train' ) {
    print "\nEntrenando modelo de REGRESION (LSTM)...\n";
    my $net_reg = SeqNet->new(
        hidden_units => 32, input_size => $n_feats,
        units => scalar(@REG_COLS), out_activation => 'relu',   # no-negativo (conteo)
    );
    $net_reg->collect_params->initialize( init => mx->init->Xavier(), force_reinit => 1 );
    my $trainer_reg = mx->gluon->Trainer( $net_reg->collect_params(),
        optimizer => 'adam', optimizer_params => { learning_rate => 0.01 } );
    my $loss_reg = mx->gluon->loss->L2Loss();

    my $epochs     = 60;
    my $batch_size = 64;
    for my $epoch ( 1 .. $epochs ) {
        my ( $total_loss, $nb ) = ( 0, 0 );
        for ( my $s = 0; $s < $n_seq; $s += $batch_size ) {
            my $e  = $s + $batch_size - 1; $e = $n_seq - 1 if $e > $n_seq - 1;
            my $xb = $Xnd_reg->slice( [ $s, $e ] )->sever;
            my $yb = $Yreg_nd->slice( [ $s, $e ] )->sever;
            my ( $pred, $l );
            mx->autograd->record( sub { $pred = $net_reg->($xb); $l = $loss_reg->( $pred, $yb ); } );
            $l->backward();
            $trainer_reg->step( $xb->shape->[0] );
            $total_loss += $l->mean->asscalar // 0; $nb++;
        }
        printf "  epoch %2d/%d  loss=%.4f\n", $epoch, $epochs, $total_loss / ( $nb || 1 )
            if $epoch % 10 == 0 || $epoch == $epochs;
    }
    $net_reg->save_parameters('modelo_regresion_lstm.params');
    print "Guardado modelo_regresion_lstm.params\n";

    print "\nEntrenando modelo de CLASIFICACION (LSTM)...\n";
    my $net_cls = SeqNet->new(
        hidden_units => 32, input_size => $n_feats,
        units => scalar(@CLS_COLS), out_activation => undef,   # logits crudos
    );
    $net_cls->collect_params->initialize( init => mx->init->Xavier(), force_reinit => 1 );
    my $trainer_cls = mx->gluon->Trainer( $net_cls->collect_params(),
        optimizer => 'adam', optimizer_params => { learning_rate => 0.01 } );
    my $loss_cls = mx->gluon->loss->SigmoidBinaryCrossEntropyLoss();

    for my $epoch ( 1 .. $epochs ) {
        my ( $total_loss, $nb ) = ( 0, 0 );
        for ( my $s = 0; $s < $n_seq; $s += $batch_size ) {
            my $e  = $s + $batch_size - 1; $e = $n_seq - 1 if $e > $n_seq - 1;
            my $xb = $Xnd_cls->slice( [ $s, $e ] )->sever;
            my $yb = $Ycls_nd->slice( [ $s, $e ] )->sever;
            my ( $pred, $l );
            mx->autograd->record( sub { $pred = $net_cls->($xb); $l = $loss_cls->( $pred, $yb ); } );
            $l->backward();
            $trainer_cls->step( $xb->shape->[0] );
            $total_loss += $l->mean->asscalar // 0; $nb++;
        }
        printf "  epoch %2d/%d  loss=%.4f\n", $epoch, $epochs, $total_loss / ( $nb || 1 )
            if $epoch % 10 == 0 || $epoch == $epochs;
    }
    $net_cls->save_parameters('modelo_clasificacion_lstm.params');
    print "Guardado modelo_clasificacion_lstm.params\n";
    print "\nListo. Para testear: perl train_predict_lstm.pl test features_test_norm.csv\n";
    exit 0;
}

# =============================================================================
# MODO TEST
# =============================================================================
print "Cargando modelos LSTM entrenados...\n";
my $net_reg = SeqNet->new( hidden_units => 32, input_size => $n_feats, units => scalar(@REG_COLS), out_activation => 'relu' );
$net_reg->load_parameters('modelo_regresion_lstm.params');
my $net_cls = SeqNet->new( hidden_units => 32, input_size => $n_feats, units => scalar(@CLS_COLS), out_activation => undef );
$net_cls->load_parameters('modelo_clasificacion_lstm.params');

print "Prediciendo sobre $CSV...\n";
my $pred_reg_nd     = $net_reg->($Xnd_reg);
my $pred_cls_logits = $net_cls->($Xnd_cls);
my $pred_cls_prob   = nd->sigmoid($pred_cls_logits);

my @pred_reg  = @{ $pred_reg_nd->aspdl->unpdl };
my @pred_prob = @{ $pred_cls_prob->aspdl->unpdl };

print "\n=== EVALUACION — REGRESION (MAE / RMSE por ventana) — LSTM ===\n";
for my $w_idx ( 0 .. $#REG_COLS ) {
    my ( $sum_ae, $sum_se ) = ( 0, 0 );
    for my $i ( 0 .. $n_seq - 1 ) {
        my $err = $Yreg_seq->[$i][$w_idx] - $pred_reg[$i][$w_idx];
        $sum_ae += abs($err); $sum_se += $err * $err;
    }
    printf "  %-14s  MAE=%.3f  RMSE=%.3f\n", $REG_COLS[$w_idx], $sum_ae / $n_seq, sqrt( $sum_se / $n_seq );
}

print "\n=== EVALUACION — CLASIFICACION (umbral 0.5) — LSTM ===\n";
for my $w_idx ( 0 .. $#CLS_COLS ) {
    my ( $tp, $tn, $fp, $fn ) = ( 0, 0, 0, 0 );
    for my $i ( 0 .. $n_seq - 1 ) {
        my $actual = $Ycls_seq->[$i][$w_idx];
        my $pred   = ( $pred_prob[$i][$w_idx] >= 0.5 ) ? 1 : 0;
        if    ( $pred == 1 && $actual == 1 ) { $tp++; }
        elsif ( $pred == 0 && $actual == 0 ) { $tn++; }
        elsif ( $pred == 1 && $actual == 0 ) { $fp++; }
        else                                 { $fn++; }
    }
    my $precision = ( $tp + $fp ) ? $tp / ( $tp + $fp ) : 0;
    my $recall    = ( $tp + $fn ) ? $tp / ( $tp + $fn ) : 0;
    my $f1        = ( $precision + $recall ) ? 2 * $precision * $recall / ( $precision + $recall ) : 0;
    printf "  %-16s  TP=%-5d TN=%-5d FP=%-5d FN=%-5d  Precision=%.3f  Recall(Sensib.)=%.3f  F1=%.3f\n",
        $CLS_COLS[$w_idx], $tp, $tn, $fp, $fn, $precision, $recall, $f1;
}

print "\n=== DEMO (primer y ultimo evento del set de testeo) ===\n";
for my $i ( 0, $n_seq - 1 ) {
    printf "  Evento #%d:\n", $i;
    for my $w_idx ( 0 .. $#REG_COLS ) {
        printf "    %-14s  real=%d  predicho=%.2f  |  %-16s  real=%d  prob=%.2f\n",
            $REG_COLS[$w_idx], $Yreg_seq->[$i][$w_idx], $pred_reg[$i][$w_idx],
            $CLS_COLS[$w_idx], $Ycls_seq->[$i][$w_idx], $pred_prob[$i][$w_idx];
    }
}
