package CPANci::WebApp { 
    use feature ':5.18';
    no warnings 'experimental';

    use Mojo::Base 'Mojolicious';

    sub startup { 
        my $self = shift;
        $self->routes->get( '/' )->to( 'main#hello' )
    }
}

1;