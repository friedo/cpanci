package CPANci::WebApp::Main { 
    use feature ':5.10';
    no warnings 'experimental';

    use Mojo::Base 'Mojolicious::Controller';
    use MongoDB;

    sub hello { 
        my $self = shift;

        my @dists = $self->db->get_collection( 'dists' )->find( { }, { fetched => 1 } )->sort( { fetched => 1 } )->limit( 100 )->all; 
  
        $self->stash( dists => \@dists );
        return $self->render;
    }

    sub dist { 
        my $self = shift;
        my $universe = $self->stash( 'universe' );
        my $dist = $self->stash( 'dist' );
        return $self->render( text => "dist = $dist, universe = $universe" );
    }

    # abstract this somewhere
    sub db { 
        my $self = shift;
        return MongoDB::MongoClient->new->get_database( 'cpanci' );
    }
}

1;
