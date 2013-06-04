package CPANci::WebApp { 
    use feature ':5.18';
    no warnings 'experimental';

    use Mojo::Base 'Mojolicious';

    sub startup { 
        my $self = shift;
        $self->routes->get( '/' )->to( 'main#hello' );
        $self->routes->get( '/dist/:universe/#dist' )->to( 'main#dist' );
        $self->routes->get( '/dist/:universe/#dist/deps' )->to( 'main#deps' );
        $self->routes->get( '/dist/:universe/#dist/deps/log/#perl' )->to( 'main#deps_log' );
        $self->routes->get( '/dist/:universe/#dist/tests/#perl' )->to( 'main#tests' );
        $self->routes->get( '/dist/:universe/#dist/rawtap/#perl/*test' )->to( 'main#rawtap' );
        $self->routes->get( '/dist/:universe/#dist/stderr/#perl/*test' )->to( 'main#stderr' );
    }
}

1;
