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

        my $r  = $self->routes;
        my $getr  = $r->bridge( '/dist/:universe' )->via( 'GET' );
        my $postr = $r->bridge( '/dist/:universe' )->via( 'POST' ) ->to( cb => sub { shift->check_auth } );
        my $putr  = $r->bridge( '/dist/:universe' )->via( 'PUT' )  ->to( cb => sub { shift->check_auth } );

        # public routes
        $r->route( '/' )                            ->to( controller => 'main', action => 'hello' );
        $getr->route( '/#dist' )                    ->to( controller => 'main', action => 'dist' );
        $getr->route( '/#dist/deps' )               ->to( controller => 'main', action => 'deps' );
        $getr->route( '/#dist/deps/log/#perl' )     ->to( controller => 'main', action => 'deps_log' );
        $getr->route( '/#dist/tests/#perl' )        ->to( controller => 'main', action => 'tests' );
        $getr->route( '/#dist/rawtap/#perl/*test' ) ->to( controller => 'main', action => 'rawtap' );
        $getr->route( '/#dist/stderr/#perl/*test' ) ->to( controller => 'main', action => 'stderr' );

        # authenticated routes
        $putr->route( '/#dist' )                    ->to( controller => 'main', action => 'test' );

        $self->helper( check_auth => sub { 
            my ( $self ) = @_;
            my $universe = $self->stash( 'universe' );

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
