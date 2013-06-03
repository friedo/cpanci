package CPANci::WebApp::Main { 
    use feature ':5.10';
    no warnings 'experimental';

    use Mojo::Base 'Mojolicious::Controller';

    sub hello { 
        my $self = shift;

        return $self->render;
    }

}

1;
