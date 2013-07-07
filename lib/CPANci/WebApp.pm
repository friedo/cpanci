package CPANci::WebApp { 
    use feature ':5.18';
    no warnings 'experimental';

    use Mojo::Base 'Mojolicious';
    use Mojolicious::Plugin::BasicAuth;

    use MongoDB;
    use File::Slurp 'slurp';
    use Const::Fast;
    use JSON::XS;
    use Scalar::Util 'blessed', 'reftype';
    use Digest;
    use Digest::Bcrypt;
    use MIME::Base64;

    const my $CONF => decode_json slurp "$ENV{HOME}/conf.json";

    sub startup { 
        my $self = shift;

        $self->plugin( 'BasicAuth' );

        $self->routes->get( '/' )->to( 'main#hello' );
        $self->routes->get( '/dist/:universe/#dist' )->to( 'main#dist' );
        $self->routes->get( '/dist/:universe/#dist/deps' )->to( 'main#deps' );
        $self->routes->get( '/dist/:universe/#dist/deps/log/#perl' )->to( 'main#deps_log' );
        $self->routes->get( '/dist/:universe/#dist/tests/#perl' )->to( 'main#tests' );
        $self->routes->get( '/dist/:universe/#dist/rawtap/#perl/*test' )->to( 'main#rawtap' );
        $self->routes->get( '/dist/:universe/#dist/stderr/#perl/*test' )->to( 'main#stderr' );

        my $auth_route = $self->routes->bridge( '/narf/:universe/test' )->to( cb => sub { 
            my $self = shift; 
            return $self->check_auth( $self->stash( 'universe' ) );
        } );

        $auth_route->get->to( 'main#test' );

        $self->helper( check_auth => sub { 
            my ( $self, $universe ) = @_;
            return 1 if $self->basic_auth( 
                $universe => sub {
                    my ( $username, $password ) = @_; 
                    my $user = $self->db->get_collection( 'users' )->find_one( { universe => $universe, name => $username } );
                    return unless defined $user && reftype $user eq reftype { };

                    my $bc = Digest->new( 'Bcrypt' );
                    $bc->cost( 10 );
                    $bc->salt( decode_base64 $user->{salt} );
                    $bc->add( $password );

                    return 1 if $user->{password} eq $bc->b64digest;
                    return;
                } 
            );
        } ); 

        $self->helper( db => sub { 
            return MongoDB::MongoClient->new( %{ $CONF->{mongodb} } )->get_database( 'cpanci' );
        } );
    }
}

1;
