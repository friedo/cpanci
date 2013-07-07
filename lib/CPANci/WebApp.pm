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

        my $r = $self->routes;

        $r->route( '/' )->via( 'GET' )->to( 'main#hello' );
        $r->route( '/dist/:universe/#dist' )->via( 'GET' )->to( 'main#dist' );
        $r->route( '/dist/:universe/#dist/deps' )->via( 'GET' )->to( 'main#deps' );
        $r->route( '/dist/:universe/#dist/deps/log/#perl' )->via( 'GET' )->to( 'main#deps_log' );
        $r->route( '/dist/:universe/#dist/tests/#perl' )->via( 'GET' )->to( 'main#tests' );
        $r->route( '/dist/:universe/#dist/rawtap/#perl/*test' )->via( 'GET' )->to( 'main#rawtap' );
        $r->route( '/dist/:universe/#dist/stderr/#perl/*test' )->via( 'GET' )->to( 'main#stderr' );

        my $auth_route = $r->bridge( '/test/:universe' )->to( cb => sub { 
            my $self = shift;
            use Data::Dumper; warn Dumper( $self->stash );
            warn "route callback; universe = " . $self->stash( 'universe' );
            return $self->check_auth( $self->stash( 'universe' ) );
        } );

        $auth_route->route( '/#dist' )->via( 'GET' )->to( 'main#test' );

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
